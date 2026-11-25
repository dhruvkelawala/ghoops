import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClientError: Error, Equatable, LocalizedError, Sendable {
    case unauthorized, profileMismatch, storeUnavailable, offline, timedOut, incompatibleVersion, rejected, notFound, conflict
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)

    public var invalidatesPairing: Bool { self == .unauthorized || self == .profileMismatch }

    var rateLimitDelay: TimeInterval? {
        switch self {
        case .rateLimited(let retryAfter): retryAfter ?? ChangeTiming.retryInterval
        case .http(429): ChangeTiming.retryInterval
        default: nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unauthorized, .profileMismatch: "This phone is no longer paired with your Mac. Run ghoops pair on your Mac, then scan its code."
        case .rateLimited: "Your Mac is getting too many requests. Try again in a minute."
        case .storeUnavailable: "Your Mac can't open its saved health data. Log in on your Mac, then try again."
        case .offline: "Can't reach your Mac over Tailscale. Is Tailscale on?"
        case .timedOut: "Your Mac is taking too long to answer. ghoops will try again."
        case .incompatibleVersion: "Your Mac and this phone run different versions of ghoops. Update both to the same version."
        case .rejected: "Your Mac could not save this. Check the times and try again."
        case .notFound: "This activity changed on your Mac. Close and open it again."
        case .conflict: "This activity is now part of another one. Close and open it again."
        case .http: "Your Mac ran into a problem. Try again in a moment."
        }
    }

    static func transportError(_ error: Error) -> ClientError? {
        guard let error = error as? URLError else { return nil }
        switch error.code {
        case .timedOut: return .timedOut
        case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed: return .offline
        default: return nil
        }
    }

    static func rateLimited(from response: HTTPURLResponse) -> Self {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return .rateLimited(retryAfter: nil)
        }
        return .rateLimited(retryAfter: min(300, max(1, TimeInterval(value) ?? 300)))
    }
}

public protocol ActivityAPI: Sendable {
 func postActivity(_ activity: ActivityUpload) async throws -> ActivityRecord
 func deleteActivity(id: String) async throws
}

public enum MutationError: Error, Sendable { case unreadableResponse }

public struct APIClient: DaysFetching, WeekFetching, ActivityAPI, EditAPI {
    let session: URLSession
    private static let appSession = URLSession(configuration: configuration(timeout: 15))
    private static let widgetSession = URLSession(configuration: configuration(timeout: 10))
    public let baseURL: URL
    private let token: String
    let mac: PairedMac
    private let onUnauthorized: (@Sendable () async -> Void)?

    public init(baseURL: URL, token: String, profileId: String? = nil, widget: Bool = false, session: URLSession? = nil,
                onUnauthorized: (@Sendable () async -> Void)? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.mac = PairedMac(url: baseURL.absoluteString, name: "", profile: profileId)
        self.session = session ?? (widget ? Self.widgetSession : Self.appSession)
        self.onUnauthorized = onUnauthorized
    }

    func sharesSnapshotRequest(with other: Self) -> Bool {
        token == other.token && mac.url == other.mac.url && mac.matches(other.mac)
    }

