import Foundation

public struct HeartRateBody: Codable, Sendable {
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
    public var cycleDate: String
    public var start: Date
    public var end: Date
    public var restingHrBpm: Int?
    public var maxHrBpm: Int?
    public var maxHrSource: String?
    public var ratesReason: Reason?
    @DefaultEmpty public var minutes: [HeartRateMinute]
}

public struct HeartRateMinute: Codable, Sendable {
    public var t: Date
    public var avgBpm: Double
    public var maxBpm: Int
}
