import Foundation

public struct Activity: Codable, Sendable {
    public var steps: Metric
    public var activeZoneMinutes: Metric
    public var caloriesKcal: Metric
    public var distanceKm: Metric
}

public struct VO2Max: Codable, Sendable {
    public var value: Double?
    public var unit: String
    public var date: String?
    public var cardioFitnessLevel: String?
    public var estimated: Bool?
    public var status: MetricStatus
    public var reason: Reason?
}
