import Foundation
import Testing
@testable import GHealthCore

/// Two isolated fake Macs behind one URLProtocol, routed by host. Each checks its own bearer token,
/// keeps its own request log, can go offline, and can hold responses until the test releases them.
final class TwoMacs: @unchecked Sendable {
    typealias Reply = Result<(Int, Data), URLError>
    struct Mac {
        var online = true
        var token = "token-1"
        var snapshot = Data()
        var gated = false
        var log: [URLRequest] = []
        var parked: [(URLRequest, (Reply) -> Void)] = []
    }
    private let lock = NSLock()
    private var macs: [String: Mac] = [:]

    func reset() { lock.withLock { macs = ["mac-a.invalid": Mac(), "mac-b.invalid": Mac()] } }
    func update(_ host: String, _ change: (inout Mac) -> Void) { lock.withLock { change(&macs[host, default: Mac()]) } }
    func log(_ host: String) -> [URLRequest] { lock.withLock { macs[host]?.log ?? [] } }
    func posts(_ host: String) -> [String] {
        log(host).filter { $0.httpMethod == "POST" }.compactMap { request in
            request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["id"] as? String
        }
    }
    func gate(_ host: String) { update(host) { $0.gated = true } }
    func release(_ host: String) {
        let parked = lock.withLock { () -> [(URLRequest, (Reply) -> Void)] in
            macs[host]?.gated = false
            defer { macs[host]?.parked = [] }
            return macs[host]?.parked ?? []
        }
        for (request, deliver) in parked { deliver(respond(host, request)) }
    }
    func waitForRequests(_ host: String, count: Int) async throws {
        for _ in 0..<500 where log(host).count < count { try await Task.sleep(for: .milliseconds(10)) }
        #expect(log(host).count >= count)
    }
    func arrive(_ request: URLRequest, deliver: @escaping (Reply) -> Void) {
        let host = request.url?.host ?? ""
        let gated = lock.withLock { () -> Bool in
            guard macs[host]?.online == true else { return false }
            macs[host]?.log.append(request)
            if macs[host]?.gated == true { macs[host]?.parked.append((request, deliver)); return true }
            return false
        }
        if !gated { deliver(respond(host, request)) }
    }
    private func respond(_ host: String, _ request: URLRequest) -> Reply {
        let mac = lock.withLock { macs[host] ?? Mac(online: false) }
        guard mac.online else { return .failure(URLError(.cannotConnectToHost)) }
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(mac.token)" else { return .success((401, Data())) }
        switch (request.httpMethod ?? "GET", request.url?.path ?? "") {
        case ("POST", "/v2/activities"):
            guard var activity = request.httpBody.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else { return .success((400, Data())) }
            activity["created_at"] = "2026-03-10T14:30:00Z"
            return .success((201, (try? JSONSerialization.data(withJSONObject: ["schema_version": 2, "kind": "activity", "activity": activity])) ?? Data()))
        case ("DELETE", let path) where path.hasPrefix("/v2/activities/"):
            let id = String(path.dropFirst("/v2/activities/".count))
            return .success((200, (try? JSONSerialization.data(withJSONObject: ["schema_version": 2, "kind": "activity_deleted", "id": id])) ?? Data()))
        case ("GET", "/v2/snapshot"):
            return .success((200, mac.snapshot))
        default:
            return .success((404, Data()))
        }
    }
}

final class TwoMacStub: URLProtocol, @unchecked Sendable {
    static let macs = TwoMacs()
    private let stopped = NSLock()
    private var isStopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.macs.arrive(Self.withBody(request)) { [weak self] reply in self?.deliver(reply) }
    }
    override func stopLoading() { stopped.withLock { isStopped = true } }
    private func deliver(_ reply: TwoMacs.Reply) {
        guard !stopped.withLock({ isStopped }), let url = request.url else { return }
        switch reply {
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .success(let (code, data)):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    private static func withBody(_ request: URLRequest) -> URLRequest {
        var captured = request
        guard captured.httpBody == nil, let stream = request.httpBodyStream else { return captured }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        captured.httpBody = data
        return captured
    }
}

let macA = PairedMac(url: "https://mac-a.invalid", name: "Mac A")
let macB = PairedMac(url: "https://mac-b.invalid", name: "Mac B")

func fakeMacClient(_ mac: PairedMac, token: String = "token-1") -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TwoMacStub.self]
    return APIClient(baseURL: URL(string: mac.url)!, token: token, session: URLSession(configuration: config))
}

