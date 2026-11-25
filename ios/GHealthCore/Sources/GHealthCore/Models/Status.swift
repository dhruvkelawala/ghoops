import Foundation

public struct Status: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var freshness: Freshness
    public var defaultDate: String
    public var auth: AuthStatus
    public var collector: Collector
    public var device: DeviceStatus
    public var store: StoreStatus
    public var calibration: CalibrationStatus
    public var userResources: UserResources
    public var providerTimezone: String?
    public var server: ServerVersion
    public var editLimits: EditLimits?
}

public struct AuthStatus: Codable, Sendable {
    public var authorized: Bool
    public var state: String
    public var refreshable: Bool
    @DefaultEmpty public var missingScopes: [String]
    public var partialPermissions: Bool
}

public struct Collector: Codable, Sendable {
    public var scheduleInstalled: Bool
    public var intervalMinutes: Int
    public var lastRun: CollectRun?
    public var lastCoreSuccessAt: Date?
    @DefaultEmpty public var streams: [StreamStatus]
}

public struct CollectRun: Codable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date
    public var status: String
    public var pass: String
    public var coreComplete: Bool
    public var requests: Int
    @DefaultEmpty public var failedStreams: [String]
}

public struct StreamStatus: Codable, Sendable {
    public var stream: String
    public var lastDate: String?
    public var status: String
    public var lastSuccessAt: Date?
    public var error: String?
}

public struct DeviceStatus: Codable, Sendable {
    public var status: String
    public var name: String?
    public var batteryLevel: Int?
    public var batteryStatus: String?
    public var lastSyncAt: Date?
}

public struct StoreStatus: Codable, Sendable {
    public var oldestDate: String?
    public var newestDate: String?
    public var heartRateDays: Int
}

public struct CalibrationStatus: Codable, Sendable {
    public var status: String
    public var hrvValues: Int
    public var restingHrValues: Int
    public var valuesNeeded: Int
    public var valuesForFullConfidence: Int
}

public struct UserResources: Codable, Sendable {
    public var profile: UserResource
    public var settings: UserResource
    public var pairedDevices: UserResource
    public var irnProfile: IRNProfile
}

public struct UserResource: Codable, Sendable {
    public var status: String
    public var fetchedAt: Date?
}

public struct IRNProfile: Codable, Sendable {
    public var status: String
    public var fetchedAt: Date?
    public var onboarded: Bool?
    public var enrolled: Bool?
}

public struct ServerVersion: Codable, Sendable {
    public var version: String
    public var revision: String
    public var profileId: String?
}
