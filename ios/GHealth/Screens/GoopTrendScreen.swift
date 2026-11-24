import SwiftUI
import GHealthCore

struct GoopTrendScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var metric: TrendMetricKey
    @State private var window: TrendWindow
    @State private var rows: [DayRow]?
    @State private var prior: Double?
    @State private var failed = false
    @State private var retry = 0
    let root: Bool
    init(metric: TrendMetricKey = .recovery, end: String, root: Bool = false) {
        _metric = State(initialValue: metric)
        _window = State(initialValue: TrendWindow(end: end))
        self.root = root
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoopDetailHeader(title: root ? "TRENDS" : "TREND VIEW", back: root ? nil : { dismiss() })
                GoopMetricPicker(metric: $metric).padding(.top, 14).padding(.horizontal, 16)
                summary.padding(.top, 22).padding(.horizontal, 16)
                if let rows {
                    let summary = window.summary(rows: rows, metric: metric)
                    Text(Insights.trend(metric: metric, length: window.range.length, available: summary.available, average: summary.mean, range: typical)).goop(.body).foregroundStyle(Goop.Color.bodyText).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 24).padding(.horizontal, 18)
                    if summary.available == 0 { GoopPlaceholder(text: "No data in this range").frame(height: 294) }
                    else {
                        if typical != nil { GoopTypicalKey(trend: true).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 22).padding(.horizontal, 18).padding(.bottom, 6) }
                        GoopTrendChart(rows: rows, metric: metric, window: window, typical: typical, dimmed: model.valuesOpacity < 1).padding(.horizontal, 10).padding(.top, typical == nil ? 22 : 0)
                    }
                } else if failed {
                    VStack(spacing: 18) {
                        Text("Needs a connection to your Mac").goop(.bodyMid).foregroundStyle(Goop.Color.caution).frame(maxWidth: .infinity, minHeight: 120)
                        GoopButton(title: "TRY AGAIN") { retry += 1 }
                    }.padding(18).frame(minHeight: 294)
                } else { GoopLoading().frame(height: 294) }
                Color.clear.frame(height: 30)
            }
        }.contentMargins(.bottom, root ? 84 : 0, for: .scrollContent).background(Goop.Gradient.detailBackground.ignoresSafeArea()).foregroundStyle(.white)
            .accessibilityElement(children: .contain).accessibilityIdentifier(root ? "trends-screen" : "trend-view-screen")
            .toolbarVisibility(.hidden, for: .navigationBar, .tabBar).background(InteractivePopEnabler())
            .task(id: "\(model.bundleRevision)-\(window.end)-\(window.range.rawValue)-\(metric.rawValue)-\(retry)") { await load() }
            .onChange(of: model.defaultDate) { _, date in if root { window.end = date } }
    }
    private var typical: ClosedRange<Double>? {
        guard window.end == model.defaultDate, let vitals = model.cached?.snapshot.day.vitals, let vital = metric.vital(in: vitals), let low = vital.rangeLow, let high = vital.rangeHigh, low <= high else { return nil }
        return low...high
    }
    private var summary: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            GoopAverage(metric: metric, mean: rows.flatMap { window.summary(rows: $0, metric: metric).mean }, prior: prior, range: window.range, dimmed: model.valuesOpacity < 1).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 20) {
                GoopRangeSelector(range: $window.range)
                GoopRangeNavigation(window: window, oldestDate: model.oldestDate, defaultDate: model.defaultDate, previous: { window = window.prior }, next: { window = window.next(defaultDate: model.defaultDate) })
            }
        }
    }
    @MainActor private func load() async {
        rows = nil; prior = nil; failed = false
        guard let store = model.trendStore else { failed = true; return }
        let requested = window, key = metric
        do {
            let current = try await store.rows(from: requested.start, to: requested.end)
            try Task.checkCancellation()
            rows = current
        } catch {
            if Task.isCancelled { return }
            if (error as? ClientError) == .unauthorized { model.invalidPairing = true }
            failed = true
            return
        }
        do {
            let previous = try await store.rows(from: requested.prior.start, to: requested.prior.end)
            try Task.checkCancellation()
            prior = requested.prior.summary(rows: previous, metric: key).mean
        } catch {
            if !Task.isCancelled && (error as? ClientError) == .unauthorized { model.invalidPairing = true }
        }
    }
}
