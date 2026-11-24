import Foundation

public protocol WeekFetching: Sendable {
    func week(date: String?) async throws -> Week
}

/// The Mac's `week` body (contract §5.16, week-review-spec.md §4.2). The app shows these numbers and works out none of them.
public struct Week: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var kind: String
    public var generatedAt: Date
    public var date: String
    public var from: String
    public var to: String
    public var weekEnd: String
    public var daysCounted: Int
    public var complete: Bool
    public var lastWeek: WeekWindow
    public var metrics: WeekMetrics
    public var workouts: WeekWorkouts
    public var targets: WeekTargets
}

public struct WeekWindow: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
}

public struct WeekMetric: Codable, Sendable, Equatable {
    public var value: Double?
    public var availableDays: Int
    public var lastWeek: Double?
    public var change: Double?
    public var usual: Double?
}

public struct WeekMetrics: Codable, Sendable, Equatable {
    public var recovery: WeekMetric
    public var strain: WeekMetric
    public var sleepPerformance: WeekMetric
    public var asleepMinutes: WeekMetric
    public var sleepConsistency: WeekMetric
    public var hrvRmssdMs: WeekMetric
    public var restingHrBpm: WeekMetric
    public var zones13Minutes: WeekMetric
    public var zones45Minutes: WeekMetric
    public var strengthMinutes: WeekMetric
    public var steps: WeekMetric
}

public struct WeekSport: Codable, Sendable, Equatable {
    public var exerciseType: String
    public var displayName: String
    public var category: String
    public var count: Int
}

public struct WeekWorkouts: Codable, Sendable, Equatable {
    public var total: Int
    public var lastWeekTotal: Int
    public var detectedEfforts: Int
    public var bySport: [WeekSport]
}

public struct WeekTargets: Codable, Sendable, Equatable {
    public var sleep: WeekSleepTarget
    public var activity: WeekActivityTarget
    public var strength: WeekStrengthTarget
}

public struct WeekSleepTarget: Codable, Sendable, Equatable {
    public var status: String
    public var minMinutes: Int
    public var nights: Int
    public var metNights: Int
    public var missingNights: Int
}

public struct WeekActivityTarget: Codable, Sendable, Equatable {
    public var status: String
    public var minutes: Int
    public var vigorousWeight: Int
    public var creditMinutes: Int?
    public var missingDays: Int
}

public struct WeekStrengthTarget: Codable, Sendable, Equatable {
    public var status: String
    public var days: Int
    public var metDays: Int
    public var missingDays: Int
}
