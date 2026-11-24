import Foundation

public enum Format {
    public static func number(_ value: Double?, decimals: Int = 0) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }
    public static func hours(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
    public static func time(_ value: Date?) -> String {
        guard let value else { return "—" }
        let formatter = DateFormatter()
        formatter.timeZone = GoopFormat.london
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: value)
    }
    public static func date(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let value = formatter.date(from: date) else { return date }
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: value)
    }
    public static func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
    public static func band(_ raw: String?) -> String {
        raw?.replacingOccurrences(of: "_", with: " ").capitalized ?? ""
    }
    public static func arrow(_ value: Double?, baseline: Double?) -> String {
        guard let value, let baseline, baseline != 0, abs(value - baseline) / abs(baseline) > 0.05 else { return "" }
        return value > baseline ? " ↑" : " ↓"
    }
}
