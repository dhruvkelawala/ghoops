#if DEBUG
import Foundation

public enum FixtureSet: String, CaseIterable, Sendable {
    case parity, edit, fresh, stale, noSleep = "no_sleep", calibrating, newUser = "new_user", offline, unpaired
    case engineOdd = "engine_odd", engineNone = "engine_none"
    case recoveryWeights = "recovery_weights", recoveryNoWeights = "recovery_no_weights"
    case sleepUnstaged = "sleep_unstaged", sleepEdit = "sleep_edit"
    case sleepClassic = "sleep_classic", sleepUnknownStage = "sleep_unknown_stage"
    case strainSparse = "strain_sparse"
    case afterMidnight = "after_midnight"
    case honestMissing = "honest_missing"
    case healthOneNight = "health_one_night", healthAttention = "health_attention"
    case journalFirst = "journal_first", journalNone = "journal_none"
    case missingValues = "missing_values"
    case composite
}

public struct FixtureState: Sendable {
    public let cached: CachedSnapshot?
    public let now: Date
    public let offline: Bool
}

public enum FixtureLoader {
    public static func load(_ set: FixtureSet, bundle: Bundle = .main) throws -> FixtureState {
        func body<T: Decodable>(_ name: String, _: T.Type) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else { throw ClientError.incompatibleVersion }
            return try JSONCoding.decoder().decode(T.self, from: Data(contentsOf: url))
        }
        if set == .unpaired { return FixtureState(cached: nil, now: .now, offline: false) }
        let name = switch set {
        case .parity: "parity/snapshot"
        case .edit: "edits/snapshot_edited"
        case .stale: "snapshot_stale"
        case .composite: "snapshot_composite"
        default: "snapshot_fresh"
        }
        var snapshot = try body(name, Snapshot.self)
        switch set {
        case .healthOneNight, .healthAttention:
            let attention = set == .healthAttention
            let keys = ["resting_hr", "respiratory_rate"]
            snapshot.day.vitals.adverse = keys
            snapshot.day.vitals.outsideRange = keys
            snapshot.day.vitals.persistent = attention ? keys : []
            snapshot.day.vitals.monitorState = attention ? "attention" : "outside"
            snapshot.day.vitals.metricsWithRange = 5
            snapshot.day.vitals.metrics.respiratoryRate.value = attention ? 16.1 : 15.9
            snapshot.day.vitals.metrics.respiratoryRate.rangeLow = 14.1
            snapshot.day.vitals.metrics.respiratoryRate.rangeHigh = 15.6
            snapshot.day.vitals.metrics.respiratoryRate.position = "above"
            snapshot.day.vitals.metrics.restingHr.value = attention ? 60 : 59
            snapshot.day.vitals.metrics.restingHr.rangeLow = 51
            snapshot.day.vitals.metrics.restingHr.rangeHigh = 57
            snapshot.day.vitals.metrics.restingHr.position = "above"
            snapshot.day.vitals.metrics.hrvRmssd.value = attention ? 46 : 48
            snapshot.day.vitals.metrics.hrvRmssd.rangeLow = 41
            snapshot.day.vitals.metrics.hrvRmssd.rangeHigh = 60
            snapshot.day.vitals.metrics.spo2.value = 96
            snapshot.day.vitals.metrics.spo2.rangeLow = 95
            snapshot.day.vitals.metrics.spo2.rangeHigh = 98
            snapshot.day.vitals.metrics.skinTempDeviation.value = attention ? 0.2 : 0.1
            snapshot.day.vitals.metrics.skinTempDeviation.rangeLow = -0.3
            snapshot.day.vitals.metrics.skinTempDeviation.rangeHigh = 0.3
            snapshot.day.healthFlags = attention ? [HealthFlag(code: "vitals_outside_range", severity: "attention", message: "2 overnight vitals have been outside your usual range for 2 nights in a row, in the less favourable direction.")] : []
        case .journalFirst:
            snapshot.journal?.entries = []
        case .journalNone:
            snapshot.journal = nil
        case .afterMidnight:
            snapshot.generatedAt = ActivityTime.day(GoopFormat.addingDays(1, to: snapshot.defaultDate)).addingTimeInterval(10 * 60)
            snapshot.day.generatedAt = snapshot.generatedAt
        case .honestMissing:
            snapshot.sleep.need.previousCycleStrain = nil
            snapshot.sleep.need.strainExtraMinutes = 0
            snapshot.sleep.need.debtNightsUsed = 2
            snapshot.sleep.need.totalMinutes -= snapshot.day.sleep.need.strainExtraMinutes
            snapshot.sleep.performance.value = 95
            snapshot.day.sleep.need = snapshot.sleep.need
            snapshot.day.sleep.performance = snapshot.sleep.performance
            snapshot.day.sleepPlan?.needParts.cycleStrain = nil
            snapshot.day.sleepPlan?.needParts.strainExtraMinutes = 0
            snapshot.day.sleepPlan?.needParts.debtNightsUsed = 1
            if var plan = snapshot.day.sleepPlan {
                plan.needMinutes = plan.needParts.baselineMinutes + plan.needParts.debtExtraMinutes - plan.needParts.napCreditMinutes
                plan.status = .unavailable
                plan.goals = []
                snapshot.day.sleepPlan = plan
            }
            if let index = snapshot.workouts.workouts.firstIndex(where: { $0.cycleDate == snapshot.defaultDate }) {
                snapshot.workouts.workouts[index].category = "strength"
                snapshot.workouts.workouts[index].exerciseType = "WEIGHTLIFTING"
                snapshot.workouts.workouts[index].displayName = "Weightlifting"
                snapshot.day.workouts = [snapshot.workouts.workouts[index]]
            }
            snapshot.day.vitals.metrics.skinTempDeviation.position = nil
            snapshot.freshness.deviceStale = true
            snapshot.freshness.deviceSyncSource = "scope_missing"
        case .engineOdd:
            let engine = try body("engine/odd_constants", EngineFixture.self)
            engine.apply(to: &snapshot)
        case .engineNone:
            snapshot.day.scoreConstants = nil; snapshot.sleep.scoreConstants = nil
            snapshot.day.sleep.efficiencyBand = nil; snapshot.sleep.efficiencyBand = nil
            snapshot.day.vitals.valuesNeeded = nil
            snapshot.day.sleepPlan?.nightsNeeded = nil; snapshot.day.sleepPlan?.windowNights = nil
            snapshot.day.sleep.stageTypical?.nightsNeeded = nil
            snapshot.day.sleep.stageTypical?.lowPercentile = nil; snapshot.day.sleep.stageTypical?.highPercentile = nil
            snapshot.sleep.stageTypical?.nightsNeeded = nil
            snapshot.sleep.stageTypical?.lowPercentile = nil; snapshot.sleep.stageTypical?.highPercentile = nil
        case .recoveryWeights: snapshot.day.recovery = try body("recovery/weights_40_30_30", Recovery.self)
        case .recoveryNoWeights: snapshot.day.recovery = try body("recovery/no_weights", Recovery.self)
        case .sleepUnstaged, .sleepEdit:
            snapshot.sleep = try body(set == .sleepEdit ? "sleep_edit/sleep_extended" : "sleep_unstaged", Sleep.self)
            snapshot.day = try body("day_unstaged", Day.self)
        case .sleepClassic:
            // Google's classic night: asleep and restless, with no light, deep or REM.
            snapshot.sleep.session?.type = "CLASSIC"
            if var hypnogram = snapshot.sleep.hypnogram {
                hypnogram.segments = hypnogram.segments.map { segment in var copy = segment; copy.stage = segment.stage == "awake" ? "restless" : "asleep"; return copy }
                snapshot.sleep.hypnogram = hypnogram
            }
            for path in [\SleepStages.light, \SleepStages.deep, \SleepStages.rem] { snapshot.sleep.stages?[keyPath: path] = SleepStage() }
        case .sleepUnknownStage:
            // A stage value the app doesn't know, inside a staged night.
            if var hypnogram = snapshot.sleep.hypnogram, let index = hypnogram.segments.firstIndex(where: { $0.stage == "rem" }) {
                hypnogram.segments[index].stage = "unknown"
                snapshot.sleep.hypnogram = hypnogram
            }
        case .noSleep:
            snapshot.day = try body("day_no_sleep", Day.self)
            snapshot.sleep = try body("sleep_no_sleep", Sleep.self)
        case .calibrating: snapshot.day = try body("day_calibrating", Day.self)
        case .strainSparse:
            snapshot.day = try body("day_strain_sparse", Day.self)
            if let index = snapshot.days.days.firstIndex(where: { $0.date == snapshot.day.date }) {
                let strain = snapshot.day.strain
                snapshot.days.days[index].cycleStatus = snapshot.day.cycle.status
                snapshot.days.days[index].strain = strain.value
                snapshot.days.days[index].strainBand = strain.band
                snapshot.days.days[index].strainStatus = strain.status
                snapshot.days.days[index].hrCoverage = strain.hrCoverage
            }
        case .newUser:
            snapshot.day = try body("day_new_user", Day.self)
            snapshot.status = try body("status_new_user", Status.self)
            snapshot.sleep.stageTypical = snapshot.day.sleep.stageTypical
        case .missingValues: blankValueBlocks(&snapshot)
        default: break
        }
        let age: TimeInterval = set == .stale ? 6 * 3600 : set == .offline ? 2 * 86400 : 0
        let meta = SnapshotMeta(fetchedAt: snapshot.generatedAt.addingTimeInterval(-age), serverURL: "https://fixture.invalid:8787")
        return FixtureState(cached: CachedSnapshot(snapshot: snapshot, meta: meta), now: snapshot.generatedAt, offline: set == .offline)
    }
    /// Empties every value block at once: the first workout's Strain, time in bed, heart-rate coverage and the
    /// day's average heart rate, plus a detected effort with no Strain (live-polish-spec §4.1). The day is not self-consistent.
    public static func blankValueBlocks(_ snapshot: inout Snapshot) {
        let kickboxing = snapshot.day.workouts[0].id
        snapshot.day.workouts[0].strain = nil
        for index in snapshot.workouts.workouts.indices where snapshot.workouts.workouts[index].id == kickboxing { snapshot.workouts.workouts[index].strain = nil }
        snapshot.day.sleep.timeInBedMinutes = nil; snapshot.sleep.timeInBedMinutes = nil
        snapshot.day.strain.hrCoverage = nil; snapshot.day.strain.avgHrBpm = nil
        var effort = snapshot.day.workouts[0]
        effort.kind = "detected"; effort.category = "detected"; effort.id = "effort-2026-03-10T09:05:00Z"
        effort.exerciseType = nil; effort.displayName = "Detected effort"
        effort.start = ISO8601DateFormatter().date(from: "2026-03-10T09:05:00Z")!
        effort.end = ISO8601DateFormatter().date(from: "2026-03-10T09:40:00Z")!
        effort.elapsedMinutes = 35; effort.activeMinutes = nil
        effort.strain = nil; effort.trimp = nil; effort.hrCoverage = nil; effort.confidence = nil
        effort.avgHrBpm = nil; effort.peakHrBpm = nil; effort.zonesMinutes = nil
        effort.provider = nil; effort.source = nil; effort.original = nil; effort.edit = nil; effort.edited = nil
        effort.suggested = nil; effort.notes = nil; effort.rpe = nil; effort.origin = nil; effort.pausedMinutes = nil
        effort.merged = []; effort.pauses = []; effort.hrSeries = []
        snapshot.day.workouts.append(effort)
    }
}
struct EngineFixture: Decodable {
    var scoreConstants: ScoreConstants
    var calibration: Counts
    var vitalsValuesNeeded: Int
    var sleepPlan: Plan
    var stageTypical: Typical
    var comparisonWindowDays: Int
    var collectorIntervalMinutes: Int
    struct Counts: Decodable { var valuesNeeded: Int; var valuesForFullConfidence: Int }
    struct Plan: Decodable { var nightsNeeded: Int; var windowNights: Int }
    struct Typical: Decodable { var windowNights: Int; var nightsNeeded: Int; var lowPercentile: Int; var highPercentile: Int }

