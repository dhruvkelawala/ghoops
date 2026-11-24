import Foundation

public struct Collect: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var status: String
    public var pass: String
    public var from: String
    public var untilExclusive: String
    public var requests: Int
    public var durationMs: Int
    public var coreComplete: Bool
    @DefaultEmpty public var streams: [CollectedStream]
}

public struct CollectedStream: Codable, Sendable {
    public var stream: String
    public var dates: Int
    public var status: String
    public var records: Int
    public var error: String?
}

public struct PairResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var paired: Bool
    public var url: String?
    public var name: String?
    public var link: String?
    public var tokenCreatedAt: Date?
    public var tailscaleServeConfigured: Bool?
    public var pngPath: String?
}

public struct Schedule: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    @DefaultEmpty public var agents: [ScheduledAgent]
}

public struct ScheduledAgent: Codable, Sendable {
    public var label: String
    public var installed: Bool
    public var loaded: Bool
    public var path: String
}

public struct Config: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var values: ScoreConfig
    public var defaults: ScoreConfig
    public var path: String
}

public struct Export: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var exported: String
    public var id: String
    public var path: String
    public var bytes: Int
    public var plaintextExport: Bool
}
