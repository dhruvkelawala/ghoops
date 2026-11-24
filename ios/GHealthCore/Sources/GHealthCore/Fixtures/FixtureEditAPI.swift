#if DEBUG
import Foundation
import OSLog

public actor FixtureEditAPI: EditAPI {
    public enum LimitsFixture: Sendable { case mac, odd, none }
    public enum MutationMode: Sendable { case answer, hold, offline, offlineOnce, reject(ClientError) }
    public private(set) var mutationMode: MutationMode
    private var mutations = 0
    public func setMutationMode(_ mode: MutationMode) { mutationMode = mode; mutations = 0 }
    private let limits: LimitsFixture
    private let directory: URL
    private let offline: Bool
    private let parity: Bool
    private let sleepEditing: Bool
    private let journalEditing: Bool
    private var journalEntries: [String: JournalEntry?] = [:]
    public private(set) var state: String
    public private(set) var matchedRequests: [String] = []
    private var postedIDs: [String: String] = [:]
    private var ratings: [String: Int] = [:]

    public init(directory: URL, state: String = "edited", offline: Bool = false, parity: Bool = false, mutationMode: MutationMode = .answer, limits: LimitsFixture = .mac, sleepEditing: Bool = false, journalEditing: Bool = false) {
        self.sleepEditing = sleepEditing; self.journalEditing = journalEditing
        self.directory = directory; self.state = state; self.offline = offline; self.parity = parity; self.mutationMode = mutationMode; self.limits = limits
    }
    public init(bundle: Bundle = .main, state: String = "edited", offline: Bool = false, parity: Bool = false, mutationMode: MutationMode = .answer, limits: LimitsFixture = .mac, sleepEditing: Bool = false, journalEditing: Bool = false) {
        self.sleepEditing = sleepEditing; self.journalEditing = journalEditing
        directory = bundle.resourceURL!.appendingPathComponent(sleepEditing || journalEditing ? "Fixtures" : parity ? "Fixtures/parity" : "Fixtures/edits")
        self.state = state; self.offline = offline; self.parity = parity; self.mutationMode = mutationMode; self.limits = limits
    }
    public func snapshot() throws -> Snapshot {
        if journalEditing {
            var snapshot: Snapshot = try read("snapshot_fresh")
            for (date, entry) in journalEntries.sorted(by: { $0.key < $1.key }) {
                snapshot.journal = snapshot.journal.map { JournalPatch(date: date, answers: entry?.answers ?? [:], updatedAt: entry?.updatedAt ?? snapshot.generatedAt).apply(to: $0) }
            }
            return snapshot
        }
        if sleepEditing {
            var snapshot: Snapshot = try read("snapshot_fresh")
            let sleep: Sleep = try read(state == "unedited" ? "sleep_full" : "sleep_edit/sleep_\(state)")
            snapshot.sleep = sleep
            if state == "extended" { snapshot.day = try read("day_unstaged") }
            if let limits = snapshot.status.editLimits, let draft = SleepEditDraft(sleep: sleep, limits: limits, now: snapshot.generatedAt) {
                snapshot.day.sleep = SleepPatch(draft).apply(to: snapshot.day.sleep)
            }
            snapshot.day.sleep.performance = sleep.performance; snapshot.day.sleep.need = sleep.need
            snapshot.day.sleep.consistency = sleep.consistency
            return snapshot
        }
        var snapshot: Snapshot = try read(parity ? "snapshot" : "snapshot_\(state)")
        switch limits {
        case .mac: break
        case .odd:
            struct Body: Decodable { var editLimits: EditLimits }
            let body: Body = try read("odd_limits")
            snapshot.status.editLimits = body.editLimits
        case .none: snapshot.status.editLimits = nil
        }
        snapshot.workouts.workouts = snapshot.workouts.workouts.map(posted).map(rated)
        snapshot.day.workouts = snapshot.day.workouts.map(posted).map(rated)
        return snapshot
    }
    public func putSleepEdit(date: String, _ body: SleepEditBody) async throws -> SleepEdit? {
        try checkMutation()
        guard sleepEditing, date == "2026-03-10" else { throw ClientError.notFound }
        for next in ["extended", "shortened", "earlier", "unedited"] {
            let sleep: Sleep = try read(next == "unedited" ? "sleep_full" : "sleep_edit/sleep_\(next)")
            if body.start == sleep.bedtime, body.end == sleep.wakeTime {
                try await mutate("sleep-\(next)")
                state = next
                return sleep.session?.edit
            }
        }
        // A window with no fixture still waits, holds or fails as the mode says, so the pending states work for any wake.
        try await mutate("sleep-unmatched")
        throw ClientError.rejected
    }
    public func deleteSleepEdit(date: String) async throws {
        try checkMutation()
        guard sleepEditing, date == "2026-03-10", state != "unedited" else { throw ClientError.notFound }
        try await mutate("sleep-restore")
        state = "unedited"
    }
    public func putEdit(id: String, _ body: EditBody) async throws -> WorkoutEdit? {
        try checkMutation()
        guard id == "7300000000000000101" else { throw ClientError.rejected }
        let choices: [(String, String)]
        switch state {
        case "deleted_merged": choices = [("undo_merged", "merged"), ("delete_merged", "deleted_merged")]
        case "deleted": choices = [("undo", "edited"), ("delete", "deleted")]
        default: choices = [("edit", "edited"), ("merge", "merged"), ("delete", "deleted"), ("delete_merged", "deleted_merged")] + (isHolding ? [("edit_strength", "edited")] : [])
        }
        for (name, next) in choices {
            let expected: EditBody = try read("requests/\(name)")
            if body == expected {
                try await mutate(name)
                state = next
                if body.hidden { return WorkoutEdit(exerciseType: body.exerciseType, start: body.start, end: body.end, notes: body.notes, mergeWith: body.mergeWith, updatedAt: try snapshot().generatedAt) }
                return try snapshot().workouts.workouts.first { $0.id == id }?.edit
            }
        }
        throw ClientError.rejected
    }
    public func deleteEdit(id: String) async throws {
        try checkMutation()
        guard id == "7300000000000000101", state != "unedited" else { throw ClientError.notFound }
        try await mutate("restore")
        state = "unedited"
    }
    public func postActivity(_ activity: ActivityUpload) async throws -> ActivityRecord {
        try checkMutation()
        for name in ["name", "add"] + (isHolding ? ["add_midnight"] : []) {
            var expected: ActivityUpload = try read("requests/\(name == "add_midnight" ? "add" : name)")
            if name == "add_midnight" {
                let clock = ISO8601DateFormatter()
                expected.start = clock.date(from: "2026-03-12T23:40:00Z")!
                expected.end = clock.date(from: "2026-03-13T00:40:00Z")!
            }
            let fixtureID = expected.id
            expected.id = activity.id
            let encoder = JSONCoding.encoder(); encoder.outputFormatting = .sortedKeys
            if try encoder.encode(expected) == encoder.encode(activity) {
                try await mutate(name)
                state = name == "name" ? "named" : "added"
                postedIDs["goop-\(fixtureID)"] = "goop-\(activity.id)"
                return ActivityRecord(id: activity.id, exerciseType: activity.exerciseType, displayName: activity.displayName, start: activity.start, end: activity.end, pauses: activity.pauses, createdAt: try snapshot().generatedAt, origin: activity.origin, notes: activity.notes)
            }
        }
        throw ClientError.rejected
    }
    public func putRating(id: String, _ body: RatingBody) async throws {
        try checkMutation()
        guard EffortScale.values.contains(body.rpe) else { throw ClientError.rejected }
        guard try snapshot().workouts.workouts.contains(where: { $0.id == id && $0.kind != "detected" }) else { throw ClientError.notFound }
        try await mutate("rate-\(body.rpe)")
        ratings[id] = body.rpe
    }
    public func putJournal(date: String, _ body: JournalBody) async throws -> JournalEntry? {
        try checkMutation()
        let snapshot = try snapshot()
        guard journalEditing, let journal = snapshot.journal, journal.covers(date) else { throw ClientError.notFound }
        let stored = journal.entry(on: date)
        if let stored, stored.answers == body.answers { return stored }
        guard body.ifUpdatedAt.map({ floor($0.timeIntervalSince1970) }) == stored.map({ floor($0.updatedAt.timeIntervalSince1970) }) else { throw ClientError.conflict }
        try await mutate("journal")
        let entry = body.answers.isEmpty ? nil : JournalEntry(date: date, answers: body.answers, updatedAt: snapshot.generatedAt.addingTimeInterval(Double(mutations)))
        journalEntries[date] = .some(entry)
        return entry
    }
    public func heartRate(date: String) async throws -> HeartRateBody {
        try checkConnection()
        return try read("heart_rate_day_\(date)")
    }
    public func heartRate(start: Date, end: Date) async throws -> HeartRateBody {
        try checkConnection()
        if sleepEditing { return try read("sleep_edit/heart_rate") }
        return try read(parity ? "heart_rate_effort" : GoopFormat.dateKey(start) == "2026-03-10" ? "heart_rate_tue" : "heart_rate_thu_effort")
    }
    private func rated(_ workout: Workout) -> Workout {
        var result = workout
        if let rpe = ratings[workout.id] { result.rpe = rpe }
        return result
    }
    private func posted(_ workout: Workout) -> Workout {
        var result = workout
        if let id = postedIDs[workout.id] { result.id = id }
        return result
    }
    private func checkConnection() throws { if offline { throw ClientError.offline } }
    private func checkMutation() throws {
        try checkConnection()
        if parity {
            Logger(subsystem: "io.ghealth.app.fixture", category: "edits").error("FixtureEditAPI refused parity mutation")
            throw ClientError.rejected
        }
    }
    private func mutate(_ name: String) async throws {
        matched(name)
        mutations += 1
        switch mutationMode {
        case .answer: return
        case .hold: while true { try await Task.sleep(for: .seconds(86400)) }
        case .offline: throw ClientError.offline
        case .offlineOnce: if mutations == 1 { throw ClientError.offline }
        case .reject(let error): throw error
        }
    }
    private var isHolding: Bool { if case .hold = mutationMode { true } else { false } }
    private func matched(_ name: String) {
        matchedRequests.append(name)
        Logger(subsystem: "io.ghealth.app.fixture", category: "edits").notice("FixtureEditAPI matched \(name, privacy: .public)")
    }
    private func read<T: Decodable>(_ name: String) throws -> T {
        try JSONCoding.decoder().decode(T.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
    }
}
#endif
