import Foundation
import Testing
@testable import GHealthCore

func engineConstants(odd: Bool = false) throws -> ScoreConstants {
    if odd {
        struct Body: Decodable { var scoreConstants: ScoreConstants }
        return try fixture("engine/odd_constants.json", as: Body.self).scoreConstants
    }
    return try #require(fixture("day_full.json", as: Day.self).scoreConstants)
}

private func engineZones(_ zones: Zones?) -> [Int]? {
    zones.map { [$0.below, $0.z1, $0.z2, $0.z3, $0.z4, $0.z5] }
}

@Test func liveEstimatorUsesTheMacsStrainModel() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var session = ActivitySession(sport: .all[0], now: start)
    for (i, bpm) in [100, 100, 130, 130, 150, 150, 175, 175, 90, 160].enumerated() {
        session.append(.init(t: start.addingTimeInterval(Double(i * 60)), bpm: Double(bpm)))
    }
    for (odd, zones, trimp, strain, ranges): (Bool, [Int], Double, Double, [String]) in [
        (false, [1, 2, 2, 0, 3, 2], 15.6, 4.6, ["<96", "96–121", "122–134", "135–147", "148–167", "168+"]),
        (true, [3, 0, 2, 2, 1, 2], 17.2, 4.4, ["<102", "102–128", "129–141", "142–154", "155–173", "174+"])
    ] {
        let model = try engineConstants(odd: odd).strain
        let estimator = LiveEstimator(restingHR: 56, maximumHR: 187, model: model)
        let result = estimator.estimate(session, now: start.addingTimeInterval(600))
        #expect(engineZones(result.wholeZones) == zones)
        #expect(result.trimp == trimp && result.strain == strain && result.zone == 4)
        #expect(result.scale == model.scale)
        #expect((0...5).map { estimator.range(zone: $0) } == ranges)
    }
    let estimator = LiveEstimator(restingHR: 56, maximumHR: 187, model: nil)
    let result = estimator.estimate(session, now: start.addingTimeInterval(600))
    #expect(result.strain == nil && result.trimp == nil && result.zone == nil && result.scale == nil)
    #expect(estimator.range(zone: 4) == "—")
    #expect(result.average == 136 && result.maximum == 175)
}

@Test func projectedDayStrainUsesTheMacsScale() throws {
    let target = SessionTarget(cycleDate: "2026-03-10", baseTrimp: 124.1, low: 13.3, high: 16.3)
    #expect(target.projected(liveTrimp: 15.6, scale: try engineConstants().strain.scale) == 13.3)
    #expect(target.projected(liveTrimp: 17.2, scale: try engineConstants(odd: true).strain.scale) == 12.7)
    #expect(target.projected(liveTrimp: 15.6, scale: nil) == nil)
}

@Test func windowEstimateUsesTheMacsModel() throws {
    var body: HeartRateBody = try fixture("edits/heart_rate_tue.json")
    body.restingHrBpm = 56; body.maxHrBpm = 187
    let start = body.start
    body.minutes = [100, 130, 150, 175, 160].enumerated().map {
        HeartRateMinute(t: start.addingTimeInterval(Double($0.offset * 60)), avgBpm: Double($0.element), maxBpm: $0.element)
    }
    let snapshot: Snapshot = try fixture("edits/snapshot_unedited.json")
    let workout = try #require(snapshot.workouts.workouts.first { $0.id == "7300000000000000101" })
    for (constants, zones, trimp, strain, confidence): (ScoreConstants?, [Int]?, Double?, Double?, Confidence?) in [
        (try engineConstants(), [0, 1, 1, 0, 2, 1], 9.0, 3.2, .high),
        (try engineConstants(odd: true), [1, 0, 1, 1, 1, 1], 10.0, 3.0, .medium),
        (nil, nil, nil, nil, nil)
    ] {
        body.scoreConstants = constants
        let end = start.addingTimeInterval(360)
        let result = WindowEstimator(heartRate: body).estimate(start: start, end: end)
        #expect(engineZones(result.zonesMinutes) == zones && result.trimp == trimp && result.strain == strain)
        #expect(result.hrCoverage == 0.83 && result.avgHrBpm == 143 && result.peakHrBpm == 175)
        #expect(result.covered == 5 && result.expected == 6 && result.elapsedMinutes == 6)
        if let constants {
            #expect(StrainMath.confidence(covered: 5, expected: 6, cuts: constants.strain.coverage) == confidence)
            #expect(StrainMath.confidence(covered: 0, expected: 0, cuts: constants.strain.coverage) == nil)
        }
        let projected = WorkoutProjection.project(workout, body: EditBody(), window: ActivityWindow(start: start, end: end), heartRate: body, now: end)
        #expect(projected.confidence == confidence)
    }
}

