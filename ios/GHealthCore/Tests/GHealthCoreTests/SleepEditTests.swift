import Foundation
import Testing
@testable import GHealthCore

@Suite struct SleepEditTests {
    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func draft(_ name: String = "full") throws -> SleepEditDraft {
        let sleep: Sleep = try fixture(name == "full" ? "sleep_full.json" : "sleep_edit/sleep_\(name).json")
        let status: Status = try fixture("status_full.json")
        return try #require(SleepEditDraft(sleep: sleep, limits: status.editLimits, now: at("2026-03-10T14:30:00Z")))
    }
    func equal(_ got: SleepWindowValues, _ expected: SleepWindowValues) {
        #expect(got.timeInBedMinutes == expected.timeInBedMinutes)
        #expect(got.asleepMinutes == expected.asleepMinutes)
        #expect(got.efficiencyPct == expected.efficiencyPct)
        #expect(got.minutesToFallAsleep == expected.minutesToFallAsleep)
        #expect(got.awakeSegments == expected.awakeSegments)
        for (a, b) in zip([got.stages.light, got.stages.deep, got.stages.rem, got.stages.awake, got.stages.unstaged],
                          [expected.stages.light, expected.stages.deep, expected.stages.rem, expected.stages.awake, expected.stages.unstaged]) {
            #expect(a?.minutes == b?.minutes && a?.segments == b?.segments && a?.pctOfAsleep == b?.pctOfAsleep)
        }
        #expect(got.unstaged.map(\.start) == expected.unstaged.map(\.start))
        #expect(got.unstaged.map(\.end) == expected.unstaged.map(\.end))
    }
    @Test func ruleMatchesTheMac() throws {
        struct Pack: Decodable {
            struct Case: Decodable {
                struct Input: Decodable { var google: SleepGoogle; var segments: [SleepSegment]; var window: ActivityWindow }
                var name: String; var input: Input; var expected: SleepWindowValues
            }
            var cases: [Case]
        }
        let pack: Pack = try fixture("sleep_edit/rule_cases.json")
        #expect(pack.cases.count == 16)
        for test in pack.cases {
            equal(SleepWindowRule.values(google: test.input.google, segments: test.input.segments, window: test.input.window), test.expected)
        }
        var shortened = try draft("shortened")
        #expect(shortened.segments.count == 22)
        shortened.window = shortened.google.window
        #expect(shortened.values.asleepMinutes == 415)
        #expect(shortened.values.stages.light.segments == 9)
        shortened.moveEnd(to: at("2026-03-10T05:40:00Z"))
        #expect(shortened.values.stages.light.segments == 8)
    }
    @Test func boundsStopAtTheMacsRange() throws {
        var d = try draft()
        d.moveStart(to: .distantPast)
        #expect(d.window.start == d.bounds.range.earliestStart)
        d.moveEnd(to: .distantFuture)
        #expect(d.window.end == d.bounds.range.latestEnd)
        d = try draft(); d.moveStart(to: .distantFuture)
        #expect(d.window.start == at("2026-03-10T05:29:00Z"))
        d = try draft(); d.moveEnd(to: .distantPast)
        #expect(d.window.end == at("2026-03-10T00:12:00Z"))
        let bounds = SleepEditBounds(range: SleepEditRange(earliestStart: at("2026-03-09T20:12:00Z"), latestEnd: at("2026-03-10T09:29:00Z")), minimumMinutes: 60,
                                     google: d.google.window, current: d.google.window, now: at("2026-03-10T07:00:00Z"))
        #expect(bounds.endRange(start: d.google.start).upperBound == at("2026-03-10T07:00:00Z"))
        #expect(bounds.startRange(end: at("2026-03-10T09:00:00Z")).upperBound == d.google.end.addingTimeInterval(-60))
        #expect(bounds.endRange(start: at("2026-03-09T20:12:00Z")).lowerBound == d.google.start.addingTimeInterval(60))
    }
    @Test func boundsNeverTrap() throws {
        let d = try draft()
        for (start, end, now) in [("2026-03-10T08:00:00Z", "2026-03-10T08:20:00Z", "2026-03-10T07:00:00Z"),
                                  ("2026-03-10T06:00:00Z", "2026-03-10T06:20:00Z", "2026-03-10T07:00:00Z")] {
            let b = SleepEditBounds(range: SleepEditRange(earliestStart: at(start), latestEnd: at(end)), minimumMinutes: 60, google: d.google.window, current: d.window, now: at(now))
            #expect(b.startRange(end: d.window.end) == d.window.start...d.window.start)
            #expect(b.endRange(start: at(start)) == d.window.end...d.window.end)
        }
    }
    @Test func noSheetWithoutLimits() throws {
        let d = try draft(); let status: Status = try fixture("status_full.json")
        var limits = status.editLimits
        limits?.sleepMinMinutes = nil
        #expect(SleepEditDraft(sleep: d.sleep, limits: limits, now: .now) == nil)
        var sleep = d.sleep; sleep.session?.editRange = nil
        #expect(SleepEditDraft(sleep: sleep, limits: status.editLimits, now: .now) == nil)
    }
    @Test func draftPrecondition() throws {
        for state in ["full", "extended"] {
            let d = try draft(state)
            let raw = try JSONCoding.encoder().encode(d.body)
            let object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            if state == "full" { #expect(object["if_updated_at"] is NSNull) }
            else { #expect(d.body.ifUpdatedAt == d.sleep.session?.edit?.updatedAt) }
        }
    }
    @Test func sleepChangeLifecycle() async throws {
        var d = try draft(); d.moveEnd(to: at("2026-03-10T07:41:00Z"))
        let change = ChangeBuilder.sleep(d, serverURL: "https://fixture.invalid", now: d.sleep.generatedAt)
        #expect(change.targets == ["sleep-2026-03-10"])
        #expect(change.cycleDates == ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12", "2026-03-13"])
        #expect(change.sleepPatch?.updating == ["2026-03-09", "2026-03-10"])
        let sleep = Overlay.apply([change], to: d.sleep)
        #expect(sleep.asleepMinutes == 487 && sleep.efficiencyPct == 96)
        #expect(sleep.performance.value == d.sleep.performance.value)
        #expect(sleep.disturbances?.total == d.sleep.disturbances?.total)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: change.serverURL)
        try await queue.load(); try await queue.submit(change)
        let reloaded = try await ChangeQueue(directory: directory, serverURL: change.serverURL).load()
        #expect(reloaded.first?.sleepPatch?.values.asleepMinutes == 487)
        let pack = directory.appendingPathComponent("Fixtures")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        for name in ["sleep_full.json", "day_unstaged.json", "sleep_edit", "snapshot_fresh.json"] {
            let source = fixtureRoot.appendingPathComponent(name == "snapshot_fresh.json" ? "preview/" + name : name)
            try FileManager.default.createSymbolicLink(at: pack.appendingPathComponent(name), withDestinationURL: source)
        }
        let api = FixtureEditAPI(directory: pack, state: "unedited", mutationMode: .reject(.notFound), sleepEditing: true)
        let refused = try await queue.drain(api: api, uploads: {})
        #expect(refused.changes.isEmpty)
        #expect(refused.rollbacks.first?.text == "Your sleep on Tue 10 Mar changed on your Mac. It's back as it was.")
        await api.setMutationMode(.answer)
        try await queue.submit(change)
        let accepted = try await queue.drain(api: api, uploads: {})
        #expect(accepted.changes.first?.state == .accepted)
        #expect(try await api.snapshot().sleep.asleepMinutes == 487)
        try await queue.settle(acceptedBefore: .distantFuture)
        #expect(await queue.changes.isEmpty)
        let restore = ChangeBuilder.sleep(try draft("extended"), restore: true, serverURL: change.serverURL, now: .now)
        try await queue.submit(restore)
        _ = try await queue.drain(api: api, uploads: {})
        #expect(try await api.snapshot().sleep.session?.edit == nil)
        try await queue.settle(acceptedBefore: .distantFuture)
        try await queue.submit(restore)
        let replay = try await queue.drain(api: api, uploads: {})
        #expect(replay.changes.first?.state == .accepted)
    }
    @Test func olderMacDecodes() throws {
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("sleep_full.json"))) as? [String: Any])
        object["score_version"] = "2.2.0"
        var session = try #require(object["session"] as? [String: Any])
        for key in ["google", "edit", "edit_range"] { session.removeValue(forKey: key) }
        object["session"] = session
        var h = try #require(object["hypnogram"] as? [String: Any]); h.removeValue(forKey: "outside"); object["hypnogram"] = h
        let sleep = try JSONCoding.decoder().decode(Sleep.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(sleep.session?.google == nil && sleep.session?.edit == nil && sleep.session?.editRange == nil && sleep.hypnogram?.outside == nil)
        #expect(sleep.asleepMinutes == 415)
    }
}
