import Foundation

public struct Recovery: Codable, Sendable {
    public var value: Int?
    public var band: Band3?
    public var status: ScoreStatus
    public var reason: Reason?
    @DefaultEmpty public var missingInputs: [String]
    public var confidence: Confidence?
    public var calibrating: Bool
    public var calibration: Calibration
    public var inputs: RecoveryInputs
    public var baseline: RecoveryBaseline
    public var components: RecoveryComponents?
}

public struct RecoveryInputs: Codable, Sendable {
    public var hrvRmssdMs: Double?
    public var restingHrBpm: Int?
    public var respiratoryRateBpm: Double?
    public var skinTempDeviationC: Double?
    public var sleepPerformance: Int?
}

public struct RecoveryBaseline: Codable, Sendable {
    public var windowDays: Int
    public var hrv: HRVBaseline
    public var restingHr: Baseline
    public var respiratoryRate: Baseline
}

public struct HRVBaseline: Codable, Sendable {
    public var valuesUsed: Int
    public var lnMean: Double?
    public var lnSd: Double?
    public var sdFloorApplied: Bool?
    public var meanMs: Double?
}

public struct Baseline: Codable, Sendable {
    public var valuesUsed: Int
    public var mean: Double?
    public var sd: Double?
    public var sdFloorApplied: Bool?
}

/// The factors the Mac's engine used for this score (contract §5.3).
public struct RecoveryWeights: Codable, Sendable, Equatable {
    public var hrv: Double
    public var restingHr: Double
    public var sleep: Double
}

public struct RecoveryComponents: Codable, Sendable {
    public var hrvZ: Double
    public var hrvScore: Double
    public var restingHrZ: Double
    public var restingHrScore: Double
    public var sleepScore: Int
    public var weightedBase: Double
    public var weights: RecoveryWeights?
    public var respiratoryRateZ: Double?
    public var respiratoryRatePenalty: Double
    public var skinTempZ: Double?
    public var skinTempPenalty: Double
    @DefaultEmpty public var optionalMissing: [String]
}
