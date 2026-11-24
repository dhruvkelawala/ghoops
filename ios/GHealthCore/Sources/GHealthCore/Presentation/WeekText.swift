import Foundation

/// Words for the Week in Review card and sheet (week-review-spec.md §5). Every number comes from the Mac's `week` body.
public enum WeekText {
    public enum Target: String, CaseIterable, Sendable { case sleep, activity, strength }

    public struct Row: Sendable, Equatable {
        public var label: String
        public var metric: TrendMetricKey
        public var value: WeekMetric
        public var note: String?
    }

    public struct Section: Sendable, Equatable {
        public var title: String
        public var rows: [Row]
    }

    /// "Mon 9 – Sun 15 Mar", with " · so far" while the week runs.
    public static func span(_ week: Week) -> String {
        let sameMonth = GoopFormat.dateLabel(week.from, format: "MMM") == GoopFormat.dateLabel(week.weekEnd, format: "MMM")
        let start = GoopFormat.dateLabel(week.from, format: sameMonth ? "EEE d" : "EEE d MMM")
        let text = start + " – " + GoopFormat.dateLabel(week.weekEnd, format: "EEE d MMM")
        return week.complete ? text : text + " · so far"
    }

    /// The legend's two labels: the shown week, then the days it is compared with.
    public static func legend(_ week: Week) -> (shown: String, compared: String) {
        week.complete ? ("Last week", "Week before") : ("This week", "Same days last week")
    }

    public static func label(_ target: Target, in week: Week) -> String {
        switch target {
        case .sleep: "Nights of \(hours(week.targets.sleep.minMinutes)) or more"
        case .activity: "Zone minutes"
        case .strength: "Strength days"
        }
    }

    public static func cellLabel(_ target: Target) -> String {
        switch target {
        case .sleep: "SLEEP"
        case .activity: "ZONE MINUTES"
        case .strength: "STRENGTH"
        }
    }

    /// The rule under the zone-minute row, built from the Mac's weight.
    public static func activityRule(_ week: Week) -> String {
        "Zones 4–5 count \(week.targets.activity.vigorousWeight) times" // goop-lint: allow enginenumber: zone names
    }

    /// The count and what it is counted against, as a Sofia value and a Nunito unit.
    public static func progress(_ target: Target, in week: Week) -> (value: String, unit: String) {
        let t = week.targets
        switch target {
        case .sleep: return ("\(t.sleep.metNights)", "of \(t.sleep.nights)")
        case .activity: return (GoopFormat.duration(t.activity.creditMinutes), "of " + GoopFormat.duration(t.activity.minutes))
        case .strength: return ("\(t.strength.metDays)", "of \(t.strength.days)")
        }
    }

    public static func status(_ target: Target, in week: Week) -> String {
        switch target {
        case .sleep: week.targets.sleep.status
        case .activity: week.targets.activity.status
        case .strength: week.targets.strength.status
        }
    }

    /// MET, SO FAR, NOT MET or NO DATA; nil for a status this app does not know.
    public static func statusWord(_ status: String) -> String? {
        switch status {
        case "met": "MET"
        case "open": "SO FAR"
        case "not_met": "NOT MET"
        case "no_data": "NO DATA"
        default: nil
        }
    }

    /// Why a finished week has no answer: "· 1 night missing". Only `no_data` carries one.
    public static func statusDetail(_ target: Target, in week: Week) -> String? {
        guard status(target, in: week) == "no_data" else { return nil }
        let t = week.targets
        switch target {
        case .sleep: return "· " + missing(t.sleep.missingNights, nights: true)
        case .activity: return "· " + missing(t.activity.missingDays, nights: false)
        case .strength: return "· " + missing(t.strength.missingDays, nights: false)
        }
    }

    /// The pillar sections under TARGETS, in the order of spec §5.2.
    public static func sections(_ week: Week) -> [Section] {
        let m = week.metrics
        func row(_ label: String, _ key: TrendMetricKey, _ value: WeekMetric, nights: Bool) -> Row {
            let gap = week.daysCounted - value.availableDays
            return Row(label: label, metric: key, value: value, note: gap > 0 ? missing(gap, nights: nights) : nil)
        }
        return [
            Section(title: "SLEEP", rows: [
                row("Sleep performance", .sleepPerformance, m.sleepPerformance, nights: true),
                row("Hours of sleep", .hours, m.asleepMinutes, nights: true),
                row("Sleep consistency", .consistency, m.sleepConsistency, nights: true),
            ]),
            Section(title: "RECOVERY", rows: [
                row("Recovery", .recovery, m.recovery, nights: true),
                row("Heart rate variability", .hrv, m.hrvRmssdMs, nights: true),
                row("Resting heart rate", .restingHR, m.restingHrBpm, nights: true),
            ]),
            Section(title: "STRAIN", rows: [
                row("Day Strain", .strain, m.strain, nights: false),
                row("Zones 1–3", .zones13, m.zones13Minutes, nights: false), // goop-lint: allow enginenumber: zone names
                row("Zones 4–5", .zones45, m.zones45Minutes, nights: false), // goop-lint: allow enginenumber: zone names
                row("Steps", .steps, m.steps, nights: false),
            ]),
            Section(title: "ACTIVITIES", rows: [
                row("Strength activity time", .strength, m.strengthMinutes, nights: false),
            ]),
        ]
    }

    public static let footnote = "Weeks run Monday to Sunday. Set the targets on your Mac with ghoops config set."

    /// VoiceOver for the Trends card, for example "Week in review, Monday 9 to Sunday 15 March, so far. Sleep, 1 of 5 nights. …".
    public static func cardSpoken(_ week: Week) -> String {
        let t = week.targets
        let from = GoopFormat.dateLabel(week.from, format: "EEEE d"), to = GoopFormat.dateLabel(week.weekEnd, format: "EEEE d MMMM")
        let zones = spokenDuration(t.activity.creditMinutes) + " of " + spokenDuration(t.activity.minutes)
        return "Week in review, \(from) to \(to)\(week.complete ? "" : ", so far"). "
            + "Sleep, \(t.sleep.metNights) of \(t.sleep.nights) nights. Zone minutes, \(zones). Strength, \(t.strength.metDays) of \(t.strength.days) days."
    }

    /// 420 → "7 h", 450 → "7 h 30 min".
    static func hours(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    static func missing(_ count: Int, nights: Bool) -> String {
        "\(count) \(nights ? "night" : "day")\(count == 1 ? "" : "s") missing"
    }

    static func spokenDuration(_ minutes: Int?) -> String {
        guard let minutes else { return "no data" }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) minutes" }
        return m == 0 ? "\(h) hour\(h == 1 ? "" : "s")" : "\(h) hour\(h == 1 ? "" : "s") \(m)"
    }
}
