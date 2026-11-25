import Foundation
import Testing
@testable import GHealthCore

final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: Result<(Int, Data, [String: String]), URLError> = .success((200, Data(), [:]))
    private var destination: URL?
    private var requests: [URLRequest] = []
    func set(_ code: Int, _ data: Data, headers: [String: String] = [:]) {
        lock.withLock { reply = .success((code, data, headers)); destination = nil; requests = [] }
    }
    func fail(_ code: URLError.Code) {
        lock.withLock { reply = .failure(URLError(code)); destination = nil; requests = [] }
    }
    func redirect(to url: URL, replyingWith data: Data) {
        lock.withLock { reply = .success((200, data, [:])); destination = url; requests = [] }
    }
    func take(_ request: URLRequest) -> Result<(Int, Data, [String: String]), URLError> {
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
        return lock.withLock {
            requests.append(captured)
            if let destination, requests.count == 1 {
                return .success((302, Data(), ["Location": destination.absoluteString]))
            }
            return reply
        }
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
        case .success(let (code, data, headers)):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            if code == 302, let location = headers["Location"], let destination = URL(string: location) {
                var next = request
                next.url = destination
                client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
func stubClient() -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return APIClient(baseURL: URL(string: "https://fixture.invalid:8787")!, token: "fixture-token", session: URLSession(configuration: config))
}

@Suite(.serialized) struct ClientTests {
    @Test(arguments: [
        ("https://fixture.invalid:8787/next", true),
        ("https://mac-b.invalid:8787/next", false),
        ("https://fixture.invalid:443/next", false),
        ("http://fixture.invalid:8787/next", false),
    ])
    func redirectsStayAtTheOriginalOrigin(_ location: String, _ shouldFollow: Bool) async throws {
        let body = try liveStatusBody()
        let url = try #require(URL(string: location))
        StubProtocol.state.redirect(to: url, replyingWith: body)
        if shouldFollow {
            #expect(try await stubClient().status().kind == "status")
        } else {
            await #expect(throws: ClientError.http(302)) { try await stubClient().status() }
        }
        let sent = StubProtocol.state.seen
        #expect(sent.map { $0.url?.path } == (shouldFollow ? ["/v2/status", "/next"] : ["/v2/status"]))
        #expect(sent.allSatisfy { $0.url?.host == "fixture.invalid" })
    }

    @Test func responseBodyLimitAppliesToBothClients() async throws {
        let body = try liveStatusBody()
        StubProtocol.state.set(200, padded(body, toMiB: 1))
        #expect(try await stubClient().status().kind == "status")
        StubProtocol.state.set(200, padded(body, toMiB: 9))
        await #expect(throws: ClientError.incompatibleVersion) { try await stubClient().status() }

        let pairing = PairingRecord(url: URL(string: "https://fixture.invalid:8787")!, credential: "ghv3_<redacted>",
                                    name: "Fixture Mac", deviceId: "fixture-device")
        let pending = PendingEnrolment(record: pairing, verificationCode: "<code>")
        let state = Data("""
        {"schema_version":2,"kind":"pair_status","source":"ghoops","generated_at":"2026-03-10T12:00:00Z","timezone":"UTC",
        "device_id":"fixture-device","state":"active"}
        """.utf8)
        StubProtocol.state.set(200, padded(state, toMiB: 9))
        await #expect(throws: ClientError.incompatibleVersion) {
            try await EnrolmentClient(session: stubClient().session).state(for: pending)
        }
    }

    private func padded(_ data: Data, toMiB size: Int) -> Data {
        data + Data(repeating: 0x20, count: size * 1024 * 1024 - data.count)
    }

    private func liveStatusBody() throws -> Data {
        let fixture = try Data(contentsOf: fixtureRoot.appendingPathComponent("status_full.json"))
        var status = try #require(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        status.removeValue(forKey: "synthetic_fixture")
        return try JSONSerialization.data(withJSONObject: status)
    }

    @Test func enrolmentUsesTheCheckedOriginAndAuthenticatesOnlyStatus() async throws {
        let redeem = Data("""
        {"schema_version":2,"kind":"pair_redeem","source":"ghoops","generated_at":"2026-03-10T12:00:00Z","timezone":"UTC",
        "device_id":"fixture-device","credential":"ghv3_<redacted>","verification_code":"482913","mac_name":"Mac A",
        "profile_id":"fixture-profile","expires_at":"2026-03-10T12:05:00Z"}
        """.utf8)
        let status = Data("""
        {"schema_version":2,"kind":"pair_status","source":"ghoops","generated_at":"2026-03-10T12:00:00Z","timezone":"UTC",
        "device_id":"fixture-device","state":"active"}
        """.utf8)
        let client = EnrolmentClient(session: stubClient().session)
        let code = String(repeating: "A", count: 43)
        let parsed = try PairingCode("GHOOPS1 https://mac-a.invalid:8787 \(code)")
        StubProtocol.state.set(201, redeem)
        let pending = try await client.redeem(parsed, deviceName: "iPhone")
        #expect(StubProtocol.state.seen.count == 1)
        let post = try #require(StubProtocol.state.seen.first)
        #expect(post.url?.absoluteString == "https://mac-a.invalid:8787/v2/pair/redeem")
        #expect(post.httpMethod == "POST")
        #expect(post.value(forHTTPHeaderField: "Authorization") == nil)
        let postBody = try #require(post.httpBody)
        let json = try JSONDecoder().decode([String: String].self, from: postBody)
        #expect(json == ["code": code, "device_name": "iPhone"])

        StubProtocol.state.set(200, status)
        #expect(try await client.state(for: pending) == .active)
        #expect(StubProtocol.state.seen.count == 1)
        let get = try #require(StubProtocol.state.seen.first)
        #expect(get.url?.absoluteString == "https://mac-a.invalid:8787/v2/pair/status")
        #expect(get.httpMethod == "GET")
        #expect(get.value(forHTTPHeaderField: "Authorization") == "Bearer ghv3_<redacted>")
    }

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

    @Test func successfulFetchPersistsVerbatimAndRejectsBadReplacements() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedMac: { PairedMac(url: "https://fixture.invalid:8787", name: "Fixture Mac") })
        let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"))
        StubProtocol.state.set(200, data)
        let date = Date(timeIntervalSince1970: 1000)
        let cacheDirectory = directory.appendingPathComponent("Cache")
        let cache = cacheDirectory.appendingPathComponent("snapshot-cache.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for old in ["snapshot.json", "snapshot-meta.json"] { try Data("{}".utf8).write(to: directory.appendingPathComponent(old)) }
        let fetched = try await stubClient().snapshot(into: store, now: date)
        #expect(fetched.meta.fetchedAt == date)
        let saved = try Data(contentsOf: cache)
        #expect(saved.range(of: data) != nil)
        #expect(try cacheDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("snapshot.json").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("snapshot-meta.json").path))
        let loaded = try await store.load()
        #expect(loaded?.meta.fetchedAt == date)
        #expect(StubProtocol.state.seen.first?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(StubProtocol.state.seen.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        StubProtocol.state.set(200, Data("{}".utf8))
        await #expect(throws: ClientError.incompatibleVersion) { try await stubClient().snapshot(into: store) }
        #expect(try Data(contentsOf: cache) == saved)
        let liveStore = SnapshotStore(directory: directory, pairedMac: { PairedMac(url: "https://fixture.invalid", name: "Fixture Mac") })
        await #expect(throws: ClientError.incompatibleVersion) { try await liveStore.save(data, from: PairedMac(url: "https://fixture.invalid", name: "Fixture Mac"), fetchedAt: date) }
        let badSchema = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"schema_version\": 2", with: "\"schema_version\": 3").utf8)
        await #expect(throws: ClientError.incompatibleVersion) { try await store.save(badSchema, from: PairedMac(url: "https://fixture.invalid:8787", name: "Fixture Mac"), fetchedAt: date) }
        #expect(try Data(contentsOf: cache) == saved)
        StubProtocol.state.set(200, data)
        let updated = try await stubClient().snapshot(into: store, now: date.addingTimeInterval(1))
        #expect(try await store.load()?.meta.fetchedAt == updated.meta.fetchedAt)
        #expect(try directory.appendingPathComponent("Cache").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test(arguments: ["snapshot-cache.json", "directory"])
    func unreadSnapshotThrowsThenRecovers(_ name: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedMac: { PairedMac(url: "https://fixture.invalid", name: "Fixture Mac") })
        let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"))
        let date = Date(timeIntervalSince1970: 1000)
        try await store.save(data, from: PairedMac(url: "https://fixture.invalid", name: "Fixture Mac"), fetchedAt: date)
        let file = name == "directory" ? directory : directory.appendingPathComponent("Cache").appendingPathComponent(name)
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

    @Test(arguments: [(401, "unauthorized", ClientError.unauthorized), (503, "store_unavailable", .storeUnavailable), (429, "rate_limited", .rateLimited(retryAfter: nil))])
    func httpErrors(_ code: Int, _ file: String, _ expected: ClientError) async throws {
        let suite = "ghealth-test-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let marker = RevokedCredentials(suiteName: suite)
        let credential = "fixture-credential"
        let client = APIClient(baseURL: URL(string: "https://mac-a.invalid")!, token: credential, session: stubClient().session,
                               onUnauthorized: { marker.insert(credential) })
        StubProtocol.state.set(code, try Data(contentsOf: fixtureRoot.appendingPathComponent("errors/\(file).json")))
        await #expect(throws: expected) { try await client.status() }
        #expect(marker.contains(credential) == (code == 401))
    }

    @Test(arguments: [
        ("5", TimeInterval?(5)), ("0", 1), ("500", 300), ("999999999999999999999999", 300),
        ("5.5", nil), ("-1", nil), ("Tue, 10 Mar 2026 12:00:05 GMT", nil)
    ])
    func retryAfterAcceptsOnlyDeltaSeconds(_ header: String, _ expected: TimeInterval?) async {
        StubProtocol.state.set(429, Data(), headers: ["Retry-After": header])
        await #expect(throws: ClientError.rateLimited(retryAfter: expected)) { try await stubClient().status() }
    }
}

extension ClientTests {
    @Test func concurrentRefreshesMakeOneRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedMac: { PairedMac(url: "https://fixture.invalid:8787", name: "Fixture Mac") })
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
