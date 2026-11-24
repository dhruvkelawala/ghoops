import Foundation

public struct APIError: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var error: ErrorDetail
}

public struct ErrorDetail: Codable, Sendable {
    public var code: String
    public var message: String
    public var httpStatus: Int?
}
