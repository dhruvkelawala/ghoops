import SwiftUI
import GHealthCore

struct LiveActivityScreen: View {
    @Environment(AppModel.self) private var model
    private var activity: ActivityController { model.activity }
    var body: some View {
        ScrollView {
            if let session = activity.session {
                let readout = LiveReadout(session: session, estimate: activity.estimate, now: activity.now)
                let caption = session.state == .paused ? "Paused" : activity.estimator.isAvailable ? "Activity Strain" : "Strain needs your Mac"
                VStack(spacing: 0) {
                    navigation(session, readout: readout)
                    Text(activity.elapsed).monospacedDigit().goop(.valueTimer).padding(.top, 4).accessibilityIdentifier("activity-timer")
                    ZStack {
                        ScoreRing(value: activity.estimate?.strain, maximum: 21, color: Goop.Color.strain, variant: .detail, diameter: 232, strokeWidth: 15, fixture: model.isFixture)
                        VStack(spacing: 0) {
                            GoopWordmark(size: 24, color: Goop.Color.chevronDial).frame(width: 60, height: 60 / 3.75).padding(.bottom, 8)
                            Text(GoopFormat.number(activity.estimate?.strain, decimals: 1)).goop(.scoreLive)
                                .foregroundStyle(activity.estimate?.strain == nil ? Goop.Color.text2 : Goop.Color.text1)
                                .accessibilityIdentifier("activity-strain")
                            Text(caption.uppercased()).goop(.labelRing).multilineTextAlignment(.center).padding(.top, 10).frame(maxWidth: 194)
                                .accessibilityLabel(caption).accessibilityIdentifier("activity-ring-caption")
                        }
                    }.padding(.top, 6)
                    if let target = session.target {
                        LiveTargetRow(projected: target.projected(liveTrimp: activity.estimate?.trimp, scale: activity.estimate?.scale), low: target.low, high: target.high)
                            .padding(.horizontal, 16).padding(.top, 14)
                    }
                    heartCard(session, readout: readout).padding(.horizontal, 16).padding(.top, 22)
                    HStack(spacing: 12) {
                        Button { Task { await activity.togglePause() } } label: { GoopSymbol(name: session.state == .paused ? "play.fill" : "pause.fill", size: 18, color: .white).frame(width: 64, height: 58).background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusButton)) }.accessibilityIdentifier("activity-pause").accessibilityLabel(session.state == .paused ? "Resume" : "Pause")
                        HoldToEnd(highlighted: activity.highlightEnd) { Task { await activity.finish() } }
                    }.padding(.horizontal, 16).padding(.top, 18)
                    if let error = activity.error { Text(error).goop(.bodyMid).foregroundStyle(Goop.Color.caution).padding(16) }
                    Color.clear.frame(height: 34)
                }
            }
        }.background(Goop.Gradient.detailBackground.ignoresSafeArea()).foregroundStyle(.white).buttonStyle(.plain).accessibilityIdentifier("activity-live-screen")
    }
    private func navigation(_ session: ActivitySession, readout: LiveReadout) -> some View {
        ZStack {
            HStack(spacing: 9) { GoopSymbol(name: ActivitySport.sport(session.exerciseType).symbol, size: 18, color: .white); Text(session.displayName.uppercased()).goop(.labelNav) }
            HStack {
                Button { activity.livePresented = false; activity.highlightEnd = false } label: { GoopSymbol(name: "chevron.down", size: 13, color: .white, weight: .semibold).frame(width: 44, height: 44) }.accessibilityIdentifier("activity-minimise").accessibilityLabel("Minimise")
                Spacer()
                HStack(spacing: 6) { GoopSymbol(name: readout.heart == .none ? "heart.slash" : "antenna.radiowaves.left.and.right", size: 13, color: readout.chipColor); Text(readout.chipText).goop(.labelTiny) }
                    .foregroundStyle(readout.chipColor).accessibilityElement(children: .ignore)
                    .accessibilityLabel(readout.chipSpoken).accessibilityIdentifier("activity-hr-state")
            }
        }.frame(height: 50).padding(.horizontal, 16)
    }
    private func heartCard(_ session: ActivitySession, readout: LiveReadout) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    GoopSymbol(name: "heart.fill", size: 22, color: readout.heartColor)
                    Text(readout.value).goop(.valueLiveHR).foregroundStyle(readout.valueColor)
                    if readout.showsUnit { Text("bpm").goop(.legend).foregroundStyle(Goop.Color.iconMuted).padding(.top, 14) }
                }.opacity(readout.opacity).accessibilityElement(children: .ignore)
                    .accessibilityLabel(readout.spoken).accessibilityIdentifier("activity-bpm")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(readout.zoneText).goop(.labelSmall).foregroundStyle(readout.zoneColor)
                        .accessibilityLabel(readout.zoneSpoken).accessibilityIdentifier("activity-zone-label")
                    let range = readout.zone.map { activity.estimator.range(zone: $0) }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(range ?? "—").goop(.valueZoneRange)
                        if readout.zone != nil { Text("BPM").goop(.unitSmall) }
                    }.foregroundStyle(range == nil ? Goop.Color.text2 : Goop.Color.iconMuted)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("activity-zone-range")
                }.opacity(readout.opacity)
            }
            ActivityZoneMeter(zone: readout.zone).opacity(readout.opacity).padding(.top, 14)
            LiveHRChart(samples: session.samples, now: activity.now).frame(height: 114).padding(.top, 16)
            HStack(spacing: 0) {
                stat("AVG HR", value: activity.estimate?.average.map(String.init) ?? "—")
                Rectangle().fill(Goop.Color.cardDivider).frame(width: 1, height: 40)
                stat("MAX HR", value: activity.estimate?.maximum.map(String.init) ?? "—")
                Rectangle().fill(Goop.Color.cardDivider).frame(width: 1, height: 40)
                stat("ZONES 4–5", value: GoopFormat.duration(activity.estimate?.zones45Minutes), identifier: "activity-zones45") // goop-lint: allow enginenumber: zone names, contract §5.10
            }.padding(.top, 14)
        }.padding(16).background(Goop.Gradient.card, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusCard))
    }
    private func stat(_ title: String, value: String, identifier: String = "") -> some View {
        VStack(spacing: 2) {
            Text(value).goop(.valueLiveStat).foregroundStyle(value == "—" ? Goop.Color.text2 : Goop.Color.text1).accessibilityIdentifier(identifier)
            Text(title).goop(.labelStat).foregroundStyle(Goop.Color.iconMuted)
        }.frame(maxWidth: .infinity)
    }
}

