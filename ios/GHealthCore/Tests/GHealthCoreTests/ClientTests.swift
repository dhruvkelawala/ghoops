import Foundation
import Testing
@testable import GHealthCore

final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: Result<(Int, Data), URLError> = .success((200, Data()))
    private var requests: [URLRequest] = []
    func set(_ code: Int, _ data: Data) { lock.withLock { reply = .success((code, data)); requests = [] } }
    func fail(_ code: URLError.Code) { lock.withLock { reply = .failure(URLError(code)); requests = [] } }
    func take(_ request: URLRequest) -> Result<(Int, Data), URLError> {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        return lock.withLock { requests.append(captured); return reply }
    }
    var seen: [URLRequest] { lock.withLock { requests } }
}
final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.state.take(request) {
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .success(let (code, data)):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
final class MemoryTokens: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func load() -> String? { lock.withLock { value } }
    func save(_ token: String) { lock.withLock { value = token } }
    func delete() { lock.withLock { value = nil } }
}
func stubClient() -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return APIClient(baseURL: URL(string: "https://fixture.invalid:8787")!, token: "fixture-token", session: URLSession(configuration: config))
}

@Suite(.serialized) struct ClientTests {
    @Test func transportErrorsKeepTheirMeaning() async {
        for code: URLError.Code in [.timedOut, .cannotConnectToHost, .secureConnectionFailed, .cancelled] {
            StubProtocol.state.fail(code)
            do { _ = try await stubClient().status(); Issue.record("Failed transport returned a status") }
            catch {
                switch code {
                case .timedOut: #expect(error as? ClientError == .timedOut)
                case .cannotConnectToHost: #expect(error as? ClientError == .offline)
                default: #expect((error as? URLError)?.code == code)
                }
            }
        }
    }

    @Test func clientsReuseSeparateAppAndWidgetSessions() {
        let url = URL(string: "https://fixture.invalid")!
        let app = APIClient(baseURL: url, token: "fixture")
        let other = APIClient(baseURL: url, token: "other")
        let widget = APIClient(baseURL: url, token: "fixture", widget: true)
        let otherWidget = APIClient(baseURL: url, token: "other", widget: true)
        #expect(app.session === other.session)
        #expect(widget.session === otherWidget.session)
        #expect(app.session !== widget.session)
        #expect(app.session.configuration.timeoutIntervalForRequest == 15)
        #expect(widget.session.configuration.timeoutIntervalForRequest == 10)
        #expect(app.session.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(widget.session.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        let injected = URLSession(configuration: .ephemeral)
        #expect(APIClient(baseURL: url, token: "fixture", session: injected).session === injected)
    }

    @Test func pairingLinkRules() throws {
        let valid = "ghealth://pair?v=1&url=https%3A%2F%2Ffixture.invalid%3A8787&token=fixture&name=Fixture%20Mac"
        let link = try PairingLink(URL(string: valid)!)
        #expect(link.url.absoluteString == "https://fixture.invalid:8787")
        #expect(link.name == "Fixture Mac")
        #expect(throws: PairingError.self) { try PairingLink(URL(string: valid.replacingOccurrences(of: "&token=fixture", with: ""))!) }
        #expect(throws: PairingError.self) { try PairingLink(URL(string: valid.replacingOccurrences(of: "https%3A", with: "http%3A"))!) }
    }

