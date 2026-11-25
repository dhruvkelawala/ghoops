import Testing
@testable import GHealthCore

@Test func compositeBodiesKeepTheMacsValues() throws {
    let day: Day = try fixture("composite/day_full.json")
    let sleep: Sleep = try fixture("composite/sleep_full.json")
    let snapshot: Snapshot = try fixture("composite/snapshot.json")
    let days: Days = try fixture("composite/days_full.json")
    let version = try #require(day.scoreVersion)
    #expect(version == sleep.scoreVersion && version == snapshot.scoreVersion && version == days.scoreVersion)
    #expect(day.scoreConfig?.sleepScoreMode == "composite")
    #expect(sleep.performanceComposite?.parts?.efficiency == 100)
    #expect(snapshot.day.sleep.performanceComposite?.value == 94)
    #expect(snapshot.sleep.performanceComposite?.value == 94)
    #expect(snapshot.sleep.scoreConstants?.sleep.composite?.weights.efficiency == 0.15)
    #expect(snapshot.sleep.scoreConstants?.sleep.composite?.efficiencyFullPct == 90)
    let score = SleepScore(day)
    #expect(day.comparison?.metrics[score.comparisonKey]?.mean == 93.9)
    let row = try #require(days.days.first)
    #expect(SleepScore.rowValue(row, composite: true) == 98)
    #expect(SleepScore.rowValue(row, composite: false) == 99)
    let empty = try #require(days.days.first { $0.date == "2026-03-05" })
    #expect(SleepScore.rowValue(empty, composite: true) == nil)
}

@Test func sleepScoreSelectsTheDialAndComparisonTogether() throws {
    var composite = try compositeNight("odd_time_poor_efficiency")
    var day: Day = try fixture("composite/day_full.json")
    day.sleep.performanceComposite = composite.performanceComposite
    for score in [SleepScore(composite), SleepScore(day)] {
        #expect(score.performance.value == 84 && score.performance.band == .medium)
        #expect(score.comparisonKey == "sleep_performance_composite")
    }
    composite.scoreConfig?.sleepScoreMode = nil
    day.sleep.performanceComposite = nil
    for score in [SleepScore(composite), SleepScore(day)] {
        #expect(score.performance.value == 94 && score.performance.band == .high)
        #expect(score.comparisonKey == "sleep_performance")
    }
    let pending = try compositeNight("no_sleep_today")
    let score = SleepScore(pending)
    #expect(score.isComposite && score.performance.value == nil)
    #expect(score.performance.status == .pending && score.performance.reason == .noSleep)
}

@Test(arguments: [
    (false, false, ""),
    (true, false, " Irregular bed and wake times lowered it."),
    (false, true, " Time awake in bed lowered it."),
    (true, true, " Irregular bed and wake times and time awake in bed lowered it.")
])
func compositeInsightUsesEachReportedBand(consistencyLow: Bool, efficiencyLow: Bool, ending: String) throws {
    var sleep = try compositeNight("odd_time_poor_efficiency")
    sleep.asleepMinutes = 444
    sleep.need.totalMinutes = 472
    sleep.need.debtExtraMinutes = 0
    sleep.need.strainExtraMinutes = 0
    sleep.consistency.band = consistencyLow ? .low : .medium
    sleep.efficiencyBand = efficiencyLow ? .low : .medium
    let intro = "Your Sleep Performance is sufficient. "
    #expect(Insights.sleep(sleep) == intro + "You got 7:24 of the 7:52 you needed." + ending)
    var sufficiency = sleep
    sufficiency.scoreConfig?.sleepScoreMode = nil
    #expect(Insights.sleep(sufficiency) == "Your Sleep Performance is optimal. You got 7:24 of the 7:52 you needed.")
    sleep.performance.band = .medium
    #expect(Insights.sleep(sleep) == intro + "You were 0:28 short of the 7:52 you needed." + ending)
}

@Test func compositeBreakdownShowsTheNightsSharesAndReportedTotal() throws {
    var sleep = try compositeNight("odd_time_poor_efficiency")
    let breakdown = try #require(SleepScore.breakdown(sleep))
    #expect(breakdown.lines.map(\.label) == ["Hours vs. needed", "Consistency", "Efficiency"])
    #expect(breakdown.lines.map(\.note) == ["94% · 70% weight", "52% · 15% weight", "84% · scores 70 · 15% weight"])
    #expect(breakdown.lines.map(\.value) == ["+65.8", "+7.8", "+10.5"])
    #expect(breakdown.total == "84%")
    let defaultBody: Sleep = try fixture("sleep_full.json")
    #expect(SleepScore.breakdown(defaultBody) == nil)

    sleep = try compositeNight("no_consistency")
    let partial = try #require(SleepScore.breakdown(sleep))
    #expect(partial.lines.map(\.note) == ["94% · 85% weight", "Not available · share moved to hours", "88% · scores 90 · 15% weight"])
    #expect(partial.lines.map(\.value) == ["+79.9", "—", "+13.5"])
    #expect(partial.total == "93%")

    let noSleep = try compositeNight("no_sleep")
    let empty = try #require(SleepScore.breakdown(noSleep))
    #expect(empty.lines.map(\.value) == ["—", "—", "—"] && empty.total == "—")
    let pending = try #require(SleepScore.breakdown(sleep, pending: true))
    #expect(pending.lines.map(\.value) == ["—", "—", "—"] && pending.total == "—")
}

@Test func compositeBreakdownUsesTheMacsRules() throws {
    var sleep = try compositeNight("odd_time_poor_efficiency")
    sleep.scoreConstants?.sleep.composite?.efficiencyZeroPct = 71
    sleep.scoreConstants?.sleep.composite?.efficiencyFullPct = 93
    let changed = try #require(SleepScore.breakdown(sleep))
    #expect(changed.rule == "Efficiency scores nothing at 71% and full marks from 93%. The total is rounded to a whole percent.")
    sleep.scoreConstants?.sleep.composite = nil
    let unknown = try #require(SleepScore.breakdown(sleep))
    #expect(unknown.rule == nil && unknown.lines.map(\.value) == ["—", "—", "—"])
    #expect(unknown.total == "84%")
}

private func compositeNight(_ name: String) throws -> Sleep {
    struct Vectors: Decodable {
        struct Night: Decodable {
            struct Input: Decodable { let efficiencyPct: Int? }
            let name: String
            let input: Input
            let expected: SleepComposite
        }
        let cases: [Night]
    }
    let vectors: Vectors = try fixture("scores/sleep_composite.json")
    let night = try #require(vectors.cases.first { $0.name == name })
    var sleep: Sleep = try fixture("composite/sleep_full.json")
    sleep.performanceComposite = night.expected
    sleep.efficiencyPct = night.input.efficiencyPct
    return sleep
}
