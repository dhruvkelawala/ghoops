#if DEBUG
import SwiftUI
import GHealthCore
import WidgetKit

struct WidgetPreviewHost: View {
    @Environment(AppModel.self) private var model
    private var data: WidgetData { WidgetData(cached: model.cached, paired: model.paired, date: model.now) }
    var body: some View {
        if let live = model.livePreview { LiveActivityPreview(preview: live) } else { scores }
    }
    private var scores: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Widgets · \(model.fixtureSet?.rawValue ?? "fresh")").goop(.heading)
                HStack(spacing: 18) {
                    home().frame(width: 170, height: 170)
                    home(metric: .all).frame(width: 170, height: 170)
                }
                home(medium: true).frame(width: 364, height: 170)
                Text("9:41").font(Font(GoopFont.nunito(64, weight: 600))).foregroundStyle(.white.opacity(0.88)).padding(.top, 6) // goop-lint: allow rawfont: simulated Lock Screen clock
                HStack(spacing: 14) {
                    ForEach(GoopScore.allCases, id: \.self) { score in
                        LockScoresView(data: data, family: .accessoryCircular, metric: ScoreMetric(rawValue: score.rawValue.lowercased()) ?? .recovery).frame(width: 76, height: 76).background(.white.opacity(0.12), in: Circle())
                    }
                }
                LockScoresView(data: data, family: .accessoryRectangular).frame(width: 172, height: 76)
                LockScoresView(data: data, family: .accessoryInline).frame(width: 257, height: 26)
                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        home(metric: .hrv).frame(width: 170, height: 170).accessibilityIdentifier("widget-hrv-small")
                    }
                    HStack(spacing: 14) {
                        LockScoresView(data: data, family: .accessoryCircular, metric: .hrv).frame(width: 76, height: 76).background(.white.opacity(0.12), in: Circle()).accessibilityIdentifier("widget-lock-hrv")
                        LockScoresView(data: data, family: .accessoryRectangular, line: .bedtime).frame(width: 172, height: 76).accessibilityElement(children: .contain).accessibilityIdentifier("widget-lock-rect-bedtime")
                    }
                    LockScoresView(data: data, family: .accessoryRectangular, line: .hrv).frame(width: 172, height: 76).accessibilityElement(children: .contain).accessibilityIdentifier("widget-lock-rect-hrv")
                }.accessibilityElement(children: .contain).accessibilityIdentifier("widget-parity")
                Text(GoopFont.check).goop(.bodySmall).accessibilityIdentifier("font-check")
            }.padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 40).frame(maxWidth: .infinity)
        }.background(Goop.Gradient.widgetWallpaper.ignoresSafeArea()).foregroundStyle(.white).dynamicTypeSize(.large).accessibilityIdentifier("widget-preview")
    }
    private func home(medium: Bool = false, metric: ScoreMetric = .recovery) -> some View {
        HomeScoresView(data: data, medium: medium, metric: metric).background(Goop.Color.widgetFill, in: RoundedRectangle(cornerRadius: 22)) // goop-lint: allow radius: simulated system widget corner
    }
}
#endif
