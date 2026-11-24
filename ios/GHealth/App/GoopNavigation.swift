import SwiftUI
import GHealthCore

enum Route: Hashable {
    case recovery, strain, sleep
    case workout(id: String, date: String)
    case trend(metric: TrendMetricKey, end: String)
}

struct DayBundle: Sendable {
    let day: Day
    let sleep: Sleep
    let workouts: [Workout]
}

enum DayBundleState {
    case loading
    case loaded(DayBundle)
    case failed(Error)
}

struct OfflineDaysClient: DaysFetching {
    func days(from: String, to: String) async throws -> Days { throw ClientError.offline }
}

struct GoopTabs: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "house", value: GoopTab.home) { stack(path: $model.homePath, tab: .home) }
            Tab("Health", systemImage: "heart", value: GoopTab.health) { stack(path: $model.healthPath, tab: .health) }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: GoopTab.trends) { stack(path: $model.trendsPath, tab: .trends) }
            Tab("More", systemImage: "line.3.horizontal", value: GoopTab.more) { stack(path: $model.morePath, tab: .more) }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.currentPath.isEmpty { GoopTabBar(selected: $model.tab) }
        }
    }
    private func stack(path: Binding<[Route]>, tab: GoopTab) -> some View {
        NavigationStack(path: path) {
            Group {
                if model.cached == nil && tab != .more { GoopNoDataState() }
                else if tab == .home { HomeScreen() }
                else if tab == .health { GoopHealthScreen() }
                else if tab == .trends { GoopTrendScreen(end: model.defaultDate, root: true) }
                else { GoopMoreScreen() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .recovery: RecoveryScreen()
                case .strain: StrainScreen()
                case .sleep: SleepScreen()
                case .workout(let id, let date): WorkoutScreen(id: id, date: date)
                case .trend(let metric, let end): GoopTrendScreen(metric: metric, end: end)
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar, .tabBar)
        }
    }
}

struct GoopDayContent<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: (DayBundle) -> Content
    var body: some View {
        Group {
            switch model.bundles[model.selectedDate] {
            case .loaded(let bundle): content(bundle)
            case .failed: GoopFullState(title: "Needs a connection to your Mac", text: "Days other than today load from your Mac.", button: "BACK TO TODAY") { model.selectedDate = model.defaultDate }.frame(minHeight: 500)
            case .loading, .none: GoopLoading().frame(maxHeight: .infinity)
            }
        }
        .task(id: "\(model.bundleRevision)-\(model.selectedDate)") { await model.loadDay(model.selectedDate) }
    }
}

struct GoopNoDataState: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        GoopFullState(title: "No data yet", text: "Connect to your Mac to fetch your first snapshot." + (model.error.map { "\n" + $0 } ?? ""), button: "TRY AGAIN") { Task { await model.refresh() } }
            .frame(maxHeight: .infinity).background(Goop.Gradient.homeBackground.ignoresSafeArea())
            .task { await model.refresh() }
    }
}

struct InteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PopController { PopController() }
    func updateUIViewController(_ controller: PopController, context: Context) { controller.enablePop() }
    final class PopController: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enablePop()
        }
        func enablePop() {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
