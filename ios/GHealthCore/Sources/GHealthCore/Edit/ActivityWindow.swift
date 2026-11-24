import Foundation

public struct ActivityWindow: Sendable, Equatable, Codable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
    public var interval: DateInterval { DateInterval(start: start, end: end) }
    public mutating func moveStart(to value: Date, bounds: EditBounds, pauses: [ActivityPause] = []) {
        start = min(bounds.latestStart(end: end), max(bounds.span.start, Self.minute(value)))
        if let activeMax = bounds.activeMax {
            while activeSeconds(pauses: pauses) > activeMax && start < bounds.latestStart(end: end) { start = start.addingTimeInterval(60) }
        }
        while activeSeconds(pauses: pauses) < bounds.activeMin && start > bounds.span.start { start = max(bounds.span.start, start.addingTimeInterval(-60)) }
    }
    public mutating func moveEnd(to value: Date, bounds: EditBounds, pauses: [ActivityPause] = []) {
        end = max(bounds.earliestEnd(start: start), min(bounds.span.end, Self.minute(value)))
        if let activeMax = bounds.activeMax {
            while activeSeconds(pauses: pauses) > activeMax && end > bounds.earliestEnd(start: start) { end = end.addingTimeInterval(-60) }
        }
        while activeSeconds(pauses: pauses) < bounds.activeMin && end < bounds.span.end { end = min(bounds.span.end, end.addingTimeInterval(60)) }
    }
    public static func minute(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60) }
    public static func ceilMinute(_ date: Date) -> Date { Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / 60) * 60) }
    func activeSeconds(pauses: [ActivityPause]) -> TimeInterval {
        end.timeIntervalSince(start) - pauses.reduce(0) { total, pause in
            total + max(0, min(end, pause.end ?? end).timeIntervalSince(max(start, pause.start)))
        }
    }
}

public enum ActivityTime {
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }
    public static func dateLabels(_ window: ActivityWindow) -> (start: String, end: String)? {
        let start = GoopFormat.dateKey(window.start), end = GoopFormat.dateKey(window.end)
        guard start != end else { return nil }
        return (GoopFormat.dateLabel(start, format: "EEE d MMM"), GoopFormat.dateLabel(end, format: "EEE d MMM"))
    }
    public static func spokenDate(_ date: Date) -> String {
        GoopFormat.dateLabel(GoopFormat.dateKey(date), format: "EEEE d MMMM")
    }
    public static func picker(_ value: Date, within span: DateInterval) -> Date {
        let c = calendar
        let parts = c.dateComponents([.hour, .minute], from: value)
        let first = c.startOfDay(for: span.start)
        let candidates = (-1...2).compactMap { offset -> Date? in
            guard let day = c.date(byAdding: .day, value: offset, to: first) else { return nil }
            return c.date(bySettingHour: parts.hour!, minute: parts.minute!, second: 0, of: day)
        }
        if let match = candidates.first(where: { $0 >= span.start && $0 <= span.end }) { return match }
        let closest = candidates.min { a, b in
            min(abs(a.timeIntervalSince(span.start)), abs(a.timeIntervalSince(span.end))) < min(abs(b.timeIntervalSince(span.start)), abs(b.timeIntervalSince(span.end)))
        } ?? value
        return abs(closest.timeIntervalSince(span.start)) <= abs(closest.timeIntervalSince(span.end)) ? span.start : span.end
    }
    public static func day(_ key: String) -> Date { calendar.startOfDay(for: GoopFormat.dateValue(key)!) }
    public static func addingDays(_ count: Int, to key: String) -> String { GoopFormat.dateKey(calendar.date(byAdding: .day, value: count, to: day(key))!) }
    public static func weekday(_ key: String, short: Bool = false) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_GB"); formatter.timeZone = calendar.timeZone
        formatter.dateFormat = short ? "EEE" : "EEEE"
        return formatter.string(from: day(key))
    }
}
