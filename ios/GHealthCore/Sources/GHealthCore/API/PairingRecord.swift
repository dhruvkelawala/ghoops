import Foundation
import Security

public struct PairingRecord: Codable, Equatable, Sendable {
    public let version: Int
    public let url: URL
    public let credential: String
    public let name: String
    public let deviceId: String?
    public let profileId: String?
    public let pairedAt: Date

    public init(url: URL, credential: String, name: String, deviceId: String? = nil, profileId: String? = nil, pairedAt: Date = .now) {
        self.version = 1
        self.url = url
        self.credential = credential
        self.name = name
        self.deviceId = deviceId
        self.profileId = profileId
        self.pairedAt = pairedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, url, credential, name, deviceId, profileId, pairedAt
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(version, forKey: .version)
        try fields.encode(url, forKey: .url)
        try fields.encode(credential, forKey: .credential)
        try fields.encode(name, forKey: .name)
        try fields.encode(deviceId, forKey: .deviceId)
        try fields.encode(profileId, forKey: .profileId)
        try fields.encode(pairedAt, forKey: .pairedAt)
    }
}

protocol RecordStore: Sendable {
    func load() throws -> PairingRecord?
    func addIfAbsent(_ record: PairingRecord) throws
    func save(_ record: PairingRecord) throws
    func delete() throws
}

struct KeychainRecordStore: RecordStore {
    private let item: PairingKeychainItem

    init(accessGroup: String) {
        item = PairingKeychainItem(service: "io.ghealth.app.pairing", accessGroup: accessGroup)
    }

    func load() throws -> PairingRecord? {
        guard let data = try item.load() else { return nil }
        guard let record = try? JSONCoding.decoder().decode(PairingRecord.self, from: data), record.version == 1 else {
            throw PairingError.keychain(errSecDecode)
        }
        return record
    }

    func addIfAbsent(_ record: PairingRecord) throws {
        _ = try item.add(JSONCoding.encoder().encode(record))
    }

    func save(_ record: PairingRecord) throws {
        try item.save(JSONCoding.encoder().encode(record))
    }

    func delete() throws { try item.delete() }
}

protocol TokenStore: Sendable {
    func load() throws -> String?
    func delete() throws
}

struct KeychainTokenStore: TokenStore {
    private let item: PairingKeychainItem

    init(accessGroup: String) {
        item = PairingKeychainItem(service: "io.ghealth.app.token", accessGroup: accessGroup)
    }

    func load() throws -> String? {
        try item.load().flatMap { String(data: $0, encoding: .utf8) }
    }

    func delete() throws { try item.delete() }
}

private struct PairingKeychainItem: Sendable {
    let service: String
    let accessGroup: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "default",
         kSecAttrAccessGroup as String: accessGroup,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PairingError.keychain(status) }
        return data
    }

    func add(_ data: Data) throws -> Bool {
        var request = query
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        request[kSecValueData as String] = data
        let status = SecItemAdd(request as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw PairingError.keychain(status) }
        return true
    }

    func save(_ data: Data) throws {
        let attributes = [kSecValueData as String: data] as CFDictionary
        var status = SecItemUpdate(query as CFDictionary, attributes)
        if status == errSecItemNotFound {
            if try add(data) { return }
            status = SecItemUpdate(query as CFDictionary, attributes)
        }
        guard status == errSecSuccess else { throw PairingError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PairingError.keychain(status) }
    }
}
