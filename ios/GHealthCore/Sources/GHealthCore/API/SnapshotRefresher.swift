import Foundation

/// Shares one in-flight snapshot request per Mac. A request for another Mac cancels the old one.
public actor SnapshotRefresher {
    public static let shared = SnapshotRefresher()
    private var flight: (server: String, id: UUID, task: Task<CachedSnapshot, any Error>)?
    public init() {}

    public func refresh(client: APIClient, store: SnapshotStore, now: Date = .now) async throws -> CachedSnapshot {
        let server = client.baseURL.absoluteString
        if let flight, flight.server == server { return try await flight.task.value }
        flight?.task.cancel()
        let id = UUID()
        let task = Task { try await client.snapshot(into: store, now: now) }
        flight = (server, id, task)
        defer { if flight?.id == id { flight = nil } }
        return try await task.value
    }
    public func cancel() { flight?.task.cancel() }
}

public struct RefreshPolicy: Sendable {
    public enum Trigger: Sendable { case active, widget }
    private let now: @Sendable () -> Date
    public init(now: @escaping @Sendable () -> Date = { .now }) { self.now = now }
    public func needsRefresh(fetchedAt: Date?, trigger: Trigger) -> Bool {
        guard let fetchedAt else { return true }
        return now().timeIntervalSince(fetchedAt) > (trigger == .active ? 60 : 1800)
    }
}
