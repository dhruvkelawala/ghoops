#if DEBUG
import Foundation
import GHealthCore

private final class FixtureReply: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var count = 0
    func prepare(_ data: Data) { lock.withLock { self.data = data } }
    func take() -> Data { lock.withLock { count += 1; return data } }
    var requests: Int { lock.withLock { count } }
}
private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let reply = FixtureReply()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = Self.reply.take()
        var status = 200
        if request.httpMethod == "POST", let body = body(),
           var activity = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            activity["created_at"] = ISO8601DateFormatter().string(from: .now)
            data = (try? JSONSerialization.data(withJSONObject: ["schema_version": 2, "kind": "activity", "activity": activity])) ?? Data()
            status = 201
        } else if request.httpMethod == "DELETE" {
            data = (try? JSONSerialization.data(withJSONObject: ["schema_version": 2, "kind": "activity_deleted", "id": request.url!.lastPathComponent])) ?? Data()
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    private func body() -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    override func stopLoading() {}
}

enum FixtureTransport {
    static func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return APIClient(baseURL: URL(string: "https://fixture.invalid:8787")!, token: "fixture", session: URLSession(configuration: config))
    }
    static func refresh(_ cached: CachedSnapshot) async throws -> Int {
        FixtureProtocol.reply.prepare(try JSONCoding.encoder().encode(cached.snapshot))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://fixture.invalid:8787")!, token: "fixture", session: URLSession(configuration: config))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ghealth-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = client.baseURL.absoluteString
        _ = try await SnapshotRefresher.shared.refresh(client: client, store: SnapshotStore(directory: directory, allowSynthetic: true, pairedURL: { server }), now: cached.meta.fetchedAt)
        return FixtureProtocol.reply.requests
    }
}
#endif
