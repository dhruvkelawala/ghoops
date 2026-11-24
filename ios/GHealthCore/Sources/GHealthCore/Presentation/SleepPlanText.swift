import Foundation

/// Numbers and captions for the TONIGHT section of the Sleep info sheet.
public enum SleepPlanText {
    public static func unavailable(_ plan: SleepPlan) -> String {
        guard let needed = plan.nightsNeeded, let window = plan.windowNights else { return "Tonight's plan needs more nights of sleep." }
        return "Tonight's plan needs at least \(needed) nights of sleep from the last \(window)."
    }
    public static func placeholder(_ plan: SleepPlan) -> String {
        plan.nightsNeeded.map { "Needs \($0) nights of sleep to plan tonight." } ?? "Needs more nights of sleep to plan tonight."
    }

    /// Sleep the goal asks for: need × goal, to the nearest minute.
    public static func asleepMinutes(_ plan: SleepPlan, goal: SleepGoal) -> Int {
        Int((Double(plan.needMinutes) * Double(goal.pct) / 100).rounded())
    }

    /// The rest of the goal's time in bed: falling asleep and the usual time awake.
    public static func awakeMinutes(_ plan: SleepPlan, goal: SleepGoal) -> Int {
        goal.inBedMinutes - asleepMinutes(plan, goal: goal)
    }

    /// Where the time awake comes from, for example "92.5% efficiency · 6 min to fall asleep".
    public static func awakeNote(_ plan: SleepPlan) -> String? {
        guard let efficiency = plan.efficiencyPctUsed else { return nil }
        let eff = GoopFormat.number(efficiency, decimals: efficiency.rounded() == efficiency ? 0 : 1) + "% efficiency"
        guard let latency = plan.latencyMinutesUsed, latency > 0 else { return eff }
        return eff + " · \(latency) min to fall asleep"
    }

    public static func wakeLabel(_ plan: SleepPlan) -> String {
        plan.wakeSource == "config" ? "WAKE · SET ON MAC" : "WAKE · TYPICAL"
    }

    public static func footnote(_ plan: SleepPlan) -> String {
        let source = "Usual values come from your last \(plan.nightsUsed) nights."
        return plan.wakeSource == "config"
            ? source + " The wake time is set on your Mac with ghoops config."
            : source + " Set a fixed wake time on your Mac with ghoops config."
    }

    public static func goalAccessibility(_ goal: SleepGoal) -> String {
        "\(goal.pct) percent of need: \(goal.inBedMinutes / 60) hours \(goal.inBedMinutes % 60) minutes in bed, bed by \(GoopFormat.time(goal.bedtime))"
    }
}

/// One line of an explanation breakdown: a part, where it comes from, and what it adds.
public struct BreakdownLine: Sendable, Equatable {
    public var id: String
    public var label: String
    public var note: String?
    public var value: String
}

/// The Recovery info sheet's breakdown: each input's points, adding up to the score.
public enum RecoveryExplain {
    /// HRV, resting heart rate and sleep, each as weighted points.
    public static func base(_ recovery: Recovery) -> [BreakdownLine] {
        let c = recovery.components, inputs = recovery.inputs, baseline = recovery.baseline
        let weights = c?.weights
        var rows = [
            line("recovery-hrv", "HRV", value: inputs.hrvRmssdMs, metric: .hrv, usual: baseline.hrv.meanMs, weight: weights?.hrv, score: c?.hrvScore),
            line("recovery-resting-hr", "Resting heart rate", value: inputs.restingHrBpm.map(Double.init), metric: .restingHR, usual: baseline.restingHr.mean, weight: weights?.restingHr, score: c?.restingHrScore),
            line("recovery-sleep", "Sleep performance", value: inputs.sleepPerformance.map(Double.init), metric: .sleepPerformance, usual: nil, weight: weights?.sleep, score: c.map { Double($0.sleepScore) })
        ]
        if let c, weights == nil {
            rows.append(BreakdownLine(id: "recovery-inputs", label: "HRV, resting HR and sleep", note: "Update ghoops on your Mac to see each part", value: "+" + GoopFormat.number(c.weightedBase, decimals: 1)))
        }
        return rows
    }

    /// Breathing rate and skin temperature, which only subtract.
    public static func penalties(_ recovery: Recovery) -> [BreakdownLine] {
        let c = recovery.components, inputs = recovery.inputs
        let breathing = inputs.respiratoryRateBpm.map { value in
            TrendMetricKey.respiratoryRate.display(value, includeUnit: true) + (recovery.baseline.respiratoryRate.mean.map { " · usual " + TrendMetricKey.respiratoryRate.display($0) } ?? "")
        }
        let skin = inputs.skinTempDeviationC.map { TrendMetricKey.skinTemp.display($0, includeUnit: true) + " from usual" }
        return [
            BreakdownLine(id: "recovery-breathing", label: "Breathing rate", note: breathing ?? "Not available", value: penalty(c?.respiratoryRatePenalty, recorded: c != nil)),
            BreakdownLine(id: "recovery-skin", label: "Skin temperature", note: skin ?? "Not available", value: penalty(c?.skinTempPenalty, recorded: c != nil))
        ]
    }

    private static func line(_ id: String, _ label: String, value: Double?, metric: TrendMetricKey, usual: Double?, weight: Double?, score: Double?) -> BreakdownLine {
        let measured = value.map { metric.display($0, includeUnit: true) } ?? "Not available"
        let usualText = usual.map { " · usual " + metric.display($0) } ?? ""
        let points: String
        if let weight, let score { points = "+" + GoopFormat.number(score * weight, decimals: 1) }
        else { points = "—" }
        let weightText = weight.map { " · \(Int(($0 * 100).rounded()))% weight" } ?? ""
        return BreakdownLine(id: id, label: label, note: measured + usualText + weightText, value: points)
    }

    private static func penalty(_ points: Double?, recorded: Bool) -> String {
        guard recorded, let points else { return "—" }
        return points > 0 ? "−" + GoopFormat.number(points, decimals: 1) : "0.0"
    }
}

/// Labels for the Day Strain info sheet.
public enum StrainExplain {
    public static func startLabel(_ cycle: Cycle) -> String {
        cycle.startSource == "typical_wake_fallback" ? "TYPICAL WAKE" : "WOKE"
    }

    public static func maxSource(_ source: String?) -> String {
        switch source {
        case "override": "MAX · YOUR SETTING"
        case "age_predicted_profile": "MAX · AGE-BASED"
        case "fitbit_zone_peak": "MAX · FITBIT ZONES"
        case "observed": "MAX · HIGHEST SEEN"
        default: "MAX"
        }
    }

    public static func restingSource(_ source: String?) -> String {
        switch source {
        case "baseline_mean": "RESTING · BASELINE"
        case "daily_resting_heart_rate": "RESTING · DAILY"
        default: "RESTING"
        }
    }
}
