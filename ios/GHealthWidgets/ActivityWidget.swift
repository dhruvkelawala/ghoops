import ActivityKit
import SwiftUI
import WidgetKit

struct GoopActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoopActivityAttributes.self) { context in
            GoopLiveActivityView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .background(Goop.Color.liveActivityFill.opacity(0.93))
                .overlay { RoundedRectangle(cornerRadius: Goop.Metric.radiusLiveActivity).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
                .activityBackgroundTint(Goop.Color.liveActivityFill.opacity(0.93))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "ghealth://activity"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    GoopLiveActivityView(attributes: context.attributes, state: context.state, showZone: false, isStale: context.isStale, identifier: "live-island-expanded")
                }
            } compactLeading: {
                GoopIslandLeading(readout: context.state.readout(isStale: context.isStale))
            } compactTrailing: {
                GoopActivityTimer(attributes: context.attributes, state: context.state).goop(.valueLock).frame(width: 58)
            } minimal: {
                GoopIslandMinimal(readout: context.state.readout(isStale: context.isStale))
            }.keylineTint(Goop.Color.strain).widgetURL(URL(string: "ghealth://activity"))
        }
    }
}
