import Foundation

public protocol EnrolmentTransport: Sendable {
    func redeem(_ code: PairingCode, deviceName: String) async throws -> PendingEnrolment
    func state(for pending: PendingEnrolment) async throws -> PairedDeviceState
}

public struct PendingEnrolment: Sendable {
    public let record: PairingRecord
    let verificationCode: String

    public init(record: PairingRecord, verificationCode: String) {
        self.record = record
        self.verificationCode = verificationCode
    }
}

public struct EnrolmentClient: EnrolmentTransport {
    private static let appSession = URLSession(configuration: APIClient.configuration(timeout: 15))
    private let session: URLSession

    public init() { session = Self.appSession }
    init(session: URLSession) { self.session = session }

    public func redeem(_ code: PairingCode, deviceName: String) async throws -> PendingEnrolment {
        var request = URLRequest(url: code.origin.appendingPathComponent("v2/pair/redeem"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder().encode(RedeemBody(code: code.code, deviceName: deviceName))
        let response: PairRedeemResponse = try await exchange(request, expecting: 201)
        guard response.schemaVersion == 2, response.kind == "pair_redeem", response.syntheticFixture == nil,
              response.credential.hasPrefix("ghv3_"), !response.deviceId.isEmpty, !response.profileId.isEmpty else {
            throw ClientError.incompatibleVersion
        }
        let record = PairingRecord(url: code.origin, credential: response.credential, name: response.macName,
                                   deviceId: response.deviceId, profileId: response.profileId)
        return PendingEnrolment(record: record, verificationCode: response.verificationCode)
    }

    public func state(for pending: PendingEnrolment) async throws -> PairedDeviceState {
        let record = pending.record
        var request = URLRequest(url: record.url.appendingPathComponent("v2/pair/status"))
        request.setValue("Bearer \(record.credential)", forHTTPHeaderField: "Authorization")
        let response: PairStatusResponse = try await exchange(request, expecting: 200)
        guard response.schemaVersion == 2, response.kind == "pair_status", response.syntheticFixture == nil,
              response.deviceId == record.deviceId else { throw ClientError.incompatibleVersion }
        return response.state
    }

    private func exchange<Body: Decodable>(_ request: URLRequest, expecting status: Int) async throws -> Body {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, http) = try await MacTransport.response(for: request, in: session)
        switch http.statusCode {
        case status:
            guard let body = try? JSONCoding.decoder().decode(Body.self, from: data) else { throw ClientError.incompatibleVersion }
            return body
        case 401: throw ClientError.unauthorized
        case 429: throw ClientError.rateLimited(from: http)
        case 503: throw ClientError.storeUnavailable
        default: throw ClientError.http(http.statusCode)
        }
    }

    private struct RedeemBody: Encodable {
        let code: String
        let deviceName: String
    }
}
