import Foundation

public enum ReasonText {
    public static func score(_ reason: Reason?, status: ScoreStatus, calibration: Calibration? = nil) -> String {
        let pending = status == .pending
        switch reason {
        case .noSleep: return pending ? "Waiting for last night's sleep" : "No sleep recorded"
        case .sleepProcessing: return "Fitbit is still processing your sleep"
        case .noHrv: return pending ? "Waiting for overnight HRV" : "No overnight HRV"
        case .hrvConflict: return "Conflicting HRV values"
        case .noRestingHr: return pending ? "Waiting for resting heart rate" : "No resting heart rate"
        case .rhrConflict: return "Conflicting resting heart rate values"
        case .insufficientBaseline: return calibration.map { "Calibrating: \($0.nightsUsed) of \($0.valuesNeeded) nights" } ?? "Calibrating"
        case .cycleNotStarted: return "Your day starts when you wake"
        case .restingHrUnknown: return "No resting heart rate to measure strain"
        case .maxHrUnknown: return "Set your max heart rate: ghoops config set max_hr_override_bpm N"
        case .noHeartRate: return pending ? "No heart rate yet today" : "No heart rate recorded"
        case .insufficientNights: return "Not enough nights yet"
        case .noData: return "Not available"
        default: return pending ? "Waiting for data" : "Not available"
        }
    }
    public static func metric(_ status: MetricStatus) -> String {
        switch status {
        case .available: "Available"
        case .missing: "No data"
        case .notSynced: "Not collected yet"
        case .unavailable: "Couldn't collect"
        case .permissionMissing: "Needs permission"
        case .conflict: "Conflicting values"
        case .unknown: "Not available"
        }
    }
}
