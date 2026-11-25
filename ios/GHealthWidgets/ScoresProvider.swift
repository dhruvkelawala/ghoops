import Foundation
import WidgetKit
import GHealthCore

struct ScoresEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    let metric: ScoreMetric
    let line: LockExtraLine
}

struct ScoresProvider<Configuration: ScoresConfiguration>: AppIntentTimelineProvider {
    typealias Intent = Configuration
    typealias Entry = ScoresEntry

    func placeholder(in context: Context) -> ScoresEntry {
        ScoresEntry(date: .now, data: WidgetData(cached: nil, paired: true, date: .now), metric: .recovery, line: .none)
    }
    func snapshot(for configuration: Configuration, in context: Context) async -> ScoresEntry {
        let data = await load()
        return ScoresEntry(date: data.date, data: data, metric: configuration.selectedMetric, line: configuration.extraLine)
    }
    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<ScoresEntry> {
        let data = await load()
        let entries = (0..<5).map { index in
            let date = data.date.addingTimeInterval(Double(index) * 15 * 60)
            return ScoresEntry(date: date, data: WidgetData(cached: data.cached, paired: data.paired, date: date), metric: configuration.selectedMetric, line: configuration.extraLine)
        }
        return Timeline(entries: entries, policy: .after(data.date.addingTimeInterval(30 * 60)))
    }
    private func load() async -> WidgetData {
        let now = Date.now
        guard let directory = SharedAppGroup.directory,
              let keychainGroup = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String else { return WidgetData(cached: nil, paired: false, date: now) }
        let pairing = PairingRepository(suiteName: SharedAppGroup.id, accessGroup: keychainGroup)
        try? await pairing.migrateLegacy()
        let pairedMac: @Sendable () -> PairedMac? = {
            PairingRepository.current(accessGroup: keychainGroup, suiteName: SharedAppGroup.id)?.mac
        }
        let store = SnapshotStore(directory: directory, pairedMac: pairedMac)
        guard let credentials = try? await pairing.credentials() else {
            await pairing.deleteRevokedCache(from: store)
            return WidgetData(cached: nil, paired: false, date: now)
        }
        var cached = try? await store.load()
        if cached?.meta.mac.matches(credentials.mac) != true { cached = nil }
        if RefreshPolicy(now: { now }).needsRefresh(fetchedAt: cached?.meta.fetchedAt, trigger: .widget) {
            do {
                cached = try await SnapshotRefresher.shared.refresh(client: credentials.client(widget: true), store: store, now: now)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                switch WidgetRefreshOutcome(error: error) {
                case .revoke:
                    await pairing.recordRevocation(of: credentials, cache: store)
                    WidgetCenter.shared.reloadAllTimelines()
                    return WidgetData(cached: nil, paired: pairedMac() != nil, date: now)
                case .unpaired:
                    return WidgetData(cached: nil, paired: false, date: now)
                case .keepCache:
                    break
                }
            }
        }
        let current = pairedMac()
        if cached?.meta.mac.matches(current) != true { cached = nil }
        return WidgetData(cached: cached, paired: current != nil, date: now)
    }
}
