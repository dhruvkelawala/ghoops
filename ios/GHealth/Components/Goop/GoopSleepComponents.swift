import SwiftUI
import GHealthCore

struct GoopHatchedBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 16
    var typical: ClosedRange<Double>? = nil
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Goop.Color.hatchDark))
                    var hatch = Path()
                    for x in stride(from: -size.height, through: size.width + size.height, by: 8.485) {
                        hatch.move(to: CGPoint(x: x, y: size.height)); hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }
                    context.stroke(hatch, with: .color(Goop.Color.hatchLight), lineWidth: 2)
                }
                RoundedRectangle(cornerRadius: Goop.Metric.radiusBar).fill(color).frame(width: geometry.size.width * min(1, max(0, fraction)))
                if let typical {
                    let low = min(1, max(0, typical.lowerBound)), high = min(1, max(0, typical.upperBound))
                    Rectangle().fill(Goop.Color.typicalFill).frame(width: geometry.size.width * (high - low)).offset(x: geometry.size.width * low)
                    Canvas { context, size in
                        for value in [low, high] {
                            var edge = Path(); edge.move(to: CGPoint(x: size.width * value, y: 0)); edge.addLine(to: CGPoint(x: size.width * value, y: size.height))
                            context.stroke(edge, with: .color(Goop.Color.typicalEdge), style: StrokeStyle(lineWidth: 1.3, dash: [3, 2]))
                        }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: Goop.Metric.radiusBar))
        }.frame(height: height).accessibilityHidden(true)
    }
}

