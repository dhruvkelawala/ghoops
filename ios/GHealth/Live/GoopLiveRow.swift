import SwiftUI
import GHealthCore

struct GoopLiveRow: View {
    var activity: ActivityController
    var body: some View {
        if let session = activity.session {
            let readout = LiveReadout(session: session, estimate: activity.estimate, now: activity.now)
            Button { activity.livePresented = true } label: {
                HStack(spacing: 0) {
                    GoopValueBlock(symbol: ActivitySport.sport(session.exerciseType).symbol, value: GoopFormat.number(activity.estimate?.strain, decimals: 1), fill: Goop.Color.strain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.displayName.uppercased()).goop(.labelActivity)
                        HStack(spacing: 6) {
                            Circle().fill(Goop.Color.zone5).frame(width: 7, height: 7)
                            Text(session.state == .paused ? "PAUSED ·" : "LIVE ·").goop(.labelStat)
                            Text(activity.elapsed).goop(.axisTime)
                        }.foregroundStyle(Goop.Color.strainPale)
                    }.padding(.leading, 17)
                    Spacer(minLength: 4)
                    VStack(spacing: 0) {
                        Text(readout.value).goop(.valueLiveRow).foregroundStyle(readout.valueColor)
                        if readout.showsUnit { Text("BPM").goop(.unitSmall).foregroundStyle(Goop.Color.iconMuted) }
                    }.opacity(readout.opacity).padding(.horizontal, 8)
                }.padding(.horizontal, 9).frame(minHeight: 58)
                    .background(LinearGradient(colors: [Goop.Color.strainDeep, Goop.Color.activityRow, Goop.Color.activityRow], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: Goop.Metric.radiusActivities))
                    .overlay { RoundedRectangle(cornerRadius: Goop.Metric.radiusActivities).strokeBorder(Goop.Color.strain, lineWidth: 1.5) }
            }.buttonStyle(.plain).accessibilityIdentifier("activity-live-row").accessibilityLabel("\(session.displayName), \(session.state == .paused ? "paused" : "live"), \(activity.elapsed), \(readout.spoken)")
        }
    }
}