private func isolationUpload(_ n: Int) throws -> ActivityUpload {
    var upload = try JSONCoding.decoder().decode(ActivityUpload.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("activities/valid.json")))
    upload.id = "3f0c0000-0000-4000-8000-00000000010\(n)"
    upload.start = upload.start.addingTimeInterval(Double(n) * 7200)
    upload.end = upload.end.addingTimeInterval(Double(n) * 7200)
    return upload
}

private func isolationDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pairing-isolation-\(UUID())") }

private func state(_ store: ActivityStore, _ id: String, now: Date) async throws -> ActivityUploadState? {
    try await store.activities(now: now).first { $0.id == id }?.uploadState
}

@Suite(.serialized) struct PairingIsolationTests {
    let macs = TwoMacStub.macs

    /// A1: a workout recorded offline for Mac A is never sent to Mac B, and reaches A once A is paired again.
    @Test func offlineWorkoutForMacAStaysWithMacA() async throws {
        macs.reset(); macs.update("mac-a.invalid") { $0.online = false }
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let upload = try isolationUpload(1), now = upload.end
        let store = ActivityStore(directory: dir)
        await store.bind(macA, api: fakeMacClient(macA))
        try await store.save(LocalActivity(upload: upload, mac: macA), now: now)
        #expect(try await store.retry(now: now))
        #expect(try await state(store, upload.id, now: now) == .pending)

        await store.bind(macB, api: fakeMacClient(macB))
        #expect(try await !store.retry(now: now))
        #expect(macs.log("mac-b.invalid").isEmpty)
        #expect(try await store.held(now: now).map(\.id) == [upload.id])
        #expect(try await store.activities(now: now).filter { $0.mac == macB }.isEmpty)
        await #expect(throws: ClientError.unauthorized) { try await store.deleteOnMac(id: upload.id, now: now) }
        #expect(macs.log("mac-b.invalid").isEmpty)

        macs.update("mac-a.invalid") { $0.online = true }
        await store.bind(macA, api: fakeMacClient(macA))
        #expect(try await !store.retry(now: now))
        #expect(macs.posts("mac-a.invalid") == [upload.id])
        #expect(try await state(store, upload.id, now: now) == .uploaded)
        #expect(try await store.held(now: now).isEmpty)
        #expect(macs.log("mac-b.invalid").isEmpty)
    }

    /// A3 (activities): the same Mac going offline and coming back still delivers.
    @Test func sameMacOfflineRecovery() async throws {
        macs.reset(); macs.update("mac-a.invalid") { $0.online = false }
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let upload = try isolationUpload(2), now = upload.end
        let store = ActivityStore(directory: dir)
        await store.bind(macA, api: fakeMacClient(macA))
        try await store.save(LocalActivity(upload: upload, mac: macA), now: now)
        #expect(try await store.retry(now: now))
        #expect(try await state(store, upload.id, now: now) == .pending)
        macs.update("mac-a.invalid") { $0.online = true }
        #expect(try await !store.retry(now: now))
        #expect(try await state(store, upload.id, now: now) == .uploaded)
        #expect(macs.posts("mac-a.invalid") == [upload.id])
    }

