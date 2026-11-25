import Foundation

public enum PairedDeviceState: String, Codable, Sendable {
    case pending, active
}

public struct PairRedeemResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var generatedAt: Date
    public var timezone: String
    public var syntheticFixture: Bool?
    public var deviceId: String
    public var credential: String
    public var verificationCode: String
    public var macName: String
    public var profileId: String
    public var expiresAt: Date
}

public struct PairStatusResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var generatedAt: Date
    public var timezone: String
    public var syntheticFixture: Bool?
    public var deviceId: String
    public var state: PairedDeviceState
}

public struct PairDevicesResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var generatedAt: Date
    public var timezone: String
    public var syntheticFixture: Bool?
    public var devices: [PairedDeviceSummary]
}

public struct PairedDeviceSummary: Codable, Sendable {
    public var id: String
    public var name: String
    public var state: PairedDeviceState
    public var createdAt: Date
    public var approvedAt: Date?
}
