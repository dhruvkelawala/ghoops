import Foundation

public struct Days: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var freshness: Freshness
    public var from: String
    public var to: String
    @DefaultEmpty public var days: [DayRow]
    public var summary: [String:DayStats]
}

public struct DayRow: Codable, Sendable {
    public var date: String
    public var cycleStatus: String
    public var recovery: Int?
    public var recoveryBand: Band3?
    public var recoveryStatus: ScoreStatus
    public var recoveryReason: Reason?
    public var strain: Double?
    public var strainBand: StrainBand?
    public var strainStatus: ScoreStatus
    public var hrCoverage: Double?
    public var sleepPerformance: Int?
    public var sleepPerformanceBand: Band3?
    public var asleepMinutes: Int?
    public var sleepNeedMinutes: Int
    public var timeInBedMinutes: Int?
    public var efficiencyPct: Int?
    public var hrvRmssdMs: Double?
    public var restingHrBpm: Int?
    public var respiratoryRateBpm: Double?
    public var spo2Pct: Double?
    public var skinTempDeviationC: Double?
    public var steps: Int?
    public var activeZoneMinutes: Int?
    public var caloriesKcal: Int?
    public var workouts: Int
    public var detectedEfforts: Int
    public var zones13Minutes: Int?
    public var zones45Minutes: Int?
    public var strengthMinutes: Int?
    public var restorativeMinutes: Int?
    public var sleepConsistency: Int?
    public var vitalsAdverse: Int
}

public struct DayStats: Codable, Sendable {
    public var mean: Double?
    public var min: Double?
    public var max: Double?
    public var availableDays: Int
}
