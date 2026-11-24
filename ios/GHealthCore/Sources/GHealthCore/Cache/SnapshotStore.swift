import Foundation

public struct SnapshotMeta: Codable, Sendable {
    public let fetchedAt: Date
    public let serverUrl: String
    public let schemaVersion: Int

    public init(fetchedAt: Date, serverURL: String) {
        self.fetchedAt = fetchedAt
        self.serverUrl = serverURL
        self.schemaVersion = 2
    }
}

public struct CachedSnapshot: Sendable {
    public let snapshot: Snapshot
    public let meta: SnapshotMeta
    public init(snapshot: Snapshot, meta: SnapshotMeta) {
        self.snapshot = snapshot
        self.meta = meta
    }
}

/// The phone's copy of one Mac's snapshot. Meta and body share one file, written once, so the app and the
/// widget can't tear them apart. Only the paired Mac's snapshot is read or written.
public actor SnapshotStore {
    static let file = "snapshot-cache.json"
    private let directory: URL
    private let allowSynthetic: Bool
    private let pairedURL: @Sendable () -> String?

    public init(directory: URL, allowSynthetic: Bool = false, pairedURL: @escaping @Sendable () -> String?) {
        self.directory = directory
        self.pairedURL = pairedURL
        #if DEBUG
        self.allowSynthetic = allowSynthetic
        #else
        self.allowSynthetic = false
        #endif
    }

    public func load() throws -> CachedSnapshot? {
        guard let data = try SavedFiles.read(directory.appendingPathComponent(Self.file)) else { return nil }
        let file: CacheFile
        do { file = try JSONCoding.decoder().decode(CacheFile.self, from: data) }
        catch { throw ClientError.incompatibleVersion }
        guard file.meta.schemaVersion == 2 else { throw ClientError.incompatibleVersion }
        try validate(file.snapshot)
        guard let paired = pairedURL(), file.meta.serverUrl == paired else { return nil }
        return CachedSnapshot(snapshot: file.snapshot, meta: file.meta)
    }

    /// Saves a snapshot fetched from `serverURL`. A late response from a Mac that is no longer paired is
    /// dropped with `CancellationError` and the file is left as it was.
    public func save(_ data: Data, serverURL: String, fetchedAt: Date) throws -> CachedSnapshot {
        let snapshot = try decode(data)
        guard serverURL == pairedURL() else { throw CancellationError() }
        let meta = SnapshotMeta(fetchedAt: fetchedAt, serverURL: serverURL)
        let metaData = try JSONCoding.encoder().encode(meta)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(Data(#"{"meta":"#.utf8) + metaData + Data(#","snapshot":"#.utf8) + data + Data("}".utf8), name: Self.file)
        for old in ["snapshot.json", "snapshot-meta.json"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old)) }
        return CachedSnapshot(snapshot: snapshot, meta: meta)
    }

    private struct CacheFile: Decodable {
        let meta: SnapshotMeta
        let snapshot: Snapshot
    }

    private func decode(_ data: Data) throws -> Snapshot {
        let snapshot: Snapshot
        do { snapshot = try JSONCoding.decoder().decode(Snapshot.self, from: data) }
        catch { throw ClientError.incompatibleVersion }
        try validate(snapshot)
        return snapshot
    }

    private func validate(_ snapshot: Snapshot) throws {
        let bodies = [snapshot.schemaVersion, snapshot.status.schemaVersion, snapshot.day.schemaVersion, snapshot.sleep.schemaVersion, snapshot.days.schemaVersion, snapshot.workouts.schemaVersion]
        let markers = [snapshot.syntheticFixture, snapshot.status.syntheticFixture, snapshot.day.syntheticFixture, snapshot.sleep.syntheticFixture, snapshot.days.syntheticFixture, snapshot.workouts.syntheticFixture]
        guard bodies.allSatisfy({ $0 == 2 }), allowSynthetic || markers.allSatisfy({ $0 == nil }) else { throw ClientError.incompatibleVersion }
    }

    private func write(_ data: Data, name: String) throws {
        let url = directory.appendingPathComponent(name)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
