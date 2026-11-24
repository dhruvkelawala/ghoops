import SwiftUI
import GHealthCore

struct GoopHomeDials: View {
    var pending: Set<String> = []
    var updating: Set<String> = []
    var day: Day?
    var fixture = false
    var dimmed = false
    var action: (GoopScore) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            dial(.sleep, value: day?.sleep.performance.value.map(Double.init), caption: day.flatMap { $0.sleep.performance.value == nil ? ReasonText.score($0.sleep.performance.reason, status: $0.sleep.performance.status) : nil })
            Spacer(minLength: 0)
            dial(.recovery, value: day?.recovery.value.map(Double.init), caption: recoveryCaption)
            Spacer(minLength: 0)
            dial(.strain, value: day?.strain.value, caption: day.flatMap { $0.strain.value == nil ? ReasonText.score($0.strain.reason, status: $0.strain.status) : $0.strain.confidence == .low ? "Low data" : nil })
        }.padding(.horizontal, 29)
    }
    private var recoveryCaption: String? {
        guard let recovery = day?.recovery else { return nil }
        if recovery.value == nil { return ReasonText.score(recovery.reason, status: recovery.status, calibration: recovery.calibration) }
        return recovery.calibrating ? "Calibrating" : recovery.confidence == .low ? "Low data" : nil
    }
    private func dial(_ score: GoopScore, value: Double?, caption: String?) -> some View {
        let pending = pending.contains(score.rawValue.lowercased())
        let value = pending ? nil : value
        let caption = updating.contains(score.rawValue.lowercased()) ? "UPDATING" : pending ? nil : caption
        return Button { action(score) } label: {
            VStack(spacing: 0) {
                ZStack {
                    ScoreRing(value: value, maximum: score.maximum, color: score.color(band: day?.recovery.band), fixture: fixture)
                    ScoreText(value: value, percent: score != .strain)
                }.opacity(dimmed ? Goop.Opacity.stale : 1)
                HStack(spacing: 4) {
                    Text(score.rawValue.uppercased()).goop(.labelDial).lineLimit(1).minimumScaleFactor(0.7)
                    GoopSymbol(name: "chevron.right", size: 11, color: Goop.Color.chevronDial)
                }.padding(.top, 12)
                if let caption { Text(caption).goop(.captionDial).foregroundStyle(Goop.Color.text2).multilineTextAlignment(.center).frame(width: 110).lineLimit(2).padding(.top, 4) }
            }.frame(width: 92)
        }.buttonStyle(.plain).accessibilityIdentifier("\(score.rawValue.lowercased())-link")
            .accessibilityLabel(score.label(value: value, band: day?.recovery.band, strainBand: day?.strain.band, inProgress: day?.strain.status == .inProgress))
            .accessibilityHint(caption ?? "")
    }
}

struct GoopDetailDial: View {
    var score: GoopScore
    var value: Double?
    var band: Band3?
    var strainBand: StrainBand?
    var secondary: String?
    var level: SleepLevel?
    var fixture = false
    var dimmed = false
    var body: some View {
        ZStack {
            ScoreRing(value: value, maximum: score.maximum, color: score.color(band: band), variant: .detail, fixture: fixture).opacity(dimmed ? Goop.Opacity.stale : 1)
            VStack(spacing: 0) {
                GoopWordmark(size: 24, color: Goop.Color.wordmarkDial).frame(width: 72, height: 72 / 3.75)
                ScoreText(value: value, percent: score != .strain, size: 76).opacity(dimmed ? Goop.Opacity.stale : 1).padding(.top, 10)
                VStack(spacing: 0) {
                    Text(score == .sleep ? "SLEEP\nPERFORMANCE" : score == .strain ? "DAY STRAIN" : "RECOVERY").goop(.labelDialInner)
                    if let secondary { Text(secondary).goop(.labelDialInner).foregroundStyle(Goop.Color.text2) }
                }.multilineTextAlignment(.center).padding(.top, 12)
                if score == .sleep { GoopLevelSegments(level: level, dial: true).opacity(dimmed ? Goop.Opacity.stale : 1).padding(.top, 14) }
            }
        }.frame(width: 262, height: 262)
            .accessibilityElement(children: .ignore).accessibilityLabel(score.label(value: value, band: band, strainBand: strainBand, inProgress: secondary == "SO FAR") + (secondary == "UPDATING" ? ", UPDATING" : ""))
    }
}

