#if DEBUG
import Foundation
import GHealthCore

enum EnrolmentFixture: String, EnrolmentTransport {
    case approve, decline, expired

    static let originalMac = PairedMac(url: "https://mac-a.invalid:8787", name: "Mac A")

    func redeem(_ code: PairingCode, deviceName: String) async throws -> PendingEnrolment {
        guard self != .expired,
              ["https://mac-a.invalid:8787", "https://mac-b.invalid:8787"].contains(code.origin.absoluteString),
              code.code == String(repeating: "A", count: 43) else { throw ClientError.unauthorized }
        let name = code.host == "mac-a.invalid" ? "Mac A" : "Mac B"
        let record = PairingRecord(url: code.origin, credential: "ghv3_<redacted>", name: name,
                                   deviceId: "fixture-device", profileId: "fixture-profile")
        return PendingEnrolment(record: record, verificationCode: "482913")
    }

    func state(for pending: PendingEnrolment) async throws -> PairedDeviceState {
        guard self == .approve else { throw ClientError.unauthorized }
        try await Task.sleep(for: .seconds(7))
        return .active
    }
}
#endif
