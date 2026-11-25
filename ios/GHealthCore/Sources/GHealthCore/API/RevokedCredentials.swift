import CryptoKit
import Foundation

struct RevokedCredentials: Sendable {
    private static let key = "revokedCredentials"
    private static let lock = NSLock()
    private let suiteName: String

    init(suiteName: String) { self.suiteName = suiteName }

    func contains(_ credential: String) -> Bool {
        let prefix = Self.prefix(for: credential)
        return Self.lock.withLock {
            UserDefaults(suiteName: suiteName)?.stringArray(forKey: Self.key)?.contains(prefix) == true
        }
    }

    func insert(_ credential: String) {
        let prefix = Self.prefix(for: credential)
        Self.lock.withLock {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return }
            var entries = defaults.stringArray(forKey: Self.key) ?? []
            entries.removeAll { $0 == prefix }
            entries.append(prefix)
            defaults.set(Array(entries.suffix(8)), forKey: Self.key)
        }
    }

    private static func prefix(for credential: String) -> String {
        SHA256.hash(data: Data(credential.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
