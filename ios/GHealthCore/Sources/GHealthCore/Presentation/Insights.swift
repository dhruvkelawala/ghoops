import Foundation

public enum Insights {
    public static func recovery(_ recovery: Recovery, pending: Bool = false) -> String {
        if pending { return updating("Your Recovery") }
        guard recovery.value != nil else {
            if recovery.reason == .insufficientBaseline {
                return "Recovery is calibrating: \(recovery.calibration.nightsUsed) of \(recovery.calibration.valuesNeeded) nights so far. It starts once ghoops has \(recovery.calibration.valuesNeeded) nights of your HRV and resting heart rate."
            }
            return sentence(ReasonText.score(recovery.reason, status: recovery.status, calibration: recovery.calibration))
        }
        var parts: [String] = []
        if let components = recovery.components {
            let hrv = components.hrvZ >= 0.5 ? 0 : components.hrvZ <= -0.5 ? 2 : 1
            let rhr = components.restingHrZ >= 0.5 ? 0 : components.restingHrZ <= -0.5 ? 2 : 1
            let phrases = [
                ["Your HRV is above baseline while your resting heart rate is higher than usual.", "Your HRV is above baseline and your resting heart rate is near baseline.", "Your HRV is above baseline and your resting heart rate is lower than usual."],
                ["Your HRV is near baseline while your resting heart rate is higher than usual.", "Your HRV and resting heart rate are both near baseline.", "Your HRV is near baseline and your resting heart rate is lower than usual."],
                ["Your HRV is below baseline and your resting heart rate is higher than usual.", "Your HRV is below baseline while your resting heart rate is near baseline.", "Your HRV is below baseline while your resting heart rate is lower than usual."]
            ]
            parts.append(phrases[hrv][rhr])
            if components.respiratoryRatePenalty > 0 { parts.append("A raised breathing rate overnight took \(GoopFormat.number(components.respiratoryRatePenalty, decimals: 1)) points off.") }
            if components.skinTempPenalty > 0 { parts.append("A raised skin temperature overnight took \(GoopFormat.number(components.skinTempPenalty, decimals: 1)) points off.") }
        }
        if let band = recovery.band { parts.append("Recovery is \(band.rawValue) today.") }
        if recovery.calibrating { parts.append("It is still calibrating.") }
        return parts.joined(separator: " ")
    }

    public static func strain(_ strain: Strain, workouts: [Workout], isToday: Bool, target: StrainTarget? = nil, recoveryBand: Band3? = nil, constants: ScoreConstants?, pending: Bool = false) -> String {
        if pending { return updating("Your Day Strain") }
        var parts: [String] = []
        if let target {
            let showPosition = strain.confidence != .low && target.reason != .lowCoverage
            parts.append(targetSentence(target, isToday: isToday, band: recoveryBand, showPosition: showPosition))
        }
        guard strain.value != nil else {
            parts.append(sentence(ReasonText.score(strain.reason, status: strain.status)))
            return parts.filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let edges = constants?.strain.bands {
            let d = GoopFormat.number(edges.moderate, decimals: 1)
            let s = GoopFormat.number(edges.strenuous, decimals: 1)
            let a = GoopFormat.number(edges.allOut, decimals: 1)
            switch strain.band {
            case .light: parts.append("Strain under \(d) is considered light.")
            case .moderate: parts.append("Strain between \(d) and \(GoopFormat.number(edges.strenuous - 0.1, decimals: 1)) is considered moderate.")
            case .strenuous: parts.append("Strain between \(s) and \(GoopFormat.number(edges.allOut - 0.1, decimals: 1)) is considered strenuous.")
            case .allOut: parts.append("Strain of \(a) or more is considered all out.")
            default: break
            }
            if let workout = workouts.filter({ ($0.strain ?? 0) >= edges.moderate }).max(by: { $0.strain! < $1.strain! }) {
                let hour = GoopFormat.calendar.component(.hour, from: workout.start)
                let part = (5...11).contains(hour) ? "morning" : (12...16).contains(hour) ? "afternoon" : (17...21).contains(hour) ? "evening" : "night"
                let name = workout.kind == "detected" || workout.category == "detected" ? "a detected effort" : workout.displayName?.lowercased() ?? "a detected effort"
                parts.append("Your heart worked hardest during \(name) \(isToday ? "this" : "in the") \(part).")
            }
        }
        if let coverage = strain.hrCoverage, let confidence = strain.confidence, confidence != .high { parts.append("This is based on \(GoopFormat.number(coverage * 100))% of the day's heart rate.") }
        if strain.status == .inProgress { parts.append("Strain keeps building until you sleep.") }
        return parts.joined(separator: " ")
    }

    /// The sentence for a score the Mac is recalculating after a sleep edit.
    public static func updating(_ subject: String) -> String {
        "\(subject) will update once your Mac has the change to your sleep."
    }

    /// While a sleep edit waits for the Mac, only the phone's projected hours are shown.
    public static func sleep(_ sleep: Sleep, pending: Bool = false) -> String {
        SleepScore.insight(sleep, pending: pending)
    }

    /// The Trends week view's sentence from the Mac's weekly HRV position (scores.md §5.3), or nil for any other position.
    public static func hrvWeek(position: String?, days: Int) -> String? {
        guard let position, ["within", "below", "above"].contains(position) else { return nil }
        return "Your \(days)-day HRV average is \(position) your usual range."
    }

    public static func trend(metric: TrendMetricKey, length: Int, available: Int, average: Double?, range: ClosedRange<Double>? = nil, week: String? = nil) -> String {
        guard available > 0, let average else { return "No \(metric.summaryName) data in these \(length) days." }
        var text: String
        if let week {
            text = week
        } else if let range {
            let position = average < range.lowerBound ? "below" : average > range.upperBound ? "above" : "within"
            text = "Your average \(metric.summaryName) over these \(length) days was \(position) its typical range (\(metric.display(range.lowerBound)) - \(metric.display(range.upperBound)))."
        } else {
            text = "Your average \(metric.summaryName) over these \(length) days was \(metric.display(average, includeUnit: true))."
        }
        if available < length { text += " \(available) of \(length) days have data." }
        return text
    }

    private static func targetSentence(_ target: StrainTarget, isToday: Bool, band: Band3?, showPosition: Bool) -> String {
        if target.status == .pending { return "Today's target appears when Recovery is ready." }
        if target.status == .unavailable { return "There is no target without a Recovery score." }
        guard target.status == .ok, let low = target.low, let high = target.high, let band else { return "" }
        let intent = target.intent == "restore" ? " on a restore day" : target.intent == "overreach" ? " on an overreach day" : ""
        var text = "\(isToday ? "Today's target is" : "The target was") \(GoopFormat.number(low, decimals: 1)) to \(GoopFormat.number(high, decimals: 1)) for \(band.rawValue) recovery\(intent). The target is ghoops' own rule of thumb, not a published method."
        if showPosition, let position = target.position { text += " \(isToday ? "You are" : "You finished") \(position) it." }
        return text
    }

    static func sentence(_ text: String) -> String { text.hasSuffix(".") ? text : text + "." }
}
