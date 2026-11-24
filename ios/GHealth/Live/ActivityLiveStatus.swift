@preconcurrency import ActivityKit
import Foundation
import GHealthCore

@MainActor final class ActivityLiveStatus {
    private var activity: ActivityKit.Activity<GoopActivityAttributes>?
    private var lastState: GoopActivityAttributes.ContentState?
    private var lastStaleDate: Date?
    private var lastUpdate = Date.distantPast

    func update(session: ActivitySession, estimate: LiveEstimate?, now: Date, targetReached: Bool = false) async {
        let state = GoopActivityAttributes.ContentState(session: session, estimate: estimate, now: now)
        let staleDate = session.liveUntil
        if activity == nil {
            activity = ActivityKit.Activity<GoopActivityAttributes>.activities.first { $0.attributes.id == session.id && $0.activityState == .active }
            if activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled {
                activity = try? ActivityKit.Activity.request(attributes: GoopActivityAttributes(session: session), content: ActivityContent(state: state, staleDate: staleDate), pushType: nil)
                lastState = state; lastStaleDate = staleDate; lastUpdate = .now
            }
        }
        guard let activity, targetReached || ((state != lastState || staleDate != lastStaleDate) && Date.now.timeIntervalSince(lastUpdate) >= 2) else { return }
        lastState = state; lastStaleDate = staleDate; lastUpdate = .now
        let alert: AlertConfiguration?
        if targetReached, let projected = state.dayStrain, let low = state.targetLow, let high = state.targetHigh {
            alert = AlertConfiguration(title: "Strain target reached", body: "Your Day Strain estimate is \(GoopFormat.number(projected, decimals: 1)), inside today's target of \(GoopFormat.number(low, decimals: 1)) to \(GoopFormat.number(high, decimals: 1)).", sound: .default)
        } else { alert = nil }
        await activity.update(ActivityContent(state: state, staleDate: staleDate), alertConfiguration: alert)
    }
    func end(session: ActivitySession, estimate: LiveEstimate?, now: Date, saved: Bool) async {
        let current = activity ?? ActivityKit.Activity<GoopActivityAttributes>.activities.first { $0.attributes.id == session.id }
        activity = nil; lastState = nil; lastStaleDate = nil
        guard let current else { return }
        let state = GoopActivityAttributes.ContentState(session: session, estimate: estimate, now: now)
        await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: saved ? .after((session.end ?? now).addingTimeInterval(15 * 60)) : .immediate)
    }
}