    static func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if !os(Linux)
        config.waitsForConnectivity = false
        #endif
        return config
    }

    public func status() async throws -> Status {
        let status = try await read(Status.self, path: "status")
        try mac.checkProfile(status.server.profileId)
        return status
    }

    public func days(_ count: Int) async throws -> Days {
        try await read(Days.self, path: "days", query: [URLQueryItem(name: "days", value: String(count))])
    }

    public func day(date: String) async throws -> Day {
        try await read(Day.self, path: "day", query: [URLQueryItem(name: "date", value: date)])
    }

    public func sleep(date: String) async throws -> Sleep {
        try await read(Sleep.self, path: "sleep", query: [URLQueryItem(name: "date", value: date)])
    }

    public func workouts(from: String, to: String) async throws -> Workouts {
        try await read(Workouts.self, path: "workouts", query: rangeQuery(from: from, to: to))
    }

    public func days(from: String, to: String) async throws -> Days {
        try await read(Days.self, path: "days", query: rangeQuery(from: from, to: to))
    }

    /// The week containing `date`, or the current week when `date` is nil (contract §5.16).
    public func week(date: String?) async throws -> Week {
        try await read(Week.self, path: "week", query: date.map { [URLQueryItem(name: "date", value: $0)] } ?? [])
    }

    public func workouts(days: Int) async throws -> Workouts {
        try await read(Workouts.self, path: "workouts", query: [URLQueryItem(name: "days", value: String(days))])
    }
    public func postActivity(_ activity: ActivityUpload) async throws -> ActivityRecord {
        let data = try await send(path: "activities", method: "POST", body: JSONCoding.encoder().encode(activity))
        do { return try decode(ActivityResponse.self, data: data).activity }
        catch { throw MutationError.unreadableResponse }
    }
    public func deleteActivity(id: String) async throws {
        let data = try await send(path: "activities/\(id)", method: "DELETE")
        _ = try decode(ActivityDeleted.self, data: data)
    }
    public func putEdit(id: String, _ body: EditBody) async throws -> WorkoutEdit? {
        let data = try await send(path: "edits/\(id)", method: "PUT", body: JSONCoding.encoder().encode(body))
        do { return try decode(EditResponse.self, data: data).edit }
        catch { throw MutationError.unreadableResponse }
    }
    public func deleteEdit(id: String) async throws {
        let data = try await send(path: "edits/\(id)", method: "DELETE")
        do { _ = try decode(EditResponse.self, data: data) }
        catch { throw MutationError.unreadableResponse }
    }
    public func putRating(id: String, _ body: RatingBody) async throws {
        let data = try await send(path: "ratings/\(id)", method: "PUT", body: JSONCoding.encoder().encode(body))
        do { _ = try decode(RatingResponse.self, data: data) }
        catch { throw MutationError.unreadableResponse }
    }
    public func putSleepEdit(date: String, _ body: SleepEditBody) async throws -> SleepEdit? {
        let data = try await send(path: "sleep-edits/\(date)", method: "PUT", body: JSONCoding.encoder().encode(body))
        do { return try decode(SleepEditResponse.self, data: data).sleepEdit }
        catch { throw MutationError.unreadableResponse }
    }
    public func putJournal(date: String, _ body: JournalBody) async throws -> JournalEntry? {
        let data = try await send(path: "journal/\(date)", method: "PUT", body: JSONCoding.encoder().encode(body))
        do { return try decode(JournalEntryResponse.self, data: data).entry }
        catch { throw MutationError.unreadableResponse }
    }
    public func deleteSleepEdit(date: String) async throws {
        let data = try await send(path: "sleep-edits/\(date)", method: "DELETE")
        do { _ = try decode(SleepEditResponse.self, data: data) }
        catch { throw MutationError.unreadableResponse }
    }
    public func heartRate(date: String) async throws -> HeartRateBody {
        try await read(HeartRateBody.self, path: "heart-rate", query: [URLQueryItem(name: "date", value: date)])
    }
    public func heartRate(start: Date, end: Date) async throws -> HeartRateBody {
        let formatter = ISO8601DateFormatter()
        return try await read(HeartRateBody.self, path: "heart-rate", query: [URLQueryItem(name: "start", value: formatter.string(from: start)), URLQueryItem(name: "end", value: formatter.string(from: end))])
    }
    private func rangeQuery(from: String, to: String) -> [URLQueryItem] {
        [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
    }

    public func snapshot(into store: SnapshotStore, now: Date = .now) async throws -> CachedSnapshot {
        let data = try await snapshotData()
        return try await store.save(data, from: mac, fetchedAt: now)
    }

    public func snapshotData() async throws -> Data { try await get(path: "snapshot") }

    private func read<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await get(path: path, query: query)
        return try decode(type, data: data)
    }
    private func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        do {
            let envelope = try JSONCoding.decoder().decode(ResponseHeader.self, from: data)
            guard envelope.schemaVersion == 2, envelope.syntheticFixture == nil else { throw ClientError.incompatibleVersion }
            return try JSONCoding.decoder().decode(type, from: data)
        } catch { throw ClientError.incompatibleVersion }
    }

    private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await send(path: path, query: query)
    }
    private func send(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> Data {
        if method != "GET", mac.profile != nil {
            _ = try await status()
            try Task.checkCancellation()
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("v2/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, http) = try await MacTransport.response(for: request, in: session)
        switch http.statusCode {
        case 200..<300: return data
        case 400: throw ClientError.rejected
        case 404: throw ClientError.notFound
        case 409: throw ClientError.conflict
        case 401:
            await onUnauthorized?()
            throw ClientError.unauthorized
        case 429: throw ClientError.rateLimited(from: http)
        default:
            let body = try? JSONCoding.decoder().decode(APIError.self, from: data)
            if body?.error.code == "store_unavailable" { throw ClientError.storeUnavailable }
            throw ClientError.http(http.statusCode)
        }
    }
}

private struct ResponseHeader: Decodable {
    let schemaVersion: Int
    let syntheticFixture: Bool?
}
