import Foundation
import Testing
@testable import GHealthCore

@Suite struct WidgetFreshnessTests {
    private let clock = ISO8601DateFormatter()
    private func at(_ text: String) -> Date { clock.date(from: text)! }
    private func cached(fetched: String, day: Day? = nil, edit: (inout Freshness) -> Void = { _ in }) throws -> CachedSnapshot {
        var snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
        if let day { snapshot.day = day }
        edit(&snapshot.freshness)
        return CachedSnapshot(snapshot: snapshot, meta: SnapshotMeta(fetchedAt: at(fetched), serverURL: "https://fixture.invalid:8787"))
    }

    @Test func freshOpenCycleIsCurrentAndDatedByTheBand() throws {
        let freshness = WidgetFreshness(try cached(fetched: "2026-03-10T14:30:00Z"), now: at("2026-03-10T14:30:00Z"))
        #expect(!freshness.stale && !freshness.pastWake)
        #expect(freshness.badge == "22m")
        #expect(freshness.label == "14:08")
        #expect(freshness.spoken == "")
        let calibrating = WidgetFreshness(try cached(fetched: "2026-03-10T14:30:00Z", day: fixture("day_calibrating.json")), now: at("2026-03-10T14:45:00Z"))
        #expect(!calibrating.stale)
    }

    @Test func preWakeSnapshotStaysTodayUntilARefreshFails() throws {
        let snapshot = try cached(fetched: "2026-03-11T00:10:00Z") { freshness in
            freshness.collectedAt = self.at("2026-03-11T00:05:00Z"); freshness.deviceLastSyncAt = self.at("2026-03-11T00:00:00Z")
        }
        let preWake = WidgetFreshness(snapshot, now: at("2026-03-11T00:25:00Z"))
        #expect(!preWake.stale && !preWake.pastWake)
        let afterWake = WidgetFreshness(snapshot, now: at("2026-03-11T05:00:00Z"))
        #expect(afterWake.pastWake && afterWake.stale)
        #expect(afterWake.badge == "Tue 10")
        #expect(afterWake.label == "Tue 10")
        #expect(afterWake.spoken == ", from Tuesday 10 March")
    }

    @Test func aFreshDownloadOfOldDataIsNeverNow() throws {
        let stale = try cached(fetched: "2026-03-10T15:00:00Z") { $0.collectorStale = true }
        let freshness = WidgetFreshness(stale, now: at("2026-03-10T15:00:00Z"))
        #expect(freshness.stale && !freshness.pastWake)
        #expect(freshness.badge == "52m")
        #expect(freshness.spoken == ", as of 14:08")
        let yesterday = try cached(fetched: "2026-03-11T09:00:00Z") { $0.collectorStale = true }
        #expect(WidgetFreshness(yesterday, now: at("2026-03-11T09:00:00Z")).badge != "now")
    }

    @Test func bandSyncCountsUnlessItsScopeIsMissing() throws {
        let band = try cached(fetched: "2026-03-10T14:30:00Z") { $0.deviceStale = true }
        #expect(WidgetFreshness(band, now: at("2026-03-10T14:30:00Z")).stale)
        let missing = try cached(fetched: "2026-03-10T14:30:00Z") { $0.deviceStale = true; $0.deviceSyncSource = "scope_missing" }
        let freshness = WidgetFreshness(missing, now: at("2026-03-10T14:30:00Z"))
        #expect(!freshness.stale)
        #expect(freshness.label == "14:16")
    }
}
