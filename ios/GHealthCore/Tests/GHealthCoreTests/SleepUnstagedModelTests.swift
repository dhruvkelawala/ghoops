import Foundation
import Testing
@testable import GHealthCore

@Test func unstagedSleepDecodesAndRoundTrips() throws {
    let sleep: Sleep = try fixture("sleep_unstaged.json")
    #expect(sleep.stages?.unstaged?.minutes == 72)
    #expect(sleep.stages?.unstaged?.segments == 1)
    #expect(sleep.stages?.unstaged?.pctOfAsleep == 14.8)
    #expect(sleep.scoreConstants?.sleep.unstagedCountsAs == "asleep")
    let span = try #require(sleep.hypnogram?.unstaged.first)
    #expect(GoopFormat.time(span.start) == "06:29" && GoopFormat.time(span.end) == "07:41")
    #expect(span.end.timeIntervalSince(span.start) == 72 * 60)
    let copy = try JSONCoding.decoder().decode(Sleep.self, from: JSONCoding.encoder().encode(sleep))
    #expect(copy.stages?.unstaged?.minutes == 72)
    #expect(copy.hypnogram?.unstaged.count == 1)
    #expect(copy.scoreConstants?.sleep.unstagedCountsAs == "asleep")
    let day: Day = try fixture("day_unstaged.json")
    #expect(day.sleep.stages?.unstaged?.minutes == 72)
}

@Test func olderMacOmitsUnstagedSleep() throws {
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("sleep_full.json"))) as? [String: Any])
    object["score_version"] = "2.2.0"
    var stages = try #require(object["stages"] as? [String: Any])
    stages.removeValue(forKey: "unstaged")
    object["stages"] = stages
    var hypnogram = try #require(object["hypnogram"] as? [String: Any])
    hypnogram.removeValue(forKey: "unstaged")
    object["hypnogram"] = hypnogram
    var constants = try #require(object["score_constants"] as? [String: Any])
    var sleepConstants = try #require(constants["sleep"] as? [String: Any])
    sleepConstants.removeValue(forKey: "unstaged_counts_as")
    constants["sleep"] = sleepConstants
    object["score_constants"] = constants
    let sleep = try JSONCoding.decoder().decode(Sleep.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(sleep.scoreVersion == "2.2.0")
    #expect(sleep.stages?.unstaged == nil)
    #expect(sleep.hypnogram?.unstaged.isEmpty == true)
    #expect(sleep.scoreConstants?.sleep.unstagedCountsAs == nil)
    #expect(sleep.asleepMinutes == 415 && sleep.hypnogram?.segments.count == 22)
}