struct GoopTypicalKey: View {
    var trend = false
    var body: some View {
        HStack(spacing: 8) {
            if trend { Rectangle().fill(Goop.Color.trendBand).frame(width: 12, height: 12) }
            else { GoopHatchedBar(fraction: 0, color: .clear, height: 13).frame(width: 13).overlay { Rectangle().strokeBorder(Goop.Color.typicalKeyEdge, style: StrokeStyle(lineWidth: 1, dash: [3, 2])) } }
            Text("TYPICAL RANGE").goop(trend ? .labelDial : .labelSmall).foregroundStyle(Goop.Color.textSoft)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Typical range")
    }
}

enum GoopStage: String, CaseIterable, Identifiable {
    case awake, light, deep, rem, unstaged
    var id: String { rawValue }
    var title: String { self == .deep ? "SWS (DEEP)" : rawValue.uppercased() }
    var color: Color { switch self { case .awake: Goop.Color.stageAwake; case .light: Goop.Color.stageLight; case .deep: Goop.Color.stageDeep; case .rem: Goop.Color.stageREM; case .unstaged: Goop.Color.stageUnstaged } }
    var lane: Int? { switch self { case .awake: 0; case .rem: 1; case .light: 2; case .deep: 3; case .unstaged: nil } }
    /// One of the four staged lanes, or nil for classic `asleep`/`restless` and any value Google adds later.
    static func stage(_ raw: String) -> GoopStage? { Self(rawValue: raw).flatMap { $0 == .unstaged ? nil : $0 } }
    /// How a segment is named when spoken: its stage, its classic category, or "Unknown stage".
    static func spoken(_ raw: String) -> String {
        if let stage = stage(raw) { return stage.rawValue.capitalized }
        return GoopSleepChart.classicStages.contains(raw) ? raw.capitalized : "Unknown stage"
    }
    func data(_ stages: SleepStages?) -> SleepStage? { switch self { case .awake: stages?.awake; case .light: stages?.light; case .deep: stages?.deep; case .rem: stages?.rem; case .unstaged: stages?.unstaged } }
    func percent(_ sleep: Sleep) -> Double? {
        guard self == .awake else { return data(sleep.stages)?.pctOfAsleep }
        guard let minutes = data(sleep.stages)?.minutes, let total = sleep.timeInBedMinutes, total > 0 else { return nil }
        return Double(minutes) / Double(total) * 100
    }
    func typical(_ typical: StageTypical?) -> StageRange? { switch self { case .awake: typical?.awake; case .light: typical?.light; case .deep: typical?.deep; case .rem: typical?.rem; case .unstaged: nil } }
}

struct GoopStageRow: View {
    var stage: GoopStage
    var minutes: Int?
    var percent: Double?
    var typical: StageRange?
    var scale: Double
    var selected: Bool
    var dimmed = false
    var action: () -> Void
    private var range: ClosedRange<Double>? {
        guard let lo = typical?.lowMinutes, let hi = typical?.highMinutes, scale > 0 else { return nil }
        return Double(lo) / scale...Double(hi) / scale
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(selected ? stage.color : .clear)
                        Circle().strokeBorder(selected ? stage.color : Goop.Color.stageRing, lineWidth: 1.8)
                        if selected { GoopSymbol(name: "checkmark", size: 12, color: Goop.Color.widgetFill, weight: .semibold) }
                    }.frame(width: 26, height: 26)
                    Text(stage.title).goop(.labelStage)
                    Text(GoopFormat.percent(percent)).goop(.valueTiny).foregroundStyle(stage == .awake || stage == .unstaged ? Goop.Color.textSoft : stage.color).opacity(dimmed ? Goop.Opacity.stale : 1)
                    Spacer(minLength: 0)
                    Text(GoopFormat.duration(minutes)).goop(.valueStage).opacity(dimmed ? Goop.Opacity.stale : 1)
                }
                GoopHatchedBar(fraction: Double(minutes ?? 0) / max(1, scale), color: stage.color, typical: range).opacity(dimmed ? Goop.Opacity.stale : 1)
            }.padding(.vertical, 10)
        }.buttonStyle(.plain).accessibilityIdentifier("stage-\(stage.rawValue)")
            .accessibilityLabel("\(stage == .deep ? "Deep" : stage.rawValue.capitalized), \(GoopFormat.number(percent)) percent, \(GoopSpeech.duration(minutes))" + (range == nil ? "" : ", typical \(GoopFormat.duration(typical?.lowMinutes)) to \(GoopFormat.duration(typical?.highMinutes))"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct GoopRestorativeRow: View {
    var minutes: Int?
    var mean: Double?
    var dimmed = false
    var body: some View {
        VStack(spacing: 0) {
            GoopDivider(card: true)
            HStack(spacing: 12) {
                RestorativeSwatch()
                Text("RESTORATIVE SLEEP").goop(.labelStage).frame(maxWidth: .infinity, alignment: .leading)
                GoopValue(metric: .restorative, value: minutes.map(Double.init), mean: mean, style: .valueStage, gap: 7, dimmed: dimmed)
            }.padding(.top, 16).padding(.bottom, 10)
        }
    }
}

struct GoopNeedCard: View {
    var pending = false
    var updating = false
    var sleep: Sleep
    var comparison: Comparison?
    var dimmed = false
    var info: () -> Void
    private var need: SleepNeed { sleep.need }
    private var scale: Double { Double(max(1, max(sleep.asleepMinutes ?? 0, need.baselineMinutes + need.strainExtraMinutes + need.debtExtraMinutes))) }
    var body: some View {
        GoopCard {
            HStack {
                Text(sleep.asleepMinutes == nil ? "TONIGHT'S NEED SO FAR" : "HOURS VS. NEEDED").goop(.labelCard)
                Spacer()
                Button(action: info) { GoopSymbol(name: "info.circle", size: 19).frame(width: 28, height: 24).contentShape(Rectangle().inset(by: -10)) }.accessibilityLabel("How sleep need works")
            }
            if pending {
                ForEach(["HOURS OF SLEEP", "SLEEP NEEDED", "BASELINE NEED", "RECENT STRAIN", "SLEEP DEBT", "NAP CREDIT"], id: \.self) { title in
                    HStack { Text(title).goop(.labelSmall).foregroundStyle(Goop.Color.textSoft); Spacer(); GoopUpdatingValue(updating: updating) }.padding(.top, 12)
                }
            } else {
                if sleep.asleepMinutes != nil {
                    GoopValue(metric: .sleepPerformance, value: sleep.performance.value.map(Double.init), mean: comparison?.metrics["sleep_performance"]?.mean, style: .valueHours, dimmed: dimmed).padding(.top, 6)
                    needLabel("HOURS OF SLEEP", value: sleep.asleepMinutes).padding(.top, 16).padding(.bottom, 8)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: Goop.Metric.radiusBar).fill(Goop.Gradient.hoursBar).frame(width: geometry.size.width * Double(sleep.asleepMinutes ?? 0) / scale)
                    }.frame(height: 16).padding(.horizontal, 10).opacity(dimmed ? Goop.Opacity.stale : 1)
                }
                GoopNeedBar(baseline: need.baselineMinutes, strain: need.strainExtraMinutes, debt: need.debtExtraMinutes, naps: need.napCreditMinutes, scale: scale)
                    .padding(.horizontal, 10).padding(.top, 9).opacity(dimmed ? Goop.Opacity.stale : 1)
                needLabel("SLEEP NEEDED", value: need.totalMinutes).padding(.top, 8)
                GoopNeedParts(baseline: need.baselineMinutes, strain: need.previousCycleStrain == nil ? nil : need.strainExtraMinutes, debt: need.debtExtraMinutes, naps: need.napCreditMinutes, debtNightsUsed: need.debtNightsUsed, dimmed: dimmed)
                    .padding(.vertical, 6).padding(.horizontal, 14).background(Goop.Color.legendFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusLegend)).padding(.top, 12)
            }
        }.buttonStyle(.plain)
    }
    private func needLabel(_ title: String, value: Int?) -> some View {
        HStack { Text(title).goop(.labelSmall).foregroundStyle(Goop.Color.textSoft); Spacer(); Text(GoopFormat.duration(value)).goop(.valueMid).opacity(dimmed ? Goop.Opacity.stale : 1) }.padding(.horizontal, 10)
    }
}

