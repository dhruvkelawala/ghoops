import Foundation
import Testing
@testable import GHealthCore

@Test(arguments: ["2026-03-10T07:29:00Z", "2026-03-10T23:50:00Z"])
func liveContentStateProjectsTargetAndDecodesOlderStates(_ timestamp: String) throws {
    let day: Day = try fixture("day_full.json")
    let start = try #require(ISO8601DateFormatter().date(from: timestamp))
    let now = start.addingTimeInterval(20 * 60)
    var session = ActivitySession(sport: .sport("BOXING"), now: start)
    let estimate = LiveEstimate(strain: 6.4, trimp: 26.7, scale: try engineConstants().strain.scale, average: 146, maximum: 170, zone: 4, zones: Array(repeating: 0, count: 6))
    let original = ActivityContentState(session: session, estimate: estimate, now: now)
    #expect(original.dayStrain == nil && original.targetLow == nil && original.targetHigh == nil && original.targetWithin == nil)
    session.target = SessionTarget.make(day: day, sessionStart: start)
    #expect(session.target?.cycleDate == "2026-03-10")
    let targeted = ActivityContentState(session: session, estimate: estimate, now: now)
    #expect(targeted.strainEstimate == 6.4 && targeted.avgHR == 146 && targeted.zone == 4)
    #expect(targeted.dayStrain == 13.7 && targeted.targetLow == 13.3 && targeted.targetHigh == 16.3 && targeted.targetWithin == true)
    #expect(targeted != original)
    #expect(try JSONDecoder().decode(ActivityContentState.self, from: JSONEncoder().encode(targeted)) == targeted)
    var unavailable = estimate
    unavailable.trimp = nil
    let missing = ActivityContentState(session: session, estimate: unavailable, now: now)
    #expect(missing.dayStrain == nil && missing.targetWithin == nil && missing.targetLow == 13.3)
    let older = Data(#"{"bpm":158,"zone":4,"strainEstimate":6.4,"avgHR":146,"pausedTotal":0,"isPaused":false,"hrState":"live"}"#.utf8)
    let decoded = try JSONDecoder().decode(ActivityContentState.self, from: older)
    #expect(decoded.bpm == 158 && decoded.dayStrain == nil && decoded.targetLow == nil && decoded.targetHigh == nil && decoded.targetWithin == nil)
    let savedSession = session.finish(at: now)
    #expect(savedSession)
    let ended = ActivityContentState(session: session, estimate: estimate, now: now)
    #expect(ended.elapsed == 1200 && session.start == start)
    let saved = LiveEstimator(restingHR: nil, maximumHR: nil, model: nil).localActivity(session, now: now).workout()
    #expect(saved.cycleDate == "2026-03-10" && saved.start == start && saved.end == now)
}

@Test func parityModelsDecodeValuesAndOlderBodies() throws {
    let day: Day = try fixture("day_full.json")
    #expect(day.strainTarget?.low == 13.3 && day.strainTarget?.high == 16.3)
    #expect(day.strainTarget?.intent == "maintain" && day.strainTarget?.position == "below")
    #expect(day.sleepPlan?.needMinutes == 483 && day.sleepPlan?.goals.first?.inBedMinutes == 522)
    // Since 2.3.3 the Mac's efficiency already holds the time to fall asleep, so it sends no separate latency.
    let plan = try #require(day.sleepPlan)
    #expect(plan.latencyMinutesUsed == nil && SleepPlanText.awakeNote(plan) == "92.5% efficiency")
    #expect(plan.goals.map { SleepPlanText.awakeMinutes(plan, goal: $0) } == [39, 33, 28])
    #expect(day.sleepPlan?.needParts.cycleStrain == 12.8)
    let workouts: Workouts = try fixture("parity/workouts.json")
    let suggestion = try #require(workouts.workouts.first { $0.kind == "detected" }?.suggested)
    #expect(suggestion.exerciseType == "BOXING" && suggestion.displayName == "Boxing")
    #expect(suggestion.matches == 3 && suggestion.windowDays == 56)
    let brief: Brief = try fixture("brief_full_evening_values.json")
    #expect(brief.part == "evening" && brief.strainTarget?.low == 13.3)
    #expect(brief.sleepPlan?.needMinutes == 483 && GoopFormat.time(brief.sleepPlan?.bedtime) == "22:25")
    #expect(brief.trend?["hrv_rmssd_ms"]?.mean7 == 53.1 && brief.trend?["hrv_rmssd_ms"]?.days30 == 28)
    #expect(brief.review?.workouts == 1 && brief.review?.zones13Minutes == 27 && brief.review?.zones45Minutes == 33)
    let config: Config = try fixture("commands/config_show.json")
    #expect(config.values.strainIntent == "maintain" && config.defaults.strainIntent == "maintain")
    #expect(config.values.wakeTarget == nil)
    let configured: Day = try fixture("day_full_config.json")
    #expect(configured.scoreConfig?.strainIntent == "restore" && configured.scoreConfig?.wakeTarget == "06:45")

    func removing<T: Codable>(_ value: T, keys: [String], as type: T.Type) throws -> T {
        var object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(value)) as? [String: Any])
        for key in keys { object.removeValue(forKey: key) }
        return try JSONCoding.decoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    let oldDay = try removing(day, keys: ["strain_target", "sleep_plan"], as: Day.self)
    #expect(oldDay.strainTarget == nil && oldDay.sleepPlan == nil)
    let oldWorkout = try removing(workouts.workouts[0], keys: ["suggested"], as: Workout.self)
    #expect(oldWorkout.suggested == nil)
    let oldBrief = try removing(brief, keys: ["part", "strain_target", "sleep_plan", "trend", "review"], as: Brief.self)
    #expect(oldBrief.part == nil && oldBrief.strainTarget == nil && oldBrief.sleepPlan == nil && oldBrief.trend == nil && oldBrief.review == nil)
    let oldConfig = try removing(config.values, keys: ["strain_intent", "wake_target"], as: ScoreConfig.self)
    #expect(oldConfig.strainIntent == nil && oldConfig.wakeTarget == nil)
}