    /// A4 (activities): after `ghoops pair --rotate`, a 401 keeps the row pending and ends the pass;
    /// pairing again with the new token sends it.
    @Test func tokenRotationKeepsQueuedWorkouts() async throws {
        macs.reset(); macs.update("mac-a.invalid") { $0.token = "token-2" }
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = try isolationUpload(3), second = try isolationUpload(4), now = second.end
        let store = ActivityStore(directory: dir)
        await store.bind(macA, api: fakeMacClient(macA, token: "token-1"))
        try await store.save(LocalActivity(upload: first, mac: macA), now: now)
        try await store.save(LocalActivity(upload: second, mac: macA), now: now)
        #expect(try await !store.retry(now: now))
        #expect(macs.log("mac-a.invalid").count == 1)
        #expect(try await state(store, first.id, now: now) == .pending)
        #expect(try await state(store, second.id, now: now) == .pending)

        await store.bind(macA, api: fakeMacClient(macA, token: "token-2"))
        #expect(try await !store.retry(now: now))
        #expect(macs.log("mac-a.invalid").last?.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
        #expect(try await state(store, first.id, now: now) == .uploaded)
        #expect(try await state(store, second.id, now: now) == .uploaded)
    }

    /// A5: a row written before this change has no Mac. It is never sent on its own; SEND TO and DISCARD are explicit.
    @Test func unknownOriginNeverSentAutomatically() async throws {
        macs.reset()
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let kept = try isolationUpload(5), dropped = try isolationUpload(6), now = dropped.end
        let legacy = try JSONCoding.encoder().encode([LocalActivity(upload: kept), LocalActivity(upload: dropped)])
        #expect(!String(decoding: legacy, as: UTF8.self).contains("\"mac\""))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try legacy.write(to: dir.appendingPathComponent("activities-local.json"))

        let store = ActivityStore(directory: dir)
        await store.bind(macB, api: fakeMacClient(macB))
        #expect(try await !store.retry(now: now))
        #expect(macs.log("mac-b.invalid").isEmpty)
        #expect(Set(try await store.held(now: now).map(\.id)) == [kept.id, dropped.id])

        try await store.discard(ids: [dropped.id], now: now)
        #expect(try await store.activities(now: now).map(\.id) == [kept.id])
        #expect(macs.log("mac-b.invalid").isEmpty)

        try await store.adopt(ids: [kept.id], now: now)
        #expect(try await store.held(now: now).isEmpty)
        #expect(try await !store.retry(now: now))
        #expect(macs.posts("mac-b.invalid") == [kept.id])
        #expect(try await state(store, kept.id, now: now) == .uploaded)
        #expect(macs.log("mac-a.invalid").isEmpty)
    }

    /// A6: a switch during an upload pass stops the pass; nothing more goes to A and nothing goes to B.
    @Test func switchDuringPassStopsDelivery() async throws {
        macs.reset(); macs.gate("mac-a.invalid")
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let first = try isolationUpload(7), second = try isolationUpload(8), now = second.end
        let store = ActivityStore(directory: dir)
        await store.bind(macA, api: fakeMacClient(macA))
        try await store.save(LocalActivity(upload: first, mac: macA), now: now)
        try await store.save(LocalActivity(upload: second, mac: macA), now: now)
        let pass = Task { try await store.retry(now: now) }
        try await macs.waitForRequests("mac-a.invalid", count: 1)
        await store.bind(macB, api: fakeMacClient(macB))
        macs.release("mac-a.invalid")
        _ = try await pass.value
        #expect(macs.posts("mac-a.invalid") == [first.id])
        #expect(macs.log("mac-b.invalid").isEmpty)
        #expect(try await state(store, first.id, now: now) == .uploaded)
        #expect(try await state(store, second.id, now: now) == .pending)
        #expect(try await store.held(now: now).map(\.id) == [second.id])
    }

