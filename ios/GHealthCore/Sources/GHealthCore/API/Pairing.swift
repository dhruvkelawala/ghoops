import Foundation
import Security

public enum PairingError: Error, LocalizedError {
    case keychain(OSStatus), activityRunning
    case invalidCode, enrolmentExpired, enrolmentDeclined
    public var errorDescription: String? {
        switch self {
        case .keychain: "ghoops couldn't use the pairing saved on this phone. Run ghoops pair on your Mac, then scan its code."
        case .activityRunning: "Finish your activity before you pair with another Mac."
        case .invalidCode: PairingCopy.invalidCode
        case .enrolmentExpired: PairingCopy.expiredCode
        case .enrolmentDeclined: PairingCopy.declined
        }
    }
}

public struct Credentials: Sendable {
    public let url: URL
    public let name: String
    public let token: String
    public let profileId: String?
    private let pairedAt: Date

    init(_ record: PairingRecord) {
        url = record.url
        name = record.name
        token = record.credential
        profileId = record.profileId
        pairedAt = record.pairedAt
    }

    public func samePairing(as other: Self?) -> Bool {
        guard let other else { return false }
        return url == other.url && token == other.token && pairedAt == other.pairedAt
    }

    public func client(widget: Bool = false, onUnauthorized: (@Sendable () async -> Void)? = nil) -> APIClient {
        APIClient(baseURL: url, token: token, profileId: profileId, widget: widget, onUnauthorized: onUnauthorized)
    }
}

public actor PairingRepository {
    private let defaults: UserDefaults
    private let tokens: any TokenStore
    private let records: any RecordStore
    private let revoked: RevokedCredentials
    private static let legacyURL = "serverURL"
    private static let legacyName = "macName"

    public static func current(accessGroup: String, suiteName: String) -> PairingRecord? {
        guard let record = try? KeychainRecordStore(accessGroup: accessGroup).load(),
              !RevokedCredentials(suiteName: suiteName).contains(record.credential) else { return nil }
        return record
    }

    public init(suiteName: String, accessGroup: String) {
        self.init(suiteName: suiteName, tokens: KeychainTokenStore(accessGroup: accessGroup), records: KeychainRecordStore(accessGroup: accessGroup))
    }

    init(suiteName: String, tokens: any TokenStore, records: any RecordStore) {
        self.defaults = UserDefaults(suiteName: suiteName)!
        self.tokens = tokens
        self.records = records
        revoked = RevokedCredentials(suiteName: suiteName)
    }

    public func credentials() throws -> Credentials? {
        let record: PairingRecord?
        if let saved = try records.load() { record = saved }
        else {
            let legacy = try readLegacy()
            record = try records.load() ?? legacy
        }
        guard let record else { return nil }
        guard !revoked.contains(record.credential) else { throw ClientError.unauthorized }
        return Credentials(record)
    }

    public func isRevoked(_ credentials: Credentials) -> Bool {
        revoked.contains(credentials.token)
    }

    public func recordRevocation(of credentials: Credentials, cache: SnapshotStore) async {
        revoked.insert(credentials.token)
        await deleteCache(for: credentials, from: cache)
    }

    @discardableResult
    public func deleteRevokedCache(from cache: SnapshotStore) async -> PairedMac? {
        guard let record = try? records.load(), revoked.contains(record.credential) else { return nil }
        await deleteCache(for: Credentials(record), from: cache)
        return record.mac
    }

    private func deleteCache(for expected: Credentials, from cache: SnapshotStore) async {
        let records = self.records
        try? await cache.deleteIfMatches(expected.mac, stillCurrent: {
            guard let current = try? records.load() else { return false }
            return expected.samePairing(as: Credentials(current))
        })
    }

    public func migrateLegacy() throws {
        if try records.load() == nil {
            guard let legacy = try readLegacy() else { return }
            try records.addIfAbsent(legacy)
            guard try records.load() != nil else { return }
        }
        try deleteLegacy()
    }

    public func save(_ record: PairingRecord) throws {
        try Task.checkCancellation()
        try records.save(record)
    }

    public func stampProfile(_ reported: String, for expected: Credentials) throws -> Credentials {
        guard let record = try records.load(), expected.samePairing(as: Credentials(record)) else { throw CancellationError() }
        try record.mac.checkProfile(reported)
        guard record.profileId == nil else { return Credentials(record) }
        let stamped = PairingRecord(url: record.url, credential: record.credential, name: record.name,
                                    deviceId: record.deviceId, profileId: reported, pairedAt: record.pairedAt)
        try records.save(stamped)
        return Credentials(stamped)
    }

    public func unpair() throws {
        try deleteLegacy()
        try records.delete()
    }

    public func unpair(clearing cache: SnapshotStore) throws {
        try cache.deleteAll(then: unpair)
    }

    private func readLegacy() throws -> PairingRecord? {
        guard let credential = try tokens.load(), let text = defaults.string(forKey: Self.legacyURL), let url = URL(string: text) else { return nil }
        return PairingRecord(url: url, credential: credential, name: defaults.string(forKey: Self.legacyName) ?? "Mac")
    }

    private func deleteLegacy() throws {
        try tokens.delete()
        defaults.removeObject(forKey: Self.legacyURL)
        defaults.removeObject(forKey: Self.legacyName)
    }
}
