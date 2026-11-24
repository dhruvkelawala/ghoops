import SwiftUI
import GHealthCore

struct GoopMetricPicker: View {
    @Binding var metric: TrendMetricKey
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 14) {
                GoopSymbol(name: metric.icon, size: 17)
                Text(metric.name.uppercased()).goop(.labelPicker).frame(maxWidth: .infinity, alignment: .leading)
                GoopSymbol(name: "chevron.down", size: 11, color: .white, weight: .semibold)
            }.padding(.horizontal, 18).frame(minHeight: 54).background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
        }.buttonStyle(.plain).accessibilityIdentifier("metric-picker").accessibilityLabel(metric.name)
            .sheet(isPresented: $open) {
                GoopSheet(title: "METRIC") {
                    VStack(spacing: 0) {
                        ForEach(TrendMetricKey.Group.allCases, id: \.self) { group in
                            GoopSectionLabel(title: group.rawValue.uppercased()).padding(.horizontal, 2).padding(.top, group == .recovery ? 4 : 18).padding(.bottom, 6)
                            ForEach(TrendMetricKey.allCases.filter { $0.group == group }) { key in
                                GoopChoiceRow(symbol: key.icon, title: key.name.uppercased(), selected: key == metric, identifier: "metric-\(key.rawValue)") { metric = key; open = false }
                            }
                        }
                    }
                }.accessibilityIdentifier("metric-sheet")
            }
    }
}

struct GoopRangeSelector: View {
    var options: [String]
    @Binding var selection: String
    var identifier: (String) -> String
    var numeric: Bool
    init(options: [String], selection: Binding<String>, identifier: @escaping (String) -> String, numeric: Bool = false) {
        self.options = options
        self._selection = selection
        self.identifier = identifier
        self.numeric = numeric
    }
    init(range: Binding<TrendWindow.Range>) {
        self.init(options: TrendWindow.Range.allCases.map(\.rawValue), selection: Binding(get: { range.wrappedValue.rawValue }, set: { value in
            if let next = TrendWindow.Range(rawValue: value) { range.wrappedValue = next }
        }), identifier: { "range-\($0)" })
    }
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { value in
                Button { selection = value } label: {
                    Text(value).goop(numeric ? .valueSmall : .labelSegment).foregroundStyle(selection == value ? .white : Goop.Color.rangeText).frame(width: 52, height: 32).background(selection == value ? Goop.Color.rangeSelected : .clear, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusRangeSegment)).contentShape(Rectangle().inset(by: -6))
                }.accessibilityIdentifier(identifier(value)).accessibilityLabel(value.capitalized).accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }.padding(3).background(Goop.Color.rangeTrack, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusRange)).buttonStyle(.plain)
    }
}

struct GoopRangeNavigation: View {
    var window: TrendWindow
    var oldestDate: String?
    var defaultDate: String
    var previous: () -> Void
    var next: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            arrow("chevron.left", id: "range-prev", enabled: window.canPrevious(oldestDate: oldestDate), action: previous)
            Text(GoopFormat.range(from: window.start, to: window.end)).goop(.labelCard).fixedSize(horizontal: true, vertical: false).accessibilityIdentifier("range-label")
            arrow("chevron.right", id: "range-next", enabled: window.canNext(defaultDate: defaultDate), action: next)
        }.buttonStyle(.plain)
    }
    private func arrow(_ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { GoopSymbol(name: symbol, size: 13, color: enabled ? .white : Goop.Color.disabledChevronDark, weight: .semibold).frame(width: 16, height: 44).contentShape(Rectangle().inset(by: -14)) }.disabled(!enabled).accessibilityIdentifier(id).accessibilityLabel(id == "range-prev" ? "Previous range" : "Next range")
    }
}

struct GoopChip: View {
    var text: String
    var direction: ComparisonDirection?
    var metric: TrendMetricKey
    var body: some View {
        HStack(spacing: 5) {
            if let direction { GoopComparison(direction: direction, metric: metric) }
            Text(text).goop(.chip)
        }.foregroundStyle(Goop.Color.chipText).padding(.vertical, 3).padding(.horizontal, 8).background(Goop.Color.chipFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusChip))
    }
}