    @Test func successfulFetchPersistsVerbatimAndRejectsBadReplacements() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedURL: { "https://fixture.invalid:8787" })
        let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"))
        StubProtocol.state.set(200, data)
        let date = Date(timeIntervalSince1970: 1000)
        let cache = directory.appendingPathComponent("snapshot-cache.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for old in ["snapshot.json", "snapshot-meta.json"] { try Data("{}".utf8).write(to: directory.appendingPathComponent(old)) }
        let fetched = try await stubClient().snapshot(into: store, now: date)
        #expect(fetched.meta.fetchedAt == date)
        let saved = try Data(contentsOf: cache)
        #expect(saved.range(of: data) != nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("snapshot.json").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("snapshot-meta.json").path))
        let loaded = try await store.load()
        #expect(loaded?.meta.fetchedAt == date)
        #expect(StubProtocol.state.seen.first?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(StubProtocol.state.seen.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        StubProtocol.state.set(200, Data("{}".utf8))
        await #expect(throws: ClientError.incompatibleVersion) { try await stubClient().snapshot(into: store) }
        #expect(try Data(contentsOf: cache) == saved)
        let liveStore = SnapshotStore(directory: directory, pairedURL: { "https://fixture.invalid" })
        await #expect(throws: ClientError.incompatibleVersion) { try await liveStore.save(data, serverURL: "https://fixture.invalid", fetchedAt: date) }
        let badSchema = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"schema_version\": 2", with: "\"schema_version\": 3").utf8)
        await #expect(throws: ClientError.incompatibleVersion) { try await store.save(badSchema, serverURL: "https://fixture.invalid:8787", fetchedAt: date) }
        #expect(try Data(contentsOf: cache) == saved)
    }

    @Test(arguments: ["snapshot-cache.json", "directory"])
    func unreadSnapshotThrowsThenRecovers(_ name: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedURL: { "https://fixture.invalid" })
        let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"))
        let date = Date(timeIntervalSince1970: 1000)
        try await store.save(data, serverURL: "https://fixture.invalid", fetchedAt: date)
        let file = name == "directory" ? directory : directory.appendingPathComponent(name)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        do {
            _ = try await store.load()
            Issue.record("Unread snapshot loaded")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
            #expect((error as NSError).code == 257)
        }
        try FileManager.default.setAttributes([.posixPermissions: name == "directory" ? 0o700 : 0o600], ofItemAtPath: file.path)
        #expect(try await store.load()?.meta.fetchedAt == date)
    }

    @Test(arguments: [(401, "unauthorized", ClientError.unauthorized), (503, "store_unavailable", .storeUnavailable), (429, "rate_limited", .rateLimited)])
    func httpErrors(_ code: Int, _ file: String, _ expected: ClientError) async throws {
        StubProtocol.state.set(code, try Data(contentsOf: fixtureRoot.appendingPathComponent("errors/\(file).json")))
        await #expect(throws: expected) { try await stubClient().status() }
    }

    @Test func pairingIsSavedOnlyAfterSuccessfulConnection() async throws {
        let tokens = MemoryTokens()
        let suite = "ghealth-test-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = PairingRepository(suiteName: suite, tokens: tokens)
        let link = try PairingLink(URL(string: "ghealth://pair?v=1&url=https%3A%2F%2Ffixture.invalid&token=fixture&name=Fixture")!)
        StubProtocol.state.set(401, Data())
        await #expect(throws: ClientError.unauthorized) { try await repository.pair(link, client: stubClient()) }
        #expect(try await repository.credentials() == nil)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("status_full.json"))) as? [String: Any])
        object.removeValue(forKey: "synthetic_fixture")
        StubProtocol.state.set(200, try JSONSerialization.data(withJSONObject: object))
        try await repository.pair(link, client: stubClient())
        #expect(try await repository.credentials()?.name == "Fixture")
        #expect(tokens.load() == "fixture")
        try await repository.unpair()
        #expect(tokens.load() == nil)
        #expect(try await repository.credentials() == nil)
    }
}

extension ClientTests {
    @Test func concurrentRefreshesMakeOneRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedURL: { "https://fixture.invalid:8787" })
        let refresher = SnapshotRefresher()
        StubProtocol.state.set(200, try Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json")))
        let client = stubClient()
        async let first = refresher.refresh(client: client, store: store)
        async let second = refresher.refresh(client: client, store: store)
        let results = try await (first, second)
        #expect(results.0.snapshot.day.recovery.value == 73)
        #expect(results.1.snapshot.day.recovery.value == 73)
        #expect(StubProtocol.state.seen.count == 1)
    }
}

