import SwiftUI
import Charts
import GHealthCore

struct GoopWindowChart: View {
    var heartRate: HeartRateBody
    var window: ActivityWindow
    var bounds: EditBounds? = nil
    var originalWindows: [ActivityWindow] = []
    var bandStrips: [WorkoutOriginal] = []
    var pauses: [ActivityPause] = []
    var editable = true
    var prefix = "edit"
    var onChange: (ActivityWindow) -> Void
    @State private var visible: DateInterval?
    @State private var dragging = false
    @State private var snap: Date?
    private var range: DateInterval { visible ?? rangeForWindow() }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Canvas { context, size in draw(context, width: size.width) }
            if editable {
                handle(start: true, width: width)
                handle(start: false, width: width)
            }
        }.frame(height: bandStrips.isEmpty ? 216 : 230).coordinateSpace(name: "window-chart")
            .accessibilityElement(children: .contain).accessibilityIdentifier("\(prefix)-chart")
            .accessibilityChartDescriptor(ChartAccessibility(title: "Activity heart rate and selected window", xTitle: "Time", unit: "bpm", categories: heartRate.minutes.map { GoopFormat.time($0.t) }, series: [.init(name: "Heart rate", continuous: true, values: heartRate.minutes.map { (GoopFormat.time($0.t), $0.avgBpm) })]))
            .onChange(of: window) { _, _ in if !dragging { visible = rangeForWindow() } }
    }
    private func rangeForWindow() -> DateInterval {
        let first = ([window.start] + bandStrips.map(\.start) + originalWindows.map(\.start)).min()!.addingTimeInterval(-1800)
        let last = ([window.end] + bandStrips.map(\.end) + originalWindows.map(\.end)).max()!.addingTimeInterval(1800)
        return DateInterval(start: max(bounds?.span.start ?? heartRate.start, first), end: min(bounds?.span.end ?? heartRate.end, last))
    }
    private func x(_ date: Date, width: CGFloat) -> CGFloat { date.timeIntervalSince(range.start) / max(60, range.duration) * width }
    private func handle(start: Bool, width: CGFloat) -> some View {
        let date = start ? window.start : window.end
        return Color.clear.frame(width: 44, height: 190).contentShape(Rectangle())
            .position(x: x(date, width: width), y: 95)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("window-chart"))
                .onChanged { value in
                    if !dragging { visible = range; dragging = true }
                    move(start: start, to: range.start.addingTimeInterval(min(width, max(0, value.location.x)) / width * range.duration))
                }.onEnded { _ in dragging = false; visible = rangeForWindow(); snap = nil })
            .accessibilityElement().accessibilityLabel("\(start ? "Start" : "End"), \(GoopFormat.time(date))")
            .accessibilityIdentifier("\(prefix)-handle-\(start ? "start" : "end")")
            .accessibilityAdjustableAction { direction in
                move(start: start, to: date.addingTimeInterval(direction == .increment ? 60 : -60))
            }
    }
    private func move(start: Bool, to date: Date) {
        var next = window
        let limits = (bounds ?? EditBounds(span: DateInterval(start: heartRate.start, end: heartRate.end), activeMin: 60, activeMax: nil, originals: [], covers: [])).clipped(to: range, window: window)
        if start { next.moveStart(to: date, bounds: limits, pauses: pauses) }
        else { next.moveEnd(to: date, bounds: limits, pauses: pauses) }
        let minute = start ? next.start : next.end
        if snap != minute { UISelectionFeedbackGenerator().selectionChanged(); snap = minute }
        onChange(next)
    }
    private func draw(_ context: GraphicsContext, width: CGFloat) {
        let h = 190.0
        let minutes = heartRate.minutes.filter { $0.t >= range.start && $0.t <= range.end }
        let lo = floor((minutes.map(\.avgBpm).min() ?? 60) / 10) * 10 - 10
        let hi = ceil((minutes.map(\.avgBpm).max() ?? 180) / 10) * 10 + 10
        for k in 0..<4 {
            let y = Double(k) * h / 3
            GoopPlot.line(context: context, from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y), color: Goop.Color.plotGrid)
            if k < 3 { GoopPlot.text(GoopFormat.number(hi - Double(k) * (hi - lo) / 3), context: context, x: 4, y: max(2, y - 16), size: 11, color: Goop.Color.textSoft, anchor: .topLeading) }
        }
        var runs: [[HeartRateMinute]] = []
        for minute in minutes {
            if let last = runs.last?.last, minute.t.timeIntervalSince(last.t) <= 60 { runs[runs.count - 1].append(minute) }
            else { runs.append([minute]) }
        }
        for run in runs {
            for section in [run.filter { $0.t <= window.start }, run.filter { $0.t >= window.start && $0.t <= window.end }, run.filter { $0.t >= window.end }] where section.count > 1 {
                let inside = section.first!.t >= window.start && section.last!.t <= window.end
                let points = section.map { CGPoint(x: x($0.t, width: width), y: h - ($0.avgBpm - lo) / (hi - lo) * h) }
                let path = GoopPlot.path(points)
                if inside { context.fill(GoopPlot.area(path, points: points, baseline: h), with: .linearGradient(Gradient(colors: [Goop.Color.strain.opacity(0.35), Goop.Color.strain.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h))) }
                context.stroke(path, with: .color(inside ? Goop.Color.workoutLine : Goop.Color.neutral.opacity(0.5)), style: StrokeStyle(lineWidth: inside ? 2 : 1.6, lineJoin: .round))
            }
        }
        for strip in bandStrips {
            let left = x(strip.start, width: width), right = x(strip.end, width: width)
            context.fill(Path(roundedRect: CGRect(x: left, y: h + 6, width: right - left, height: 10), cornerRadius: Goop.Metric.radiusBar), with: .color(Goop.Color.typicalFill))
            for edge in [left, right] { GoopPlot.line(context: context, from: CGPoint(x: edge, y: h + 6), to: CGPoint(x: edge, y: h + 16), color: Goop.Color.typicalEdge, dash: [3, 2]) }
        }
        let labelY = h + (bandStrips.isEmpty ? 23 : 37)
        for date in [window.start, window.end] {
            let edge = min(width - 1, max(1, x(date, width: width)))
            GoopPlot.line(context: context, from: CGPoint(x: edge, y: 0), to: CGPoint(x: edge, y: h), color: .white, dash: [3, 3])
            context.fill(Path(ellipseIn: CGRect(x: edge - 2.5, y: h - 2.5, width: 5, height: 5)), with: .color(.white))
            GoopPlot.text(GoopFormat.time(date), context: context, x: edge, y: labelY, size: 12, color: .white, anchor: edge < 22 ? .bottomLeading : edge > width - 22 ? .bottomTrailing : .bottom, weight: 750)
        }
        var tick = ActivityTime.calendar.dateInterval(of: .hour, for: range.start)!.end
        while tick < range.end {
            let edge = x(tick, width: width)
            if edge >= 22 && edge <= width - 22 && abs(edge - x(window.start, width: width)) > 34 && abs(edge - x(window.end, width: width)) > 34 { GoopPlot.text(GoopFormat.time(tick), context: context, x: edge, y: labelY, size: 11, color: Goop.Color.iconMuted, anchor: .bottom, weight: 750) }
            tick = tick.addingTimeInterval(3600)
        }
    }
}

struct GoopBandLegend: View {
    var title = "BAND'S VERSION"
    var times: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Goop.Color.typicalFill))
                for x in [0.6, size.width - 0.6] { GoopPlot.line(context: context, from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: size.height), color: Goop.Color.typicalEdge, dash: [3, 2]) }
            }.frame(width: 13, height: 13).accessibilityHidden(true)
            Text(title).goop(.labelSmall).foregroundStyle(Goop.Color.textSoft)
            Spacer(minLength: 0)
            if let times { Text(times).goop(.time).foregroundStyle(Goop.Color.text2) }
        }
    }
}
