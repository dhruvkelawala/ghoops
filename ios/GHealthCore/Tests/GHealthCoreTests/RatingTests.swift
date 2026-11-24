import Foundation
import Testing
@testable import GHealthCore

private let ratingServer = "https://fixture.invalid:18780"
private let ratingTime = Date(timeIntervalSince1970: 1_773_311_400)
private let rated = "7300000000000000101"

private func ratingSnapshot(_ state: String = "rated") throws -> Snapshot { try fixture("edits/snapshot_\(state).json", as: Snapshot.self) }
private func ratingWorkout(_ state: String = "edited") throws -> Workout { try #require(try ratingSnapshot(state).workouts.workouts.first { $0.id == rated }) }

private actor RatingAPI: EditAPI {
    var reply: ClientError?
    var order: [String] = []
    var bodies: [RatingBody] = []
    init(reply: ClientError? = nil) { self.reply = reply }
    func uploads() { order.append("uploads") }
    func putRating(id: String, _ body: RatingBody) async throws {
        order.append("rating"); bodies.append(body)
        if let reply { throw reply }
    }
    func putSleepEdit(date: String, _ body: SleepEditBody) async throws -> SleepEdit? { nil }
    func deleteSleepEdit(date: String) async throws {}
    func putEdit(id: String, _ body: EditBody) async throws -> WorkoutEdit? { nil }
    func deleteEdit(id: String) async throws {}
    func postActivity(_ upload: ActivityUpload) async throws -> ActivityRecord { throw ClientError.offline }
    func putJournal(date: String, _ body: JournalBody) async throws -> JournalEntry? { throw ClientError.offline }
    func heartRate(date: String) throws -> HeartRateBody { throw ClientError.offline }
    func heartRate(start: Date, end: Date) throws -> HeartRateBody { throw ClientError.offline }
}

@Test func scaleWords() {
    let words = EffortScale.values.map { EffortScale.word($0) }
    #expect(words == ["Rest", "Very, very easy", "Easy", "Moderate", "Somewhat hard", "Hard", nil, "Very hard", nil, nil, "Maximal"])
    #expect(EffortScale.rowValue(7) == "7 · Very hard")
    #expect(EffortScale.rowValue(6) == "6")
    #expect(EffortScale.spoken(7) == "7, very hard")
    #expect(EffortScale.spoken(9) == "9")
}

@Test func supportedOnlyWithScale() {
    func limits(_ scale: String?) -> EditLimits {
        EditLimits(horizonDays: 30, shiftMinutes: 180, mergeGapMinutes: 15, mergeMaxIds: 4, notesMaxChars: 500, activeMinMinutes: 1, activeMaxMinutes: 720, heartRateSpanMaxMinutes: 1080, rpeScale: scale)
    }
    #expect(EffortScale.supported(limits("cr10")))
    #expect(!EffortScale.supported(limits(nil)))
    #expect(!EffortScale.supported(limits("borg")))
    #expect(!EffortScale.supported(nil))
}

@Test func decodesRatedSnapshot() throws {
    let snapshot = try ratingSnapshot()
    #expect(snapshot.status.editLimits?.rpeScale == "cr10")
    #expect(snapshot.workouts.workouts.first { $0.id == rated }?.rpe == 7)
    #expect(snapshot.workouts.workouts.filter { $0.id != rated }.allSatisfy { $0.rpe == nil })
    #expect(snapshot.workouts.workouts.count > 1)
}

@Test func decodesOlderMac() throws {
    let url = fixtureRoot.appendingPathComponent("edits/snapshot_rated.json")
    var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    func strip(_ value: Any) -> Any {
        if let dict = value as? [String: Any] { return dict.filter { $0.key != "rpe" && $0.key != "rpe_scale" }.mapValues(strip) }
        if let list = value as? [Any] { return list.map(strip) }
        return value
    }
    json = try #require(strip(json) as? [String: Any])
    let older = try JSONCoding.decoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(older.status.editLimits != nil)
    #expect(older.status.editLimits?.rpeScale == nil)
    #expect(older.workouts.workouts.allSatisfy { $0.rpe == nil })
    #expect(!EffortScale.supported(older.status.editLimits))
}

@Test func rateChange() async throws {
    let workout = try ratingWorkout()
    #expect(workout.rpe == nil)
    let change = ChangeBuilder.rate(workout, rpe: 7, serverURL: ratingServer, now: ratingTime)
    #expect(change.kind == .rate)
    #expect(change.targets == [rated])
    #expect(change.cycleDates == [workout.cycleDate])
    #expect(change.patch.upsert.map(\.rpe) == [7])
    #expect(change.patch.remove.isEmpty && change.patch.updating.isEmpty)
    guard case .putRating(let id, let body) = change.request else { Issue.record("not a rating request"); return }
    #expect(id == rated)
    let sent = try JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(body)) as? NSDictionary
    let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("edits/requests/rate.json"))) as? NSDictionary
    #expect(sent == expected)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rating-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: ratingServer)
    try await queue.load()
    try await queue.submit(change)
    let reloaded = try await ChangeQueue(directory: directory, serverURL: ratingServer).load()
    #expect(reloaded.first?.kind == .rate)
    #expect(Set(reloaded.flatMap(\.targets)) == [rated])
    if case .putRating(let id, let body) = try #require(reloaded.first).request { #expect(id == rated && body.rpe == 7) }
    else { Issue.record("saved request lost its kind") }
}

