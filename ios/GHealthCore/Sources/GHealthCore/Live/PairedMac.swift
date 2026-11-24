import Foundation

/// The Mac a piece of phone-side work belongs to. Two values are the same Mac when their URLs match,
/// so a rotated token or a renamed Mac stays the same pairing.
public struct PairedMac: Codable, Sendable, Hashable {
    public let url: String
    public let name: String
    public init(url: String, name: String) { self.url = url; self.name = name }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

extension Credentials {
    public var mac: PairedMac { PairedMac(url: url.absoluteString, name: name) }
}
