import Foundation
import Testing
@testable import GHealthCore

let fixtureRoot: URL = {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: url.appendingPathComponent("fixtures/v2/README.md").path) {
        precondition(url.path != "/", "Repository fixtures not found")
        url.deleteLastPathComponent()
    }
    return url.appendingPathComponent("fixtures/v2")
}()

let responseFixtures: [URL] = {
    let walker = FileManager.default.enumerator(at: fixtureRoot, includingPropertiesForKeys: nil)!
    return walker.compactMap { $0 as? URL }.filter { url in
        url.pathExtension == "json"
            && !["inputs", "scores", "activities", "live", "requests", "recovery", "engine"].contains { url.path.contains("/\($0)/") }
            && !url.lastPathComponent.hasPrefix("book_")
            && url.lastPathComponent != "preview_parity.json"
            && !["limit_cases.json", "odd_limits.json", "rule_cases.json"].contains(url.lastPathComponent)
    }.sorted { $0.path < $1.path }
}()

func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    try JSONCoding.decoder().decode(type, from: Data(contentsOf: fixtureRoot.appendingPathComponent(name)))
}

@Test(arguments: responseFixtures)
func everyContractFixtureDecodes(_ url: URL) throws {
    let data = try Data(contentsOf: url)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    func roundTrip<T: Codable>(_ type: T.Type) throws {
        let body = try JSONCoding.decoder().decode(type, from: data)
        _ = try JSONCoding.decoder().decode(type, from: JSONCoding.encoder().encode(body))
    }
    switch object["kind"] as? String {
    case "day": try roundTrip(Day.self)
    case "sleep": try roundTrip(Sleep.self)
    case "days": try roundTrip(Days.self)
    case "workouts": try roundTrip(Workouts.self)
    case "heart_rate": try roundTrip(HeartRateBody.self)
    case "status": try roundTrip(Status.self)
    case "snapshot": try roundTrip(Snapshot.self)
    case "brief": try roundTrip(Brief.self)
    case "collect": try roundTrip(Collect.self)
    case "pair": try roundTrip(PairResponse.self)
    case "schedule": try roundTrip(Schedule.self)
    case "config": try roundTrip(Config.self)
    case "export": try roundTrip(Export.self)
    case "error": try roundTrip(APIError.self)
    case "journal": try roundTrip(Journal.self)
    case "week": try roundTrip(Week.self)
    default: Issue.record("Unknown fixture kind: \(url.lastPathComponent)")
    }
}

@Test func roundTripPreservesSnapshotValues() throws {
    let body: Snapshot = try fixture("preview/snapshot_fresh.json")
    let copy = try JSONCoding.decoder().decode(Snapshot.self, from: JSONCoding.encoder().encode(body))
    #expect(copy.day.recovery.value == 73)
    #expect(copy.day.strain.value == 12.8)
    #expect(copy.sleep.hypnogram?.segments.count == body.sleep.hypnogram?.segments.count)
    #expect(copy.days.days.count == 30)
    #expect(copy.sleep.hypnogram?.segments.isEmpty == false)
}

@Test func additiveEvolutionAndMissingArrays() throws {
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("day_full.json"))) as? [String: Any])
    object["future_key"] = ["anything": true]
    var recovery = try #require(object["recovery"] as? [String: Any])
    recovery["status"] = "future_status"
    object["recovery"] = recovery
    object.removeValue(forKey: "workouts")
    let day = try JSONCoding.decoder().decode(Day.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(day.recovery.status == .unknown("future_status"))
    #expect(day.workouts.isEmpty)
}

@Test func acceptsFractionalProviderTimes() throws {
    let date = try JSONCoding.decoder().decode(Date.self, from: Data("\"2026-03-10T06:29:35.600Z\"".utf8))
    #expect(abs(date.timeIntervalSince1970 - 1773124175.6) < 0.001)
}

@Test func goopFieldsDecodeAndRoundTrip() throws {
    let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    #expect(snapshot.day.comparison?.metrics["hrv_rmssd_ms"]?.mean != nil)
    #expect(snapshot.sleep.stageTypical?.light.lowMinutes == 196)
    #expect(snapshot.day.sleep.stageTypical?.light.lowMinutes == 196)
    let row = try #require(snapshot.days.days.last)
    #expect(row.zones13Minutes == 27)
    #expect(row.zones45Minutes == 33)
    #expect(row.strengthMinutes == 0)
    #expect(row.restorativeMinutes == 201)
    #expect(row.sleepConsistency == 87)
    let copy = try JSONCoding.decoder().decode(Snapshot.self, from: JSONCoding.encoder().encode(snapshot))
    #expect(copy.days.days.last?.zones13Minutes == 27)
    #expect(copy.day.comparison?.metrics["hrv_rmssd_ms"]?.mean == snapshot.day.comparison?.metrics["hrv_rmssd_ms"]?.mean)
    let newUser: Day = try fixture("day_new_user.json")
    #expect(newUser.comparison?.metrics.values.allSatisfy { $0.mean == nil } == true)
}

@Test func olderServerOmitsGoopFields() throws {
    var day = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("day_full.json"))) as? [String: Any])
    day.removeValue(forKey: "comparison")
    day.removeValue(forKey: "strength_minutes")
    var sleep = try #require(day["sleep"] as? [String: Any])
    sleep.removeValue(forKey: "stage_typical")
    day["sleep"] = sleep
    let decoded = try JSONCoding.decoder().decode(Day.self, from: JSONSerialization.data(withJSONObject: day))
    #expect(decoded.comparison == nil)
    #expect(decoded.strengthMinutes == nil)
    #expect(decoded.sleep.stageTypical == nil)
}

@Test func journalKeepsSnakeCaseAnswerKeys() throws {
    let journal: Journal = try fixture("journal/journal_basic.json")
    #expect(journal.behaviours.map(\.key) == ["alcohol", "late_caffeine", "late_meal", "screen_in_bed", "stress"])
    #expect(journal.entry(on: "2026-03-09")?.answers == ["alcohol": false, "sauna": true])
    #expect(journal.entry(on: "2026-02-10")?.answers["late_meal"] == true)
    let copy = try JSONCoding.decoder().decode(Journal.self, from: JSONCoding.encoder().encode(journal))
    #expect(copy == journal)
    let body = String(decoding: try JSONCoding.encoder().encode(JournalBody(answers: ["late_caffeine": true], ifUpdatedAt: nil)), as: UTF8.self)
    #expect(body.contains("\"late_caffeine\":true") && body.contains("\"if_updated_at\":null"))
}

@Test func missingValuesBlankEveryBlock() throws {
    var snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    FixtureLoader.blankValueBlocks(&snapshot)
    let kickboxing = snapshot.day.workouts[0]
    #expect(kickboxing.id == "7000000000000000002" && kickboxing.strain == nil)
    #expect(snapshot.workouts.workouts.first { $0.id == kickboxing.id }?.strain == nil)
    #expect(snapshot.day.sleep.timeInBedMinutes == nil && snapshot.sleep.timeInBedMinutes == nil)
    #expect(snapshot.day.sleep.bedtime != nil && snapshot.day.sleep.wakeTime != nil)
    #expect(snapshot.day.strain.hrCoverage == nil && snapshot.day.strain.avgHrBpm == nil)
    let effort = try #require(snapshot.day.workouts.last)
    #expect(effort.id == "effort-2026-03-10T09:05:00Z" && effort.category == "detected" && effort.strain == nil)
    #expect(effort.end.timeIntervalSince(effort.start) == 35 * 60)
    #expect(snapshot.day.recovery.value == 73)
}