struct GoopAverage: View {
    var metric: TrendMetricKey
    var mean: Double?
    var prior: Double?
    var range: TrendWindow.Range
    var dimmed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AVERAGE").goop(.labelSmall).foregroundStyle(Goop.Color.iconMuted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.display(mean)).goop(.valueAverage)
                if metric.unit != "%" && !metric.unit.isEmpty { Text(metric.unit).goop(.unitLarge).foregroundStyle(Goop.Color.textSoft) }
            }.padding(.top, 4).opacity(dimmed ? Goop.Opacity.stale : 1)
            if let mean, let prior, prior != 0 || metric == .skinTemp {
                let period = range == .week ? "week" : range == .month ? "month" : "6 months" // goop-lint: allow enginenumber: trend window
                let difference = metric == .skinTemp ? GoopFormat.temperature(mean - prior) + " °C" : GoopFormat.number(abs(mean - prior) / abs(prior) * 100) + "%"
                GoopChip(text: difference + " vs. prior " + period, direction: GoopFormat.direction(mean, mean: prior, metric: metric), metric: metric).padding(.top, 8).opacity(dimmed ? Goop.Opacity.stale : 1)
            }
        }
    }
}

struct GoopTrendChart: View {
    var rows: [DayRow]
    var metric: TrendMetricKey
    var window: TrendWindow
    var typical: ClosedRange<Double>?
    var dimmed = false
    private var dates: [String] { GoopFormat.dates(from: window.start, to: window.end) }
    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }.frame(height: 294).opacity(dimmed ? Goop.Opacity.stale : 1)
            .accessibilityChartDescriptor(ChartAccessibility(title: metric.name, unit: metric.unit, categories: dates, series: [.init(name: metric.name, continuous: metric.chart == .line, values: dates.compactMap { date in rows.first { $0.date == date }.flatMap { row in metric.value(row).map { (date, $0) } } })]))
    }
    private var scale: (low: Double, high: Double, step: Double) {
        if [.recovery, .sleepPerformance, .consistency, .efficiency].contains(metric) { return (0, 100, 20) }
        if metric == .strain { return (0, 21, 4) }
        let values = rows.filter { $0.date >= window.start && $0.date <= window.end }.compactMap { metric.value($0) } + (typical.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let low = values.min() ?? 0, high = values.max() ?? 1, span = max(high - low, 1)
        let steps: [Double] = [1, 2, 4, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000]
        let step = steps.first { floor((low - 0.15 * span) / $0) * $0 + 5 * $0 >= high + 0.15 * span } ?? 5000
        let bottom = floor((low - 0.15 * span) / step) * step
        return (bottom, bottom + 5 * step, step)
    }
    private func draw(context: GraphicsContext, size: CGSize) {
        var plot = context; plot.translateBy(x: 30, y: 18)
        let w = max(1, size.width - 30), h = 232.0, step = w / Double(window.range.length), scale = scale
        let dates = dates
        let indexed = Dictionary(rows.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        func y(_ value: Double) -> CGFloat { h - (value - scale.low) / (scale.high - scale.low) * h }
        func x(_ index: Int) -> CGFloat { (CGFloat(index) + 0.5) * step }
        for k in 0..<6 {
            let value = scale.low + Double(k) * scale.step, cy = y(value)
            GoopPlot.line(context: plot, from: CGPoint(x: 0, y: cy), to: CGPoint(x: w, y: cy), color: Goop.Color.plotGrid)
            let label = metric.isDuration ? GoopFormat.duration(Int(value)) : GoopFormat.number(value, decimals: metric == .skinTemp ? 1 : 0, grouped: metric == .steps)
            GoopPlot.text(label, context: context, x: 24, y: cy + 18, size: 11, color: Goop.Color.iconMuted, anchor: .trailing)
        }
        if let typical { plot.fill(Path(CGRect(x: 0, y: y(typical.upperBound), width: w, height: y(typical.lowerBound) - y(typical.upperBound))), with: .color(Goop.Color.trendBand)) }
        plot.fill(Path(roundedRect: CGRect(x: w - step + 3, y: -6, width: max(0, step - 6), height: h + 44), cornerRadius: Goop.Metric.radiusHighlight), with: .color(.white.opacity(0.05)))
        var run: [CGPoint] = []
        func strokeRun(_ points: [CGPoint]) {
            guard points.count >= 2 else { return }
            plot.stroke(GoopPlot.path(points), with: .color(Goop.Color.trendLine.opacity(window.range == .sixMonths ? 0.3 : 1)), lineWidth: window.range == .sixMonths ? 1 : 1.6)
        }
        for (index, date) in dates.enumerated() {
            guard let row = indexed[date], let value = metric.value(row) else { strokeRun(run); run = []; continue }
            let point = CGPoint(x: x(index), y: y(value)), color = metric == .recovery ? Goop.recoveryColor(row.recoveryBand) : Goop.color(metric.color)
            if metric.chart == .line {
                run.append(point)
            } else {
                let width = step * (window.range == .week ? 0.4 : 0.6), baseline = y(max(0, scale.low))
                plot.fill(Path(CGRect(x: point.x - width / 2, y: min(point.y, baseline), width: width, height: abs(baseline - point.y))), with: .color(color.opacity(window.range == .sixMonths ? 0.3 : 1)))
            }
            if window.range == .week { GoopPlot.text(metric.display(value), context: plot, x: point.x, y: point.y - (metric.chart == .line ? 11 : 7), size: 14, color: color, anchor: .bottom) }
        }
        strokeRun(run)
        if metric.chart == .line && window.range != .sixMonths {
            for (index, date) in dates.enumerated() {
                guard let row = indexed[date], let value = metric.value(row) else { continue }
                let radius: CGFloat = window.range == .week ? 5 : 3
                let circle = Path(ellipseIn: CGRect(x: x(index) - radius, y: y(value) - radius, width: radius * 2, height: radius * 2))
                plot.fill(circle, with: .color(Goop.Color.dotHole))
                plot.stroke(circle, with: .color(Goop.Color.trendLine), lineWidth: 1.8)
            }
        }
        switch window.range {
        case .week:
            for (index, date) in dates.enumerated() {
                GoopPlot.text(GoopFormat.dateLabel(date, format: "EEE"), context: plot, x: x(index), y: h + 20, size: 12, color: index == 6 ? .white : Goop.Color.iconMuted, anchor: .bottom, nunito: true, weight: index == 6 ? 700 : 500)
                GoopPlot.text(GoopFormat.dateLabel(date, format: "d"), context: plot, x: x(index), y: h + 36, size: 10.5, color: index == 6 ? .white : Goop.Color.iconMuted, anchor: .bottom, nunito: true)
            }
        case .month:
            for index in stride(from: 0, to: dates.count, by: 7) { GoopPlot.text(GoopFormat.dateLabel(dates[index], format: "MMM d"), context: plot, x: x(index), y: h + 23, size: 11, color: Goop.Color.iconMuted, anchor: .top, nunito: true) }
        case .sixMonths:
            let months = Dictionary(grouping: Array(dates.enumerated()), by: { String($0.element.prefix(7)) })
            for month in months.values {
                let first = month.map(\.offset).min()!, last = month.map(\.offset).max()!
                let cx = (x(first) + x(last)) / 2
                let values = month.compactMap { indexed[$0.element].flatMap { metric.value($0) } }
                if !values.isEmpty {
                    let mean = values.reduce(0, +) / Double(values.count), cy = y(mean), color = Goop.color(metric.color)
                    GoopPlot.line(context: plot, from: CGPoint(x: x(first) - step / 2, y: cy), to: CGPoint(x: x(last) + step / 2, y: cy), color: color, width: 2)
                    GoopPlot.text(metric.display(mean), context: plot, x: cx, y: cy - 8, size: 14, color: color, anchor: .bottom)
                }
                GoopPlot.text(GoopFormat.dateLabel(dates[first], format: "MMM"), context: plot, x: cx, y: h + 23, size: 11, color: Goop.Color.iconMuted, anchor: .top, nunito: true)
            }
        }
    }
}
