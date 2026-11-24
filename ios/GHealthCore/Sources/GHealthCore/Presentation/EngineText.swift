import Foundation

public enum EngineText {
    public static func penaltyNote(_ constants: ScoreConstants?) -> String {
        let limit = constants.map { ", up to \(GoopFormat.number($0.recovery.penaltyMax, decimals: $0.recovery.penaltyMax.rounded() == $0.recovery.penaltyMax ? 0 : 1)) points each," } ?? ""
        return "Breathing rate and skin temperature only subtract\(limit) when they run above usual."
    }
    public static func calibrationNote(_ calibration: Calibration) -> String {
        "\(calibration.valuesNeeded) nights to start · \(calibration.valuesForFullConfidence) for full confidence"
    }
    public static func calibrationFill(_ calibration: Calibration) -> Double {
        let full = calibration.valuesForFullConfidence
        return full > 0 ? Double(min(calibration.nightsUsed, full)) / Double(full) : 0
    }
    public static func calibrationTick(_ calibration: Calibration) -> Double? {
        let full = calibration.valuesForFullConfidence
        guard full > 0, calibration.valuesNeeded < full else { return nil }
        return Double(calibration.valuesNeeded) / Double(full)
    }
    public static func comparisonNote(_ comparison: Comparison?) -> String {
        let average = comparison.map { "your average over the \($0.windowDays) days before it" } ?? "your recent average"
        return "Arrows compare today with \(average). Green and orange show the usual direction for that measure; they are not medical advice."
    }
    public static func comparisonLegend(_ comparison: Comparison?) -> String { comparisonLegend(windowDays: comparison?.windowDays) }
    public static func comparisonLegend(windowDays: Int?) -> String {
        windowDays.map { "vs. prior \($0) days" } ?? "vs. your average"
    }
    public static func comparisonSpoken(_ windowDays: Int?) -> String {
        windowDays.map { "versus prior \($0) days average" } ?? "versus prior average"
    }
    public static func typicalNote(_ typical: StageTypical?) -> String {
        guard let typical else { return "Typical ranges come from your recent nights with sleep stages." }
        guard let low = typical.lowPercentile, let high = typical.highPercentile, let needed = typical.nightsNeeded else {
            return "Typical ranges come from your last \(typical.windowNights) nights with sleep stages."
        }
        return "Typical ranges are the middle \(high - low)% of your last \(typical.windowNights) nights with sleep stages (shown after \(needed) such nights)."
    }
    public static func uploadedNote(collectorMinutes: Int?) -> String {
        let timing = collectorMinutes.map { ", usually within \($0) minutes" } ?? ""
        return "Live estimate. Final Strain arrives when your band syncs with your Mac\(timing)."
    }
}
