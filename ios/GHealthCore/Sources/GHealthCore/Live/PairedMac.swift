import Foundation

public struct PairedMac: Codable, Sendable, Equatable {
    public let url: String
    public let name: String
    public let profile: String?

    public init(url: String, name: String, profile: String? = nil) {
        self.url = url
        self.name = name
        self.profile = profile
    }

    public func matches(_ other: Self?) -> Bool {
        guard let other else { return false }
        if let profile, let otherProfile = other.profile { return profile == otherProfile }
        return url == other.url
    }

    func stamped(with current: Self) -> Self {
        guard profile == nil, url == current.url, let profile = current.profile else { return self }
        return Self(url: url, name: name, profile: profile)
    }

    func checkProfile(_ reported: String?) throws {
        if let profile, let reported, profile != reported { throw ClientError.profileMismatch }
    }
}

extension Credentials {
    public var mac: PairedMac { PairedMac(url: url.absoluteString, name: name, profile: profileId) }
}

extension PairingRecord {
    public var mac: PairedMac { PairedMac(url: url.absoluteString, name: name, profile: profileId) }
}
