import Foundation
import Testing
@testable import GHealthCore

@Suite(.serialized) struct GoopFormatTests {
    @Test func durationsAndSignedNeed() {
        for (minutes, expected) in [(0, "0:00"), (7, "0:07"), (59, "0:59"), (60, "1:00"), (415, "6:55"), (1440, "24:00")] {
            #expect(GoopFormat.duration(minutes) == expected)
        }
        #expect(GoopFormat.duration(nil) == "—")
        #expect(GoopFormat.signedDuration(6) == "+0:06")
        #expect(GoopFormat.signedDuration(28, credit: true) == "−0:28")
        #expect(GoopFormat.signedDuration(-28) == "−0:28")
        #expect(GoopFormat.signedDuration(0, credit: true) == "−0:00")
    }
    @Test func precisionGroupingAndMissing() {
        #expect(GoopFormat.temperature(0.2) == "+0.2")
        #expect(GoopFormat.temperature(-0.1) == "−0.1")
        #expect(GoopFormat.temperature(-0.01) == "+0.0")
        #expect(GoopFormat.temperature(0) == "+0.0")
        #expect(GoopFormat.number(6904, grouped: true) == "6,904")
        #expect(GoopFormat.number(56.5) == "57")
        #expect(GoopFormat.number(-56.5) == "-57")
        #expect(TrendMetricKey.hours.display(414.5) == "6:55")
        #expect(TrendMetricKey.strain.display(12.75) == "12.8")
        #expect(TrendMetricKey.sleepPerformance.display(93) == "93%")
        #expect(TrendMetricKey.hrv.display(nil) == "—")
    }
    @Test func londonTimesAndDatesRegardlessOfDeviceZone() throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        defer { NSTimeZone.default = previous }
        let winter = try JSONCoding.decoder().decode(Date.self, from: Data("\"2026-03-09T23:12:00Z\"".utf8))
        let summer = try JSONCoding.decoder().decode(Date.self, from: Data("\"2026-07-01T05:30:00Z\"".utf8))
        #expect(GoopFormat.time(winter) == "23:12")
        #expect(GoopFormat.time(summer) == "06:30")
        #expect(Format.time(summer) == "06:30")
        #expect(GoopFormat.dateControl("2026-03-10", defaultDate: "2026-03-10") == "TODAY")
        #expect(GoopFormat.dateControl("2026-03-09", defaultDate: "2026-03-10") == "MON 9 MAR")
        #expect(GoopFormat.range(from: "2026-03-04", to: "2026-03-10") == "MAR 4 - MAR 10, 26")
        #expect(GoopFormat.dateLabel("2026-09-01", format: "MMM") == "Sep")
        #expect(GoopFormat.addingDays(1, to: "2026-03-29") == "2026-03-30")
        #expect(GoopFormat.addingDays(1, to: "2026-10-25") == "2026-10-26")
    }
    @Test func comparisonsRoundBeforeChoosingDirectionAndColor() {
        #expect(GoopFormat.direction(56.4, mean: 56, metric: .hrv) == .equal)
        #expect(GoopFormat.direction(56.5, mean: 56, metric: .hrv) == .up)
        #expect(GoopFormat.direction(55.4, mean: 56, metric: .hrv) == .down)
        #expect(GoopFormat.direction(nil, mean: 56, metric: .hrv) == nil)
        #expect(GoopFormat.direction(56, mean: nil, metric: .hrv) == nil)
        for metric in TrendMetricKey.allCases {
            let up: GoopColorRole = metric == .restingHR ? .caution : [.respiratoryRate, .skinTemp].contains(metric) ? .neutral : .positive
            let down: GoopColorRole = metric == .restingHR ? .positive : [.respiratoryRate, .skinTemp].contains(metric) ? .neutral : .caution
            #expect(ComparisonDirection.up.color(for: metric) == up)
            #expect(ComparisonDirection.down.color(for: metric) == down)
            #expect(ComparisonDirection.equal.color(for: metric) == .neutral)
        }
    }
    @Test func everyMetricHasItsOwnIcon() {
        let icons = TrendMetricKey.allCases.map(\.icon)
        #expect(Set(icons).count == icons.count)
    }
}

