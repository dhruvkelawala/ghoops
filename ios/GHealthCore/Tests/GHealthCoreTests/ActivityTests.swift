import Foundation
import Testing
@testable import GHealthCore

@Test func localActivityMergeUsesMacOnlyWhenFinal() throws {
    let upload = try JSONCoding.decoder().decode(ActivityUpload.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("activities/valid.json")))
    let local = LocalActivity(upload: upload)
    var server = local.workout()
    server.strain = 15
    server.hrCoverage = 0.79
    server.confidence = .medium
    let now = upload.end.addingTimeInterval(3600)
    #expect(ActivityMerge.workouts(server: [server], local: [local], now: now).first?.strain == upload.live?.strainEstimate)
    server.hrCoverage = 0.8
    server.confidence = .high
    #expect(ActivityMerge.workouts(server: [server], local: [local], now: now).first?.strain == 15)
    server.confidence = nil
    #expect(ActivityMerge.workouts(server: [server], local: [local], now: now).first?.strain == upload.live?.strainEstimate)
    server.hrCoverage = 0.1
    server.confidence = .low
    #expect(ActivityMerge.workouts(server: [server], local: [local], now: upload.end.addingTimeInterval(21601)).first?.strain == 15)
    #expect(ActivityMerge.workouts(server: [], local: [local], now: now).count == 1)
    let decoded = try JSONCoding.decoder().decode(Workout.self, from: JSONCoding.encoder().encode(server))
    #expect(decoded.kind == "goop")
    #expect(decoded.pausedMinutes == 0)
    #expect(decoded.id == "goop-\(upload.id)")
}

private let measurementCases: [([UInt8], Int?)] = [
    ([0, 158], 158), ([1, 200, 0], 200), ([8, 150, 0, 0], 150),
    ([16, 160, 0, 4], 160), ([4, 160], nil), ([6, 160], 160),
    ([0, 0], nil), ([1, 251, 0], nil), ([1, 150], nil), ([8, 150], nil), ([], nil)
]
@Test(arguments: measurementCases) func heartRateMeasurementFlags(_ bytes: [UInt8], _ expected: Int?) {
    #expect(HeartRateMeasurement.parse(Data(bytes)) == expected)
}

@Test func sessionTimingLimitsAndRestore() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let limits = try reportedEditLimits()
    var session = ActivitySession(sport: .all[0], now: now, limits: limits)
    session.append(.init(t: now.addingTimeInterval(10), bpm: 150))
    session.pause(at: now.addingTimeInterval(30))
    #expect(session.elapsed(at: now.addingTimeInterval(100)) == 30)
    session.resume(at: now.addingTimeInterval(100))
    #expect(session.elapsed(at: now.addingTimeInterval(140)) == 70)
    #expect(session.hrState(at: now.addingTimeInterval(20)) == .reconnecting)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ActivityStore(directory: dir)
    try await store.saveSession(session, now: now.addingTimeInterval(140))
    let restored = try #require(await store.restoreSession(now: now.addingTimeInterval(141)))
    #expect(restored.samples == session.samples)
    #expect(restored.elapsed(at: now.addingTimeInterval(141)) == 71)
    let stale = try #require(await store.restoreSession(now: now.addingTimeInterval(14 * 3600)))
    #expect(stale.state == .ended)
    #expect(stale.end == session.samples.last?.t)
    let saved = session.finish(at: now.addingTimeInterval(150))
    #expect(saved)
    var short = ActivitySession(sport: .all[0], now: now, limits: limits)
    let tooShort = short.finish(at: now.addingTimeInterval(59))
    #expect(!tooShort)
    var capped = ActivitySession(sport: .all[0], now: now, limits: limits)
    let didCap = capped.enforceLimit(at: now.addingTimeInterval(13 * 3600))
    #expect(didCap)
    #expect(capped.elapsed(at: now.addingTimeInterval(13 * 3600)) == 12 * 3600)
    var older = try JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(session)) as! [String: Any]
    #expect(older["active_min"] as? Double == 60 && older["active_max"] as? Double == 12 * 3600)
    older["active_min"] = nil; older["active_max"] = nil
    let fromOlderBuild = try JSONCoding.decoder().decode(ActivitySession.self, from: JSONSerialization.data(withJSONObject: older))
    #expect(fromOlderBuild.activeMin == nil && fromOlderBuild.activeMax == nil)
}

private func oddLiveLimits() throws -> EditLimits {
    struct Body: Decodable { var editLimits: EditLimits }
    return try fixture("edits/odd_limits.json", as: Body.self).editLimits
}

