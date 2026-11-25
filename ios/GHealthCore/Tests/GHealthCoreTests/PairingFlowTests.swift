import Foundation
import Testing
@testable import GHealthCore

private let code = String(repeating: "A", count: 43)
private let origin = "https://mac-a.invalid:8787"
private let payload = "GHOOPS1 \(origin) \(code)"

@Test(arguments: [payload, " \n\(payload)\t "])
func pairingCodeReadsTheCheckedOrigin(_ text: String) throws {
    let parsed = try PairingCode(text)
    #expect(parsed.origin.absoluteString == origin)
    #expect(parsed.host == "mac-a.invalid")
    #expect(parsed.port == 8787)
    #expect(try PairingCode("GHOOPS1 https://mac-a.invalid \(code)").port == 443)
}

@Test(arguments: [
    "GHOOPS1 \(origin)", "\(payload) extra", "GHOOPS2 \(origin) \(code)",
    "GHOOPS1 http://mac-a.invalid \(code)", "GHOOPS1 https://user@mac-a.invalid \(code)",
    "GHOOPS1 \(origin)/ \(code)", "GHOOPS1 \(origin)?x=1 \(code)", "GHOOPS1 \(origin)#part \(code)",
    "GHOOPS1 https://mac-a.invalid:0 \(code)", "GHOOPS1 https://mac-a.invalid:65536 \(code)",
    "GHOOPS1 https://mac-a.invalid: \(code)", "GHOOPS1 \(origin) \(code.dropLast())",
    "\(payload)A", "GHOOPS1 \(origin) \(code.dropLast())+",
])
func pairingCodeRejectsInvalidFields(_ text: String) {
    #expect(throws: PairingError.self) { try PairingCode(text) }
}

@MainActor @Test func pairingSavesOneRecordAfterApproval() async throws {
    let records = MemoryPairingRecords()
    let repository = PairingRepository(suiteName: "ghealth-test-\(UUID())", tokens: MemoryTokens(), records: records)
    let transport = EnrolmentStub(.approve)
    let flow = PairingFlow(transport: transport, waitForPoll: { #expect(records.saveCount == 0) })
    try flow.scan(payload)
    #expect(await transport.redeemCount == 0)
    try await flow.confirm(deviceName: "iPhone", checkMac: { _ in }) { record in
        try await repository.save(record)
    }
    let record = try #require(try records.load())
    #expect(record.url.absoluteString == origin)
    #expect(record.credential == "ghv3_<redacted>")
    #expect(record.deviceId == "fixture-device")
    #expect(record.profileId == "fixture-profile")
    #expect(records.saveCount == 1)
    #expect(await transport.pollCount == 2)
}

@MainActor @Test(arguments: [
    (EnrolmentStub.Outcome.expire, "This code has expired or was already used. Run ghoops pair on your Mac again."),
    (.decline, "Your Mac didn't pair this iPhone. Run ghoops pair on your Mac to try again."),
    (.offline, "Can't reach your Mac over Tailscale. Is Tailscale on?"),
])
private func pairingFailureDoesNotSaveThePendingCredential(_ outcome: EnrolmentStub.Outcome, _ message: String) async throws {
    let flow = PairingFlow(transport: EnrolmentStub(outcome), waitForPoll: {})
    try flow.scan(payload)
    do {
        try await flow.confirm(deviceName: "iPhone", checkMac: { _ in }) { _ in
            Issue.record("Pairing wrote a record before approval")
        }
        Issue.record("Pairing should report the failure")
    } catch {
        #expect(error.localizedDescription == message)
    }
}

private actor EnrolmentStub: EnrolmentTransport {
    enum Outcome: Sendable { case approve, expire, decline, offline }
    private let outcome: Outcome
    private(set) var redeemCount = 0
    private(set) var pollCount = 0

    init(_ outcome: Outcome) { self.outcome = outcome }

    func redeem(_ code: PairingCode, deviceName: String) async throws -> PendingEnrolment {
        redeemCount += 1
        if outcome == .expire { throw ClientError.unauthorized }
        if outcome == .offline { throw ClientError.offline }
        let record = PairingRecord(url: code.origin, credential: "ghv3_<redacted>", name: "Mac A",
                                   deviceId: "fixture-device", profileId: "fixture-profile")
        return PendingEnrolment(record: record, verificationCode: "482913")
    }

    func state(for pending: PendingEnrolment) async throws -> PairedDeviceState {
        pollCount += 1
        if outcome == .decline { throw ClientError.unauthorized }
        return pollCount == 1 ? .pending : .active
    }
}
