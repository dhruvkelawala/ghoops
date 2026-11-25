import Foundation
import Observation

@MainActor @Observable
public final class PairingFlow {
    public enum Step {
        case scan, check(PairingCode), redeeming, waiting(String), done
        case failed(any Error, verifying: Bool)
    }

    public private(set) var step: Step = .scan
    private let transport: any EnrolmentTransport
    private let waitForPoll: @Sendable () async throws -> Void

    public init(transport: any EnrolmentTransport = EnrolmentClient(),
                waitForPoll: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }) {
        self.transport = transport
        self.waitForPoll = waitForPoll
    }

    public func scan(_ text: String) throws {
        guard case .scan = step else { return }
        step = try .check(PairingCode(text))
    }

    public func scanAgain() {
        guard case .check = step else { return }
        step = .scan
    }

    public func confirm(deviceName: String, checkMac: @MainActor (PairedMac) throws -> Void,
                        save: @MainActor (PairingRecord) async throws -> Void) async throws {
        guard case .check(let code) = step else { return }
        step = .redeeming
        var verifying = false
        do {
            try Task.checkCancellation()
            let pending: PendingEnrolment
            do { pending = try await transport.redeem(code, deviceName: deviceName) }
            catch ClientError.unauthorized { throw PairingError.enrolmentExpired }
            try Task.checkCancellation()
            try checkMac(pending.record.mac)
            let comparison = pending.verificationCode
            guard comparison.utf8.count == 6, comparison.utf8.allSatisfy({ (48...57).contains($0) }) else {
                throw ClientError.incompatibleVersion
            }
            verifying = true
            step = .waiting("\(comparison.prefix(3)) \(comparison.suffix(3))")
            while true {
                try await waitForPoll()
                try Task.checkCancellation()
                let state: PairedDeviceState
                do { state = try await transport.state(for: pending) }
                catch ClientError.unauthorized { throw PairingError.enrolmentDeclined }
                if state == .active { break }
            }
            try Task.checkCancellation()
            try await save(pending.record)
            step = .done
        } catch {
            step = .failed(error, verifying: verifying)
            throw error
        }
    }
}
