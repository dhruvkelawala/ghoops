import Foundation

public struct StrainTarget: Codable, Sendable {
    public var low: Double?
    public var high: Double?
    public var intent: String
    public var position: String?
    public var status: ScoreStatus
    public var reason: Reason?
}