struct GoopMonitorCard: View {
    var health: HealthState?
    var constants: ScoreConstants?
    var strain: Strain?
    var dimmed = false
    var loading = false
    var action: () -> Void
    var body: some View {
        let tint = health.map { Goop.color($0.color) } ?? Goop.Color.dayHR
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(health != nil ? "HEALTH MONITOR" : "DAY HEART RATE").goop(.labelMonitor).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    GoopSymbol(name: "chevron.right", size: 12, color: Goop.Color.textSoft)
                }
                HStack(spacing: 10) {
                    let badge: String? = loading || health?.kind == .building ? "—" : health == nil ? GoopFormat.number(strain?.avgHrBpm.map(Double.init)) : nil
                    let emptyBadge = badge.map(Goop.missing) ?? false
                    ZStack {
                        RoundedRectangle(cornerRadius: Goop.Metric.radiusBadge).fill((emptyBadge ? Goop.Color.neutral : tint).opacity(0.15))
                        if let badge { Text(badge).goop(.valueChart).foregroundStyle(emptyBadge ? Goop.Color.text2 : tint).opacity(!emptyBadge && dimmed && health == nil && !loading ? Goop.Opacity.stale : 1) }
                        else if let health { GoopSymbol(name: health.kind == .within ? "checkmark" : "heart", size: 12, color: tint, weight: health.kind == .within ? .semibold : .light) }
                    }.frame(width: health == nil ? 34 : 28, height: 28)
                    let title = loading ? "—" : health?.title ?? "AVG BPM"
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).goop(.labelStatus).foregroundStyle(Goop.missing(title) ? Goop.Color.text2 : tint).lineLimit(1).minimumScaleFactor(0.75)
                        Text(loading ? "" : health?.subline ?? (strain?.avgHrBpm == nil ? "No heart rate yet" : "Peak \(strain?.peakHrBpm.map(String.init) ?? "—")")).goop(.bodySmall).foregroundStyle(Goop.Color.monitorSub)
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, 15).padding(.horizontal, 16).padding(.bottom, 16)
                .background(Goop.Gradient.monitor, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusMonitor))
        }.buttonStyle(.plain).accessibilityIdentifier(health == nil ? "monitor-dayhr-link" : "monitor-health-link")
            .accessibilityLabel(accessible)
    }
    private var accessible: String {
        if loading { return health == nil ? "Day heart rate, loading" : "Health monitor, loading" }
        if let health { return "Health monitor, \(health.title.lowercased()), \(health.within) of \(health.total) metrics" + (health.kind == .attention ? ", " + HealthText.attentionSpoken(constants) : "") }
        return "Day heart rate, average \(strain?.avgHrBpm.map(String.init) ?? "no data") beats per minute, peak \(strain?.peakHrBpm.map(String.init) ?? "no data")"
    }
}

/// Two cards side by side at the taller card's height, stacked at accessibility sizes.
/// Each card needs `maxHeight: .infinity` in its frame to fill the row.
struct GoopPair<Leading: View, Trailing: View>: View {
    var spacing: CGFloat
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: spacing) { leading(); trailing() }
        } else {
            HStack(alignment: .top, spacing: spacing) { leading(); trailing() }.fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GoopComparison: View {
    var direction: ComparisonDirection
    var metric: TrendMetricKey
    var body: some View {
        GoopSymbol(name: direction == .equal ? "circle.fill" : direction == .up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill", size: direction == .equal ? 6 : 8, color: Goop.color(direction.color(for: metric)), weight: .regular)
    }
}

struct GoopValue: View {
    var metric: TrendMetricKey
    var value: Double?
    var mean: Double?
    var style: Goop.TextStyle = .valueRow
    var compareStyle: Goop.TextStyle = .compareRow
    var gap: CGFloat = 8
    var dimmed = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: gap) {
                Text(metric.display(value)).goop(style)
                if let direction = GoopFormat.direction(value, mean: mean, metric: metric) { GoopComparison(direction: direction, metric: metric) }
            }
            if GoopFormat.direction(value, mean: mean, metric: metric) != nil {
                Text(metric.display(mean)).goop(compareStyle).foregroundStyle(Goop.Color.text2).padding(.trailing, gap == 6 ? 14 : 17)
            }
        }.opacity(dimmed ? Goop.Opacity.stale : 1)
    }
}