@Test func strainTargetCopyCoversPositionsIntentsAndMissingScores() throws {
    let day: Day = try fixture("day_full.json")
    let existing = Insights.strain(day.strain, workouts: day.workouts, isToday: true, constants: try engineConstants())
    for today in [true, false] {
        for intent in ["maintain", "restore", "overreach"] {
            for position: String? in ["below", "within", "above", nil] {
                var target = try #require(day.strainTarget)
                target.intent = intent; target.position = position
                let start = today ? "Today's target is" : "The target was"
                let extra = intent == "restore" ? " on a restore day" : intent == "overreach" ? " on an overreach day" : ""
                var prefix = "\(start) 13.3 to 16.3 for high recovery\(extra). The target is ghoops' own rule of thumb, not a published method."
                if let position { prefix += " \(today ? "You are" : "You finished") \(position) it." }
                let text = Insights.strain(day.strain, workouts: day.workouts, isToday: today, target: target, recoveryBand: .high, constants: try engineConstants())
                #expect(text.hasPrefix(prefix + " Strain between 10.0 and 13.9 is considered moderate."))
            }
        }
    }
    #expect(Insights.strain(day.strain, workouts: day.workouts, isToday: true, target: day.strainTarget, recoveryBand: .high, constants: try engineConstants()) == "Today's target is 13.3 to 16.3 for high recovery. The target is ghoops' own rule of thumb, not a published method. You are below it. " + existing)
    for (status, prefix) in [(ScoreStatus.pending, "Today's target appears when Recovery is ready."), (.unavailable, "There is no target without a Recovery score.")] {
        var target = try #require(day.strainTarget); target.status = status
        #expect(Insights.strain(day.strain, workouts: [], isToday: true, target: target, constants: try engineConstants()).hasPrefix(prefix))
    }
    var strain = day.strain; strain.value = nil; strain.reason = .noHeartRate
    var target = try #require(day.strainTarget); target.position = nil
    #expect(Insights.strain(strain, workouts: [], isToday: true, target: target, recoveryBand: .high, constants: try engineConstants()) == "Today's target is 13.3 to 16.3 for high recovery. The target is ghoops' own rule of thumb, not a published method. " + Insights.strain(strain, workouts: [], isToday: true, constants: try engineConstants()))
}

