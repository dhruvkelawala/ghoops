import Foundation

public enum TrendMetricKey: String, CaseIterable, Sendable, Identifiable {
    case recovery, hrv, restingHR = "resting_hr", respiratoryRate = "respiratory_rate"
    case strain, zones13 = "zones_1_3", zones45 = "zones_4_5", strength, steps
    case sleepPerformance = "sleep_performance", hours, restorative, consistency, efficiency
    case spo2, skinTemp = "skin_temp"

    public var id: String { rawValue }
    public enum Group: String, CaseIterable, Sendable { case recovery = "Recovery", strain = "Strain", sleep = "Sleep", health = "Health" }
    public enum ChartKind: Sendable { case line, bars }

    public var name: String {
        switch self {
        case .recovery: "Recovery"
        case .hrv: "Heart Rate Variability"
        case .restingHR: "Resting Heart Rate"
        case .respiratoryRate: "Respiratory Rate"
        case .strain: "Day Strain"
        case .zones13: "Heart Rate Zones 1-3" // goop-lint: allow enginenumber: zone names
        case .zones45: "Heart Rate Zones 4-5" // goop-lint: allow enginenumber: zone names
        case .strength: "Strength Activity Time"
        case .steps: "Steps"
        case .sleepPerformance: "Sleep Performance"
        case .hours: "Hours of Sleep"
        case .restorative: "Restorative Sleep"
        case .consistency: "Sleep Consistency"
        case .efficiency: "Sleep Efficiency"
        case .spo2: "Blood Oxygen"
        case .skinTemp: "Skin Temp"
        }
    }
    public var summaryName: String { self == .hrv ? "HRV" : name.lowercased() }
    public var group: Group {
        switch self {
        case .recovery, .hrv, .restingHR, .respiratoryRate: .recovery
        case .strain, .zones13, .zones45, .strength, .steps: .strain
        case .sleepPerformance, .hours, .restorative, .consistency, .efficiency: .sleep
        case .spo2, .skinTemp: .health
        }
    }
    public var chart: ChartKind {
        switch self {
        case .hrv, .restingHR, .respiratoryRate, .consistency, .efficiency, .spo2, .skinTemp: .line
        default: .bars
        }
    }
    public var color: GoopColorRole {
        guard chart == .bars else { return .trendLine }
        switch self {
        case .recovery: return .recovery
        case .zones13: return .zone2
        case .zones45: return .zone4
        case .sleepPerformance, .hours: return .sleep
        case .restorative: return .stageREM
        default: return .strain
        }
    }
    public var unit: String {
        switch self {
        case .recovery, .sleepPerformance, .consistency, .efficiency, .spo2: "%"
        case .hrv: "ms"
        case .restingHR: "bpm"
        case .respiratoryRate: "rpm"
        case .skinTemp: "°C"
        default: ""
        }
    }
    public var isDuration: Bool { [.zones13, .zones45, .strength, .hours, .restorative].contains(self) }
    public var decimals: Int { [.strain, .respiratoryRate, .skinTemp].contains(self) ? 1 : 0 }
    public var icon: String {
        switch self {
        case .recovery: "bolt.heart"
        case .hrv: "waveform.path.ecg"
        case .respiratoryRate: "lungs"
        case .strain: "flame"
        case .zones13: "gauge.with.dots.needle.33percent"
        case .zones45: "gauge.with.dots.needle.67percent"
        case .strength: "dumbbell"
        case .steps: "shoe.2"
        case .sleepPerformance: "moon"
        case .hours: "bed.double"
        case .restorative: "moon.zzz"
        case .consistency: "clock"
        case .efficiency: "chart.bar"
        case .spo2: "drop"
        case .skinTemp: "thermometer.medium"
        default: "heart"
        }
    }
    public var comparisonKey: String {
        switch self {
        case .hrv: "hrv_rmssd_ms"
        case .restingHR: "resting_hr_bpm"
        case .respiratoryRate: "respiratory_rate_bpm"
        case .hours: "asleep_minutes"
        case .restorative: "restorative_minutes"
        case .efficiency: "efficiency_pct"
        case .consistency: "sleep_consistency"
        case .zones13: "zones_1_3_minutes"
        case .zones45: "zones_4_5_minutes"
        case .strength: "strength_minutes"
        case .spo2: "spo2_pct"
        case .skinTemp: "skin_temp_deviation_c"
        default: rawValue
        }
    }
    public func value(_ row: DayRow) -> Double? {
        switch self {
        case .recovery: row.recovery.map(Double.init)
        case .hrv: row.hrvRmssdMs
        case .restingHR: row.restingHrBpm.map(Double.init)
        case .respiratoryRate: row.respiratoryRateBpm
        case .strain: row.strain
        case .zones13: row.zones13Minutes.map(Double.init)
        case .zones45: row.zones45Minutes.map(Double.init)
        case .strength: row.strengthMinutes.map(Double.init)
        case .steps: row.steps.map(Double.init)
        case .sleepPerformance: row.sleepPerformance.map(Double.init)
        case .hours: row.asleepMinutes.map(Double.init)
        case .restorative: row.restorativeMinutes.map(Double.init)
        case .consistency: row.sleepConsistency.map(Double.init)
        case .efficiency: row.efficiencyPct.map(Double.init)
        case .spo2: row.spo2Pct
        case .skinTemp: row.skinTempDeviationC
        }
    }
    public func display(_ value: Double?, includeUnit: Bool = false) -> String {
        guard let value else { return "—" }
        if isDuration { return GoopFormat.duration(Int(GoopFormat.rounded(value))) }
        let number = self == .skinTemp ? GoopFormat.temperature(value) : GoopFormat.number(value, decimals: decimals, grouped: self == .steps)
        if unit == "%" { return number + "%" }
        return includeUnit && !unit.isEmpty ? number + " " + unit : number
    }
    public func vital(in vitals: Vitals) -> VitalMetric? {
        switch self {
        case .hrv: vitals.metrics.hrvRmssd
        case .restingHR: vitals.metrics.restingHr
        case .respiratoryRate: vitals.metrics.respiratoryRate
        case .spo2: vitals.metrics.spo2
        case .skinTemp: vitals.metrics.skinTempDeviation
        default: nil
        }
    }
}