@Test func refreshAgeBoundariesUseInjectedClock() {
    let now = Date(timeIntervalSince1970: 10_000)
    let policy = RefreshPolicy(now: { now })
    #expect(policy.needsRefresh(fetchedAt: nil, trigger: .widget))
    #expect(!policy.needsRefresh(fetchedAt: now.addingTimeInterval(-1799), trigger: .widget))
    #expect(!policy.needsRefresh(fetchedAt: now.addingTimeInterval(-1800), trigger: .widget))
    #expect(policy.needsRefresh(fetchedAt: now.addingTimeInterval(-1801), trigger: .widget))
    #expect(!policy.needsRefresh(fetchedAt: now.addingTimeInterval(-60), trigger: .active))
    #expect(policy.needsRefresh(fetchedAt: now.addingTimeInterval(-61), trigger: .active))
}

extension ClientTests {
    @Test func dateEndpointsUseSchemaChecksAndExplicitRanges() async throws {
        for (path, file) in [("day", "day_full.json"), ("sleep", "sleep_full.json"), ("workouts", "workouts_full.json"), ("days", "days_full.json")] {
            var body = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent(file))) as? [String: Any])
            body.removeValue(forKey: "synthetic_fixture")
            StubProtocol.state.set(200, try JSONSerialization.data(withJSONObject: body))
            let client = stubClient()
            switch path {
            case "day": #expect(try await client.day(date: "2026-03-10").date == "2026-03-10")
            case "sleep": #expect(try await client.sleep(date: "2026-03-10").date == "2026-03-10")
            case "workouts": _ = try await client.workouts(from: "2026-03-04", to: "2026-03-10")
            default: _ = try await client.days(from: "2026-03-04", to: "2026-03-10")
            }
            let request = try #require(StubProtocol.state.seen.first)
            #expect(request.url?.path == "/v2/\(path)")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            if path == "day" || path == "sleep" { #expect(query == [URLQueryItem(name: "date", value: "2026-03-10")]) }
            else { #expect(query == [URLQueryItem(name: "from", value: "2026-03-04"), URLQueryItem(name: "to", value: "2026-03-10")]) }
        }
        StubProtocol.state.set(200, try Data(contentsOf: fixtureRoot.appendingPathComponent("day_full.json")))
        await #expect(throws: ClientError.incompatibleVersion) { try await stubClient().day(date: "2026-03-10") }
    }
}

extension ClientTests {
    @Test func activityWritesUseJSONAndAcceptCreateReplayAndDelete() async throws {
        let upload = try JSONCoding.decoder().decode(ActivityUpload.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("activities/valid.json")))
        var object = try #require(JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(upload)) as? [String: Any])
        object["created_at"] = "2026-03-10T14:30:00Z"
        let body = try JSONSerialization.data(withJSONObject: ["schema_version": 2, "kind": "activity", "activity": object])
        for status in [201, 200] {
            StubProtocol.state.set(status, body)
            let record = try await stubClient().postActivity(upload)
            #expect(record.id == upload.id)
            let request = try #require(StubProtocol.state.seen.first)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v2/activities")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        }
        StubProtocol.state.set(409, Data())
        await #expect(throws: ClientError.conflict) { try await stubClient().postActivity(upload) }
        StubProtocol.state.set(200, try JSONSerialization.data(withJSONObject: ["schema_version": 2, "kind": "activity_deleted", "id": upload.id]))
        try await stubClient().deleteActivity(id: upload.id)
        #expect(StubProtocol.state.seen.first?.httpMethod == "DELETE")
        #expect(StubProtocol.state.seen.first?.url?.lastPathComponent == upload.id)
    }
}

