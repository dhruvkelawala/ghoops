import Foundation

public struct SleepPlan: Codable, Sendable {
    public var status: ScoreStatus
    public var reason: Reason?
    public var needMinutes: Int
    public var needParts: SleepPlanNeed
    public var wakeTarget: Date?
    public var wakeSource: String
    public var efficiencyPctUsed: Double?
    public var latencyMinutesUsed: Int?
    public var nightsUsed: Int
    public var nightsNeeded: Int?
    public var windowNights: Int?
    public var goals: [SleepGoal]
}

public struct SleepPlanNeed: Codable, Sendable {
    public var baselineMinutes: Int
    public var strainExtraMinutes: Int
    public var debtExtraMinutes: Int
    public var napCreditMinutes: Int
    public var cycleStrain: Double?
    public var debtNightsUsed: Int
}

public struct SleepGoal: Codable, Sendable {
    public var pct: Int
    public var inBedMinutes: Int
    public var bedtime: Date
}