@Test func liveSessionKeepsInsideTheMacsLength() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let limits = try oddLiveLimits()
    #expect(limits.activeMinMinutes == 5 && limits.activeMaxMinutes == 150)
    var short = ActivitySession(sport: .all[0], now: start, limits: limits)
    let shortSaves = short.finish(at: start.addingTimeInterval(299))
    #expect(!shortSaves)
    var enough = ActivitySession(sport: .all[0], now: start, limits: limits)
    let enoughSaves = enough.finish(at: start.addingTimeInterval(300))
    #expect(enoughSaves)
    let running = ActivitySession(sport: .all[0], now: start, limits: limits)
    #expect(!running.limitReached(at: start.addingTimeInterval(150 * 60 - 1)))
    #expect(running.limitReached(at: start.addingTimeInterval(150 * 60)))
    var paused = ActivitySession(sport: .all[0], now: start, limits: limits)
    paused.pause(at: start.addingTimeInterval(20 * 60))
    paused.resume(at: start.addingTimeInterval(30 * 60))
    #expect(!paused.limitReached(at: start.addingTimeInterval(159 * 60)))
    let enforced = paused.enforceLimit(at: start.addingTimeInterval(175 * 60))
    #expect(enforced)
    #expect(paused.state == .ended)
    #expect(paused.end == start.addingTimeInterval(160 * 60))
    #expect(paused.elapsed(at: start.addingTimeInterval(175 * 60)) == 9000)
    var held = ActivitySession(sport: .all[0], now: start, limits: limits)
    held.pause(at: start.addingTimeInterval(60 * 60))
    #expect(!held.limitReached(at: start.addingTimeInterval(5 * 3600)))
    let heldSaves = held.finish(at: start.addingTimeInterval(5 * 3600))
    #expect(heldSaves)
    #expect(held.end == start.addingTimeInterval(5 * 3600) && held.elapsed(at: start.addingTimeInterval(5 * 3600)) == 3600)
}

@Test func liveSessionWithoutLimits() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var second = ActivitySession(sport: .all[0], now: start)
    #expect(second.activeMin == nil && second.activeMax == nil)
    let secondSaves = second.finish(at: start.addingTimeInterval(1))
    #expect(secondSaves)
    var instant = ActivitySession(sport: .all[0], now: start)
    let instantSaves = instant.finish(at: start.addingTimeInterval(0.6))
    #expect(!instantSaves)
    let running = ActivitySession(sport: .all[0], now: start)
    #expect(!running.limitReached(at: start.addingTimeInterval(ActivitySession.recordingSpan - 1)))
    #expect(running.limitReached(at: start.addingTimeInterval(ActivitySession.recordingSpan)))
}

@Test func liveSessionTimesAreWholeSeconds() throws {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    var session = ActivitySession(sport: .all[0], now: t.addingTimeInterval(0.7))
    #expect(session.start == t)
    session.pause(at: t.addingTimeInterval(10.4))
    session.resume(at: t.addingTimeInterval(20.9))
    #expect(session.pauses == [ActivityPause(start: t.addingTimeInterval(10), end: t.addingTimeInterval(20))])
    session.finish(at: t.addingTimeInterval(95.5))
    #expect(session.end == t.addingTimeInterval(95))
    let upload = try JSONCoding.decoder().decode(ActivityUpload.self, from: JSONCoding.encoder().encode(LiveEstimator(restingHR: nil, maximumHR: nil, model: nil).localActivity(session, now: t.addingTimeInterval(96)).upload))
    let active = upload.end.timeIntervalSince(upload.start) - upload.pauses.reduce(0) { $0 + ($1.end ?? upload.end).timeIntervalSince($1.start) }
    #expect(active == session.elapsed(at: t.addingTimeInterval(96)))
    #expect(active == 85)
}

@Test func unreadSessionCannotBeOverwritten() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let saved = ActivitySession(sport: .all[0], now: now)
    let store = ActivityStore(directory: directory)
    try await store.saveSession(saved, now: now)
    let file = directory.appendingPathComponent("live-session.json")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    do {
        _ = try await store.restoreSession(now: now)
        Issue.record("Unread session restored")
    } catch {
        #expect((error as NSError).domain == NSCocoaErrorDomain)
        #expect((error as NSError).code == 257)
        let failure = SavedDataError(error, area: .activities)
        #expect(failure.message(protectedDataAvailable: false) == nil)
        #expect(failure.message(protectedDataAvailable: true) == "ghoops couldn't read its saved activities on this phone. It will try again.")
    }
    await #expect(throws: (any Error).self) {
        _ = try await store.startSession(ActivitySession(sport: .all[1], now: now), now: now)
    }
    await #expect(throws: (any Error).self) {
        try await store.saveSession(ActivitySession(sport: .all[1], now: now), now: now)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #expect(try await store.restoreSession(now: now)?.id == saved.id)
    #expect(try await store.startSession(ActivitySession(sport: .all[1], now: now), now: now).id == saved.id)
}

