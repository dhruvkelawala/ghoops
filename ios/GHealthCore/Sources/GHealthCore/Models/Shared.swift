import Foundation

public protocol OpenStringEnum: Codable, Hashable, Sendable {
    var rawValue: String { get }
    init(rawValue: String)
}

public extension OpenStringEnum {
    init(from decoder: any Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum Band3: OpenStringEnum {
    case high
    case medium
    case low
    case unknown(String)
    public init(rawValue: String) {
        switch rawValue {
        case "high": self = .high
        case "medium": self = .medium
        case "low": self = .low
        default: self = .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case .unknown(let value): value
        }
    }
}

public enum StrainBand: OpenStringEnum {
    case light
    case moderate
    case strenuous
    case allOut
    case unknown(String)
    public init(rawValue: String) {
        switch rawValue {
        case "light": self = .light
        case "moderate": self = .moderate
        case "strenuous": self = .strenuous
        case "all_out": self = .allOut
        default: self = .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .light: "light"
        case .moderate: "moderate"
        case .strenuous: "strenuous"
        case .allOut: "all_out"
        case .unknown(let value): value
        }
    }
}

public enum ScoreStatus: OpenStringEnum {
    case ok
    case calibrating
    case inProgress
    case pending
    case unavailable
    case unknown(String)
    public init(rawValue: String) {
        switch rawValue {
        case "ok": self = .ok
        case "calibrating": self = .calibrating
        case "in_progress": self = .inProgress
        case "pending": self = .pending
        case "unavailable": self = .unavailable
        default: self = .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .ok: "ok"
        case .calibrating: "calibrating"
        case .inProgress: "in_progress"
        case .pending: "pending"
        case .unavailable: "unavailable"
        case .unknown(let value): value
        }
    }
}

public enum Confidence: OpenStringEnum {
    case high
    case medium
    case low
    case unknown(String)
    public init(rawValue: String) {
        switch rawValue {
        case "high": self = .high
        case "medium": self = .medium
        case "low": self = .low
        default: self = .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        case .unknown(let value): value
        }
    }
}

public enum MetricStatus: OpenStringEnum {
    case available
    case missing
    case notSynced
    case unavailable
    case permissionMissing
    case conflict
    case unknown(String)
    public init(rawValue: String) {
        switch rawValue {
        case "available": self = .available
        case "missing": self = .missing
        case "not_synced": self = .notSynced
        case "unavailable": self = .unavailable
        case "permission_missing": self = .permissionMissing
        case "conflict": self = .conflict
        default: self = .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .available: "available"
        case .missing: "missing"
        case .notSynced: "not_synced"
        case .unavailable: "unavailable"
        case .permissionMissing: "permission_missing"
        case .conflict: "conflict"
        case .unknown(let value): value
        }
    }
}

public enum Reason: OpenStringEnum {
    case noSleep
    case sleepProcessing
    case noHrv
    case hrvConflict
    case noRestingHr
    case rhrConflict
    case insufficientBaseline
    case cycleNotStarted
    case restingHrUnknown
    case maxHrUnknown
    case noHeartRate
    case lowCoverage
    case insufficientNights
    case noData
    case unknown(String)
    public init(rawValue: String) {
        switch rawValue {
        case "no_sleep": self = .noSleep
        case "sleep_processing": self = .sleepProcessing
        case "no_hrv": self = .noHrv
        case "hrv_conflict": self = .hrvConflict
        case "no_resting_hr": self = .noRestingHr
        case "rhr_conflict": self = .rhrConflict
        case "insufficient_baseline": self = .insufficientBaseline
        case "cycle_not_started": self = .cycleNotStarted
        case "resting_hr_unknown": self = .restingHrUnknown
        case "max_hr_unknown": self = .maxHrUnknown
        case "no_heart_rate": self = .noHeartRate
        case "low_coverage": self = .lowCoverage
        case "insufficient_nights": self = .insufficientNights
        case "no_data": self = .noData
        default: self = .unknown(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .noSleep: "no_sleep"
        case .sleepProcessing: "sleep_processing"
        case .noHrv: "no_hrv"
        case .hrvConflict: "hrv_conflict"
        case .noRestingHr: "no_resting_hr"
        case .rhrConflict: "rhr_conflict"
        case .insufficientBaseline: "insufficient_baseline"
        case .cycleNotStarted: "cycle_not_started"
        case .restingHrUnknown: "resting_hr_unknown"
        case .maxHrUnknown: "max_hr_unknown"
        case .noHeartRate: "no_heart_rate"
        case .lowCoverage: "low_coverage"
        case .insufficientNights: "insufficient_nights"
        case .noData: "no_data"
        case .unknown(let value): value
        }
    }
}

public struct ScoreConfig: Codable, Sendable {
    public var maxHrOverrideBpm: Int?
    public var sleepBaseNeedMinutes: Int
    public var trimpProfile: String
    public var sportAliases: [String: String]
    public var strainIntent: String?
    public var wakeTarget: String?
    public var sleepScoreMode: String?
    private enum CodingKeys: String, CodingKey { case maxHrOverrideBpm, sleepBaseNeedMinutes, trimpProfile, sportAliases, strainIntent, wakeTarget, sleepScoreMode }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxHrOverrideBpm = try c.decodeIfPresent(Int.self, forKey: .maxHrOverrideBpm)
        sleepBaseNeedMinutes = try c.decode(Int.self, forKey: .sleepBaseNeedMinutes)
        trimpProfile = try c.decode(String.self, forKey: .trimpProfile)
        sportAliases = try c.decodeIfPresent([String: String].self, forKey: .sportAliases) ?? [:]
        strainIntent = try c.decodeIfPresent(String.self, forKey: .strainIntent)
        wakeTarget = try c.decodeIfPresent(String.self, forKey: .wakeTarget)
        sleepScoreMode = try c.decodeIfPresent(String.self, forKey: .sleepScoreMode)
    }
}

public struct Freshness: Codable, Sendable {
    public var collectedAt: Date?
    public var collectAgeMinutes: Int?
    public var lastCollectStatus: String
    public var collectorStale: Bool
    public var deviceLastSyncAt: Date?
    public var deviceSyncAgeMinutes: Int?
    public var deviceStale: Bool?
    public var deviceSyncSource: String
    public var bandSyncStale: Bool { deviceStale == true && deviceSyncSource != "scope_missing" }
}

public struct Zones: Codable, Sendable {
    public var below: Int
    public var z1: Int
    public var z2: Int
    public var z3: Int
    public var z4: Int
    public var z5: Int
}

public struct Metric: Codable, Sendable {
    public var value: Double?
    public var unit: String
    public var status: MetricStatus
    public var reason: Reason?
}

public struct HealthFlag: Codable, Sendable {
    public var code: String
    public var severity: String
    public var message: String
}

public struct Performance: Codable, Sendable {
    public var value: Int?
    public var band: Band3?
    public var status: ScoreStatus
    public var reason: Reason?
}

public struct Calibration: Codable, Sendable {
    public var nightsUsed: Int { min(hrvValues, restingHrValues) }
    public var valuesNeeded: Int
    public var valuesForFullConfidence: Int
    public var hrvValues: Int
    public var restingHrValues: Int
}

public struct HeartRatePoint: Codable, Sendable {
    public var t: Date
    public var bpm: Int
    public init(t: Date, bpm: Int) { self.t = t; self.bpm = bpm }
}

public struct HRVPoint: Codable, Sendable {
    public var t: Date
    public var rmssdMs: Double
}