struct LiveHRChart: View {
    var samples: [HeartRateSample]
    var now: Date
    var body: some View {
        VStack(spacing: 3) {
            Canvas { context, size in
                for i in 0...2 { var grid = Path(); let y = CGFloat(i) * size.height / 2; grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y)); context.stroke(grid, with: .color(Goop.Color.plotGrid), lineWidth: 1) }
                let visible = samples.filter { $0.t >= now.addingTimeInterval(-600) && $0.t <= now }
                guard !visible.isEmpty else { return }
                let points = visible.map { CGPoint(x: CGFloat($0.t.timeIntervalSince(now.addingTimeInterval(-600)) / 600) * size.width, y: size.height * (1 - CGFloat(($0.bpm - 80) / 105).clamped(to: 0...1))) }
                var line = Path(); line.addLines(points)
                var area = line; area.addLine(to: .init(x: points.last!.x, y: size.height)); area.addLine(to: .init(x: points.first!.x, y: size.height)); area.closeSubpath()
                context.fill(area, with: .linearGradient(Gradient(colors: [Goop.Color.zone4.opacity(0.3), Goop.Color.zone4.opacity(0)]), startPoint: .zero, endPoint: .init(x: 0, y: size.height)))
                context.stroke(line, with: .color(Goop.Color.zone4), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                if let last = points.last { let dot = CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8); context.fill(Path(ellipseIn: dot), with: .color(Goop.Color.zone4)) }
            }
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("−10").goop(.axis)
                    Text("MIN").goop(.labelLane)
                }.foregroundStyle(Goop.Color.chevronDial)
                Spacer()
                Text("NOW").goop(.labelLane)
            }
        }.accessibilityLabel("Heart rate during the last ten minutes")
    }
}
private extension CGFloat { func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) } }

struct HoldToEnd: View {
    var highlighted: Bool
    var action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var task: Task<Void, Never>?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Goop.Metric.radiusButton).fill(Goop.Color.controlFill)
                Rectangle().fill(Goop.Color.zone5.opacity(0.2)).frame(width: geometry.size.width * progress)
                HStack(spacing: 10) { GoopSymbol(name: "stop.fill", size: 15, color: Goop.Color.zone5); Text("HOLD TO END").goop(.labelStage) }.frame(maxWidth: .infinity)
            }.clipShape(RoundedRectangle(cornerRadius: Goop.Metric.radiusButton))
                .overlay { RoundedRectangle(cornerRadius: Goop.Metric.radiusButton).strokeBorder(highlighted ? Goop.Color.zone5.opacity(0.7) : .clear, lineWidth: 1) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in begin() }.onEnded { _ in cancel() })
                .accessibilityElement(children: .ignore).accessibilityLabel("Hold to End").accessibilityAddTraits(.isButton).accessibilityIdentifier("activity-hold-end")
                .accessibilityAction { UINotificationFeedbackGenerator().notificationOccurred(.success); action() }
        }.frame(height: 58).onDisappear { cancel() }
    }
    private func begin() {
        guard task == nil else { return }
        withAnimation(.linear(duration: 1.2)) { progress = 1 }
        task = Task {
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success); action(); task = nil; progress = 0
        }
    }
    private func cancel() { task?.cancel(); task = nil; withAnimation(.linear(duration: 0.1)) { progress = 0 } }
}
