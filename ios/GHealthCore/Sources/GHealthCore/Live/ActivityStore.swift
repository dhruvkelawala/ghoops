import Foundation

public actor ActivityStore {
    private let directory: URL
    private var uploading = false
    private var inFlight: [String: Task<ActivityRecord, Error>] = [:]
    private var deleting = Set<String>()
    private var bound: PairedMac?
    private var api: (any ActivityAPI)?
    public init(directory: URL) { self.directory = directory }
    /// Ties uploads and Mac deletes to one pairing. `nil` means unpaired: nothing is sent.
    public func bind(_ mac: PairedMac?, api: (any ActivityAPI)?) { bound = mac; self.api = mac == nil ? nil : api }
    public func prepareForProtectedData() throws {
        try SavedFiles.prepare(["activities-local.json", "live-session.json"], in: directory)
    }
    public func startSession(_ session: ActivitySession, now: Date) throws -> ActivitySession {
        if let saved = try restoreSession(now: now) { return saved }
        try saveSession(session, now: now)
        return session
    }
    public func saveSession(_ session: ActivitySession, now: Date) throws {
        if let saved = try read(ActivitySession.self, name: "live-session.json"), saved.id != session.id {
            throw SavedDataError(area: .activities)
        }
        var saved = session; saved.updatedAt = now
        try write(saved, name: "live-session.json")
    }
    public func restoreSession(now: Date) throws -> ActivitySession? {
        guard var session = try read(ActivitySession.self, name: "live-session.json") else { return nil }
        if session.state != .ended && now.timeIntervalSince(session.updatedAt) >= ActivitySession.recordingSpan {
            session.finish(at: session.samples.last?.t ?? session.updatedAt)
        } else { _ = session.enforceLimit(at: now) }
        return session
    }
    public func clearSession() throws {
        let url = directory.appendingPathComponent("live-session.json")
        do { try FileManager.default.removeItem(at: url) }
        catch CocoaError.fileNoSuchFile {}
    }
    public func activities(now: Date) throws -> [LocalActivity] {
        let rows = try read([LocalActivity].self, name: "activities-local.json") ?? []
        let kept = rows.filter { $0.uploadState != .uploaded || now.timeIntervalSince($0.upload.end) <= 7 * 86400 }
        if kept.count != rows.count { try write(kept, name: "activities-local.json") }
        return kept
    }
    public func save(_ activity: LocalActivity, now: Date) throws {
        var rows = try activities(now: now)
        rows.removeAll { $0.id == activity.id }; rows.append(activity)
        try write(rows, name: "activities-local.json")
    }
    public func delete(id: String, now: Date) throws {
        var rows = try activities(now: now); rows.removeAll { $0.id == id }
        try write(rows, name: "activities-local.json")
    }
    /// Deletes an activity on the bound Mac and on this phone. A local row saved for another Mac is refused.
    public func deleteOnMac(id: String, now: Date) async throws {
        guard let mac = bound, let api else { throw ClientError.unauthorized }
        if let row = try activities(now: now).first(where: { $0.id == id }), row.mac != mac { throw ClientError.unauthorized }
        deleting.insert(id); defer { deleting.remove(id) }
        if let task = inFlight[id] { _ = try? await task.value }
        do { try await api.deleteActivity(id: id) }
        catch ClientError.notFound {}
        catch ClientError.http(404) {}
        try delete(id: id, now: now)
    }
    /// Sends the bound Mac's pending rows. Returns true when one should be retried soon.
    /// The pass stops when the binding moves to another Mac, and on a 401 (the row stays pending for the next pairing link).
    public func retry(now: Date) async throws -> Bool {
        guard !uploading, let mac = bound, api != nil else { return false }
        uploading = true; defer { uploading = false }
        var failed = false
        let pending = try activities(now: now).filter { $0.uploadState == .pending && $0.mac == mac }
        for entry in pending {
            guard bound == mac, let api else { break }
            guard !deleting.contains(entry.id), try activities(now: now).contains(where: { $0.id == entry.id && $0.uploadState == .pending && $0.mac == mac }) else { continue }
            let upload = entry.upload
            let task = Task { try await api.postActivity(upload) }
            inFlight[entry.id] = task
            var state = ActivityUploadState.pending
            var unauthorized = false
            do { _ = try await task.value; state = .uploaded }
            catch {
                switch error as? ClientError {
                case .conflict, .http(409): state = .uploaded
                case .unauthorized: unauthorized = true
                case .http(let code) where (400..<500).contains(code): state = .rejected
                case .rejected, .notFound, .rateLimited: state = .rejected
                default: failed = true
                }
            }
            inFlight[entry.id] = nil
            if state != .pending {
                var current = try activities(now: now)
                if let index = current.firstIndex(where: { $0.id == entry.id }) {
                    current[index].uploadState = state
                    try write(current, name: "activities-local.json")
                }
            }
            if unauthorized { break }
        }
        return failed
    }
    /// Pending rows that belong to another Mac or to no known Mac. They are never sent automatically.
    public func held(now: Date) throws -> [LocalActivity] {
        try activities(now: now).filter { $0.uploadState == .pending && $0.mac != bound }
    }
    /// Moves unsent rows to the bound Mac, at the person's request. The next `retry` sends them.
    public func adopt(ids: Set<String>, now: Date) throws {
        guard let mac = bound else { return }
        var rows = try activities(now: now)
        for index in rows.indices where ids.contains(rows[index].id) && rows[index].uploadState == .pending && rows[index].mac != mac { rows[index].mac = mac }
        try write(rows, name: "activities-local.json")
    }
    /// Deletes unsent rows from this phone only.
    public func discard(ids: Set<String>, now: Date) throws {
        var rows = try activities(now: now)
        rows.removeAll { ids.contains($0.id) && $0.uploadState == .pending && $0.mac != bound }
        try write(rows, name: "activities-local.json")
    }
    private func read<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard let data = try SavedFiles.read(url) else { return nil }
        return try JSONCoding.decoder().decode(type, from: data)
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder().encode(value)
        let url = directory.appendingPathComponent(name)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
