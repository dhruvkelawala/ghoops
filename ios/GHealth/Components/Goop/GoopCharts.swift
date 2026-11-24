import SwiftUI
import GHealthCore

enum GoopPlot {
    static func text(_ string: String, context: GraphicsContext, x: CGFloat, y: CGFloat, size: CGFloat, color: Color, anchor: UnitPoint = .center, nunito: Bool = false, weight: CGFloat = 500) {
        let font = nunito ? GoopFont.nunito(size, weight: weight) : GoopFont.sofia(size) // goop-lint: allow rawfont: Canvas chart text has fixed chart sizes
        context.draw(Text(string).font(Font(font)).foregroundStyle(color), at: CGPoint(x: x, y: y), anchor: anchor)
    }
    static func line(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat = 1, dash: [CGFloat] = []) {
        var path = Path(); path.move(to: from); path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
    }
    static func runs(_ points: [HeartRatePoint], gap: TimeInterval) -> [[HeartRatePoint]] {
        var runs: [[HeartRatePoint]] = []
        for point in points.sorted(by: { $0.t < $1.t }) {
            if let previous = runs.last?.last, point.t.timeIntervalSince(previous.t) <= gap { runs[runs.count - 1].append(point) }
            else { runs.append([point]) }
        }
        return runs
    }
    static func path(_ points: [CGPoint], smooth: Bool = false) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 0..<max(0, points.count - 1) {
            let p1 = points[index], p2 = points[index + 1]
            if smooth {
                let p0 = points[max(0, index - 1)], p3 = points[min(points.count - 1, index + 2)]
                path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6), control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
            } else { path.addLine(to: p2) }
        }
        return path
    }
    static func area(_ path: Path, points: [CGPoint], baseline: CGFloat) -> Path {
        var area = path
        if let first = points.first, let last = points.last { area.addLine(to: CGPoint(x: last.x, y: baseline)); area.addLine(to: CGPoint(x: first.x, y: baseline)); area.closeSubpath() }
        return area
    }
}

struct GoopWeeklyCard: View {
    var rows: [DayRow]
    var metric: TrendMetricKey
    var end: String
    var dimmed = false
    var action: () -> Void
    private var dates: [String] { GoopFormat.dates(from: GoopFormat.addingDays(-6, to: end), to: end) }
    var body: some View {
        Button(action: action) {
            GoopCard {
                HStack { Text(metric == .recovery ? "RECOVERY" : "STRAIN").goop(.labelCard); Spacer(); GoopSymbol(name: "chevron.right", size: 12, color: Goop.Color.textSoft) }
                Canvas { context, size in
                    let step = size.width / 7
                    context.fill(Path(roundedRect: CGRect(x: step * 6.5 - 17, y: 0, width: 34, height: 244), cornerRadius: Goop.Metric.radiusHighlight), with: .color(Goop.Color.highlightColumn))
                    for k in 0..<4 { GoopPlot.line(context: context, from: CGPoint(x: 0, y: 10 + Double(k) * 190 / 3), to: CGPoint(x: size.width, y: 10 + Double(k) * 190 / 3), color: Goop.Color.chartGrid) }
                    for (index, date) in dates.enumerated() {
                        let cx = (CGFloat(index) + 0.5) * step
                        if let row = rows.first(where: { $0.date == date }), let value = metric.value(row) {
                            let height = value / (metric == .recovery ? 100 : 21) * 170
                            let color = metric == .recovery ? Goop.recoveryColor(row.recoveryBand) : Goop.Color.strain
                            context.fill(Path(CGRect(x: cx - 11, y: 200 - height, width: 22, height: height)), with: .color(color))
                            GoopPlot.text(metric.display(value), context: context, x: cx, y: 193 - height, size: 14, color: color, anchor: .bottom)
                        }
                        GoopPlot.text(GoopFormat.dateLabel(date, format: "EEE"), context: context, x: cx, y: 220, size: 12, color: index == 6 ? .white : Goop.Color.iconMuted, anchor: .bottom, nunito: true, weight: index == 6 ? 700 : 500)
                        GoopPlot.text(GoopFormat.dateLabel(date, format: "d"), context: context, x: cx, y: 236, size: 10.5, color: index == 6 ? .white : Goop.Color.iconMuted, anchor: .bottom, nunito: true)
                    }
                }.frame(height: 246).padding(.top, 14).opacity(dimmed ? Goop.Opacity.stale : 1)
                    .accessibilityChartDescriptor(ChartAccessibility(title: "Weekly \(metric.name)", unit: metric.unit, categories: dates, series: [.init(name: metric.name, values: dates.compactMap { date in rows.first { $0.date == date }.flatMap { row in metric.value(row).map { (date, $0) } } })]))
            }
        }.buttonStyle(.plain).accessibilityIdentifier("weekly-trend-\(metric.rawValue)")
    }
}

