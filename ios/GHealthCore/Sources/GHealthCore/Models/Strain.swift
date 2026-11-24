import Foundation

public struct Strain: Codable, Sendable {
    public var value: Double?
    public var band: StrainBand?
    public var status: ScoreStatus
    public var reason: Reason?
    public var confidence: Confidence?
    public var trimp: Double?
    public var hrCoverage: Double?
    public var coveredMinutes: Int?
    public var expectedMinutes: Int?
    public var coverageUntil: Date?
    public var avgHrBpm: Int?
    public var peakHrBpm: Int?
    public var restingHrBpm: Int?
    public var restingHrSource: String?
    public var maxHrBpm: Int?
    public var maxHrSource: String?
    public var zonesMinutes: Zones?
}