struct GoopMetricRow: View {
    var metric: TrendMetricKey
    var title: String? = nil
    var value: Double?
    var mean: Double? = nil
    let windowDays: Int?
    var level: SleepLevel? = nil
    var sleep = false
    var tile = false
    var hint = ""
    var status: String? = nil
    var dimmed = false
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { label; values }
                } else { HStack(spacing: tile ? 12 : 11) { label; Spacer(minLength: 0); values } }
            }.frame(maxWidth: .infinity, minHeight: tile ? 62 : 57, alignment: .leading)
                .padding(.horizontal, tile ? 16 : 0).padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)
                .background { if tile { RoundedRectangle(cornerRadius: Goop.Metric.radiusTile).fill(Goop.Gradient.tile) } }
        }.buttonStyle(.plain).accessibilityIdentifier("\(tile ? "tile" : "contributor")-\(metric.rawValue)")
            .accessibilityLabel(accessible).accessibilityHint(hint)
    }
    private var label: some View {
        HStack(spacing: tile ? 12 : 11) {
            GoopSymbol(name: metric.icon, size: metric == .steps ? 13 : metric == .strength ? 14 : metric == .hrv || metric == .sleepPerformance || metric == .consistency ? 17 : 16).frame(width: 18)
            Text((title ?? metric.name).uppercased()).goop(.labelCard).lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var values: some View {
        HStack(spacing: 14) {
            if sleep { GoopLevelSegments(level: level).opacity(dimmed ? Goop.Opacity.stale : 1) }
            if let status {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("—").goop(.valueRow)
                    Text(status).goop(.labelMicro)
                }.foregroundStyle(Goop.Color.text2)
            } else {
                GoopValue(metric: metric, value: value, mean: sleep ? nil : mean, compareStyle: tile ? .compareTile : .compareRow, gap: tile ? 6 : 8, dimmed: dimmed)
            }
        }
    }
    private var accessible: String {
        if let status { return "\(metric == .strength ? "Strength" : title ?? metric.name), \(status.lowercased())" }
        var label = "\(title ?? metric.name), \(metric.display(value, includeUnit: true))"
        if sleep { if let level { label += ", \(level.rawValue.lowercased())" } }
        else if let direction = GoopFormat.direction(value, mean: mean, metric: metric) { label += ", \(direction == .equal ? "same" : direction == .up ? "up" : "down") \(EngineText.comparisonSpoken(windowDays)) \(metric.display(mean, includeUnit: true))" }
        return label
    }
}

struct GoopLevelSegments: View {
    var level: SleepLevel?
    var dial = false
    var body: some View {
        HStack(spacing: dial ? 4 : 3) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: Goop.Metric.radiusHairline).fill(level?.segments == index + 1 ? (level == .sufficient ? Goop.Color.sufficient : Goop.color(level!.color)) : (dial ? Goop.Color.dialSegmentOff : Goop.Color.segmentOff)).frame(width: dial ? 16 : 17, height: dial ? 3 : 4)
            }
        }.accessibilityHidden(true)
    }
}

