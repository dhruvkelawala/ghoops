import Foundation
import Security

public struct PairingLink: Sendable {
    public let url: URL
    public let token: String
    public let name: String

    public init(_ link: URL) throws {
        guard let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
              components.scheme == "ghealth", components.host == "pair" else { throw PairingError.invalidLink }
        let items = components.queryItems ?? []
        func value(_ key: String) -> String? {
            let matches = items.filter { $0.name == key }
            return matches.count == 1 ? matches[0].value : nil
        }
        guard value("v") == "1", let token = value("token"), !token.isEmpty,
              let rawURL = value("url"), let url = URL(string: rawURL),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw PairingError.invalidLink }
        self.url = url
        self.token = token
        self.name = value("name") ?? "Mac"
    }
}

public enum PairingError: Error, LocalizedError {
    case invalidLink, keychain(OSStatus), activityRunning
    public var errorDescription: String? {
        switch self {
        case .invalidLink: "Paste a valid ghoops pairing link from your Mac."
        case .keychain: "ghoops couldn't use the pairing saved on this phone. Run ghoops pair on your Mac, then scan its code."
        case .activityRunning: "Finish your activity before you pair with another Mac."
        }
    }
}

public protocol TokenStore: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

public struct KeychainTokenStore: TokenStore {
    private let accessGroup: String
    public init(accessGroup: String) { self.accessGroup = accessGroup }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "io.ghealth.app.token",
         kSecAttrAccount as String: "default",
         kSecAttrAccessGroup as String: accessGroup,
         kSecAttrSynchronizable as String: false]
    }
    public func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PairingError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }
    public func save(_ token: String) throws {
        let attrs: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if update == errSecItemNotFound {
            let status = SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw PairingError.keychain(status) }
        } else if update != errSecSuccess { throw PairingError.keychain(update) }
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PairingError.keychain(status) }
    }
}

public struct Credentials: Sendable {
    public let url: URL
    public let name: String
    public let token: String
}

public actor PairingRepository {
    private let defaults: UserDefaults
    private let tokens: any TokenStore
    /// The paired server URL from the App Group defaults, readable from any process without the Keychain.
    public static func pairedURL(suiteName: String) -> String? { UserDefaults(suiteName: suiteName)?.string(forKey: "serverURL") }
    public init(suiteName: String, tokens: any TokenStore) {
        self.defaults = UserDefaults(suiteName: suiteName)!
        self.tokens = tokens
    }
    public func credentials() throws -> Credentials? {
        guard let token = try tokens.load(), let text = defaults.string(forKey: "serverURL"), let url = URL(string: text) else { return nil }
        return Credentials(url: url, name: defaults.string(forKey: "macName") ?? "Mac", token: token)
    }
    public func pair(_ link: PairingLink, client: APIClient? = nil) async throws {
        _ = try await (client ?? APIClient(baseURL: link.url, token: link.token)).status()
        try tokens.save(link.token)
        defaults.set(link.url.absoluteString, forKey: "serverURL")
        defaults.set(link.name, forKey: "macName")
    }
    public func unpair() throws {
        try tokens.delete()
        defaults.removeObject(forKey: "serverURL")
        defaults.removeObject(forKey: "macName")
    }
}
