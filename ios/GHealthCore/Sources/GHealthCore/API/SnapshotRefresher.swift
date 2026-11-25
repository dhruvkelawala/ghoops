import Foundation

/// Shares a snapshot request for the same Mac and credential.
public actor SnapshotRefresher {
    public static let shared = SnapshotRefresher()
    private var flight: (client: APIClient, id: UUID, task: Task<CachedSnapshot, any Error>)?
    public init() {}

    public func refresh(client: APIClient, store: SnapshotStore, now: Date = .now) async throws -> CachedSnapshot {
        if let flight, flight.client.sharesSnapshotRequest(with: client) { return try await flight.task.value }
        flight?.task.cancel()
        let id = UUID()
        let task = Task { try await client.snapshot(into: store, now: now) }
        flight = (client, id, task)
        defer { if flight?.id == id { flight = nil } }
        return try await task.value
    }
    public func cancel() {
        let task = flight?.task
        flight = nil
        task?.cancel()
    }
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