    /// A7: a live session keeps the Mac it started for, through unpair and a new pairing.
    @Test func liveSessionKeepsItsMac() async throws {
        macs.reset()
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let start = try isolationUpload(9).start
        let store = ActivityStore(directory: dir)
        await store.bind(macA, api: fakeMacClient(macA))
        var session = ActivitySession(sport: .all[0], now: start, mac: macA)
        for second in 0..<600 { session.append(HeartRateSample(t: start.addingTimeInterval(Double(second)), bpm: 140)) }
        _ = try await store.startSession(session, now: start.addingTimeInterval(600))

        await store.bind(nil, api: nil)
        await store.bind(macB, api: fakeMacClient(macB))
        var restored = try #require(try await store.restoreSession(now: start.addingTimeInterval(601)))
        #expect(restored.mac == macA)
        #expect(restored.blocksPairing(with: macB.url))
        #expect(!restored.blocksPairing(with: macA.url))
        #expect(ActivitySession(sport: .all[0], now: start).blocksPairing(with: macA.url))
        restored.finish(at: start.addingTimeInterval(600))
        let entry = LiveEstimator(restingHR: nil, maximumHR: nil, model: nil).localActivity(restored, now: start.addingTimeInterval(600))
        #expect(entry.mac == macA)
        try await store.save(entry, now: entry.upload.end)
        try await store.clearSession()
        #expect(try await !store.retry(now: entry.upload.end))
        #expect(macs.log("mac-b.invalid").isEmpty)
        #expect(try await store.held(now: entry.upload.end).map(\.id) == [entry.id])
    }
}

/// The paired URL as the App Group defaults hold it, switchable mid-test.
private final class PairedURL: @unchecked Sendable {
    private let lock = NSLock()
    private var url: String?
    init(_ url: String?) { self.url = url }
    var value: String? { get { lock.withLock { url } } set { lock.withLock { url = newValue } } }
}

private func fakeSnapshot(at time: String) throws -> Data {
    var body = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"))) as? [String: Any])
    body["generated_at"] = time
    return try JSONSerialization.data(withJSONObject: body)
}

private func isCancellation(_ error: Error) -> Bool { error is CancellationError || (error as? URLError)?.code == .cancelled }

extension PairingIsolationTests {
    private func fakeMacsWithSnapshots() throws -> (a: Date, b: Date) {
        macs.reset()
        let aData = try fakeSnapshot(at: "2026-03-10T08:00:00Z"), bData = try fakeSnapshot(at: "2026-03-10T09:00:00Z")
        macs.update("mac-a.invalid") { $0.snapshot = aData }
        macs.update("mac-b.invalid") { $0.snapshot = bData }
        let decoder = JSONCoding.decoder()
        return (try decoder.decode(Snapshot.self, from: aData).generatedAt, try decoder.decode(Snapshot.self, from: bData).generatedAt)
    }

