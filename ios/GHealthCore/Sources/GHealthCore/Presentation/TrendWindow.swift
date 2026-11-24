import Foundation

public struct TrendWindow: Sendable, Equatable {
    public enum Range: String, CaseIterable, Sendable { case week = "W", month = "M", sixMonths = "6M"
        public var length: Int { self == .week ? 7 : self == .month ? 30 : 180 }
    }
    public var range: Range
    public var end: String
    public init(range: Range = .week, end: String) { self.range = range; self.end = end }
    public var start: String { GoopFormat.addingDays(1 - range.length, to: end) }
    public var prior: TrendWindow { TrendWindow(range: range, end: GoopFormat.addingDays(-range.length, to: end)) }
    public func canPrevious(oldestDate: String?) -> Bool { oldestDate.map { prior.end >= $0 } ?? false }
    public func canNext(defaultDate: String) -> Bool { end < defaultDate }
    public func next(defaultDate: String) -> TrendWindow { TrendWindow(range: range, end: min(GoopFormat.addingDays(range.length, to: end), defaultDate)) }
    public func summary(rows: [DayRow], metric: TrendMetricKey) -> (mean: Double?, available: Int) {
        let values = rows.filter { $0.date >= start && $0.date <= end }.compactMap { metric.value($0) }
        guard !values.isEmpty else { return (nil, 0) }
        return (GoopFormat.rounded(values.reduce(0, +) / Double(values.count), decimals: metric.decimals), values.count)
    }
}