@Test func overlapRulesUseTheMacsShares() throws {
    let snapshot: Snapshot = try fixture("edits/snapshot_unedited.json")
    var recorded = try #require(snapshot.workouts.workouts.first)
    let start = try #require(ISO8601DateFormatter().date(from: "2026-03-10T18:00:00Z"))
    recorded.id = "recorded"; recorded.kind = "recorded"; recorded.start = start; recorded.end = start.addingTimeInterval(3600)
    let date = recorded.cycleDate
    for (minutes, defaultHidden, oddHidden) in [(33, false, false), (27, true, false), (24, true, true)] {
        var goop = recorded; goop.id = "goop"; goop.kind = "goop"
        goop.start = start.addingTimeInterval(Double(minutes * 60)); goop.end = goop.start.addingTimeInterval(3600)
        for (rules, hidden): (WorkoutOverlap?, Bool) in [(try engineConstants().workouts, defaultHidden), (try engineConstants(odd: true).workouts, oddHidden), (nil, false)] {
            let result = OverlapRules.apply([recorded, goop], cycleDates: [date], rules: rules)
            #expect(!result.contains { $0.id == recorded.id } == hidden)
        }
    }
    var effort = recorded; effort.id = "effort"; effort.kind = "detected"; effort.end = start.addingTimeInterval(2400)
    recorded.end = start.addingTimeInterval(1080)
    for (rules, hidden): (WorkoutOverlap?, Bool) in [(try engineConstants().workouts, false), (try engineConstants(odd: true).workouts, true), (nil, false)] {
        let result = OverlapRules.apply([recorded, effort], cycleDates: [date], rules: rules)
        #expect(!result.contains { $0.id == effort.id } == hidden)
    }
}

@Test func scalesUseTheMacsEdges() throws {
    for (constants, expected): (ScoreConstants?, [[String]]) in [
        (try engineConstants(), [["0–33", "34–66", "67–100"], ["0–9.9", "10–13.9", "14–17.9", "18–21"], ["0–69%", "70–84%", "85–100%"], ["0–59%", "60–79%", "80–100%"], ["0–84%", "85–89%", "90–100%"]]),
        (try engineConstants(odd: true), [["0–39", "40–69", "70–100"], ["0–10.9", "11–15.4", "15.5–18.9", "19–21"], ["0–74%", "75–89%", "90–100%"], ["0–64%", "65–84%", "85–100%"], ["0–87%", "88–92%", "93–100%"]]),
        (nil, [["—", "—", "—"], ["—", "—", "—", "—"], ["—", "—", "—"], ["—", "—", "—"], ["—", "—", "—"]])
    ] {
        #expect(engineScales(constants).map { $0.bands.map(\.range) } == expected)
    }
    for (band, level, index): (Band3?, SleepLevel?, Int?) in [(.low, .poor, 0), (.medium, .sufficient, 1), (.high, .optimal, 2), (.unknown("future"), nil, nil), (nil, nil, nil)] {
        #expect(SleepLevel(band) == level && LevelScale.index(band) == index)
    }
    for (band, index): (StrainBand?, Int?) in [(.light, 0), (.moderate, 1), (.strenuous, 2), (.allOut, 3), (.unknown("future"), nil), (nil, nil)] {
        #expect(LevelScale.index(band) == index)
    }
}

