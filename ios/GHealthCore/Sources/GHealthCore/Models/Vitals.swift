import Foundation

public struct Vitals: Codable, Sendable {
    public var metrics: VitalMetrics
    @DefaultEmpty public var outsideRange: [String]
    @DefaultEmpty public var adverse: [String]
    @DefaultEmpty public var persistent: [String]
    public var metricsWithRange: Int
    public var valuesNeeded: Int?
    public var monitorState: String?
    /// scores.md §5.3. Nil from a Mac built before 2026-11-22.
    public var hrvTrend: HRVTrend?

    public func inAttention(_ key: String) -> Bool { monitorState == "attention" && persistent.contains(key) }
}

/// The 7-day ln RMSSD mean against the range built before the week (contract §5.6): a VitalMetric plus `nights`.
public struct HRVTrend: Codable, Sendable {
    public var value: Double?
    public var unit: String
    public var status: MetricStatus
    public var rangeLow: Double?
    public var rangeHigh: Double?
    public var baselineValues: Int?
    public var position: String?
    public var nights: Int

    public var metric: VitalMetric { VitalMetric(value: value, unit: unit, status: status, rangeLow: rangeLow, rangeHigh: rangeHigh, baselineValues: baselineValues, position: position) }
}

public struct VitalMetrics: Codable, Sendable {
    public var hrvRmssd: VitalMetric
    public var restingHr: VitalMetric
    public var respiratoryRate: VitalMetric
    public var spo2: VitalMetric
    public var skinTempDeviation: VitalMetric
}

public struct VitalMetric: Codable, Sendable {
    public var value: Double?
    public var unit: String
    public var status: MetricStatus
    public var rangeLow: Double?
    public var rangeHigh: Double?
    public var baselineValues: Int?
    public var position: String?
}
