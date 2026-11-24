import Foundation

public enum GoopColorRole: Sendable {
    case positive, caution, neutral, healthOK, recovery, strain, sleep, trendLine, zone2, zone4, stageREM
}

public enum ComparisonDirection: Sendable {
    case up, down, equal

    public func color(for metric: TrendMetricKey) -> GoopColorRole {
        guard self != .equal else { return .neutral }
        switch metric {
        case .respiratoryRate, .skinTemp: return .neutral
        case .restingHR: return self == .up ? .caution : .positive
        default: return self == .up ? .positive : .caution
        }
    }
}

public enum GoopFormat {
    public static let london = TimeZone(identifier: "Europe/London")!
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar
    }

    public static func rounded(_ value: Double, decimals: Int = 0) -> Double {
        let scale = pow(10.0, Double(decimals))
        let result = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        return result == 0 ? 0 : result
    }

    public static func number(_ value: Double?, decimals: Int = 0, grouped: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouped
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: rounded(value, decimals: decimals))) ?? "—"
    }

    public static func percent(_ value: Double?) -> String {
        value.map { number($0) + "%" } ?? "—"
    }

    public static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        return String(format: "%d:%02d", abs(minutes) / 60, abs(minutes) % 60)
    }

    public static func signedDuration(_ minutes: Int, credit: Bool = false) -> String {
        (credit || minutes < 0 ? "−" : "+") + duration(minutes)
    }

    public static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        let result = rounded(value, decimals: 1)
        return (result < 0 ? "−" : "+") + number(abs(result), decimals: 1)
    }

    public static func time(_ value: Date?) -> String {
        guard let value else { return "—" }
        return formatted(value, "HH:mm")
    }

    public static func weekdayShort(_ date: Date) -> String { weekday(date, format: "EEE") }
    public static func weekdayLong(_ date: Date) -> String { weekday(date, format: "EEEE") }

    private static func weekday(_ date: Date, format: String) -> String {
        let formatter = formatter(format)
        formatter.locale = Locale(identifier: "en_GB")
        return formatter.string(from: date)
    }

    public static func dateControl(_ date: String, defaultDate: String) -> String {
        date == defaultDate ? "TODAY" : dateLabel(date, format: "EEE d MMM").uppercased()
    }

    public static func dateLabel(_ date: String, format: String) -> String {
        dateValue(date).map { formatted($0, format) } ?? date
    }

    public static func range(from: String, to: String) -> String {
        "\(dateLabel(from, format: "MMM d")) - \(dateLabel(to, format: "MMM d, yy"))".uppercased()
    }

    public static func direction(_ value: Double?, mean: Double?, metric: TrendMetricKey) -> ComparisonDirection? {
        guard let value, let mean else { return nil }
        let current = rounded(value, decimals: metric.decimals)
        let prior = rounded(mean, decimals: metric.decimals)
        return current > prior ? .up : current < prior ? .down : .equal
    }

    public static func dateKey(_ date: Date) -> String { formatted(date, "yyyy-MM-dd") }

    public static func addingDays(_ count: Int, to date: String) -> String {
        guard let day = dateValue(date), let next = calendar.date(byAdding: .day, value: count, to: day) else { return date }
        return formatted(next, "yyyy-MM-dd")
    }

    public static func dates(from: String, to: String) -> [String] {
        guard from <= to, dateValue(from) != nil, dateValue(to) != nil else { return [] }
        var dates: [String] = []
        var date = from
        while date <= to {
            dates.append(date)
            date = addingDays(1, to: date)
        }
        return dates
    }

    public static func dateValue(_ date: String) -> Date? {
        let formatter = formatter("yyyy-MM-dd")
        guard let value = formatter.date(from: date), formatter.string(from: value) == date else { return nil }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: value)
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        formatter(format).string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = london
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}
