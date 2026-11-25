import Foundation

public actor ChangeQueue {
    public struct DrainResult: Sendable {
        public var changes: [PendingChange]
        public var rollbacks: [RollbackNotice]
        public var refused: [PendingChange]
        public var waitingError: ClientError? = nil
    }

    public private(set) var changes: [PendingChange] = []
    public private(set) var isLoaded = false
    private let directory: URL
    private var mac: PairedMac
    private let clock: @Sendable () -> Date
    private var notBefore: Date?
    private var draining = false
    private var inFlight: UUID?
    private var generation = UUID()

    public init(directory: URL, serverURL: String, profileId: String? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.directory = directory
        self.mac = PairedMac(url: serverURL, name: "", profile: profileId)
        self.clock = clock
    }

    public func bind(to mac: PairedMac) throws {
        guard let profile = mac.profile, self.mac.profile == nil, self.mac.matches(mac) else { return }
        if isLoaded {
            var next = changes.filter { mac.matches($0.mac) }
            for index in next.indices { next[index].bind(to: mac) }
            try write(next)
            changes = next
        }
        self.mac = PairedMac(url: mac.url, name: "", profile: profile)
    }

    @discardableResult public func load() throws -> [PendingChange] {
        isLoaded = false
        let file = directory.appendingPathComponent("pending-changes.json")
        var loaded: [PendingChange] = []
        if let data = try SavedFiles.read(file) {
            let saved = try JSONCoding.decoder().decode([PendingChange].self, from: data)
            loaded = saved.filter { mac.matches($0.mac) }
            let needsWrite = loaded.count != saved.count || loaded.contains { $0.serverURL != mac.url || ($0.profileId == nil && mac.profile != nil) }
            if needsWrite {
                for index in loaded.indices { loaded[index].bind(to: mac) }
                try write(loaded)
            }
        }
        changes = loaded
        isLoaded = true
        return changes
    }

    public func prepareForProtectedData() throws {
        try SavedFiles.prepare(["pending-changes.json"], in: directory)
    }

    public func submit(_ change: PendingChange) throws {
        guard isLoaded else { throw SavedDataError(area: .changes) }
        guard mac.matches(change.mac), !changes.contains(where: { $0.id == change.id }) else { return }
        var change = change
        change.bind(to: mac)
        let submitted = changes + [change]
        try write(submitted)
        changes = submitted
    }

    public func drain(api: any EditAPI, uploads: @Sendable () async -> Void, onChange: @Sendable (DrainResult) async -> Void = { _ in }) async throws -> DrainResult {
        guard isLoaded else { throw SavedDataError(area: .changes) }
        guard !draining else { return DrainResult(changes: changes, rollbacks: [], refused: []) }
        if let notBefore, clock() < notBefore { return DrainResult(changes: changes, rollbacks: [], refused: []) }
        notBefore = nil
        draining = true
        defer { draining = false; inFlight = nil }
        let pass = generation
        var notices: [RollbackNotice] = []
        var refused: [PendingChange] = []
        await uploads()
        while !Task.isCancelled, pass == generation, let index = changes.firstIndex(where: { $0.state != .accepted }) {
            let id = changes[index].id
            changes[index].state = .sending
            changes[index].attempts += 1
            try write(changes)
            await onChange(DrainResult(changes: changes, rollbacks: notices, refused: refused))
            let result: Result<WorkoutEdit?, Error>
            do {
                guard !Task.isCancelled, pass == generation else { break }
                guard let attempt = changes.firstIndex(where: { $0.id == id }) else { continue }
                inFlight = id
                if let replay = changes[attempt].replayBeforeUndo {
                    let edit: WorkoutEdit?
                    do { edit = try await send(replay, api: api) }
                    catch MutationError.unreadableResponse { edit = nil }
                    guard pass == generation, let current = changes.firstIndex(where: { $0.id == id }) else { break }
                    if case .putEdit(let target, var body) = changes[current].request {
                        body.precondition = edit.map { .updatedAt($0.updatedAt) } ?? .none
                        changes[current].request = .putEdit(target, body)
                    }
                    changes[current].replayBeforeUndo = nil
                    try write(changes)
                }
                guard pass == generation, let current = changes.firstIndex(where: { $0.id == id }) else { break }
                result = .success(try await send(changes[current].request, api: api))
            } catch { result = .failure(error) }
            guard pass == generation, let current = changes.firstIndex(where: { $0.id == id }) else { break }
            inFlight = nil
            switch outcome(result) {
            case .accepted(let edit):
                changes[current].state = .accepted
                changes[current].acceptedAt = clock()
                changes[current].acceptedEdit = edit
                if case .putEdit = changes[current].request, case .success = result {
                    for row in changes[current].patch.upsert.indices { changes[current].patch.upsert[row].edit = edit }
                }
                if changes[current].undoRequested, var undo = ChangeBuilder.undo(changes[current], now: clock()) {
                    changes[current].patch.remove = changes[current].kept.map { [$0.id] } ?? []
                    changes[current].patch.upsert = []
                    undo.bind(to: mac)
                    changes.append(undo)
                }
            case .waiting:
                let error: ClientError? = if case .failure(let error) = result { error as? ClientError } else { nil }
                if let delay = error?.rateLimitDelay { notBefore = clock().addingTimeInterval(delay) }
                if changes[current].undoRequested { changes.remove(at: current) }
                for later in current..<changes.count where changes[later].state != .accepted { changes[later].state = .waiting }
                try write(changes)
                let waiting = DrainResult(changes: changes, rollbacks: notices, refused: refused, waitingError: error)
                await onChange(waiting)
                return waiting
            case .refused(let error):
                let change = changes.remove(at: current)
                changes.removeAll { $0.state != .accepted && !Set($0.targets).isDisjoint(with: change.targets) }
                if !change.undoRequested {
                    refused.append(change)
                    notices.append(RollbackNotice(changeID: id, kind: change.kind, name: change.name, error: error))
                }
            }
            try write(changes)
            await onChange(DrainResult(changes: changes, rollbacks: notices, refused: refused))
        }
        return DrainResult(changes: changes, rollbacks: notices, refused: refused)
    }

    @discardableResult public func cancel(id: UUID) throws -> Bool {
        guard isLoaded else { throw SavedDataError(area: .changes) }
        guard let index = changes.firstIndex(where: { $0.id == id }), changes[index].state != .accepted else { return false }
        if inFlight == id {
            changes[index].undoRequested = true
            if let kept = changes[index].kept { changes[index].patch.remove = []; changes[index].patch.upsert = [kept] }
        } else { changes.remove(at: index) }
        try write(changes)
        return true
    }

    public func settle(acceptedBefore: Date) throws {
        guard isLoaded else { throw SavedDataError(area: .changes) }
        changes.removeAll { $0.state == .accepted && ($0.acceptedAt.map { $0 <= acceptedBefore } ?? false) }
        try write(changes)
    }

    public func clear() throws {
        guard isLoaded else { throw SavedDataError(area: .changes) }
        generation = UUID()
        changes = []
        try write(changes)
    }

    public func suspend() { generation = UUID() }

    private func send(_ request: PendingChange.Request, api: any EditAPI) async throws -> WorkoutEdit? {
        switch request {
        case .putSleepEdit(let date, let body): _ = try await api.putSleepEdit(date: date, body); return nil
        case .deleteSleepEdit(let date):
            do { try await api.deleteSleepEdit(date: date) }
            catch ClientError.notFound {}
            catch ClientError.http(404) {}
            return nil
        case .putEdit(let id, let body): return try await api.putEdit(id: id, body)
        case .deleteEdit(let id):
            do { try await api.deleteEdit(id: id) }
            catch ClientError.notFound {}
            catch ClientError.http(404) {}
            return nil
        case .postActivity(let upload): _ = try await api.postActivity(upload); return nil
        case .putRating(let id, let body): try await api.putRating(id: id, body); return nil
        case .putJournal(let date, let body): _ = try await api.putJournal(date: date, body); return nil
        }
    }

    private enum Outcome { case accepted(WorkoutEdit?), waiting, refused(ClientError) }
    private func outcome(_ result: Result<WorkoutEdit?, Error>) -> Outcome {
        switch result {
        case .success(let edit): return .accepted(edit)
        case .failure(let error):
            if error is MutationError { return .accepted(nil) }
            guard let error = error as? ClientError else { return .waiting }
            switch error {
            case .rejected, .notFound, .conflict, .http(400), .http(404), .http(409), .http(413): return .refused(error)
            default: return .waiting
            }
        }
    }

    private func write(_ changes: [PendingChange]) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONCoding.encoder().encode(changes)
            let file = directory.appendingPathComponent("pending-changes.json")
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
        } catch {
            if SavedDataError.isPermissionError(error) { throw SavedDataError(error, area: .changes) }
            throw error
        }
    }
}
