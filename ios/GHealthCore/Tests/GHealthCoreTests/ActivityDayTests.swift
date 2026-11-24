import Foundation
import Testing
@testable import GHealthCore

private func afterMidnightFixture(in directory: URL) throws -> FixtureState {
    let resources = directory.appendingPathComponent("Fixtures")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"), to: resources.appendingPathComponent("snapshot_fresh.json"))
    return try FixtureLoader.load(.afterMidnight, bundle: #require(Bundle(url: directory)))
}

@Test(arguments: [true, false])
func afterMidnightSessionKeepsItsGhoopsDayAcrossRestoreAndSave(_ hasTarget: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).bundle")
    defer { try? FileManager.default.removeItem(at: directory) }
    let state = try afterMidnightFixture(in: directory)
    let snapshot = try #require(state.cached?.snapshot)
    #expect(GoopFormat.dateKey(state.now) == "2026-03-11")
    #expect(snapshot.defaultDate == "2026-03-10")
    var session = ActivitySession(sport: .sport("BOXING"), now: state.now, cycleDate: snapshot.defaultDate)
    if hasTarget { session.target = SessionTarget.make(day: snapshot.day, sessionStart: state.now) }
    let store = ActivityStore(directory: directory)
    try await store.saveSession(session, now: state.now)
    var restored = try #require(await store.restoreSession(now: state.now.addingTimeInterval(60)))
    let finished = restored.finish(at: state.now.addingTimeInterval(60))
    #expect(finished)
    let entry = LiveEstimator(restingHR: nil, maximumHR: nil, model: nil).localActivity(restored, now: state.now.addingTimeInterval(60))
    try await store.save(entry, now: entry.upload.end)
    let saved = try #require(await ActivityStore(directory: directory).activities(now: entry.upload.end).first)
    let workout = saved.workout()
    #expect(restored.cycleDate == snapshot.defaultDate)
    #expect(saved.cycleDate == snapshot.defaultDate)
    #expect(workout.cycleDate == snapshot.defaultDate)
    #expect(ActivityMerge.workouts(server: [], local: [saved], now: entry.upload.end).filter { $0.cycleDate == snapshot.defaultDate }.map(\.id) == [workout.id])
}

@Test(arguments: [true, false])
func olderSavedSessionsAndActivitiesRemainReadable(_ hasTarget: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = hasTarget ? #", "target":{"cycle_date":"2026-03-10","low":13.3,"high":16.3,"crossing":"unknown"}"# : ""
    let session = Data("""
    {"id":"legacy", "exercise_type":"BOXING", "display_name":"Boxing", "start":"2026-03-11T00:10:00Z", "pauses":[], "samples":[[0,150]], "state":"running", "updated_at":"2026-03-11T00:10:00Z"\(target)}
    """.utf8)
    try session.write(to: directory.appendingPathComponent("live-session.json"))
    let activities = Data(#"[{"upload":{"id":"legacy","exercise_type":"BOXING","display_name":"Boxing","start":"2026-03-11T00:10:00Z","end":"2026-03-11T00:11:00Z","pauses":[]},"hr_series":[],"upload_state":"pending"}]"#.utf8)
    try activities.write(to: directory.appendingPathComponent("activities-local.json"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-03-11T00:11:00Z"))
    let store = ActivityStore(directory: directory)
    var restored = try #require(await store.restoreSession(now: now))
    #expect(restored.samples.count == 1)
    let finished = restored.finish(at: now)
    #expect(finished)
    let entry = LiveEstimator(restingHR: nil, maximumHR: nil, model: nil).localActivity(restored, now: now)
    #expect(entry.cycleDate == (hasTarget ? "2026-03-10" : "2026-03-11"))
    let saved = try #require(await store.activities(now: now).first)
    #expect(saved.workout().cycleDate == "2026-03-11")
    try await store.save(entry, now: now)
    #expect(try await ActivityStore(directory: directory).activities(now: now).first?.cycleDate == entry.cycleDate)
}

@Test func addedAfterMidnightActivityKeepsTheDraftDay() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).bundle")
    defer { try? FileManager.default.removeItem(at: directory) }
    let state = try afterMidnightFixture(in: directory)
    let snapshot = try #require(state.cached?.snapshot)
    let end = state.now.addingTimeInterval(120)
    let heartRate: HeartRateBody = try fixture("edits/heart_rate_tue.json")
    var draft = AddDraft(defaultDate: snapshot.defaultDate, workouts: [], now: end, limits: snapshot.status.editLimits)
    draft.sport = "BOXING"
    draft.load(heartRate)
    draft.window = ActivityWindow(start: state.now, end: end)
    let saved = try #require(ChangeBuilder.add(draft, heartRate: heartRate, serverURL: "https://fixture.invalid", now: end.addingTimeInterval(86400)))
    #expect(saved.cycleDates == ["2026-03-10"])
    #expect(saved.patch.upsert.first?.cycleDate == "2026-03-10")
    #expect(saved.patch.upsert.first?.start == state.now)
}
