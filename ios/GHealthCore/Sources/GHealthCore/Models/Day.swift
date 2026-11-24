import Foundation

public struct Day: Codable, Sendable {
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
    public var isCurrentCycle: Bool
    public var cycle: Cycle
    public var recovery: Recovery
    public var strain: Strain
    public var strainTarget: StrainTarget?
    public var sleep: SleepSummary
    public var sleepPlan: SleepPlan?
    public var vitals: Vitals
    public var activity: Activity
    @DefaultEmpty public var workouts: [Workout]
    public var strengthMinutes: Int?
    public var comparison: Comparison?
    public var vo2Max: VO2Max
    @DefaultEmpty public var healthFlags: [HealthFlag]
}

public struct Cycle: Codable, Sendable {
    public var start: Date
    public var end: Date?
    public var status: String
    public var startSource: String
    public var endSource: String?
}

public struct Comparison: Codable, Sendable {
    public var windowDays: Int
    public var from: String
    public var to: String
    public var minDays: Int
    public var metrics: [String: ComparisonMetric]
}

public struct ComparisonMetric: Codable, Sendable {
    public var mean: Double?
    public var availableDays: Int
}