    /// A2: a refresh for Mac A that answers after the switch to B (here from another process's refresher,
    /// as the widget would) cannot put A's snapshot in B's cache.
    @Test func lateRefreshForMacACannotFillMacBCache() async throws {
        let times = try fakeMacsWithSnapshots(); macs.gate("mac-a.invalid")
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let paired = PairedURL(macA.url)
        let store = SnapshotStore(directory: dir, allowSynthetic: true, pairedURL: { paired.value })
        let app = SnapshotRefresher(), widget = SnapshotRefresher()
        let lateA = Task { try await app.refresh(client: fakeMacClient(macA), store: store) }
        try await macs.waitForRequests("mac-a.invalid", count: 1)
        paired.value = macB.url
        let fetchedB = try await widget.refresh(client: fakeMacClient(macB), store: store)
        #expect(fetchedB.meta.serverUrl == macB.url)
        macs.release("mac-a.invalid")
        do { _ = try await lateA.value; Issue.record("A's late response was saved") }
        catch { #expect(isCancellation(error)) }
        let loaded = try #require(try await store.load())
        #expect(loaded.meta.serverUrl == macB.url)
        #expect(loaded.snapshot.generatedAt == times.b)
    }

    /// A2, other order: asking the same refresher for B cancels A's request instead of joining it.
    @Test func refreshForMacBCancelsMacAFlight() async throws {
        let times = try fakeMacsWithSnapshots(); macs.gate("mac-a.invalid")
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let paired = PairedURL(macA.url)
        let store = SnapshotStore(directory: dir, allowSynthetic: true, pairedURL: { paired.value })
        let refresher = SnapshotRefresher()
        let flightA = Task { try await refresher.refresh(client: fakeMacClient(macA), store: store) }
        try await macs.waitForRequests("mac-a.invalid", count: 1)
        paired.value = macB.url
        let fetchedB = try await refresher.refresh(client: fakeMacClient(macB), store: store)
        #expect(fetchedB.snapshot.generatedAt == times.b)
        do { _ = try await flightA.value; Issue.record("B's caller joined A's flight") }
        catch { #expect(isCancellation(error)) }
        macs.release("mac-a.invalid")
        #expect(macs.log("mac-b.invalid").count == 1)
        #expect(try await store.load()?.meta.serverUrl == macB.url)
    }

    /// A3 (snapshots): the same Mac offline keeps its cache; back online, the refresh replaces it.
    @Test func sameMacOfflineKeepsItsCache() async throws {
        let times = try fakeMacsWithSnapshots()
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir, allowSynthetic: true, pairedURL: { macA.url })
        let refresher = SnapshotRefresher()
        _ = try await refresher.refresh(client: fakeMacClient(macA), store: store)
        macs.update("mac-a.invalid") { $0.online = false }
        await #expect(throws: ClientError.offline) { try await refresher.refresh(client: fakeMacClient(macA), store: store) }
        #expect(try await store.load()?.snapshot.generatedAt == times.a)
        let newer = try fakeSnapshot(at: "2026-03-10T10:00:00Z")
        macs.update("mac-a.invalid") { $0.online = true; $0.snapshot = newer }
        let fetched = try await refresher.refresh(client: fakeMacClient(macA), store: store)
        #expect(try await store.load()?.snapshot.generatedAt == fetched.snapshot.generatedAt)
        #expect(fetched.snapshot.generatedAt != times.a)
    }

    /// A4 (refreshes): concurrent refreshes for one Mac share one request; after a token rotation the old
    /// token is refused and the new one refreshes the same cache.
    @Test func sameMacRefreshesShareAndSurviveRotation() async throws {
        let times = try fakeMacsWithSnapshots(); macs.gate("mac-a.invalid")
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir, allowSynthetic: true, pairedURL: { macA.url })
        let refresher = SnapshotRefresher()
        async let first = refresher.refresh(client: fakeMacClient(macA), store: store)
        async let second = refresher.refresh(client: fakeMacClient(macA), store: store)
        try await macs.waitForRequests("mac-a.invalid", count: 1)
        macs.release("mac-a.invalid")
        let both = try await (first, second)
        #expect(both.0.snapshot.generatedAt == times.a && both.1.snapshot.generatedAt == times.a)
        #expect(macs.log("mac-a.invalid").count == 1)

        macs.update("mac-a.invalid") { $0.token = "token-2" }
        await #expect(throws: ClientError.unauthorized) { try await refresher.refresh(client: fakeMacClient(macA, token: "token-1"), store: store) }
        _ = try await refresher.refresh(client: fakeMacClient(macA, token: "token-2"), store: store)
        #expect(macs.log("mac-a.invalid").last?.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
        #expect(try await store.load()?.meta.serverUrl == macA.url)
    }

    /// A8: the cache is never read or written for a Mac that is not paired.
    @Test func cacheIsOnlyReadAndWrittenForThePairedMac() async throws {
        _ = try fakeMacsWithSnapshots()
        let dir = isolationDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let paired = PairedURL(macA.url)
        let store = SnapshotStore(directory: dir, allowSynthetic: true, pairedURL: { paired.value })
        let body = try fakeSnapshot(at: "2026-03-10T08:00:00Z")
        _ = try await store.save(body, serverURL: macA.url, fetchedAt: .now)
        let file = dir.appendingPathComponent("snapshot-cache.json")
        let before = try Data(contentsOf: file)
        paired.value = macB.url
        #expect(try await store.load() == nil)
        await #expect(throws: CancellationError.self) { try await store.save(body, serverURL: macA.url, fetchedAt: .now) }
        #expect(try Data(contentsOf: file) == before)
        paired.value = nil
        #expect(try await store.load() == nil)
        paired.value = macA.url
        #expect(try await store.load()?.meta.serverUrl == macA.url)
    }
}
