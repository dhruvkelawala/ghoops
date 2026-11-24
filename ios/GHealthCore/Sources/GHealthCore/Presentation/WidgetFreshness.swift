import Foundation

/// How current a widget's scores are. The age comes from the Mac's last collection and the band's last sync,
/// never from the download, and a refresh that fails after a possible wake names the scores' day (oss-data-audit row 6).
public struct WidgetFreshness: Sendable, Equatable {
    /// The older of the Mac's last collection and the band's last sync: the time the scores reflect.
    public let dataTime: Date?
    /// The ghoops day the scores belong to.
    public let cycleDate: String
    /// A refresh is overdue and the calendar day has moved past the scores' day, so a wake may have started a new one.
    public let pastWake: Bool
    public let stale: Bool
    private let now: Date

    public init(_ cached: CachedSnapshot, now: Date) {
        let snapshot = cached.snapshot, freshness = snapshot.freshness
        let band = freshness.deviceSyncSource == "scope_missing" ? nil : freshness.deviceLastSyncAt
        dataTime = [freshness.collectedAt, band].compactMap { $0 }.min()
        cycleDate = snapshot.day.date
        self.now = now
        let overdue = RefreshPolicy(now: { now }).needsRefresh(fetchedAt: cached.meta.fetchedAt, trigger: .widget)
        pastWake = overdue && cycleDate < GoopFormat.dateKey(now)
        stale = now.timeIntervalSince(cached.meta.fetchedAt) > 6 * 3600 || freshness.collectorStale || freshness.bandSyncStale || pastWake
    }

    /// The text beside the stale clock: the scores' day after a possible wake, otherwise the data's age.
    public var badge: String {
        if pastWake { return GoopFormat.dateLabel(cycleDate, format: "EEE d") }
        guard let dataTime else { return "—" }
        let minutes = max(0, Int(now.timeIntervalSince(dataTime) / 60))
        return minutes < 1 ? "now" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    /// The medium widget's header time: the scores' day after a possible wake, otherwise the data's clock time.
    public var label: String { pastWake ? GoopFormat.dateLabel(cycleDate, format: "EEE d") : GoopFormat.time(dataTime) }

    /// Appended to a stale reading's spoken label; empty while the scores are current.
    public var spoken: String {
        guard stale else { return "" }
        if pastWake { return ", from " + GoopFormat.dateLabel(cycleDate, format: "EEEE d MMMM") }
        return dataTime.map { ", as of " + GoopFormat.time($0) } ?? ""
    }
}
