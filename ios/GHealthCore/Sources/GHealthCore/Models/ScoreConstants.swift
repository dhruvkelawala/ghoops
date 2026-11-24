/// The engine's numbers (contract §5.1.1). Nil when the Mac predates them; never substitute values.
public struct ScoreConstants: Codable, Sendable, Equatable {
    public var recovery: RecoveryConstants
    public var strain: StrainModel
    public var sleep: SleepConstants
    public var workouts: WorkoutOverlap
    public var vitals: VitalConstants?
    public var hrvTrend: HRVTrendConstants?
}

public struct Band3Edges: Codable, Sendable, Equatable {
    public var medium: Int
    public var high: Int
}

public struct RecoveryConstants: Codable, Sendable, Equatable {
    public var bands: Band3Edges
    public var penaltyMax: Double
}

public struct StrainModel: Codable, Sendable, Equatable {
    public var bands: StrainBandEdges
    public var zonesHrr: ZoneFloors
    public var trimp: TrimpCoefficients
    public var scale: StrainScale
    public var coverage: CoverageCuts
}

public struct StrainBandEdges: Codable, Sendable, Equatable {
    public var moderate: Double
    public var strenuous: Double
    public var allOut: Double
}

public struct ZoneFloors: Codable, Sendable, Equatable {
    public var z1: Double
    public var z2: Double
    public var z3: Double
    public var z4: Double
    public var z5: Double
    public var all: [Double] { [z1, z2, z3, z4, z5] }
}

public struct TrimpCoefficients: Codable, Sendable, Equatable {
    public var a: Double
    public var b: Double
}

public struct StrainScale: Codable, Sendable, Equatable {
    public var k: Double
    public var trimpCap: Double
}

public struct CoverageCuts: Codable, Sendable, Equatable {
    public var medium: Double
    public var high: Double
}

public struct SleepConstants: Codable, Sendable, Equatable {
    public var unstagedCountsAs: String?
    public var performanceBands: Band3Edges
    public var consistencyBands: Band3Edges
    public var efficiencyBands: Band3Edges
    public var composite: SleepCompositeConstants?
}

public struct SleepCompositeConstants: Codable, Sendable, Equatable {
    public var weights: SleepCompositeWeights
    public var efficiencyZeroPct: Int
    public var efficiencyFullPct: Int
}

public struct WorkoutOverlap: Codable, Sendable, Equatable {
    public var recordedHiddenOverlap: Double
    public var effortHiddenOverlap: Double
}


public struct HRVTrendConstants: Codable, Sendable, Equatable {
    public var days: Int
    public var minNights: Int
    public var bandSd: Double
    public var minBaseline: Int
}

public struct VitalConstants: Codable, Sendable, Equatable {
    public var rangeSd: Double
    public var attentionNights: Int
    public var attentionMinVitals: Int
}