extension ClientTests {
    @Test func editWritesEncodeNullsAndDecodeEditOrNull() async throws {
        let body: EditBody = try fixture("edits/requests/edit.json", as: EditBody.self)
        let snapshot: Snapshot = try fixture("edits/snapshot_edited.json", as: Snapshot.self)
        let edit = snapshot.workouts.workouts.first { $0.id == "7300000000000000101" }!.edit
        for value in [edit, nil] {
            let response = EditResponse(schemaVersion: 2, kind: "edit", id: "7300000000000000101", edit: value)
            StubProtocol.state.set(200, try JSONCoding.encoder().encode(response))
            #expect(try await stubClient().putEdit(id: response.id, body) == value)
            let request = try #require(StubProtocol.state.seen.first)
            #expect(request.httpMethod == "PUT" && request.url?.path == "/v2/edits/7300000000000000101")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        }
        StubProtocol.state.set(200, Data(#"{"schema_version":2,"kind":"edit","id":"test","edit":null}"#.utf8))
        _ = try await stubClient().putEdit(id: "test", EditBody())
        let request = try #require(StubProtocol.state.seen.first)
        let requestData = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        #expect(object["exercise_type"] is NSNull && object["start"] is NSNull && object["end"] is NSNull && object["notes"] is NSNull)
        StubProtocol.state.set(200, Data(#"{"schema_version":2,"kind":"edit_deleted","id":"test"}"#.utf8))
        try await stubClient().deleteEdit(id: "test")
        #expect(StubProtocol.state.seen.first?.httpMethod == "DELETE")
        StubProtocol.state.set(404, Data())
        await #expect(throws: ClientError.notFound) { try await stubClient().deleteEdit(id: "test") }
    }

    @Test func sleepWritesCarryPreconditionsAndAcceptRestore() async throws {
        let sleep: Sleep = try fixture("sleep_edit/sleep_extended.json")
        let body = SleepEditBody(start: sleep.session!.start, end: sleep.session!.end, ifUpdatedAt: nil)
        let response = SleepEditResponse(schemaVersion: 2, kind: "sleep_edit", date: sleep.date, sleepEdit: sleep.session?.edit)
        StubProtocol.state.set(200, try JSONCoding.encoder().encode(response))
        #expect(try await stubClient().putSleepEdit(date: sleep.date, body)?.updatedAt == response.sleepEdit?.updatedAt)
        let request = try #require(StubProtocol.state.seen.last)
        #expect(request.url?.path == "/v2/sleep-edits/2026-03-10" && request.httpMethod == "PUT")
        let object = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(object["if_updated_at"] is NSNull)
        StubProtocol.state.set(200, try JSONCoding.encoder().encode(SleepEditResponse(schemaVersion: 2, kind: "sleep_edit", date: sleep.date, sleepEdit: nil)))
        try await stubClient().deleteSleepEdit(date: sleep.date)
        #expect(StubProtocol.state.seen.last?.httpMethod == "DELETE")
    }

    @Test func heartRateReadsBothQueryFormsAndMapsEditErrors() async throws {
        var hr: HeartRateBody = try fixture("edits/heart_rate_tue.json", as: HeartRateBody.self)
        hr.syntheticFixture = nil
        let data = try JSONCoding.encoder().encode(hr)
        for byDate in [true, false] {
            StubProtocol.state.set(200, data)
            let client = stubClient()
            let result = try await (byDate ? client.heartRate(date: "2026-03-10") : client.heartRate(start: hr.start, end: hr.end))
            #expect(result.minutes.count == hr.minutes.count)
            let request = try #require(StubProtocol.state.seen.first)
            #expect(request.url?.path == "/v2/heart-rate")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            if byDate { #expect(query == [URLQueryItem(name: "date", value: "2026-03-10")]) }
            else { #expect(query == [URLQueryItem(name: "start", value: "2026-03-10T15:05:00Z"), URLQueryItem(name: "end", value: "2026-03-10T20:30:00Z")]) }
        }
        for (code, expected) in [(400, ClientError.rejected), (404, .notFound), (409, .conflict)] {
            StubProtocol.state.set(code, Data())
            await #expect(throws: expected) { try await stubClient().putEdit(id: "test", EditBody()) }
        }
    }
}