private func engineScales(_ constants: ScoreConstants?) -> [LevelScale] {
    [.recovery(constants), .strain(constants), .hours(constants), .consistency(constants), .efficiency(constants)]
}

private func engineSentences(_ mode: String) throws -> [String] {
    var snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    let newUser: Day = try fixture("day_new_user.json")
    snapshot.day.recovery = newUser.recovery
    snapshot.day.vitals = newUser.vitals
    snapshot.day.vitals.metricsWithRange = 0
    snapshot.day.vitals.monitorState = "building"
    if mode == "odd" {
        let engine: EngineFixture = try fixture("engine/odd_constants.json")
        engine.apply(to: &snapshot)
    } else if mode == "none" {
        snapshot.day.scoreConstants = nil; snapshot.day.comparison = nil
        snapshot.day.sleep.stageTypical?.nightsNeeded = nil
        snapshot.day.sleep.stageTypical?.lowPercentile = nil; snapshot.day.sleep.stageTypical?.highPercentile = nil
        snapshot.day.vitals.valuesNeeded = nil
        snapshot.day.sleepPlan?.nightsNeeded = nil; snapshot.day.sleepPlan?.windowNights = nil
    }
    let day = snapshot.day, calibration = day.recovery.calibration
    let plan = try #require(day.sleepPlan)
    return [EngineText.penaltyNote(day.scoreConstants), EngineText.calibrationNote(calibration), EngineText.comparisonNote(day.comparison),
            EngineText.comparisonLegend(day.comparison), EngineText.comparisonSpoken(day.comparison?.windowDays), EngineText.typicalNote(day.sleep.stageTypical),
            EngineText.uploadedNote(collectorMinutes: mode == "none" ? nil : snapshot.status.collector.intervalMinutes),
            Insights.recovery(day.recovery), ReasonText.score(day.recovery.reason, status: day.recovery.status, calibration: calibration),
            Insights.strain(day.strain, workouts: day.workouts, isToday: true, constants: day.scoreConstants), HealthState(day.vitals).sentence,
            SleepPlanText.unavailable(plan), SleepPlanText.placeholder(plan), HealthText.attentionSpoken(day.scoreConstants)]
}