@Test func sparseStrainDoesNotRepeatALegacyTargetVerdict() throws {
    var day: Day = try fixture("day_strain_sparse.json")
    #expect(day.strainTarget?.reason == .lowCoverage)
    day.strainTarget?.reason = nil
    day.strainTarget?.position = "below"
    let insight = Insights.strain(day.strain, workouts: day.workouts, isToday: false, target: day.strainTarget, recoveryBand: day.recovery.band, constants: day.scoreConstants)
    #expect(insight.hasPrefix("The target was"))
    #expect(insight.contains("of the day's heart rate"))
    #expect(!insight.contains("You finished"))
}

@Test func sleepPlanBreakdownAddsUpToTimeInBed() throws {
    let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    var plan = try #require(snapshot.day.sleepPlan)
    // Each goal's asleep + awake is its time in bed: 8:03 + 0:45 = 8:48, 6:51 + 0:39 = 7:30, 5:38 + 0:34 = 6:12.
    #expect(plan.goals.map { SleepPlanText.asleepMinutes(plan, goal: $0) } == [483, 411, 338])
    #expect(plan.goals.map { SleepPlanText.awakeMinutes(plan, goal: $0) } == [45, 39, 34])
    for goal in plan.goals { #expect(SleepPlanText.asleepMinutes(plan, goal: goal) + SleepPlanText.awakeMinutes(plan, goal: goal) == goal.inBedMinutes) }
    #expect(SleepPlanText.awakeNote(plan) == "92.5% efficiency · 6 min to fall asleep")
    #expect(SleepPlanText.wakeLabel(plan) == "WAKE · TYPICAL")
    #expect(SleepPlanText.footnote(plan) == "Usual values come from your last 12 nights. Set a fixed wake time on your Mac with ghoops config.")
    #expect(SleepPlanText.goalAccessibility(plan.goals[0]) == "100 percent of need: 8 hours 48 minutes in bed, bed by 22:19")
    plan.latencyMinutesUsed = 0; plan.efficiencyPctUsed = 90
    #expect(SleepPlanText.awakeNote(plan) == "90% efficiency")
    plan.efficiencyPctUsed = nil
    #expect(SleepPlanText.awakeNote(plan) == nil)
    let configured = try #require((try fixture("day_full_config.json") as Day).sleepPlan)
    #expect(SleepPlanText.wakeLabel(configured) == "WAKE · SET ON MAC")
    #expect(SleepPlanText.footnote(configured).hasSuffix("The wake time is set on your Mac with ghoops config."))
}

@Test func recoveryBreakdownAddsUpToTheScore() throws {
    let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    var recovery = snapshot.day.recovery
    #expect(RecoveryExplain.base(recovery) == [
        BreakdownLine(id: "recovery-hrv", label: "HRV", note: "56 ms · usual 52 · 55% weight", value: "+42.1"),
        BreakdownLine(id: "recovery-resting-hr", label: "Resting heart rate", note: "56 bpm · usual 56 · 20% weight", value: "+10.1"),
        BreakdownLine(id: "recovery-sleep", label: "Sleep performance", note: "93% · 25% weight", value: "+23.3")
    ])
    #expect(RecoveryExplain.penalties(recovery) == [
        BreakdownLine(id: "recovery-breathing", label: "Breathing rate", note: "15.2 rpm · usual 14.6", value: "−2.3"),
        BreakdownLine(id: "recovery-skin", label: "Skin temperature", note: "+0.2 °C from usual", value: "0.0")
    ])
    #expect(recovery.value == 73)
    recovery.components?.weights = nil
    let older = RecoveryExplain.base(recovery)
    #expect(older.count == 4)
    #expect(older.prefix(3).allSatisfy { $0.value == "—" && $0.note?.contains("weight") == false })
    #expect(older.last == BreakdownLine(id: "recovery-inputs", label: "HRV, resting HR and sleep", note: "Update ghoops on your Mac to see each part", value: "+75.5"))
    recovery.inputs.skinTempDeviationC = nil; recovery.components = nil
    #expect(RecoveryExplain.penalties(recovery)[1] == BreakdownLine(id: "recovery-skin", label: "Skin temperature", note: "Not available", value: "—"))
    #expect(RecoveryExplain.base(recovery).map(\.value) == ["—", "—", "—"])
}

