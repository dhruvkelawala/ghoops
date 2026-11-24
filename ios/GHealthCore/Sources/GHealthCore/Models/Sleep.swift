import Foundation

public struct SleepSummary: Codable, Sendable {
    public var performance: Performance
    public var performanceComposite: SleepComposite?
    public var asleepMinutes: Int?
    public var timeInBedMinutes: Int?
    public var need: SleepNeed
    public var efficiencyPct: Int?
    public var efficiencyBand: Band3?
    public var consistency: SleepConsistency
    public var stageTypical: StageTypical?
    public var stages: SleepStages?
    public var disturbances: Disturbances?
    public var minutesToFallAsleep: Int?
    public var bedtime: Date?
    public var wakeTime: Date?
    @DefaultEmpty public var naps: [Nap]
}

public struct Sleep: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var scoreConstants: ScoreConstants?
    public var syntheticFixture: Bool?
    public var freshness: Freshness
    public var date: String
    public var performance: Performance
    public var performanceComposite: SleepComposite?
    public var asleepMinutes: Int?
    public var timeInBedMinutes: Int?
    public var need: SleepNeed
    public var efficiencyPct: Int?
    public var efficiencyBand: Band3?
    public var consistency: SleepConsistency
    public var stageTypical: StageTypical?
    public var stages: SleepStages?
    public var disturbances: Disturbances?
    public var minutesToFallAsleep: Int?
    public var bedtime: Date?
    public var wakeTime: Date?
    @DefaultEmpty public var naps: [Nap]
    public var session: SleepSession?
    public var respiratoryRate: SleepBreathing?
    public var hypnogram: Hypnogram?
    @DefaultEmpty public var overnightHr: [HeartRatePoint]
    @DefaultEmpty public var overnightHrv: [HRVPoint]
}

public struct SleepComposite: Codable, Sendable {
    public var value: Int?
    public var band: Band3?
    public var status: ScoreStatus
    public var reason: Reason?
    public var weights: SleepCompositeWeights?
    public var parts: SleepCompositeParts?
}

public struct SleepCompositeWeights: Codable, Sendable, Equatable {
    public var sufficiency: Double
    public var consistency: Double
    public var efficiency: Double
}

public struct SleepCompositeParts: Codable, Sendable {
    public var sufficiency: Int
    public var consistency: Int?
    public var efficiency: Double?
}

public struct SleepNeed: Codable, Sendable {
    public var totalMinutes: Int
    public var baselineMinutes: Int
    public var strainExtraMinutes: Int
    public var debtExtraMinutes: Int
    public var napCreditMinutes: Int
    public var previousCycleStrain: Double?
    public var debtNightsUsed: Int
}

public struct SleepConsistency: Codable, Sendable {
    public var value: Int?
    public var band: Band3?
    public var status: ScoreStatus
    public var reason: Reason?
    public var nightsUsed: Int
    public var bedtimeSdMinutes: Double?
    public var wakeSdMinutes: Double?
}

public struct SleepStages: Codable, Sendable {
    public var light: SleepStage
    public var deep: SleepStage
    public var rem: SleepStage
    public var awake: SleepStage
    public var unstaged: SleepStage?
}

public struct SleepStage: Codable, Sendable {
    public var minutes: Int?
    public var segments: Int?
    public var pctOfAsleep: Double?
}

public struct Disturbances: Codable, Sendable {
    public var total: Int
    public var awakeSegments: Int
    public var shortAwakenings: Int
}

public struct Nap: Codable, Sendable {
    public var start: Date
    public var end: Date
    public var asleepMinutes: Int?
}

public struct SleepSession: Codable, Sendable {
    public var google: SleepGoogle?
    public var edit: SleepEdit?
    public var editRange: SleepEditRange?
    public var start: Date
    public var end: Date
    public var type: String?
    public var mainSleep: Bool
    public var processed: Bool?
    public var stagesStatus: String?
    public var minutesAwake: Int?
    public var minutesAfterWakeUp: Int?
    public var minutesInSleepPeriod: Int?
}

public struct SleepBreathing: Codable, Sendable {
    public var fullBpm: Double?
    public var deepBpm: Double?
    public var lightBpm: Double?
    public var remBpm: Double?
}

public struct Hypnogram: Codable, Sendable {
    public var outside: [SleepSegment]?
    public var start: Date
    public var end: Date
    @DefaultEmpty public var segments: [SleepSegment]
    @DefaultEmpty public var shortAwakenings: [SleepSegment]
    @DefaultEmpty public var unstaged: [Span]
}

public struct SleepSegment: Codable, Sendable {
    public var start: Date
    public var end: Date
    public var stage: String
}

public struct StageTypical: Codable, Sendable {
    public var windowNights: Int
    public var nightsUsed: Int
    public var nightsNeeded: Int?
    public var lowPercentile: Int?
    public var highPercentile: Int?
    public var light: StageRange
    public var deep: StageRange
    public var rem: StageRange
    public var awake: StageRange
    public var restorative: StageRange
}

public struct StageRange: Codable, Sendable {
    public var lowMinutes: Int?
    public var highMinutes: Int?
    public var nightsUsed: Int
}

public struct Span: Codable, Sendable {
    public var start: Date
    public var end: Date
}
