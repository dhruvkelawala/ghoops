import SwiftUI
import GHealthCore

struct GoopDetailPage<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let identifier: String
    var info: (() -> Void)?
    @ViewBuilder var content: (DayBundle?) -> Content
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoopDetailHeader(title: GoopFormat.dateControl(model.selectedDate, defaultDate: model.defaultDate), back: { dismiss() }, trailing: info.map { .info($0) })
                content(bundle)
                Color.clear.frame(height: 30)
            }
        }.background(Goop.Gradient.detailBackground.ignoresSafeArea()).foregroundStyle(.white)
            .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
            .toolbarVisibility(.hidden, for: .navigationBar, .tabBar).background(InteractivePopEnabler())
            .task(id: "\(model.bundleRevision)-\(model.selectedDate)") { await model.loadDay(model.selectedDate) }
    }
    private var bundle: DayBundle? {
        if case .loaded(let bundle) = model.bundles[model.selectedDate] { return bundle }
        return nil
    }
}

struct GoopDayPlaceholder: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if case .failed = model.bundles[model.selectedDate] {
            GoopPlaceholder(text: "Needs a connection to your Mac")
        } else { GoopLoading() }
    }
}

struct GoopWeeklySection: View {
    @Environment(AppModel.self) private var model
    let metric: TrendMetricKey
    @State private var rows: [DayRow]?
    @State private var failed = false
    var body: some View {
        VStack(spacing: 14) {
            Text("Weekly Trends").goop(.heading).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            Group {
                if let rows {
                    GoopWeeklyCard(rows: rows, metric: metric, end: model.selectedDate, dimmed: model.valuesOpacity < 1) { model.push(.trend(metric: metric, end: model.selectedDate)) }
                } else if failed { GoopCard { GoopPlaceholder(text: "Needs a connection to your Mac") } }
                else { GoopCard { GoopLoading() } }
            }
        }.padding(.horizontal, 16).padding(.top, 30)
            .task(id: "\(model.bundleRevision)-\(model.selectedDate)") {
                rows = nil; failed = false
                guard let store = model.trendStore else { failed = true; return }
                do { rows = try await store.rows(from: GoopFormat.addingDays(-6, to: model.selectedDate), to: model.selectedDate) }
                catch { failed = true }
            }
    }
}

struct GoopSheetSection<Trailing: View, Content: View>: View {
    let title: String
    let trailing: Trailing
    let content: Content
    init(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased()).goop(.labelCard).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
            }
            content.goop(.bodyMid).foregroundStyle(Goop.Color.legendText)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 24)
    }
}

extension GoopSheetSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) { self.init(title: title, trailing: { EmptyView() }, content: content) }
}

/// A key–value row in an info sheet. Rows here are not tappable, so they sit 7pt apart rather than at 44pt.
struct GoopSheetRow: View {
    let label: String
    var note: String? = nil
    let value: String
    var unit: String? = nil
    var body: some View {
        HStack(alignment: note == nil ? .firstTextBaseline : .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).goop(.bodyMid)
                if let note { Text(note).goop(.rowNote).foregroundStyle(Goop.Color.text2) }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).goop(.valueMid).foregroundStyle(value == "—" ? Goop.Color.text2 : Goop.Color.text1)
                if let unit, value != "—" { Text(unit).goop(.unitSmall).foregroundStyle(Goop.Color.text2) }
            }.multilineTextAlignment(.trailing)
        }.padding(.vertical, 7).accessibilityElement(children: .combine)
    }
}