struct GoopNotchedCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content).padding(.top, 4).padding(.horizontal, 14).padding(.bottom, 14)
            .background(GoopNotchShape().fill(Goop.Gradient.contributorFill))
            .overlay {
                GoopNotchShape().stroke(Goop.Color.contributorBorder, lineWidth: 1)
                GeometryReader { geometry in
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width / 2 - 9, y: 0))
                        path.addLine(to: CGPoint(x: geometry.size.width / 2, y: -9))
                        path.addLine(to: CGPoint(x: geometry.size.width / 2 + 9, y: 0))
                    }.stroke(Goop.Color.notchBorder, lineWidth: 1)
                }.accessibilityHidden(true)
            }
    }
}

struct GoopNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.midX
        var p = Path()
        p.move(to: CGPoint(x: 14, y: 0))
        p.addLine(to: CGPoint(x: x - 9, y: 0)); p.addLine(to: CGPoint(x: x, y: -9)); p.addLine(to: CGPoint(x: x + 9, y: 0))
        p.addLine(to: CGPoint(x: rect.width - 14, y: 0))
        p.addArc(center: CGPoint(x: rect.width - 14, y: 14), radius: 14, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - 14)); p.addArc(center: CGPoint(x: rect.width - 14, y: rect.height - 14), radius: 14, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: 14, y: rect.height)); p.addArc(center: CGPoint(x: 14, y: rect.height - 14), radius: 14, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: 14)); p.addArc(center: CGPoint(x: 14, y: 14), radius: 14, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct GoopLegend: View {
    var sleep = false
    let windowDays: Int?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = sleep && typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 18))
        layout {
            if sleep {
                ForEach(SleepLevel.allCases, id: \.rawValue) { level in
                    HStack(spacing: 8) { RoundedRectangle(cornerRadius: Goop.Metric.radiusHairline).fill(Goop.color(level.color)).frame(width: 12, height: 4); Text(level.rawValue) }
                }
            } else {
                HStack(spacing: 2) { GoopComparison(direction: .up, metric: .hrv); GoopComparison(direction: .down, metric: .hrv) }
                HStack(spacing: 4) { Text("Today"); Text(EngineText.comparisonLegend(windowDays: windowDays)).foregroundStyle(Goop.Color.iconMuted) }.padding(.leading, -10)
            }
            if !sleep || !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }.goop(.legend).foregroundStyle(Goop.Color.legendText).padding(.horizontal, 14).padding(.vertical, typeSize.isAccessibilitySize ? 10 : 0).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).background(Goop.Color.legendFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusLegend)).padding(.top, 8)
    }
}

struct GoopInsightCard: View {
    var text: String
    var actionTitle: String
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(text).goop(.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("insight-text")
            Button(action: action) { HStack(spacing: 8) { Text(actionTitle).goop(.labelAction); GoopSymbol(name: "arrow.right", size: 13, color: Goop.Color.insightAction) }.foregroundStyle(Goop.Color.insightAction).contentShape(Rectangle().inset(by: -14)) }.accessibilityIdentifier("insight-action").accessibilityLabel(actionTitle.lowercased().capitalized)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 15).padding(.horizontal, 16)
            .background(Goop.Gradient.insightFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusInsight))
            .overlay { RoundedRectangle(cornerRadius: Goop.Metric.radiusInsight).strokeBorder(Goop.Gradient.insightBorder, lineWidth: 1.5) }.buttonStyle(.plain)
    }
}

struct GoopCard<Content: View>: View {
    var padding: CGFloat = 16
    var bottomPadding: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    var body: some View { VStack(alignment: .leading, spacing: 0, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(.top, padding).padding(.horizontal, padding).padding(.bottom, bottomPadding ?? padding).background(Goop.Gradient.card, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusCard)) }
}

struct GoopDivider: View {
    var card = false
    var body: some View { Rectangle().fill(card ? Goop.Color.cardDivider : Goop.Color.divider).frame(height: 1).accessibilityHidden(true) }
}

struct GoopUpdatingValue: View {
    var updating: Bool
    var body: some View {
        HStack(spacing: 8) {
            Text("—").goop(.valueRow).foregroundStyle(Goop.Color.text2)
            if updating { Text("UPDATING").goop(.labelMicro).foregroundStyle(Goop.Color.text2) }
        }
    }
}
