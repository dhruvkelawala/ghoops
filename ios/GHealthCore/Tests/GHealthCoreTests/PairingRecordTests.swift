import Foundation
import Testing
@testable import GHealthCore

enum MigrationPause: Error, CaseIterable {
    case beforeAdd, beforeReadback, afterTokenRemoval
}

final class MemoryTokens: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var pauseAfterRemoval: Bool

    init(_ value: String? = nil, pauseAfterRemoval: Bool = false) {
        self.value = value
        self.pauseAfterRemoval = pauseAfterRemoval
    }

    func load() -> String? { lock.withLock { value } }

    func delete() throws {
        try lock.withLock {
            value = nil
            if pauseAfterRemoval {
                pauseAfterRemoval = false
                throw MigrationPause.afterTokenRemoval
            }
        }
    }
}

final class MemoryPairingRecords: RecordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: PairingRecord?
    private var pause: MigrationPause?
    private var duplicate: PairingRecord?
    private var writes = 0

    init(pause: MigrationPause? = nil, duplicate: PairingRecord? = nil) {
        self.pause = pause
        self.duplicate = duplicate
    }

    func load() throws -> PairingRecord? {
        try lock.withLock {
            if value != nil, pause == .beforeReadback {
                pause = nil
                throw MigrationPause.beforeReadback
            }
            return value
        }
    }

    func addIfAbsent(_ record: PairingRecord) throws {
        try lock.withLock {
            if pause == .beforeAdd {
                pause = nil
                throw MigrationPause.beforeAdd
            }
            if value == nil { value = duplicate ?? record }
        }
    }

    var saveCount: Int { lock.withLock { writes } }
    func save(_ record: PairingRecord) { lock.withLock { value = record; writes += 1 } }
    func delete() { lock.withLock { value = nil } }
}

struct PairingRecordTests {
    private let macA = PairingRecord(url: URL(string: "https://mac-a.invalid")!, credential: "fixture-a", name: "Mac A")
    private let macB = PairingRecord(url: URL(string: "https://mac-b.invalid")!, credential: "fixture-b", name: "Mac B")

    @Test(arguments: MigrationPause.allCases)
    func migrationResumesAfterInterruption(_ pause: MigrationPause) async throws {
        let suite = "ghealth-test-\(UUID())"
        let defaults = try legacyDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let tokens = MemoryTokens(macA.credential, pauseAfterRemoval: pause == .afterTokenRemoval)
        let records = MemoryPairingRecords(pause: pause)
        let first = PairingRepository(suiteName: suite, tokens: tokens, records: records)

        await #expect(throws: pause) { try await first.migrateLegacy() }
        let interruptedRecord = try records.load()
        #expect((interruptedRecord != nil) == (pause != .beforeAdd))
        #expect(defaults.string(forKey: "serverURL") == macA.url.absoluteString)
        #expect(defaults.string(forKey: "macName") == macA.name)
        #expect(tokens.load() == (pause == .afterTokenRemoval ? nil : macA.credential))

        let resumed = PairingRepository(suiteName: suite, tokens: tokens, records: records)
        try await resumed.migrateLegacy()
        let stored = try #require(try records.load())
        #expect(stored.credential == macA.credential)
        #expect(stored.url == macA.url)
        #expect(stored.name == macA.name)
        try await resumed.migrateLegacy()
        #expect(try records.load() == stored)
        #expect(tokens.load() == nil)
        #expect(defaults.string(forKey: "serverURL") == nil)
        #expect(defaults.string(forKey: "macName") == nil)
    }

    @Test func duplicateAddReadsBackTheWinningRecord() async throws {
        let suite = "ghealth-test-\(UUID())"
        let defaults = try legacyDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let tokens = MemoryTokens(macA.credential)
        let records = MemoryPairingRecords(pause: .beforeReadback, duplicate: macB)
        let repository = PairingRepository(suiteName: suite, tokens: tokens, records: records)

        await #expect(throws: MigrationPause.beforeReadback) { try await repository.migrateLegacy() }
        #expect(tokens.load() == macA.credential)
        #expect(defaults.string(forKey: "serverURL") == macA.url.absoluteString)

        try await repository.migrateLegacy()
        #expect(try await repository.credentials()?.token == macB.credential)
        #expect(try records.load() == macB)
        #expect(tokens.load() == nil)
        #expect(defaults.string(forKey: "serverURL") == nil)
    }

    @Test func credentialsReadLegacyWithoutWritingAndPreferTheRecord() async throws {
        let suite = "ghealth-test-\(UUID())"
        let defaults = try legacyDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let tokens = MemoryTokens(macA.credential)
        let records = MemoryPairingRecords()
        let repository = PairingRepository(suiteName: suite, tokens: tokens, records: records)

        let legacy = try await repository.credentials()
        #expect(legacy?.url == macA.url)
        #expect(legacy?.token == macA.credential)
        #expect(try records.load() == nil)

        records.save(macB)
        let current = try await repository.credentials()
        #expect(current?.url == macB.url)
        #expect(current?.name == macB.name)
        #expect(current?.token == macB.credential)
        #expect(defaults.string(forKey: "serverURL") == macA.url.absoluteString)
        #expect(tokens.load() == macA.credential)
    }

    @Test func concurrentReadersSeeWholeRecords() async throws {
        let suite = "ghealth-test-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let records = MemoryPairingRecords()
        let tokens = MemoryTokens()
        records.save(macA)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for index in 0..<1_000 {
                    records.save(index.isMultiple(of: 2) ? macA : macB)
                    await Task.yield()
                }
            }
            for _ in 0..<4 {
                let reader = PairingRepository(suiteName: suite, tokens: tokens, records: records)
                group.addTask {
                    for _ in 0..<1_000 {
                        let credentials = try #require(try await reader.credentials())
                        let matchesA = credentials.url == macA.url && credentials.token == macA.credential && credentials.name == macA.name
                        let matchesB = credentials.url == macB.url && credentials.token == macB.credential && credentials.name == macB.name
                        #expect(matchesA || matchesB)
                        await Task.yield()
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func recordUsesOneVersionedBody() throws {
        let record = PairingRecord(url: macA.url, credential: macA.credential, name: macA.name, pairedAt: Date(timeIntervalSince1970: 0))
        let data = try JSONCoding.encoder().encode(record)
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(fields["version"] as? Int == 1)
        #expect(fields["url"] as? String == "https://mac-a.invalid")
        #expect(fields["credential"] as? String == "fixture-a")
        #expect(fields["name"] as? String == "Mac A")
        #expect(fields["device_id"] is NSNull)
        #expect(fields["profile_id"] is NSNull)
        #expect(fields["paired_at"] as? String == "1970-01-01T00:00:00Z")
        #expect(try JSONCoding.decoder().decode(PairingRecord.self, from: data) == record)
    }

    private func legacyDefaults(_ suite: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(macA.url.absoluteString, forKey: "serverURL")
        defaults.set(macA.name, forKey: "macName")
        return defaults
    }
}
