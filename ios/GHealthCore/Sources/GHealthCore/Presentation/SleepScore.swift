import Foundation

public struct SleepScore: Sendable {
    public let performance: Performance
    private let composite: SleepComposite?

    public var isComposite: Bool { composite != nil }
    public var comparisonKey: String { Self.comparisonKey(composite: isComposite) }

    public init(_ day: Day, composite: Bool) {
        self.init(day.sleep.performance, composite: day.sleep.performanceComposite, config: day.scoreConfig, enabled: composite)
    }

    public init(_ sleep: Sleep, composite: Bool) {
        self.init(sleep.performance, composite: sleep.performanceComposite, config: sleep.scoreConfig, enabled: composite)
    }

    public static func rowValue(_ row: DayRow, composite: Bool) -> Double? {
        (composite ? row.sleepPerformanceComposite : row.sleepPerformance).map(Double.init)
    }

    public static func comparisonKey(composite: Bool) -> String {
        composite ? "sleep_performance_composite" : TrendMetricKey.sleepPerformance.rawValue
    }

    public static func insight(_ sleep: Sleep, composite: Bool, pending: Bool = false) -> String {
        if pending {
            let hours = sleep.asleepMinutes.map { " You slept \(GoopFormat.duration($0))." } ?? ""
            return Insights.updating("Your Sleep Performance") + hours
        }
        let score = SleepScore(sleep, composite: composite)
        let performance = score.performance
        let need = GoopFormat.duration(sleep.need.totalMinutes)
        guard let asleep = sleep.asleepMinutes, let level = SleepLevel(performance.band) else {
            let reason = ReasonText.score(performance.reason, status: performance.status)
            return Insights.sentence(reason) + " Tonight's need so far is \(need)."
        }
        var text = "Your Sleep Performance is \(level.rawValue.lowercased()). "
        let short = sleep.need.totalMinutes - asleep
        if SleepLevel(sleep.performance.band) == .optimal || short <= 0 {
            text += "You got \(GoopFormat.duration(asleep)) of the \(need) you needed."
        } else {
            text += "You were \(GoopFormat.duration(short)) short of the \(need) you needed."
        }
        if score.isComposite {
            switch (sleep.consistency.band == .low, sleep.efficiencyBand == .low) {
            case (true, true): text += " Irregular bed and wake times and time awake in bed lowered it."
            case (true, false): text += " Irregular bed and wake times lowered it."
            case (false, true): text += " Time awake in bed lowered it."
            case (false, false): break
            }
        }
        if sleep.need.debtExtraMinutes > 0 { text += " Recent short nights added \(GoopFormat.duration(sleep.need.debtExtraMinutes)) to your need." }
        if sleep.need.strainExtraMinutes > 0 { text += " Yesterday's strain added \(GoopFormat.duration(sleep.need.strainExtraMinutes))." }
        return text
    }

    public struct Breakdown: Sendable {
        public struct Line: Sendable {
            public let label: String
            public let note: String?
            public let value: String
        }

        public let lines: [Line]
        public let total: String
        public let rule: String?
    }

    public static func breakdown(_ sleep: Sleep, composite: Bool, pending: Bool = false) -> Breakdown? {
        guard let night = SleepScore(sleep, composite: composite).composite else { return nil }
        let constants = sleep.scoreConstants?.sleep.composite
        let parts = pending ? nil : night.parts
        let weights = pending || constants == nil ? nil : night.weights
        let lines = [
            Self.line("Hours vs. needed", part: parts.map { Double($0.sufficiency) }, weight: weights?.sufficiency),
            Self.line("Consistency", part: parts?.consistency.map(Double.init), weight: weights?.consistency),
            Self.line("Efficiency", part: parts?.efficiency, weight: weights?.efficiency, percent: sleep.efficiencyPct)
        ]
        let total = GoopFormat.percent(pending ? nil : night.value.map(Double.init))
        let rule = constants.map {
            "Efficiency scores nothing at \($0.efficiencyZeroPct)% and full marks from \($0.efficiencyFullPct)%. The total is rounded to a whole percent."
        }
        return Breakdown(lines: lines, total: total, rule: rule)
    }

    private init(_ sufficiency: Performance, composite: SleepComposite?, config: ScoreConfig?, enabled: Bool) {
        self.composite = enabled && config?.sleepScoreMode == "composite" ? composite : nil
        performance = self.composite.map { Performance(value: $0.value, band: $0.band, status: $0.status, reason: $0.reason) } ?? sufficiency
    }

    private static func line(_ label: String, part: Double?, weight: Double?, percent: Int? = nil) -> Breakdown.Line {
        guard let weight else { return Breakdown.Line(label: label, note: nil, value: "—") }
        guard let part else {
            return Breakdown.Line(label: label, note: "Not available · share moved to hours", value: "—")
        }
        let input: String
        if let percent {
            let score = GoopFormat.number(part, decimals: part == part.rounded() ? 0 : 1)
            input = "\(percent)% · scores \(score)"
        } else {
            input = GoopFormat.percent(part)
        }
        return Breakdown.Line(label: label, note: "\(input) · \(GoopFormat.percent(weight * 100)) weight", value: "+\(GoopFormat.number(weight * part, decimals: 1))")
    }
}