@Test func unreadActivitiesRefuseSaveAndDeleteThenRecover() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let upload: ActivityUpload = try fixture("activities/valid.json")
    let store = ActivityStore(directory: directory)
    let saved = LocalActivity(upload: upload)
    try await store.save(saved, now: upload.end)
    let file = directory.appendingPathComponent("activities-local.json")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    await #expect(throws: CocoaError.self) { try await store.save(saved, now: upload.end) }
    await #expect(throws: CocoaError.self) { try await store.delete(id: saved.id, now: upload.end) }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #expect(try await store.activities(now: upload.end).map(\.id) == [saved.id])
}

@MainActor @Test(arguments: ["activities-local.json", "live-session.json"])
func activityLaunchReadRecoversWithoutLosingSession(_ name: String) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let upload: ActivityUpload = try fixture("activities/valid.json")
    let store = ActivityStore(directory: directory)
    let session = ActivitySession(sport: .all[0], now: upload.end)
    try await store.save(LocalActivity(upload: upload), now: upload.end)
    try await store.saveSession(session, now: upload.end)
    let state = ActivityPersistence(store: store)
    let file = directory.appendingPathComponent(name)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    #expect(!(await state.restore(now: upload.end, protectedDataAvailable: false)))
    #expect(state.error == nil)
    #expect(!(await state.start(ActivitySession(sport: .all[1], now: upload.end), now: upload.end, protectedDataAvailable: true)))
    #expect(state.error == "ghoops couldn't read its saved activities on this phone. It will try again.")
    #expect(state.session == nil)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #expect(await state.restore(now: upload.end, protectedDataAvailable: true))
    #expect(state.error == nil)
    #expect(state.local.map(\.id) == [upload.id])
    #expect(state.session?.id == session.id)
    #expect(await state.start(ActivitySession(sport: .all[1], now: upload.end), now: upload.end, protectedDataAvailable: true))
    #expect(state.session?.id == session.id)
    #expect(try await store.restoreSession(now: upload.end)?.id == session.id)
}

@Test func liveEstimatorMatchesAllGoVectorsAndScale() throws {
    struct Vectors: Decodable {
        struct Case: Decodable {
            struct Input: Decodable { var restingHr: Double; var maxHr: Double; var minuteAvgBpm: [Double] }
            struct Expected: Decodable { var trimp: Double; var strain: Double?; var zonesMinutes: Zones }
            var name: String; var input: Input; var expected: Expected
        }
        struct Scale: Decodable { var trimp: Double; var strain: Double }
        var cases: [Case]; var trimpToStrain: [Scale]
    }
    let vectors = try fixture("scores/strain.json", as: Vectors.self)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for c in vectors.cases {
        var s = ActivitySession(sport: .all[0], now: start)
        for (i, bpm) in c.input.minuteAvgBpm.enumerated() { s.append(.init(t: start.addingTimeInterval(Double(i * 60)), bpm: bpm)) }
        let estimate = LiveEstimator(restingHR: c.input.restingHr, maximumHR: c.input.maxHr, model: try engineConstants().strain).estimate(s, now: start.addingTimeInterval(Double(c.input.minuteAvgBpm.count * 60)))
        #expect(estimate.strain == c.expected.strain, "\(c.name)")
        #expect((estimate.trimp ?? 0) == c.expected.trimp, "\(c.name)")
        let actual = try JSONCoding.encoder().encode(estimate.wholeZones)
        let expected = try JSONCoding.encoder().encode(c.expected.zonesMinutes)
        #expect(try JSONSerialization.jsonObject(with: actual) as? NSDictionary == JSONSerialization.jsonObject(with: expected) as? NSDictionary)
    }
    for c in vectors.trimpToStrain { #expect(abs(StrainMath.strain(trimp: c.trimp, scale: try engineConstants().strain.scale) - c.strain) <= 0.1) }
}

@Test func liveZonesPartialBucketPauseAndMissingRates() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let engine = LiveEstimator(restingHR: 56, maximumHR: 187, model: try engineConstants().strain)
    #expect((0...5).map { engine.range(zone: $0) } == ["<96", "96–121", "122–134", "135–147", "148–167", "168+"])
    var s = ActivitySession(sport: .all[0], now: start)
    s.append(.init(t: start, bpm: 158))
    let half = engine.estimate(s, now: start.addingTimeInterval(30))
    #expect(half.zones[4] == 0.5)
    s.pause(at: start.addingTimeInterval(30))
    s.append(.init(t: start.addingTimeInterval(40), bpm: 180))
    let paused = engine.estimate(s, now: start.addingTimeInterval(50))
    #expect(paused.strain == half.strain)
    #expect(paused.maximum == 158)
    let missing = LiveEstimator(restingHR: nil, maximumHR: nil, model: nil).estimate(s, now: start.addingTimeInterval(50))
    #expect(missing.strain == nil && missing.zone == nil)
    #expect(missing.average == 158)
}