struct GoopZoneRows: View {
    var zones: Zones?
    var resting: Int?
    var maximum: Int?
    var floors: ZoneFloors?
    var dimmed = false
    private var values: [Int] { zones.map { [$0.below, $0.z1, $0.z2, $0.z3, $0.z4, $0.z5] } ?? [] }
    var body: some View {
        if zones == nil { GoopPlaceholder(text: "No heart-rate zones for this workout") }
        else {
            let total = max(1, values.reduce(0, +)), largest = Double(values.max() ?? 0) / Double(total)
            let scale = min(2.2, 0.95 / max(largest, 0.001))
            ForEach((0...5).reversed(), id: \.self) { zone in
                VStack(spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("ZONE \(zone)").goop(.labelStage)
                        if let range = range(zone) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(range).goop(.valueTiny)
                                Text("BPM").goop(.unitSmall)
                            }.foregroundStyle(Goop.Color.textSoft).opacity(dimmed ? Goop.Opacity.stale : 1)
                        }
                        Text(GoopFormat.percent(Double(values[zone]) / Double(total) * 100)).goop(.valueTiny).foregroundStyle(Goop.zones[zone]).opacity(dimmed ? Goop.Opacity.stale : 1)
                        Spacer(minLength: 0); Text(GoopFormat.duration(values[zone])).goop(.valueZone).opacity(dimmed ? Goop.Opacity.stale : 1)
                    }
                    if values[zone] > 0 { GoopHatchedBar(fraction: Double(values[zone]) / Double(total) * scale, color: Goop.zones[zone], height: 18).opacity(dimmed ? Goop.Opacity.stale : 1) }
                }.padding(.vertical, values[zone] == 0 ? 12 : 13).padding(.horizontal, 14).background(Goop.Color.zoneRowFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusZoneRow)).opacity(values[zone] == 0 ? 0.5 : 1).padding(.top, 8)
            }
        }
    }
    private func range(_ zone: Int) -> String? {
        ZoneScale(rest: resting.map(Double.init), maximum: maximum.map(Double.init), zones: floors)?.range(zone)
    }
}
