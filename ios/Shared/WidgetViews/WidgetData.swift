import Foundation
import GHealthCore

struct WidgetData {
    let cached: CachedSnapshot?
    let paired: Bool
    let date: Date
    var message: String? { !paired ? "Open ghoops to pair" : cached == nil ? "No data yet" : nil }
    private var freshness: WidgetFreshness? { cached.map { WidgetFreshness($0, now: date) } }
    var stale: Bool { freshness?.stale ?? false }
    /// A refresh failed after a possible wake: the scores may be the previous day's.
    var pastWake: Bool { freshness?.pastWake ?? false }
    /// The stale badge: the data's age, or the scores' day after a possible wake.
    var age: String { freshness?.badge ?? "" }
    /// The medium header's time: when the data was collected, or the scores' day after a possible wake.
    var timeLabel: String { freshness?.label ?? "" }
    /// Appended to a spoken reading while it is stale.
    var spoken: String { freshness?.spoken ?? "" }
    var hrv: VitalMetric? { paired ? cached?.snapshot.day.vitals.metrics.hrvRmssd : nil }
    var hrvAttention: Bool { paired && cached?.snapshot.day.vitals.inAttention("hrv_rmssd") == true }
    var hrvText: String { GoopFormat.number(hrv?.status == .available ? hrv?.value : nil) }
    var bedtime: Date? {
        guard paired, let plan = cached?.snapshot.day.sleepPlan, plan.status == .ok,
              let wake = plan.wakeTarget, date < wake else { return nil }
        return plan.goals.first { $0.pct == 100 }?.bedtime
    }
    var bedtimeText: String { bedtime.map(GoopFormat.time) ?? "—" }
    func value(_ score: GoopScore) -> Double? {
        guard paired, let day = cached?.snapshot.day else { return nil }
        switch score {
        case .recovery: return day.recovery.value.map(Double.init)
        case .strain: return day.strain.value
        case .sleep: return SleepScore(day).performance.value.map(Double.init)
        }
    }
    func text(_ score: GoopScore, percent: Bool = true) -> String {
        guard let value = value(score) else { return "—" }
        return GoopFormat.number(value, decimals: score == .strain ? 1 : 0) + (score == .strain || !percent ? "" : "%")
    }
}