private actor ActivityAPIStub: ActivityAPI {
    var error: ClientError?
    init(error: ClientError?) { self.error = error }
    func postActivity(_ activity: ActivityUpload) async throws -> ActivityRecord {
        if let error { throw error }
        var body = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(activity)) as? [String: Any])
        body["created_at"] = ISO8601DateFormatter().string(from: activity.end)
        return try JSONCoding.decoder().decode(ActivityRecord.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func deleteActivity(id: String) async throws {}
}

@Test(arguments: [nil, ClientError.http(409), .http(400), .http(403), .unauthorized, .offline, .http(503)])
func activityQueuePersistsUploadResults(_ error: ClientError?) async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let upload = try JSONCoding.decoder().decode(ActivityUpload.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("activities/valid.json")))
    let store = ActivityStore(directory: dir)
    let mac = PairedMac(url: "https://fixture.invalid", name: "Fixture Mac")
    try await store.save(LocalActivity(upload: upload, mac: mac), now: upload.end)
    await store.bind(mac, api: ActivityAPIStub(error: error))
    let failed = try await store.retry(now: upload.end)
    var entries = try await store.activities(now: upload.end)
    let expected: ActivityUploadState = error == nil || error == .http(409) ? .uploaded : error == .http(400) || error == .http(403) ? .rejected : .pending
    #expect(entries.first?.uploadState == expected)
    #expect(failed == (expected == .pending && error != .unauthorized))
    if expected == .pending {
        await store.bind(mac, api: ActivityAPIStub(error: nil))
        _ = try await store.retry(now: upload.end)
    }
    entries = try await store.activities(now: upload.end.addingTimeInterval(8 * 86400))
    #expect(entries.count == (expected == .rejected ? 1 : 0))
}

private actor DelayedActivityAPI: ActivityAPI {
    private var posting: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false
    private(set) var remote = Set<String>()
    private(set) var calls: [String] = []
    func waitForPost() async {
        if didStart { return }
        await withCheckedContinuation { started = $0 }
    }
    func releasePost() { posting?.resume(); posting = nil }
    func postActivity(_ activity: ActivityUpload) async throws -> ActivityRecord {
        calls.append("post")
        await withCheckedContinuation {
            posting = $0; didStart = true; started?.resume(); started = nil
        }
        remote.insert(activity.id)
        return try await ActivityAPIStub(error: nil).postActivity(activity)
    }
    func deleteActivity(id: String) async throws {
        calls.append("delete"); remote.remove(id)
    }
}

@Test func deletingDuringUploadRemovesPhoneAndMacEntry() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let upload = try JSONCoding.decoder().decode(ActivityUpload.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("activities/valid.json")))
    let store = ActivityStore(directory: dir)
    let api = DelayedActivityAPI()
    let mac = PairedMac(url: "https://fixture.invalid", name: "Fixture Mac")
    try await store.save(LocalActivity(upload: upload, mac: mac), now: upload.end)
    await store.bind(mac, api: api)
    let retry = Task { try await store.retry(now: upload.end) }
    await api.waitForPost()
    let removal = Task { try await store.deleteOnMac(id: upload.id, now: upload.end) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(await api.calls == ["post"])
    await api.releasePost()
    _ = try await retry.value
    try await removal.value
    #expect(try await store.activities(now: upload.end).isEmpty)
    #expect(await api.remote.isEmpty)
    #expect(await api.calls == ["post", "delete"])
}
