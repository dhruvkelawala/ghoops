#if DEBUG
import Foundation

public enum LivePreview: String, CaseIterable, Sendable {
    case live, liveTarget = "live_target", liveNoZone = "live_no_zone", liveNoHeartRate = "live_no_hr", liveLost = "live_stale", livePaused = "live_paused"

    public func make(now: Date) -> (session: ActivitySession, state: ActivityContentState, isStale: Bool) {
        var session = ActivitySession(sport: .all[0], now: now.addingTimeInterval(self == .livePaused ? -760 : -1394))
        if self == .livePaused { session.pause(at: now) }
        if self != .liveNoHeartRate {
            session.append(.init(t: self == .liveLost ? now.addingTimeInterval(-26) : now, bpm: self == .liveLost ? 159 : 158))
        }
        var state = ActivityContentState(session: session, estimate: nil, now: now)
        state.zone = self == .liveNoZone || self == .liveNoHeartRate ? nil : 4
        state.strainEstimate = self == .liveNoZone || self == .liveNoHeartRate ? nil : self == .livePaused ? 5.6 : 7.9
        state.avgHR = self == .liveNoHeartRate ? nil : self == .livePaused ? 145 : 146
        if self == .liveTarget {
            state.bpm = 161; state.strainEstimate = 10.8; state.avgHR = 152
            state.dayStrain = 12.0; state.targetLow = 11.6; state.targetHigh = 14.6
            state.targetWithin = true; state.elapsed = 48 * 60 + 10
        }
        return (session, state, self == .liveLost)
    }
}
#endif
