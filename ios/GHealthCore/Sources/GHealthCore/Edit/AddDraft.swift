import Foundation

public struct AddDraft: Sendable {
    public let defaultDate: String
    public let days: [String]
    public let workouts: [Workout]
    public let now: Date
    public let limits: EditLimits?
    public private(set) var id: String
    public var sport: String?
    public private(set) var day: String
    public var window: ActivityWindow
    public private(set) var heartRate: HeartRateBody?

    public init(defaultDate: String, workouts: [Workout], now: Date, limits: EditLimits?, day: String? = nil, id: String = UUID().uuidString.lowercased()) {
        self.defaultDate = defaultDate; self.workouts = workouts; self.now = now; self.limits = limits; self.id = id
        let days = Self.days(defaultDate: defaultDate, limits: limits)
        self.days = days
        self.day = day.flatMap { days.contains($0) ? $0 : nil } ?? defaultDate
        sport = nil
        let end = ActivityWindow.minute(now)
        window = ActivityWindow(start: end.addingTimeInterval(-3600), end: end)
        setDefaultWindow()
    }
    public static func days(defaultDate: String, limits: EditLimits?) -> [String] {
        (-3...0).map { ActivityTime.addingDays($0, to: defaultDate) }.filter { EditLimits.editable(cycleDate: $0, defaultDate: defaultDate, limits: limits) }
    }
    public var span: DateInterval {
        let start = heartRate?.start ?? ActivityTime.day(day)
        let end = day == defaultDate ? now : heartRate?.end ?? ActivityTime.calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: max(start.addingTimeInterval(60), end))
    }
    public var bounds: EditBounds { EditBounds.add(day: span, window: window, limits: limits, now: now) }
    public var efforts: [Workout] { workouts.filter { $0.kind == "detected" && $0.cycleDate == day && bounds.allows(ActivityWindow(start: $0.start, end: $0.end), pauses: []) }.sorted { $0.start < $1.start } }
    public var snapped: Workout? { efforts.first { $0.start == window.start && $0.end == window.end } }
    public var effortLabel: String {
        if let snapped { return "\(GoopFormat.time(snapped.start)) to \(GoopFormat.time(snapped.end))" }
        if efforts.isEmpty { return "None found" }
        return "\(efforts.count) found"
    }
    public var hint: String {
        let when = day == defaultDate ? "today" : "on \(ActivityTime.weekday(day))"
        if snapped != nil { return "Snapped to an effort ghoops found \(when). Drag a dashed edge to adjust." }
        if efforts.isEmpty { return "ghoops found no untracked effort \(when). Drag a dashed edge, or set the times below." }
        return "Drag a dashed edge, or set the times below."
    }
    public mutating func selectDay(_ date: String, heartRate: HeartRateBody? = nil) {
        guard days.contains(date) else { return }
        day = date; self.heartRate = heartRate; setDefaultWindow()
    }
    public mutating func load(_ heartRate: HeartRateBody) { self.heartRate = heartRate; setDefaultWindow() }
    public mutating func snap(to effort: Workout) { window = ActivityWindow(start: effort.start, end: effort.end) }
    public var upload: ActivityUpload? { sport.map { Self.upload(id: id, sport: $0, window: window) } }
    public mutating func didSave() { id = UUID().uuidString.lowercased() }
    public static func upload(id: String, sport: String, window: ActivityWindow) -> ActivityUpload {
        ActivityUpload(id: id, exerciseType: sport, displayName: ActivitySport.sport(sport).name, start: window.start, end: window.end, origin: "added")
    }
    private mutating func setDefaultWindow() {
        if day != defaultDate, let effort = efforts.last { snap(to: effort); return }
        let cycleStart = heartRate?.start ?? ActivityTime.day(day)
        if day == defaultDate {
            let end = max(cycleStart, ActivityWindow.minute(now))
            window = ActivityWindow(start: max(cycleStart, end.addingTimeInterval(-3600)), end: end)
        } else {
            let c = ActivityTime.calendar
            let start = c.date(bySettingHour: 18, minute: 0, second: 0, of: ActivityTime.day(day))!
            let end = c.date(bySettingHour: 19, minute: 0, second: 0, of: ActivityTime.day(day))!
            let limit = heartRate?.end ?? c.date(byAdding: .day, value: 1, to: ActivityTime.day(day))!
            window = ActivityWindow(start: max(cycleStart, min(start, limit.addingTimeInterval(-bounds.activeMin))), end: max(cycleStart.addingTimeInterval(bounds.activeMin), min(end, limit)))
        }
        window = bounds.clamp(window, pauses: [])
    }
}
