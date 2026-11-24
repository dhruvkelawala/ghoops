#if DEBUG
import SwiftUI
import GHealthCore

struct LiveActivityPreview: View {
    private let attributes: GoopActivityAttributes
    private let state: GoopActivityAttributes.ContentState
    private let isStale: Bool
    init(preview: LivePreview) {
        let content = preview.make(now: .now)
        attributes = GoopActivityAttributes(session: content.session)
        state = content.state
        isStale = content.isStale
    }
    var body: some View {
        let readout = state.readout(isStale: isStale)
        ScrollView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Text("Thursday 12 November").font(Font(GoopFont.nunito(19, weight: 600))).foregroundStyle(.white.opacity(0.82)) // goop-lint: allow rawfont: simulated Lock Screen clock
                    Text("18:28").font(Font(GoopFont.nunito(92, weight: 600))).foregroundStyle(.white.opacity(0.91)) // goop-lint: allow rawfont: simulated Lock Screen clock
                    Spacer()
                    GoopLiveActivityView(attributes: attributes, state: state, isStale: isStale)
                        .background(Goop.Color.liveActivityFill.opacity(0.93), in: RoundedRectangle(cornerRadius: Goop.Metric.radiusLiveActivity))
                        .overlay { RoundedRectangle(cornerRadius: Goop.Metric.radiusLiveActivity).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
                        .padding(.horizontal, 14).padding(.bottom, 86)
                }.padding(.top, 4).frame(height: geometry.size.height)
            }.frame(height: 760)
            VStack(spacing: 16) {
                Text("DYNAMIC ISLAND").goop(.labelCard)
                HStack {
                    GoopIslandLeading(readout: readout)
                    Spacer()
                    GoopActivityTimer(attributes: attributes, state: state).goop(.valueLock).frame(width: 58)
                }.padding(16).background(.black, in: Capsule())
                GoopIslandMinimal(readout: readout).padding(14).background(.black, in: Circle())
                GoopLiveActivityView(attributes: attributes, state: state, showZone: false, isStale: isStale, identifier: "live-island-expanded").background(.black, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusLiveActivity))
            }.padding(16).padding(.top, 32).accessibilityElement(children: .contain).accessibilityIdentifier("live-island-preview")
        }.background(LinearGradient(colors: [Color(goopHex: 0x3B4A58), Color(goopHex: 0x1F2830), Color(goopHex: 0x2B2333)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()) // goop-lint: allow hex: simulated Lock Screen wallpaper
            .foregroundStyle(.white).dynamicTypeSize(.large).accessibilityIdentifier("live-widget-preview")
    }
}
#endif