@Test func rateRollback() async throws {
    let workout = try ratingWorkout()
    for (reply, text) in [(ClientError.notFound, "Boxing changed on your Mac. It's back as it was."), (.rejected, "Your Mac couldn't save your rating for Boxing. It's back as it was."), (.http(400), "Your Mac couldn't save your rating for Boxing. It's back as it was.")] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rating-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: ratingServer, clock: { ratingTime })
        try await queue.load()
        try await queue.submit(ChangeBuilder.rate(workout, rpe: 7, serverURL: ratingServer, now: ratingTime))
        let result = try await queue.drain(api: RatingAPI(reply: reply), uploads: {})
        #expect(result.changes.isEmpty)
        #expect(result.rollbacks.map(\.text) == [text])
        #expect(result.refused.first?.kind == .rate)
    }
}

@Test func rateBehindUpload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rating-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: ratingServer, clock: { ratingTime })
    try await queue.load()
    try await queue.submit(ChangeBuilder.rate(try ratingWorkout(), rpe: 5, serverURL: ratingServer, now: ratingTime))
    let api = RatingAPI()
    let result = try await queue.drain(api: api, uploads: { await api.uploads() })
    #expect(await api.order == ["uploads", "rating"])
    #expect(await api.bodies == [RatingBody(rpe: 5)])
    #expect(result.changes.map(\.state) == [.accepted])
}

@Test func fixtureAPIStoresRatings() async throws {
    let api = FixtureEditAPI(directory: fixtureRoot.appendingPathComponent("edits"), state: "edited")
    try await api.putRating(id: rated, RatingBody(rpe: 4))
    #expect(try await api.snapshot().workouts.workouts.first { $0.id == rated }?.rpe == 4)
    await #expect(throws: ClientError.self) { try await api.putRating(id: rated, RatingBody(rpe: 11)) }
    await #expect(throws: ClientError.self) { try await api.putRating(id: "effort-2026-03-11T18:04:00Z", RatingBody(rpe: 4)) }
    #expect(await api.matchedRequests == ["rate-4"])
}

@Test func saveRatingErrorIsGhoopsWords() {
    let failure = NSError(domain: "io.ghealth.test", code: 1)
    #expect(ErrorCopy.message(failure, context: .saveRating) == "ghoops couldn't save your rating on this phone. Try again.")
}