@Test func sentencesUseTheMacsNumbers() throws {
    for (mode, penalty, needed, full, window, middle, typicalWindow, typicalNeeded, vitalsNeeded, planNeeded, planWindow, collector, band): (String, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, String) in [
        ("default", 10, 7, 14, 30, 50, 30, 7, 7, 3, 14, 30, "Strain between 10.0 and 13.9 is considered moderate."),
        ("odd", 8, 4, 12, 28, 60, 28, 6, 9, 4, 21, 20, "Strain between 11.0 and 15.4 is considered moderate.")
    ] {
        let text = try engineSentences(mode)
        #expect(text[0] == "Breathing rate and skin temperature only subtract, up to \(penalty) points each, when they run above usual.")
        #expect(text[1] == "\(needed) nights to start · \(full) for full confidence")
        #expect(text[2] == "Arrows compare today with your average over the \(window) days before it. Green and orange show the usual direction for that measure; they are not medical advice.")
        #expect(text[3] == "vs. prior \(window) days" && text[4] == "versus prior \(window) days average")
        #expect(text[5] == "Typical ranges are the middle \(middle)% of your last \(typicalWindow) nights with sleep stages (shown after \(typicalNeeded) such nights).")
        #expect(text[6] == "Live estimate. Final Strain arrives when your band syncs with your Mac, usually within \(collector) minutes.")
        #expect(text[7] == "Recovery is calibrating: 3 of \(needed) nights so far. It starts once ghoops has \(needed) nights of your HRV and resting heart rate.")
        #expect(text[8] == "Calibrating: 3 of \(needed) nights")
        #expect(text[9].hasPrefix(band))
        #expect(text[10] == "ghoops needs \(vitalsNeeded) nights to learn your ranges.")
        #expect(text[11] == "Tonight's plan needs at least \(planNeeded) nights of sleep from the last \(planWindow).")
        #expect(text[12] == "Needs \(planNeeded) nights of sleep to plan tonight.")
    }
    #expect(try engineSentences("default")[13] == "outside your typical range for 2 nights in a row")
    #expect(try engineSentences("odd")[13] == "outside your typical range for 3 nights in a row")
    #expect(try engineSentences("none")[13] == "outside your typical range on recent nights")
    var missingVitals = try engineConstants()
    missingVitals.vitals = nil
    #expect(HealthText.attentionSpoken(missingVitals) == "outside your typical range on recent nights")
    for (odd, days) in [(false, 7), (true, 10)] {
        let constants = try engineConstants(odd: odd)
        let sent = try #require(constants.hrvTrend).days
        #expect(HealthText.hrvTrendTitle(constants) == "HRV \(days)-day average")
        #expect(HealthText.nightsChip(nights: 3, days: sent) == "3 of \(days) nights")
        #expect(Insights.hrvWeek(position: "below", days: sent) == "Your \(days)-day HRV average is below your usual range.")
    }
    var missingTrend = try engineConstants()
    missingTrend.hrvTrend = nil
    #expect(HealthText.hrvTrendTitle(missingTrend) == nil && HealthText.hrvTrendTitle(nil) == nil)
    let fresh: Snapshot = try fixture("preview/snapshot_fresh.json")
    var workout = try #require(fresh.day.workouts.first)
    workout.strain = 10.5
    let oddConstants = try engineConstants(odd: true)
    #expect(!Insights.strain(fresh.day.strain, workouts: [workout], isToday: true, constants: oddConstants).contains("hardest"))
    workout.strain = 11
    #expect(Insights.strain(fresh.day.strain, workouts: [workout], isToday: true, constants: oddConstants).contains("hardest"))
    let missing = try engineSentences("none")
    #expect(missing[0] == "Breathing rate and skin temperature only subtract when they run above usual.")
    #expect(missing[2] == "Arrows compare today with your recent average. Green and orange show the usual direction for that measure; they are not medical advice.")
    #expect(missing[3] == "vs. your average" && missing[4] == "versus prior average")
    #expect(missing[5] == "Typical ranges come from your last 30 nights with sleep stages.")
    #expect(EngineText.typicalNote(nil) == "Typical ranges come from your recent nights with sleep stages.")
    #expect(missing[6] == "Live estimate. Final Strain arrives when your band syncs with your Mac.")
    #expect(!missing[9].contains("considered") && !missing[9].contains("hardest"))
    #expect(missing[10] == "ghoops is still learning your ranges.")
    #expect(missing[11] == "Tonight's plan needs more nights of sleep." && missing[12] == "Needs more nights of sleep to plan tonight.")
    #expect(ReasonText.score(.insufficientBaseline, status: .pending) == "Calibrating")
    #expect(ReasonText.score(.insufficientNights, status: .unavailable) == "Not enough nights yet")
    var calibration = try fixture("preview/snapshot_fresh.json", as: Snapshot.self).day.recovery.calibration
    calibration.valuesNeeded = 4; calibration.valuesForFullConfidence = 12
    #expect(EngineText.calibrationFill(calibration) == 1 && EngineText.calibrationTick(calibration) == 1.0 / 3)
    calibration.hrvValues = 3; calibration.restingHrValues = 3
    #expect(EngineText.calibrationFill(calibration) == 0.25)
    calibration.valuesNeeded = 12
    #expect(EngineText.calibrationTick(calibration) == nil)
    calibration.valuesForFullConfidence = 0
    #expect(EngineText.calibrationFill(calibration) == 0 && EngineText.calibrationTick(calibration) == nil)
    var constants = try engineConstants(); constants.recovery.penaltyMax = 8.5
    #expect(EngineText.penaltyNote(constants).contains("8.5 points"))
}

