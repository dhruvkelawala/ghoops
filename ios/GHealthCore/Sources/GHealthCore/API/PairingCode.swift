import Foundation

public struct PairingCode: Sendable {
    public let origin: URL
    public let code: String
    public let host: String
    public var port: Int { origin.port ?? 443 }

    public init(_ payload: String) throws {
        let line = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = line.split(separator: " ")
        guard line.utf8.count <= 200, fields.count == 3, fields[0] == "GHOOPS1",
              !fields[1].hasSuffix(":"),
              let url = URL(string: String(fields[1]), encodingInvalidCharacters: false),
              let origin = URLComponents(url: url, resolvingAgainstBaseURL: false),
              origin.scheme == "https", let host = origin.host, !host.isEmpty,
              origin.user == nil, origin.password == nil, origin.path.isEmpty,
              origin.query == nil, origin.fragment == nil,
              (1...65535).contains(origin.port ?? 443),
              fields[2].utf8.count == 43, fields[2].utf8.allSatisfy(Self.isBase64URL) else {
            throw PairingError.invalidCode
        }
        self.origin = url
        self.host = host
        self.code = String(fields[2])
    }

    private static func isBase64URL(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 48...57, 65...90, 95, 97...122: true
        default: false
        }
    }
}
