import Foundation

public struct Brief: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var disclosure: String
    public var part: String?
    public var date: String
    public var freshness: BriefFreshness
    public var recovery: BriefRecovery
    public var strain: BriefStrain
    public var strainTarget: BriefStrainTarget?
    public var sleep: BriefSleep
    public var sleepPlan: BriefSleepPlan?
    public var trend: [String: BriefTrend]?
    @DefaultEmpty public var vitalsAdverse: [String]
    @DefaultEmpty public var workouts: [BriefWorkout]
    @DefaultEmpty public var healthFlags: [String]
    public var review: BriefReview?
    public var note: String
}

public struct BriefFreshness: Codable, Sendable {
    public var collectedAt: Date?
    public var collectorStale: Bool
    public var deviceStale: Bool?
}

public struct BriefRecovery: Codable, Sendable {
    public var status: ScoreStatus
    public var reason: Reason?
    public var band: Band3?
    public var calibrating: Bool
    public var value: Int?
}

public struct BriefStrain: Codable, Sendable {
    public var status: ScoreStatus
    public var reason: Reason?
    public var band: StrainBand?
    public var confidence: Confidence?
    public var value: Double?
    public var hrCoverage: Double?
}

public struct BriefSleep: Codable, Sendable {
    public var status: ScoreStatus
    public var reason: Reason?
    public var band: Band3?
    public var performance: Int?
    public var asleepMinutes: Int?
    public var needMinutes: Int?
}

public struct BriefWorkout: Codable, Sendable {
    public var kind: String
    public var category: String
    public var exerciseType: String?
    public var suggestedExerciseType: String?
    public var elapsedMinutes: Double?
    public var strain: Double?
}

public struct BriefStrainTarget: Codable, Sendable {
    public var status: ScoreStatus
    public var reason: Reason?
    public var intent: String
    public var position: String?
    public var low: Double?
    public var high: Double?
}

public struct BriefSleepPlan: Codable, Sendable {
    public var status: ScoreStatus
    public var reason: Reason?
    public var wakeSource: String
    public var needMinutes: Int?
    public var bedtime: Date?
}

public struct BriefTrend: Codable, Sendable {
    public var direction: String?
    public var days7: Int
    public var days30: Int
    public var mean7: Double?
    public var mean30: Double?
}

public struct BriefReview: Codable, Sendable {
    public var workouts: Int
    public var detectedEfforts: Int
    public var newFlags: [String]
    public var zones13Minutes: Int?
    public var zones45Minutes: Int?
}
