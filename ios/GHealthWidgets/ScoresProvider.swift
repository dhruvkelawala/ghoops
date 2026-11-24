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
        let pairing = PairingRepository(suiteName: SharedAppGroup.id, tokens: KeychainTokenStore(accessGroup: keychainGroup))
        guard let credentials = try? await pairing.credentials() else { return WidgetData(cached: nil, paired: false, date: now) }
        let pairedURL: @Sendable () -> String? = { PairingRepository.pairedURL(suiteName: SharedAppGroup.id) }
        let store = SnapshotStore(directory: directory, pairedURL: pairedURL)
        var cached = try? await store.load()
        if cached?.meta.serverUrl != credentials.url.absoluteString { cached = nil }
        if RefreshPolicy(now: { now }).needsRefresh(fetchedAt: cached?.meta.fetchedAt, trigger: .widget) {
            if let fetched = try? await SnapshotRefresher.shared.refresh(client: APIClient(baseURL: credentials.url, token: credentials.token, widget: true), store: store, now: now) {
                cached = fetched
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        if cached?.meta.serverUrl != pairedURL() { cached = nil }
        return WidgetData(cached: cached, paired: true, date: now)
    }
}
