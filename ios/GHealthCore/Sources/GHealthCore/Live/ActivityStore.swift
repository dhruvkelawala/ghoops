import Foundation

public actor ActivityStore {
    private let directory: URL
    private let migrationDefaults: UserDefaults?
    private let clock: @Sendable () -> Date
    private var notBefore: Date?
    private var uploading = false
    private var uploadGeneration = UUID()
    private var inFlight: [String: Task<ActivityRecord, Error>] = [:]
    private var deleting = Set<String>()
    private var bound: PairedMac?
    private var api: (any ActivityAPI)?
    public init(directory: URL, defaultsSuiteName: String? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.directory = directory
        self.migrationDefaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:))
        self.clock = clock
    }
    /// Ties uploads and Mac deletes to one pairing. `nil` means unpaired: nothing is sent.
    public func bind(_ mac: PairedMac?, api: (any ActivityAPI)?) {
        if bound?.matches(mac) != true { notBefore = nil }
        bound = mac
        self.api = mac == nil ? nil : api
    }
    public func prepareForProtectedData() throws {
        try SavedFiles.prepare(["activities-local.json", "live-session.json"], in: directory)
        let key = "rejectedRowsReset.1"
        guard let defaults = migrationDefaults, !defaults.bool(forKey: key) else { return }
        var (rows, _) = try readRows()
        let rejected = rows.indices.filter { rows[$0].uploadState == .rejected }
        if !rejected.isEmpty {
            for index in rejected { rows[index].uploadState = .pending }
            try writeRows(rows)
        }
        defaults.set(true, forKey: key)
    }
    public func startSession(_ session: ActivitySession, now: Date) throws -> ActivitySession {
        if let saved = try restoreSession(now: now) { return saved }
        try saveSession(session, now: now)
        return session
    }
    public func saveSession(_ session: ActivitySession, now: Date) throws {
        var next = session
        if let saved = try read(ActivitySession.self, name: "live-session.json") {
            guard saved.id == session.id else { throw SavedDataError(area: .activities) }
            if let mac = saved.mac { next.stampProfile(for: mac) }
        }
        next.updatedAt = now
        try write(next, name: "live-session.json")
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
        let (rows, needsMigration) = try readRows()
        let kept = rows.filter { $0.uploadState != .uploaded || now.timeIntervalSince($0.upload.end) <= 7 * 86400 }
        if kept.count != rows.count || needsMigration { try writeRows(kept) }
        return kept
    }

    private func readRows() throws -> (rows: [LocalActivity], needsMigration: Bool) {
        let local = try read([LocalActivity].self, name: "activities-local.json") ?? []
        let uploaded = try read([LocalActivity].self, name: "Cache/activities-uploaded.json") ?? []
        let uploadedIDs = Set(uploaded.map(\.id))
        let rows = local.filter { !uploadedIDs.contains($0.id) } + uploaded
        return (rows, local.contains { $0.uploadState == .uploaded || uploadedIDs.contains($0.id) })
    }
    public func save(_ activity: LocalActivity, now: Date) throws {
        var rows = try activities(now: now)
        rows.removeAll { $0.id == activity.id }; rows.append(activity)
        try writeRows(rows)
    }
    public func delete(id: String, now: Date) throws {
        var rows = try activities(now: now); rows.removeAll { $0.id == id }
        try writeRows(rows)
    }

    public func deleteUploaded(now: Date) throws {
        uploadGeneration = UUID()
        try writeRows(activities(now: now).filter { $0.uploadState != .uploaded })
    }

    public func discardPending(for mac: PairedMac, now: Date) throws {
        let rows = try activities(now: now).filter { $0.uploadState == .uploaded || !mac.matches($0.mac) }
        try writeRows(rows)
        if let session = try read(ActivitySession.self, name: "live-session.json"), mac.matches(session.mac) {
            try clearSession()
        }
    }

    public func stampProfile(for mac: PairedMac, now: Date) throws {
        guard mac.profile != nil else { return }
        var rows = try activities(now: now)
        var changed = false
        for index in rows.indices where rows[index].uploadState == .pending {
            let prior = rows[index].mac
            rows[index].mac = prior?.stamped(with: mac)
            changed = changed || rows[index].mac != prior
        }
        if changed { try writeRows(rows) }
        if var session = try read(ActivitySession.self, name: "live-session.json") {
            let prior = session.mac
            session.stampProfile(for: mac)
            if session.mac != prior { try write(session, name: "live-session.json") }
        }
    }
    /// Deletes an activity on the bound Mac and on this phone. A local row saved for another Mac is refused.
    public func deleteOnMac(id: String, now: Date) async throws {
        guard let mac = bound, api != nil else { throw ClientError.unauthorized }
        if let row = try activities(now: now).first(where: { $0.id == id }), !mac.matches(row.mac) { throw ClientError.unauthorized }
        deleting.insert(id); defer { deleting.remove(id) }
        if let task = inFlight[id] { _ = try? await task.value }
        guard mac.matches(bound), let api else { throw CancellationError() }
        do { try await api.deleteActivity(id: id) }
        catch ClientError.notFound {}
        catch ClientError.http(404) {}
        try delete(id: id, now: now)
    }
    /// Sends the bound Mac's pending rows. Returns true when one should be retried soon.
    /// The pass stops when the binding moves to another Mac or a response is 401 or 429.
    public func retry(now: Date) async throws -> Bool {
        guard !uploading, let mac = bound, api != nil else { return false }
        if let notBefore, clock() < notBefore { return true }
        notBefore = nil
        uploading = true; defer { uploading = false }
        let generation = uploadGeneration
        var failed = false
        let pending = try activities(now: now).filter { $0.uploadState == .pending && mac.matches($0.mac) }
        for entry in pending {
            guard mac.matches(bound), let api else { break }
            guard !deleting.contains(entry.id), try activities(now: now).contains(where: { $0.id == entry.id && $0.uploadState == .pending && mac.matches($0.mac) }) else { continue }
            let upload = entry.upload
            let task = Task { try await api.postActivity(upload) }
            inFlight[entry.id] = task
            defer { inFlight[entry.id] = nil }
            var state = ActivityUploadState.pending
            var unauthorized = false
            do { _ = try await task.value; state = .uploaded }
            catch ClientError.profileMismatch {
                throw ClientError.profileMismatch
            } catch {
                let clientError = error as? ClientError
                if let delay = clientError?.rateLimitDelay {
                    guard mac.matches(bound) else { return failed }
                    notBefore = clock().addingTimeInterval(delay)
                    return true
                }
                switch clientError {
                case .conflict, .http(409): state = .uploaded
                case .unauthorized: unauthorized = true
                case .http(let code) where (400..<500).contains(code): state = .rejected
                case .rejected, .notFound: state = .rejected
                default: failed = true
                }
            }
            guard generation == uploadGeneration else { break }
            if state != .pending {
                var current = try activities(now: now)
                if let index = current.firstIndex(where: { $0.id == entry.id }) {
                    current[index].uploadState = state
                    try writeRows(current)
                }
            }
            if unauthorized { break }
        }
        return failed
    }
    /// Pending rows that belong to another Mac or to no known Mac. They are never sent automatically.
    public func held(now: Date) throws -> [LocalActivity] {
        try activities(now: now).filter { $0.uploadState == .pending && bound?.matches($0.mac) != true }
    }
    /// Moves unsent rows to the bound Mac, at the person's request. The next `retry` sends them.
    public func adopt(ids: Set<String>, now: Date) throws {
        guard let mac = bound else { return }
        var rows = try activities(now: now)
        for index in rows.indices where ids.contains(rows[index].id) && rows[index].uploadState == .pending && !mac.matches(rows[index].mac) { rows[index].mac = mac }
        try writeRows(rows)
    }
    /// Deletes unsent rows from this phone only.
    public func discard(ids: Set<String>, now: Date) throws {
        var rows = try activities(now: now)
        rows.removeAll { ids.contains($0.id) && $0.uploadState == .pending && bound?.matches($0.mac) != true }
        try writeRows(rows)
    }

    private func writeRows(_ rows: [LocalActivity]) throws {
        let uploaded = rows.filter { $0.uploadState == .uploaded }
        if uploaded.isEmpty {
            try write(rows, name: "activities-local.json")
            do { try FileManager.default.removeItem(at: directory.appendingPathComponent("Cache/activities-uploaded.json")) }
            catch CocoaError.fileNoSuchFile {}
        } else {
            try SnapshotStore.prepareCacheDirectory(in: directory)
            try write(uploaded, name: "Cache/activities-uploaded.json")
            try write(rows.filter { $0.uploadState != .uploaded }, name: "activities-local.json")
        }
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
