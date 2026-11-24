import Foundation

public struct ActivityContentState: Codable, Hashable, Sendable {
    public var bpm: Int?
    public var zone: Int?
    public var strainEstimate: Double?
    public var avgHR: Int?
    public var pausedTotal: TimeInterval
    public var isPaused: Bool
    public var hrState: String
    public var elapsed: TimeInterval?
    public var dayStrain: Double?
    public var targetLow: Double?
    public var targetHigh: Double?
    public var targetWithin: Bool?

    public func readout(isStale: Bool) -> LiveReadout {
        LiveReadout(bpm: bpm, zone: zone, hr: ActivityHRState(rawValue: hrState) ?? .none, isStale: isStale)
    }

    public init(session: ActivitySession, estimate: LiveEstimate?, now: Date) {
        bpm = session.samples.last.map { Int($0.bpm.rounded()) }
        zone = estimate?.zone
        strainEstimate = estimate?.strain
        avgHR = estimate?.average
        isPaused = session.state == .paused
        pausedTotal = session.pausedTotal(at: isPaused ? session.pauses.last!.start : (session.end ?? now))
        hrState = session.hrState(at: now).rawValue
        elapsed = session.state == .running ? nil : session.elapsed(at: now)
        if let target = session.target {
            dayStrain = target.projected(liveTrimp: estimate?.trimp, scale: estimate?.scale)
            targetLow = target.low
            targetHigh = target.high
            targetWithin = dayStrain.map { target.low <= $0 && $0 <= target.high }
        }
    }
}