@Test func recoveryBreakdownUsesTheMacsWeights() throws {
    let recovery: Recovery = try fixture("recovery/weights_40_30_30.json")
    #expect(RecoveryExplain.base(recovery) == [
        BreakdownLine(id: "recovery-hrv", label: "HRV", note: "56 ms · usual 52 · 40% weight", value: "+30.6"),
        BreakdownLine(id: "recovery-resting-hr", label: "Resting heart rate", note: "56 bpm · usual 56 · 30% weight", value: "+15.2"),
        BreakdownLine(id: "recovery-sleep", label: "Sleep performance", note: "93% · 30% weight", value: "+27.9")
    ])
    #expect(Int(try recoveryPoints(recovery).rounded()) == recovery.value)
    #expect(recovery.value == 71)
}

@Test func recoveryBreakdownWithoutWeightsStillAddsUp() throws {
    let recovery: Recovery = try fixture("recovery/no_weights.json")
    let sum = try recoveryPoints(recovery)
    #expect(abs(sum - 73.2) < 1e-9)
    #expect(Int(sum.rounded()) == recovery.value)
    #expect(recovery.value == 73)
}

@Test func valueStringsHoldOnlyNumbers() throws {
    var values = [LevelScale.hours(try engineConstants()), .consistency(try engineConstants()), .efficiency(try engineConstants()), .recovery(try engineConstants()), .strain(try engineConstants())].flatMap { $0.bands.map(\.range) }
    let fresh: Snapshot = try fixture("preview/snapshot_fresh.json")
    let weighted: Recovery = try fixture("recovery/weights_40_30_30.json")
    let older: Recovery = try fixture("recovery/no_weights.json")
    for recovery in [fresh.day.recovery, weighted, older] {
        values += (RecoveryExplain.base(recovery) + RecoveryExplain.penalties(recovery)).map(\.value)
    }
    for value in values { #expect(value.range(of: "^[0-9 .,:%+−–—<]+$", options: .regularExpression) != nil, "Invalid Sofia value: \(value)") }
}

private func recoveryPoints(_ recovery: Recovery) throws -> Double {
    try (RecoveryExplain.base(recovery) + RecoveryExplain.penalties(recovery)).reduce(0) { sum, line in
        if line.value == "—" { return sum }
        return sum + (try #require(Double(line.value.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "−", with: "-"))))
    }
}

@Test func levelScalesPlaceValuesInTheirBand() {
    for (band, index): (Band3?, Int?) in [(.low, 0), (.medium, 1), (.high, 2), (.unknown("future"), nil), (nil, nil)] {
        #expect(LevelScale.index(band) == index)
        #expect(SleepLevel(band).flatMap { SleepLevel.allCases.firstIndex(of: $0) } == index)
    }
    for (band, index): (StrainBand?, Int?) in [(.light, 0), (.moderate, 1), (.strenuous, 2), (.allOut, 3), (.unknown("future"), nil), (nil, nil)] {
        #expect(LevelScale.index(band) == index)
    }
}

@Test func strainSheetLabelsNameTheirSource() {
    #expect(StrainExplain.maxSource("age_predicted_profile") == "MAX · AGE-BASED")
    #expect(StrainExplain.maxSource(nil) == "MAX")
    #expect(StrainExplain.restingSource("daily_resting_heart_rate") == "RESTING · DAILY")
}

@Test func suggestionCopyUsesLondonWeekdays() throws {
    let start = try #require(ISO8601DateFormatter().date(from: "2026-03-23T23:30:00Z"))
    for (i, names) in zip(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]).enumerated() {
        let date = GoopFormat.calendar.date(byAdding: .day, value: i, to: start)!
        #expect(SuggestionText.note(effortStart: date) == "Usual on \(names.0)")
        #expect(SuggestionText.accessibility(sport: "Boxing", effortStart: date) == "Boxing, usual on \(names.1)")
    }
    let summer = try #require(ISO8601DateFormatter().date(from: "2026-03-29T23:30:00Z"))
    #expect(GoopFormat.weekdayShort(summer) == "Mon" && GoopFormat.weekdayLong(summer) == "Monday")
}

@Test func sessionTargetCreationFreezesBaseAndProjectsSpecExamples() throws {
    var day: Day = try fixture("day_full.json")
    let start = day.generatedAt
    for (base, live, expected) in [(25.0, 26.7, 9.0), (25.0, 79.3, 12.0), (124.1, 26.7, 13.7), (124.1, 13.1, 13.2)] {
        day.strain.trimp = base
        let target = try #require(SessionTarget.make(day: day, sessionStart: start))
        #expect(target.projected(liveTrimp: live, scale: day.scoreConstants?.strain.scale) == expected)
        #expect(target.projected(liveTrimp: nil, scale: day.scoreConstants?.strain.scale) == nil)
        day.strain.trimp = 999
        #expect(target.baseTrimp == base)
    }
    day.isCurrentCycle = false
    #expect(SessionTarget.make(day: day, sessionStart: start) == nil)
    day.isCurrentCycle = true
    #expect(SessionTarget.make(day: day, sessionStart: day.cycle.start.addingTimeInterval(-1)) == nil)
    day.strainTarget?.status = .pending
    #expect(SessionTarget.make(day: day, sessionStart: start) == nil)
    day.strainTarget?.status = .ok; day.strainTarget?.low = nil
    #expect(SessionTarget.make(day: day, sessionStart: start) == nil)
    day.strainTarget = try fixture("day_full.json", as: Day.self).strainTarget
    day.strain.trimp = nil; day.strain.reason = .noHeartRate
    #expect(SessionTarget.make(day: day, sessionStart: start)?.baseTrimp == 0)
    day.strain.reason = .maxHrUnknown
    let missing = try #require(SessionTarget.make(day: day, sessionStart: start))
    #expect(missing.baseTrimp == nil && missing.projected(liveTrimp: 26.7, scale: day.scoreConstants?.strain.scale) == nil)
}

@Test func sessionTargetCrossesOnceAndSurvivesRestore() async throws {
    var day: Day = try fixture("day_full.json")
    day.strainTarget?.low = 11.6; day.strainTarget?.high = 14.6
    for (values, alerts, state): ([Double?], [Bool], TargetCrossing) in [
        ([9.0, 11.5, 11.6, 12.0], [false, false, true, false], .fired),
        ([12.0, 13.0], [false, false], .inactive),
        ([9.0, 15.0], [false, false], .inactive),
        ([nil, 9.0, 11.6], [false, false, true], .fired),
        ([9.0, nil, 14.6, 11.6], [false, false, true, false], .fired)
    ] {
        var target = try #require(SessionTarget.make(day: day, sessionStart: day.generatedAt))
        #expect(values.map { target.update(projected: $0) } == alerts)
        #expect(target.crossing == state)
    }
    var session = ActivitySession(sport: .all[0], now: day.generatedAt)
    session.target = SessionTarget.make(day: day, sessionStart: day.generatedAt)
    #expect(session.target?.update(projected: 9) == false)
    #expect(session.target?.update(projected: 11.6) == true)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ActivityStore(directory: directory)
    try await store.saveSession(session, now: day.generatedAt)
    var restored = try #require(await store.restoreSession(now: day.generatedAt.addingTimeInterval(1)))
    #expect(restored.target?.cycleDate == "2026-03-10" && restored.target?.baseTrimp == 124.1)
    #expect(restored.target?.crossing == .fired && restored.target?.update(projected: 12) == false)
    session.target = nil
    let oldData = try JSONCoding.encoder().encode(session)
    #expect(!(String(decoding: oldData, as: UTF8.self).contains("target")))
    #expect(try JSONCoding.decoder().decode(ActivitySession.self, from: oldData).target == nil)
}

#if DEBUG
@Test func parityFixtureServesHeartRateAndRefusesAllMutations() async throws {
    let api = FixtureEditAPI(directory: fixtureRoot.appendingPathComponent("parity"), parity: true)
    let snapshot = try await api.snapshot()
    #expect(snapshot.generatedAt == ISO8601DateFormatter().date(from: "2026-03-10T14:30:00Z"))
    let effort = try #require(snapshot.workouts.workouts.first { $0.kind == "detected" })
    let hr = try await api.heartRate(start: effort.start.addingTimeInterval(-10800), end: effort.end.addingTimeInterval(10800))
    #expect(hr.start == ISO8601DateFormatter().date(from: "2026-03-09T16:40:00Z") && !hr.minutes.isEmpty)
    let edit: EditBody = try fixture("edits/requests/edit.json")
    await #expect(throws: ClientError.rejected) { try await api.putEdit(id: "7300000000000000101", edit) }
    await #expect(throws: ClientError.rejected) { try await api.deleteEdit(id: "7300000000000000101") }
    let upload: ActivityUpload = try fixture("edits/requests/name.json")
    await #expect(throws: ClientError.rejected) { try await api.postActivity(upload) }
    #expect(await api.matchedRequests.isEmpty)
}
#endif
