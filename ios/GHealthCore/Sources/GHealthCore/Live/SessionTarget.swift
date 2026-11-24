import Foundation

public enum TargetCrossing: String, Codable, Sendable {
    case unknown, armed, inactive, fired
}

public struct SessionTarget: Codable, Sendable {
    public let cycleDate: String
    public let baseTrimp: Double?
    public let low: Double
    public let high: Double
    public private(set) var crossing: TargetCrossing = .unknown

    public static func make(day: Day, sessionStart: Date) -> SessionTarget? {
        guard day.isCurrentCycle, day.cycle.start <= sessionStart,
              let target = day.strainTarget, target.status == .ok,
              let low = target.low, let high = target.high else { return nil }
        return SessionTarget(cycleDate: day.date,
                             baseTrimp: day.strain.trimp ?? (day.strain.reason == .noHeartRate ? 0 : nil),
                             low: low, high: high)
    }

    public func projected(liveTrimp: Double?, scale: StrainScale?) -> Double? {
        guard let baseTrimp, let liveTrimp, let scale else { return nil }
        return StrainMath.strain(trimp: baseTrimp + liveTrimp, scale: scale)
    }

    public mutating func update(projected: Double?) -> Bool {
        guard let projected else { return false }
        switch crossing {
        case .unknown:
            crossing = projected < low ? .armed : .inactive
        case .armed where projected >= low:
            crossing = projected <= high ? .fired : .inactive
            return crossing == .fired
        default: break
        }
        return false
    }
}
