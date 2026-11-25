import Darwin
import Foundation

public struct SnapshotMeta: Codable, Sendable {
    public let fetchedAt: Date
    public let serverUrl: String
    public let profileId: String?
    public let schemaVersion: Int

    public init(fetchedAt: Date, serverURL: String, profileId: String? = nil) {
        self.fetchedAt = fetchedAt
        self.serverUrl = serverURL
        self.profileId = profileId
        self.schemaVersion = 2
    }

    public var mac: PairedMac { PairedMac(url: serverUrl, name: "", profile: profileId) }
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
    private static let file = "snapshot-cache.json"
    private static let legacyNames = [file, "snapshot.json", "snapshot-meta.json"]
    private let directory: URL
    private let allowSynthetic: Bool
    private let pairedMac: @Sendable () -> PairedMac?

    public init(directory: URL, allowSynthetic: Bool = false, pairedMac: @escaping @Sendable () -> PairedMac?) {
        self.directory = directory
        self.pairedMac = pairedMac
        #if DEBUG
        self.allowSynthetic = allowSynthetic
        #else
        self.allowSynthetic = false
        #endif
    }

    public func load() throws -> CachedSnapshot? {
        let legacy = directory.appendingPathComponent(Self.file)
        guard let data = try SavedFiles.read(cacheFile) ?? SavedFiles.read(legacy) else { return nil }
        let file: CacheFile
        do { file = try JSONCoding.decoder().decode(CacheFile.self, from: data) }
        catch { throw ClientError.incompatibleVersion }
        guard file.meta.schemaVersion == 2 else { throw ClientError.incompatibleVersion }
        try validate(file.snapshot)
        guard file.meta.mac.matches(pairedMac()) else { return nil }
        return CachedSnapshot(snapshot: file.snapshot, meta: file.meta)
    }

    public func prepareForBackup() throws {
        try Self.prepareCacheDirectory(in: directory)
        for legacy in legacyFiles where FileManager.default.fileExists(atPath: legacy.path) {
            try Self.excludeFromBackup(legacy)
        }
    }

    public func save(_ data: Data, from mac: PairedMac, fetchedAt: Date) throws -> CachedSnapshot {
        let snapshot = try decode(data)
        let profileId = snapshot.status.server.profileId
        let meta = SnapshotMeta(fetchedAt: fetchedAt, serverURL: mac.url, profileId: profileId)
        let metaData = try JSONCoding.encoder().encode(meta)
        try Self.prepareCacheDirectory(in: directory)
        try withWriteLock {
            guard let paired = pairedMac(), mac.matches(paired) else { throw CancellationError() }
            try mac.checkProfile(profileId)
            guard meta.mac.matches(paired) else { throw CancellationError() }
            try write(Data(#"{"meta":"#.utf8) + metaData + Data(#","snapshot":"#.utf8) + data + Data("}".utf8))
            for old in legacyFiles { try remove(old) }
        }
        return CachedSnapshot(snapshot: snapshot, meta: meta)
    }

    public func deleteIfMatches(_ mac: PairedMac, stillCurrent: @Sendable () -> Bool = { true }) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try withWriteLock {
            for url in [cacheFile, directory.appendingPathComponent(Self.file)] {
                guard let data = try SavedFiles.read(url),
                      let header = try? JSONCoding.decoder().decode(CacheHeader.self, from: data),
                      header.meta.mac.matches(mac), stillCurrent() else { continue }
                try remove(url)
            }
        }
    }

    public nonisolated func deleteAll() throws {
        try deleteAll(then: {})
    }

    nonisolated func deleteAll(then finish: () throws -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try withWriteLock {
            try remove(cacheFile)
            for old in legacyFiles { try remove(old) }
            try finish()
        }
    }

    static func prepareCacheDirectory(in directory: URL) throws {
        let cache = cacheDirectory(in: directory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try excludeFromBackup(cache)
    }

    static func cacheDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("Cache", isDirectory: true)
    }

    private static func excludeFromBackup(_ item: URL) throws {
        var url = item
        var values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        guard values.isExcludedFromBackup != true else { return }
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private nonisolated var cacheFile: URL { Self.cacheDirectory(in: directory).appendingPathComponent(Self.file) }
    private nonisolated var legacyFiles: [URL] { Self.legacyNames.map { directory.appendingPathComponent($0) } }

    private nonisolated func remove(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch CocoaError.fileNoSuchFile {}
    }

    private struct CacheHeader: Decodable {
        let meta: SnapshotMeta
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

    private func write(_ data: Data) throws {
        #if os(iOS)
        try data.write(to: cacheFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: cacheFile, options: .atomic)
        #endif
    }

    private nonisolated func withWriteLock(_ operation: () throws -> Void) throws {
        let url = directory.appendingPathComponent("snapshot-cache.lock")
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        try operation()
    }
}