    func apply(to snapshot: inout Snapshot) {
        snapshot.day.scoreConstants = scoreConstants; snapshot.sleep.scoreConstants = scoreConstants
        snapshot.day.recovery.calibration.valuesNeeded = calibration.valuesNeeded
        snapshot.day.recovery.calibration.valuesForFullConfidence = calibration.valuesForFullConfidence
        snapshot.day.vitals.valuesNeeded = vitalsValuesNeeded
        snapshot.day.sleepPlan?.nightsNeeded = sleepPlan.nightsNeeded; snapshot.day.sleepPlan?.windowNights = sleepPlan.windowNights
        snapshot.day.sleep.stageTypical?.windowNights = stageTypical.windowNights
        snapshot.day.sleep.stageTypical?.nightsNeeded = stageTypical.nightsNeeded
        snapshot.day.sleep.stageTypical?.lowPercentile = stageTypical.lowPercentile
        snapshot.day.sleep.stageTypical?.highPercentile = stageTypical.highPercentile
        snapshot.sleep.stageTypical?.windowNights = stageTypical.windowNights
        snapshot.sleep.stageTypical?.nightsNeeded = stageTypical.nightsNeeded
        snapshot.sleep.stageTypical?.lowPercentile = stageTypical.lowPercentile
        snapshot.sleep.stageTypical?.highPercentile = stageTypical.highPercentile
        snapshot.day.comparison?.windowDays = comparisonWindowDays
        snapshot.status.collector.intervalMinutes = collectorIntervalMinutes
    }
}
#endif
