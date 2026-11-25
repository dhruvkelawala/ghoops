import Foundation
import Testing
@testable import GHealthCore

struct RevocationTests {
    @Test func markerKeepsTheEightMostRecentDistinctCredentialHashes() throws {
        let suite = "ghealth-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let writer = RevokedCredentials(suiteName: suite)
        let reader = RevokedCredentials(suiteName: suite)
        #expect(!reader.contains("fixture-0"))
        for index in 0...8 { writer.insert("fixture-\(index)") }
        writer.insert("fixture-8")

        #expect(!reader.contains("fixture-0"))
        for index in 1...8 { #expect(reader.contains("fixture-\(index)")) }
        let stored = try #require(defaults.stringArray(forKey: "revokedCredentials"))
        #expect(stored.count == 8)
        #expect(stored.last == "f3bc822097333cae")
    }

    @Test func deletingACacheChecksItsMac() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedMac: { macA })
        let body = try snapshotBody()
        let date = Date(timeIntervalSince1970: 1000)
        _ = try await store.save(body, from: macA, fetchedAt: date)

        try await store.deleteIfMatches(macB)
        #expect(try await store.load()?.meta.fetchedAt == date)
        try await store.deleteIfMatches(macA)
        #expect(try await store.load() == nil)
        try await store.deleteIfMatches(macA)
    }

    @Test func unpairRemovesPairingAndEverySnapshotFormat() async throws {
        let suite = "ghealth-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokens = MemoryTokens("fixture-legacy")
        let records = MemoryPairingRecords()
        let repository = PairingRepository(suiteName: suite, tokens: tokens, records: records)
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedMac: { macA })
        let url = try #require(URL(string: macA.url))
        let pairing = PairingRecord(url: url, credential: "fixture-current", name: macA.name)
        try await repository.save(pairing)
        defaults.set(url.absoluteString, forKey: "serverURL")
        defaults.set(macA.name, forKey: "macName")

        let date = Date(timeIntervalSince1970: 1000)
        _ = try await store.save(snapshotBody(), from: macA, fetchedAt: date)
        let cache = directory.appendingPathComponent("Cache/snapshot-cache.json")
        let original = directory.appendingPathComponent("snapshot-cache.json")
        try FileManager.default.moveItem(at: cache, to: original)
        try await store.prepareForBackup()
        #expect(try await store.load()?.meta.fetchedAt == date)
        #expect(try original.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let split = ["snapshot.json", "snapshot-meta.json"].map { directory.appendingPathComponent($0) }
        for file in [cache] + split { try FileManager.default.copyItem(at: original, to: file) }

        try await repository.unpair(clearing: store)
        #expect(try await repository.credentials() == nil)
        #expect(tokens.load() == nil)
        #expect(defaults.string(forKey: "serverURL") == nil && defaults.string(forKey: "macName") == nil)
        #expect(try await store.load() == nil)
        for file in [cache, original] + split {
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func revocationClearsTheSavedSnapshotAndSpareCredentialsStillWork() async throws {
        let suite = "ghealth-test-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = MemoryPairingRecords()
        let repository = PairingRepository(suiteName: suite, tokens: MemoryTokens(), records: records)
        let otherProcess = PairingRepository(suiteName: suite, tokens: MemoryTokens(), records: records)
        let store = SnapshotStore(directory: directory, allowSynthetic: true, pairedMac: { macA })

        let url = try #require(URL(string: macA.url))
        let original = PairingRecord(url: url, credential: "fixture-old", name: macA.name)
        let replacement = PairingRecord(url: url, credential: "fixture-new", name: macA.name)
        try await repository.save(original)
        let body = try snapshotBody()
        _ = try await store.save(body, from: macA, fetchedAt: .now)
        let oldCredentials = try #require(try await repository.credentials())

        await repository.recordRevocation(of: oldCredentials, cache: store)
        await #expect(throws: ClientError.unauthorized) { try await otherProcess.credentials() }
        #expect(try await store.load() == nil)

        try await repository.save(replacement)
        let date = Date(timeIntervalSince1970: 1000)
        _ = try await store.save(body, from: macA, fetchedAt: date)
        await otherProcess.recordRevocation(of: oldCredentials, cache: store)
        #expect(try await repository.credentials()?.samePairing(as: Credentials(replacement)) == true)
        #expect(try await store.load()?.meta.fetchedAt == date)
    }

    @Test(arguments: [
        (ClientError.unauthorized, WidgetRefreshOutcome.revoke),
        (.profileMismatch, .unpaired),
        (.offline, .keepCache),
        (.timedOut, .keepCache),
        (.rateLimited(retryAfter: nil), .keepCache),
        (.storeUnavailable, .keepCache),
        (.http(500), .keepCache),
    ])
    func widgetPreservesTheCacheExceptOnConfirmedRevocation(_ error: ClientError, _ outcome: WidgetRefreshOutcome) {
        #expect(WidgetRefreshOutcome(error: error) == outcome)
    }

    private func snapshotBody() throws -> Data {
        try Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"))
    }
}