@Test func defaultsNeverLeakIntoOddOutput() throws {
    let constants = try engineConstants(odd: true)
    let zones = try #require(ZoneScale(rest: 56, maximum: 187, zones: constants.strain.zonesHrr))
    let days = try #require(constants.hrvTrend).days
    let weekly = [HealthText.hrvTrendTitle(constants) ?? "", HealthText.nightsChip(nights: 3, days: days), Insights.hrvWeek(position: "within", days: days) ?? ""]
    let text = (try engineSentences("odd") + engineScales(constants).flatMap { $0.bands.map(\.range) } + (0...5).map { zones.range($0) } + weekly).joined(separator: "\n")
    for copy in ["7-day", "of 7 nights", "0–33", "34–66", "67–100", "9.9", "13.9", "17.9", "10.0", "14.0", "18.0", "7 nights", "14 for full", "10 points", "30 days", "30 nights", "middle half", "<96", "168+", "at least 3 nights", "Needs 3 nights", "last 14", "within 30", "2 nights"] {
        #expect(!text.contains(copy), "Default leaked: \(copy)")
    }
}

private func withoutEngineFields(_ value: Any) -> Any {
    if var object = value as? [String: Any] {
        for key in ["persistent", "monitor_state", "hrv_trend", "score_constants", "efficiency_band", "values_needed", "nights_needed", "window_nights", "low_percentile", "high_percentile"] {
            // window_nights on stage_typical and calibration.values_needed predate this change.
            if key == "window_nights", object["light"] != nil { continue }
            if key == "values_needed", object["values_for_full_confidence"] != nil { continue }
            object.removeValue(forKey: key)
        }
        return object.mapValues(withoutEngineFields)
    }
    if let array = value as? [Any] { return array.map(withoutEngineFields) }
    return value
}

@Test func olderMacBodiesDecode() throws {
    func older<T: Codable>(_ value: T) throws -> T {
        let original = try JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(value))
        let stripped = withoutEngineFields(original)
        let data = try JSONSerialization.data(withJSONObject: stripped, options: [.sortedKeys])
        let decoded = try JSONCoding.decoder().decode(T.self, from: data)
        let encoded = withoutEngineFields(try JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(decoded)))
        #expect(try JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys]) == data)
        return decoded
    }
    let snapshot = try older(fixture("preview/snapshot_fresh.json", as: Snapshot.self))
    let day = snapshot.day, sleep = snapshot.sleep
    #expect(day.scoreConstants == nil && sleep.scoreConstants == nil)
    #expect(day.vitals.persistent.isEmpty && day.vitals.monitorState == nil && day.vitals.hrvTrend == nil)
    #expect(!day.vitals.inAttention("resting_hr"))
    let current = try engineConstants()
    var object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(current)) as? [String: Any])
    object.removeValue(forKey: "vitals")
    object.removeValue(forKey: "hrv_trend")
    let oldConstants = try JSONCoding.decoder().decode(ScoreConstants.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(oldConstants.vitals == nil && oldConstants.hrvTrend == nil)
    let trend = try #require(fixture("day_full.json", as: Day.self).vitals.hrvTrend)
    #expect(trend.nights == 6 && trend.position == "within" && trend.metric.rangeLow == 47 && trend.metric.rangeHigh == 57.4 && current.hrvTrend?.days == 7)

    #expect(day.sleep.efficiencyBand == nil && sleep.efficiencyBand == nil && day.vitals.valuesNeeded == nil)
    #expect(day.sleepPlan?.nightsNeeded == nil && day.sleepPlan?.windowNights == nil)
    for typical in [day.sleep.stageTypical, sleep.stageTypical] {
        #expect(typical?.nightsNeeded == nil && typical?.lowPercentile == nil && typical?.highPercentile == nil)
    }
    let heartRate = try older(fixture("edits/heart_rate_tue.json", as: HeartRateBody.self))
    #expect(heartRate.scoreConstants == nil)
}

@Test func vitalsUseTheMacsAttentionClass() throws {
    var vitals = try fixture("day_full.json", as: Day.self).vitals
    vitals.adverse = ["hrv_rmssd"]
    for state in [nil, "outside", "unexpected", "attention"] as [String?] {
        vitals.monitorState = state
        vitals.persistent = ["resting_hr", "respiratory_rate"]
        #expect(vitals.inAttention("resting_hr") == (state == "attention"))
        #expect(!vitals.inAttention("hrv_rmssd"))
    }
}