struct GoopSleepChart: View {
    var sleep: Sleep
    var selected: GoopStage?
    var visibleRange: DateInterval? = nil
    var googleWindow: ActivityWindow? = nil
    var heartRate: [HeartRatePoint]? = nil
    var heartRateMessage: String? = nil
    var dimmed = false
    static let classicStages: Set<String> = ["asleep", "restless"]
    /// Google's classic sleep has no stages. Its categories are never drawn as stages (oss-data-audit row 4).
    private var classic: Bool { sleep.session?.type == "CLASSIC" || sleep.hypnogram?.segments.contains { Self.classicStages.contains($0.stage) } == true }
    var body: some View {
        Group {
            if let hypnogram = sleep.hypnogram, (!hypnogram.segments.isEmpty && !classic) || visibleRange != nil {
                Canvas { context, size in draw(context: context, width: max(1, size.width - 60), hypnogram: hypnogram) }.frame(height: googleWindow == nil ? 246 : 268)
                    .accessibilityChartDescriptor(descriptor(hypnogram))
                    .accessibilityValue((unstagedSpans(hypnogram) + unknownSpans(hypnogram)).map { "\($0.0), \(GoopFormat.number($0.1)) minutes" }.joined(separator: "; "))
                if classic { Text("Classic sleep (no stages)").goop(.bodySmall).foregroundStyle(Goop.Color.text2).padding(.top, 4) }
            } else { GoopPlaceholder(text: classic ? "Classic sleep: no sleep stages for this night" : "No sleep stages for this night").frame(height: 246) }
        }.opacity(dimmed ? Goop.Opacity.stale : 1).accessibilityIdentifier("hypnogram")
    }
    private func draw(context: GraphicsContext, width: CGFloat, hypnogram: Hypnogram) {
        var plot = context
        plot.translateBy(x: 60, y: 0)
        let range = visibleRange ?? DateInterval(start: hypnogram.start, end: hypnogram.end)
        let duration = max(1, range.duration)
        func x(_ date: Date) -> CGFloat { min(width, max(0, date.timeIntervalSince(range.start) / duration * width)) }
        func y(_ lane: Int) -> CGFloat { CGFloat(lane) * 34 + 17 }
        for stage in GoopStage.allCases {
            guard let lane = stage.lane else { continue }
            let cy = y(lane)
            GoopPlot.line(context: plot, from: CGPoint(x: 0, y: cy), to: CGPoint(x: width, y: cy), color: .white.opacity(0.043))
            context.fill(Path(ellipseIn: CGRect(x: 0, y: cy - 3, width: 6, height: 6)), with: .color(stage.color))
            GoopPlot.text(stage == .deep ? "DEEP" : stage.rawValue.uppercased(), context: context, x: 11, y: cy, size: 10.5, color: Goop.Color.laneLabel, anchor: .leading, nunito: true, weight: 750)
        }
        for span in hypnogram.unstaged {
            let block = CGRect(x: x(span.start), y: 43.5, width: x(span.end) - x(span.start), height: 83)
            let opacity = selected == nil || selected == .unstaged ? 1.0 : 0.25
            plot.fill(Path(roundedRect: block, cornerRadius: Goop.Metric.radiusSegment), with: .color(Goop.Color.stageUnstaged.opacity(opacity)))
            if block.width >= 64 {
                GoopPlot.text("UNSTAGED", context: plot, x: block.midX, y: block.midY, size: 10.5, color: Goop.Color.laneLabel.opacity(opacity), nunito: true, weight: 750)
            }
        }
        let segments = hypnogram.segments.sorted { $0.start < $1.start }
        for pair in zip(segments, segments.dropFirst()) {
            if let a = GoopStage.stage(pair.0.stage), let b = GoopStage.stage(pair.1.stage), let aLane = a.lane, let bLane = b.lane, pair.1.start.timeIntervalSince(pair.0.end) <= 60 && aLane != bLane {
                var connector = Path(); connector.move(to: CGPoint(x: x(pair.0.end), y: y(aLane))); connector.addLine(to: CGPoint(x: x(pair.0.end), y: y(bLane)))
                let colors = y(aLane) < y(bLane) ? [a.color, b.color] : [b.color, a.color]
                plot.stroke(connector, with: .linearGradient(Gradient(colors: colors.map { $0.opacity(0.55) }), startPoint: CGPoint(x: 0, y: min(y(aLane), y(bLane))), endPoint: CGPoint(x: 0, y: max(y(aLane), y(bLane)))), lineWidth: 1.5)
            }
        }
        for segment in segments {
            guard let stage = GoopStage.stage(segment.stage), let lane = stage.lane else { continue }
            let opacity = selected == nil || selected == stage ? 1.0 : 0.25
            plot.fill(Path(roundedRect: CGRect(x: x(segment.start), y: y(lane) - 7.5, width: max(3, x(segment.end) - x(segment.start)), height: 15), cornerRadius: Goop.Metric.radiusSegment), with: .color(stage.color.opacity(opacity)))
        }
        if visibleRange != nil {
            for segment in hypnogram.outside ?? [] {
                guard let lane = GoopStage.stage(segment.stage)?.lane else { continue }
                plot.fill(Path(roundedRect: CGRect(x: x(segment.start), y: y(lane) - 7.5, width: max(0, x(segment.end) - x(segment.start)), height: 15), cornerRadius: Goop.Metric.radiusSegment), with: .color(Goop.Color.neutral.opacity(0.5)))
            }
        }
        for segment in hypnogram.shortAwakenings {
            plot.fill(Path(roundedRect: CGRect(x: x(segment.start), y: 9.5, width: max(2, x(segment.end) - x(segment.start)), height: 15), cornerRadius: Goop.Metric.radiusMark), with: .color(Goop.Color.stageAwake.opacity(selected == nil || selected == .awake ? 0.7 : 0.175)))
        }
        drawHR(context: context, plot: plot, x: x)
        let edges = visibleRange == nil ? [0.75, width - 0.75] : [x(hypnogram.start), x(hypnogram.end)]
        for px in edges { GoopPlot.line(context: plot, from: CGPoint(x: px, y: -2), to: CGPoint(x: px, y: 224), color: .white.opacity(visibleRange == nil ? 0.22 : 0.9), dash: [2.5, 3]) }
        for px in edges { plot.fill(Path(ellipseIn: CGRect(x: px - 2.2, y: 222.8, width: 4.4, height: 4.4)), with: .color(.white)) }
        GoopPlot.text(GoopFormat.time(visibleRange == nil ? range.start : hypnogram.start), context: plot, x: visibleRange == nil ? 0 : x(hypnogram.start), y: 243, size: 12, color: .white, anchor: visibleRange == nil ? .bottomLeading : .bottom)
        GoopPlot.text(GoopFormat.time(visibleRange == nil ? range.end : hypnogram.end), context: plot, x: visibleRange == nil ? width : x(hypnogram.end), y: 243, size: 12, color: .white, anchor: visibleRange == nil ? .bottomTrailing : .bottom)
        var hour = GoopFormat.calendar.dateInterval(of: .hour, for: range.start)!.end
        while hour < range.end {
            if GoopFormat.calendar.component(.hour, from: hour) % 2 == 1 && hour.timeIntervalSince(range.start) >= 2400 && range.end.timeIntervalSince(hour) >= 2400 {
                let px = x(hour)
                GoopPlot.line(context: plot, from: CGPoint(x: px, y: 221), to: CGPoint(x: px, y: 225), color: .white.opacity(0.25))
                if px > 42 && px < width - 42 && (visibleRange == nil || (abs(px - x(hypnogram.start)) > 36 && abs(px - x(hypnogram.end)) > 36)) { GoopPlot.text(GoopFormat.time(hour), context: plot, x: px, y: 243, size: 11, color: Goop.Color.tickLabel, anchor: .bottom) }
            }
            hour = GoopFormat.calendar.date(byAdding: .hour, value: 1, to: hour)!
        }
        if let googleWindow {
            let left = x(googleWindow.start), right = x(googleWindow.end)
            plot.fill(Path(CGRect(x: left, y: 253, width: max(0, right - left), height: 13)), with: .color(Goop.Color.typicalFill))
            for edge in [left, right] { GoopPlot.line(context: plot, from: CGPoint(x: edge, y: 253), to: CGPoint(x: edge, y: 266), color: Goop.Color.typicalEdge, dash: [3, 2]) }
        }
    }
    private func drawHR(context: GraphicsContext, plot: GraphicsContext, x: (Date) -> CGFloat) {
        let series = (heartRate ?? sleep.overnightHr).sorted { $0.t < $1.t }
        if let heartRateMessage {
            GoopPlot.text(heartRateMessage, context: plot, x: 0, y: 186, size: 12.5, color: Goop.Color.text2, anchor: .leading, nunito: true)
        }
        guard series.count >= 2, let low = series.map(\.bpm).min(), let high = series.map(\.bpm).max() else { return }
        func point(_ item: HeartRatePoint) -> CGPoint { CGPoint(x: x(item.t.addingTimeInterval(150)), y: 220 - Double(item.bpm - low + 4) / Double(high - low + 8) * 60) }
        GoopPlot.text("HR", context: context, x: 0, y: 176, size: 10.5, color: Goop.Color.laneLabel, anchor: .topLeading, nunito: true, weight: 750)
        GoopPlot.text("\(low)–\(high)", context: context, x: 0, y: 191, size: 12, color: Goop.Color.hrLine, anchor: .topLeading)
        GoopPlot.line(context: plot, from: CGPoint(x: 0, y: 220), to: CGPoint(x: x(visibleRange?.end ?? sleep.hypnogram!.end), y: 220), color: .white.opacity(0.063))
        for run in GoopPlot.runs(series, gap: 300) where run.count >= 2 {
            let points = run.map(point), path = GoopPlot.path(points, smooth: true)
            if visibleRange != nil, let window = sleep.hypnogram {
                plot.stroke(path, with: .color(Goop.Color.neutral.opacity(0.5)), lineWidth: 1.6)
                var inside = plot
                inside.clip(to: Path(CGRect(x: x(window.start), y: 150, width: max(0, x(window.end) - x(window.start)), height: 72)))
                inside.fill(GoopPlot.area(path, points: points, baseline: 220), with: .color(Goop.Color.hrFill.opacity(0.16)))
                inside.stroke(path, with: .color(Goop.Color.hrLine), lineWidth: 1.6)
            } else {
                plot.fill(GoopPlot.area(path, points: points, baseline: 220), with: .linearGradient(Gradient(colors: [Goop.Color.hrFill.opacity(0.28), Goop.Color.hrFill.opacity(0)]), startPoint: CGPoint(x: 0, y: 160), endPoint: CGPoint(x: 0, y: 220)))
                plot.stroke(path, with: .color(Goop.Color.hrLine), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        if let minimum = series.first(where: { $0.bpm == low }), visibleRange == nil || (minimum.t >= sleep.hypnogram!.start && minimum.t < sleep.hypnogram!.end) {
            let p = point(minimum), circle = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            plot.fill(circle, with: .color(Goop.Color.dotHole)); plot.stroke(circle, with: .color(Goop.Color.hrLine), lineWidth: 1.6)
        }
    }
    private func unstagedSpans(_ hypnogram: Hypnogram) -> [(String, Double)] {
        hypnogram.unstaged.map { ("Unstaged \(GoopFormat.time($0.start)) to \(GoopFormat.time($0.end))", $0.end.timeIntervalSince($0.start) / 60) }
    }
    /// Segments whose stage the chart doesn't draw, named for VoiceOver.
    private func unknownSpans(_ hypnogram: Hypnogram) -> [(String, Double)] {
        hypnogram.segments.filter { GoopStage.stage($0.stage) == nil }.map { ("\(GoopStage.spoken($0.stage)) \(GoopFormat.time($0.start)) to \(GoopFormat.time($0.end))", $0.end.timeIntervalSince($0.start) / 60) }
    }
    private func descriptor(_ hypnogram: Hypnogram) -> ChartAccessibility {
        let stages = hypnogram.segments.map { ("\(GoopStage.spoken($0.stage)) \(GoopFormat.time($0.start)) to \(GoopFormat.time($0.end))", $0.end.timeIntervalSince($0.start) / 60) }
        let unstaged = unstagedSpans(hypnogram)
        let hr = sleep.overnightHr.map { (GoopFormat.time($0.t), Double($0.bpm)) }
        return ChartAccessibility(title: "Last night's sleep", xTitle: "Time", unit: "minutes or bpm", categories: stages.map(\.0) + unstaged.map(\.0) + hr.map(\.0), series: [.init(name: "Stages", values: stages), .init(name: "Unstaged", values: unstaged), .init(name: "Heart rate", continuous: true, values: hr)])
    }
}

struct GoopWorkoutChart: View {
    var workout: Workout
    var dimmed = false
    var body: some View {
        Group {
            if workout.hrSeries.isEmpty { GoopPlaceholder(text: "No heart rate recorded for this workout").frame(height: 216) }
            else {
                Canvas { context, size in
                    let width = size.width, h = 190.0
                    let lo = floor(Double(workout.hrSeries.map(\.bpm).min()!) / 10) * 10 - 10
                    let hi = ceil(Double(workout.hrSeries.map(\.bpm).max()!) / 10) * 10 + 10
                    for k in 0..<4 {
                        let y = Double(k) * h / 3
                        GoopPlot.line(context: context, from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y), color: Goop.Color.plotGrid)
                        if k < 3 { GoopPlot.text(GoopFormat.number(hi - Double(k) * (hi - lo) / 3), context: context, x: 4, y: max(2, y - 16), size: 11, color: Goop.Color.textSoft, anchor: .topLeading) }
                    }
                    let duration = max(1, workout.end.timeIntervalSince(workout.start))
                    for run in GoopPlot.runs(workout.hrSeries, gap: 60) where run.count >= 2 {
                        let points = run.map { CGPoint(x: $0.t.timeIntervalSince(workout.start) / duration * width, y: h - (Double($0.bpm) - lo) / (hi - lo) * h) }
                        let path = GoopPlot.path(points)
                        context.fill(GoopPlot.area(path, points: points, baseline: h), with: .linearGradient(Gradient(colors: [Goop.Color.strain.opacity(0.35), Goop.Color.strain.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                        context.stroke(path, with: .color(Goop.Color.workoutLine), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                    for x in [1.0, width - 1] {
                        GoopPlot.line(context: context, from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: h), color: .white, dash: [3, 3])
                        context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: h - 2.5, width: 5, height: 5)), with: .color(.white))
                    }
                    GoopPlot.text(GoopFormat.time(workout.start), context: context, x: 0, y: h + 23, size: 12, color: .white, anchor: .bottomLeading)
                    GoopPlot.text(GoopFormat.time(workout.end), context: context, x: width, y: h + 23, size: 12, color: .white, anchor: .bottomTrailing)
                }.frame(height: 216).accessibilityChartDescriptor(ChartAccessibility(title: "Workout heart rate", xTitle: "Time", unit: "bpm", categories: workout.hrSeries.map { GoopFormat.time($0.t) }, series: [.init(name: "Heart rate", continuous: true, values: workout.hrSeries.map { (GoopFormat.time($0.t), Double($0.bpm)) })]))
            }
        }.opacity(dimmed ? Goop.Opacity.stale : 1)
    }
}