struct GoopInsightTests {
    @Test(arguments: [
        (0.5, 0.5, "Your HRV is above baseline while your resting heart rate is higher than usual."),
        (0.5, 0.0, "Your HRV is above baseline and your resting heart rate is near baseline."),
        (0.5, -0.5, "Your HRV is above baseline and your resting heart rate is lower than usual."),
        (0.0, 0.5, "Your HRV is near baseline while your resting heart rate is higher than usual."),
        (0.0, 0.0, "Your HRV and resting heart rate are both near baseline."),
        (0.0, -0.5, "Your HRV is near baseline and your resting heart rate is lower than usual."),
        (-0.5, 0.5, "Your HRV is below baseline and your resting heart rate is higher than usual."),
        (-0.5, 0.0, "Your HRV is below baseline while your resting heart rate is near baseline."),
        (-0.5, -0.5, "Your HRV is below baseline while your resting heart rate is lower than usual.")
    ])
    func recoveryDirections(_ hrv: Double, _ rhr: Double, _ expected: String) throws {
        var day: Day = try fixture("day_full.json")
        day.recovery.components!.hrvZ = hrv
        day.recovery.components!.restingHrZ = rhr
        day.recovery.components!.respiratoryRatePenalty = 0
        day.recovery.components!.skinTempPenalty = 0
        day.recovery.calibrating = false
        day.recovery.band = .high
        #expect(Insights.recovery(day.recovery) == expected + " Recovery is high today.")
    }
    @Test func recoveryPenaltiesBandsAndCalibration() throws {
        var day: Day = try fixture("day_full.json")
        day.recovery.components!.hrvZ = 0
        day.recovery.components!.restingHrZ = 0
        day.recovery.components!.respiratoryRatePenalty = 2.25
        day.recovery.components!.skinTempPenalty = 1.5
        day.recovery.calibrating = true
        for band: Band3 in [.high, .medium, .low] {
            day.recovery.band = band
            #expect(Insights.recovery(day.recovery) == "Your HRV and resting heart rate are both near baseline. A raised breathing rate overnight took 2.3 points off. A raised skin temperature overnight took 1.5 points off. Recovery is \(band.rawValue) today. It is still calibrating.")
        }
        day.recovery.value = nil
        day.recovery.reason = .insufficientBaseline
        day.recovery.calibration.hrvValues = 3
        day.recovery.calibration.restingHrValues = 4
        #expect(Insights.recovery(day.recovery) == "Recovery is calibrating: 3 of 7 nights so far. It starts once ghoops has 7 nights of your HRV and resting heart rate.")
    }
    @Test(arguments: [
        (Reason.noSleep, "Waiting for last night's sleep."), (.sleepProcessing, "Fitbit is still processing your sleep."),
        (.noHrv, "Waiting for overnight HRV."), (.hrvConflict, "Conflicting HRV values."),
        (.noRestingHr, "Waiting for resting heart rate."), (.rhrConflict, "Conflicting resting heart rate values."),
        (.cycleNotStarted, "Your day starts when you wake."), (.noHeartRate, "No heart rate yet today."),
        (.restingHrUnknown, "No resting heart rate to measure strain."),
        (.maxHrUnknown, "Set your max heart rate: ghoops config set max_hr_override_bpm N."),
        (.noData, "Not available.")
    ])
    func nullScoreReasons(_ reason: Reason, _ expected: String) throws {
        var day: Day = try fixture("day_full.json")
        day.recovery.value = nil; day.recovery.reason = reason; day.recovery.status = .pending
        day.strain.value = nil; day.strain.reason = reason; day.strain.status = .pending
        #expect(Insights.recovery(day.recovery) == expected)
        #expect(Insights.strain(day.strain, workouts: [], isToday: true, constants: try engineConstants()) == expected)
    }
    @Test(arguments: [
        (StrainBand.light, "Strain under 10.0 is considered light."),
        (.moderate, "Strain between 10.0 and 13.9 is considered moderate."),
        (.strenuous, "Strain between 14.0 and 17.9 is considered strenuous."),
        (.allOut, "Strain of 18.0 or more is considered all out.")
    ])
    func strainBands(_ band: StrainBand, _ expected: String) throws {
        var day: Day = try fixture("day_full.json")
        day.strain.band = band; day.strain.hrCoverage = 0.8; day.strain.status = .ok
        #expect(Insights.strain(day.strain, workouts: [], isToday: true, constants: try engineConstants()) == expected)
    }
    @Test(arguments: [(5, "morning"), (11, "morning"), (12, "afternoon"), (16, "afternoon"), (17, "evening"), (21, "evening"), (22, "night"), (4, "night")])
    func strainWorkoutPartOfDayAndPastDate(_ hour: Int, _ part: String) throws {
        let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
        var workout = try #require(snapshot.workouts.workouts.first)
        workout.start = GoopFormat.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: snapshot.generatedAt)!
        workout.strain = 11; workout.kind = "recorded"; workout.category = "combat"; workout.displayName = "Boxing"
        for today in [true, false] {
            #expect(Insights.strain(snapshot.day.strain, workouts: [workout], isToday: today, constants: try engineConstants()).contains("Your heart worked hardest during boxing \(today ? "this" : "in the") \(part)."))
        }
        workout.kind = "detected"
        #expect(Insights.strain(snapshot.day.strain, workouts: [workout], isToday: true, constants: try engineConstants()).contains("during a detected effort"))
        workout.strain = 9.9
        #expect(!Insights.strain(snapshot.day.strain, workouts: [workout], isToday: true, constants: try engineConstants()).contains("hardest"))
    }
    @Test func strainHighestWorkoutCoverageAndProgress() throws {
        let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
        var strain = snapshot.day.strain
        strain.hrCoverage = 0.794; strain.confidence = .medium; strain.status = .inProgress
        var first = try #require(snapshot.workouts.workouts.first)
        first.strain = 10; first.displayName = "Walking"; first.kind = "recorded"; first.category = "walking"
        var second = first; second.strain = 14; second.displayName = "Boxing"
        let text = Insights.strain(strain, workouts: [first, second], isToday: true, constants: try engineConstants())
        #expect(text.contains("during boxing"))
        #expect(!text.contains("during walking"))
        #expect(text.hasSuffix("This is based on 79% of the day's heart rate. Strain keeps building until you sleep."))
    }
    @Test(arguments: [(93, "optimal", "You got 6:55 of the 7:23 you needed."), (75, "sufficient", "You were 0:28 short of the 7:23 you needed."), (60, "poor", "You were 0:28 short of the 7:23 you needed.")])
    func sleepLevelsAndNeedAdditions(_ performance: Int, _ level: String, _ sentence: String) throws {
        var sleep: Sleep = try fixture("sleep_full.json")
        sleep.performance.value = performance; sleep.performance.band = level == "optimal" ? .high : level == "sufficient" ? .medium : .low; sleep.asleepMinutes = 415; sleep.need.totalMinutes = 443
        sleep.need.debtExtraMinutes = 6; sleep.need.strainExtraMinutes = 17
        #expect(Insights.sleep(sleep) == "Your Sleep Performance is \(level). \(sentence) Recent short nights added 0:06 to your need. Yesterday's strain added 0:17.")
        sleep.need.debtExtraMinutes = 0; sleep.need.strainExtraMinutes = 0
        #expect(Insights.sleep(sleep) == "Your Sleep Performance is \(level). \(sentence)")
    }
    @Test func sleepShortfallOnlyWhenNeedIsUnmet() throws {
        var sleep: Sleep = try fixture("sleep_full.json")
        sleep.performance.band = .medium; sleep.asleepMinutes = 450; sleep.need.totalMinutes = 443
        sleep.need.debtExtraMinutes = 0; sleep.need.strainExtraMinutes = 0
        #expect(Insights.sleep(sleep) == "Your Sleep Performance is sufficient. You got 7:30 of the 7:23 you needed.")
    }
    @Test func pendingSleepEditHidesTheOldVerdict() throws {
        var sleep: Sleep = try fixture("sleep_full.json")
        sleep.performance.value = 94; sleep.performance.band = .high; sleep.asleepMinutes = 251
        let text = Insights.sleep(sleep, pending: true)
        #expect(text == "Your Sleep Performance will update once your Mac has the change to your sleep. You slept 4:11.")
        sleep.asleepMinutes = nil
        #expect(Insights.sleep(sleep, pending: true) == "Your Sleep Performance will update once your Mac has the change to your sleep.")
        let day: Day = try fixture("day_full.json")
        #expect(Insights.recovery(day.recovery, pending: true) == "Your Recovery will update once your Mac has the change to your sleep.")
        #expect(Insights.strain(day.strain, workouts: day.workouts, isToday: true, target: day.strainTarget, recoveryBand: .high, constants: day.scoreConstants, pending: true) == "Your Day Strain will update once your Mac has the change to your sleep.")
    }
    @Test func noMainSleep() throws {
        var sleep: Sleep = try fixture("sleep_no_sleep.json")
        sleep.need.totalMinutes = 443; sleep.performance.status = .pending
        #expect(Insights.sleep(sleep) == "Waiting for last night's sleep. Tonight's need so far is 7:23.")
    }
    @Test func trendSentencesAndAvailableSuffix() {
        #expect(Insights.trend(metric: .hrv, length: 7, available: 0, average: nil) == "No HRV data in these 7 days.")
        for (average, position) in [(50.0, "within"), (70, "above"), (30, "below"), (40, "within"), (60, "within")] {
            #expect(Insights.trend(metric: .hrv, length: 7, available: 6, average: average, range: 40...60) == "Your average HRV over these 7 days was \(position) its typical range (40 - 60). 6 of 7 days have data.")
        }
        #expect(Insights.trend(metric: .restingHR, length: 30, available: 30, average: 56) == "Your average resting heart rate over these 30 days was 56 bpm.")
        for position in ["within", "below", "above"] {
            let week = Insights.hrvWeek(position: position, days: 7)
            #expect(Insights.trend(metric: .hrv, length: 7, available: 6, average: 46, range: 41...61, week: week) == "Your 7-day HRV average is \(position) your usual range. 6 of 7 days have data.")
        }
        for position in [nil, "no_baseline", "future"] { #expect(Insights.hrvWeek(position: position, days: 7) == nil) }
        #expect(Insights.trend(metric: .hrv, length: 7, available: 7, average: 50, range: 40...60, week: nil) == "Your average HRV over these 7 days was within its typical range (40 - 60).")
        #expect(Insights.trend(metric: .hours, length: 180, available: 1, average: 415) == "Your average hours of sleep over these 180 days was 6:55. 1 of 180 days have data.")
    }
    @Test func levelsUseSentBands() {
        #expect(SleepLevel(.low) == .poor)
        #expect(SleepLevel(.medium) == .sufficient)
        #expect(SleepLevel(.high) == .optimal)
        #expect(SleepLevel(nil) == nil)
        #expect(SleepLevel(.unknown("future")) == nil)
    }
    @Test func healthStateFirstMatchAndSentences() throws {
        let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
        var vitals = snapshot.day.vitals
        for (state, kind, color): (String, HealthState.Kind, GoopColorRole) in [
            ("building", .building, .neutral), ("within", .within, .healthOK),
            ("outside", .outside, .neutral), ("attention", .attention, .caution),
            ("future", .outside, .neutral)
        ] {
            vitals.monitorState = state
            let health = HealthState(vitals)
            #expect(health.kind == kind)
            #expect(health.color == color)
        }
        vitals.monitorState = nil
        vitals.metricsWithRange = 0
        #expect(HealthState(vitals).kind == .building)
        #expect(HealthState(vitals).sentence == "ghoops needs 7 nights to learn your ranges.")
        vitals.metricsWithRange = 5; vitals.outsideRange = ["respiratory_rate"]; vitals.adverse = ["respiratory_rate"]
        #expect(HealthState(vitals).kind == .outside)
        #expect(HealthState(vitals).color == .neutral)
        #expect(HealthState(vitals).sentence == "4/5 overnight metrics in your typical range")
        vitals.adverse = []
        #expect(HealthState(vitals).kind == .outside)
        #expect(HealthState(vitals).color == .neutral)
        vitals.outsideRange = []
        #expect(HealthState(vitals).kind == .within)
        #expect(HealthState(vitals).subline == "5/5 Metrics")
    }
}
