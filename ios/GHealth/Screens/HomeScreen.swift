import SwiftUI
import GHealthCore

struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @State private var activities = false
    @State private var pendingActivity: GoopActivity?
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoopHomeHeader(date: model.selectedDate, defaultDate: model.defaultDate, oldestDate: model.oldestDate, battery: model.cached.flatMap { cached in
                    cached.snapshot.status.device.status == "ok" && !cached.snapshot.freshness.bandSyncStale ? cached.snapshot.status.device.batteryLevel : nil
                }, select: { model.selectedDate = $0 }, more: { model.tab = .more })
                if model.showsOldPairingLink {
                    OldPairingLinkBanner().padding(.horizontal, 16).padding(.top, 8)
                }
                GoopHomeBanners()
                VStack(spacing: 8) {
                    if let undo = model.activityUndo {
                        GoopBanner(text: undo.text, symbol: "trash", symbolColor: Goop.Color.iconMuted,
                                   action: GoopBannerAction(title: "UNDO", identifier: "activity-undo", perform: model.undoActivity))
                            .accessibilityElement(children: .contain).accessibilityIdentifier("activity-undo-banner")
                    }
                    ForEach(Array(model.rollbacks.enumerated()), id: \.element.id) { index, notice in
                        GoopRollbackBanner(notice: notice).accessibilityIdentifier("change-rollback-banner-\(index)")
                    }
                    let waiting = model.pending.filter { $0.state == .waiting }.count
                    if waiting > 0 {
                        GoopBanner(text: ChangeTiming.waitingText(count: waiting), symbol: "arrow.triangle.2.circlepath", symbolColor: Goop.Color.caution)
                            .accessibilityIdentifier("pending-changes-banner")
                    }
                    if model.activity.tooShort { GoopBanner(text: "Too short to save.").accessibilityIdentifier("activity-too-short") }
                    if let error = model.activity.error { GoopBanner(text: error) }
                }.padding(.horizontal, 16).padding(.top, hasChangeBanner ? 8 : 0)
                dayContent
            }
        }
        .contentMargins(.bottom, 84, for: .scrollContent)
        .background(Goop.Gradient.homeBackground.ignoresSafeArea()).foregroundStyle(.white)
        .accessibilityElement(children: .contain).accessibilityIdentifier("today-screen").accessibilityLabel("ghoops")
        .refreshable { await model.refresh(); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        .task(id: "\(model.bundleRevision)-\(model.selectedDate)") { await model.loadDay(model.selectedDate) }
        .sheet(isPresented: $activities, onDismiss: {
            if let activity = pendingActivity { pendingActivity = nil; open(activity) }
        }) {
            GoopSheet(title: model.selectedDate == model.defaultDate ? "TODAY'S ACTIVITIES" : GoopFormat.dateControl(model.selectedDate, defaultDate: model.defaultDate)) {
                if case .loaded(let bundle) = model.bundles[model.selectedDate] {
                    VStack(spacing: 12) {
                        ForEach(model.activityRows(bundle.day)) { row in
                            GoopActivityRow(activity: row, dimmed: model.valuesOpacity < 1) { pendingActivity = row; activities = false }
                        }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("activities-sheet")
        }
    }
    private var hasChangeBanner: Bool {
        model.activityUndo != nil || !model.rollbacks.isEmpty || model.pending.contains { $0.state == .waiting } || model.activity.tooShort || model.activity.error != nil
    }
    @ViewBuilder private var dayContent: some View {
        switch model.bundles[model.selectedDate] {
        case .loaded(let bundle): content(bundle)
        case .failed:
            GoopFullState(title: "Needs a connection to your Mac", text: "Days other than today load from your Mac.", button: "BACK TO TODAY") { model.selectedDate = model.defaultDate }.frame(minHeight: 500)
        case .loading, .none:
            VStack(spacing: 0) {
                GoopWordmark(size: 26, color: Goop.Color.bodyText).frame(width: 64, height: 64 / 3.75).padding(.top, 30).padding(.bottom, 22)
                GoopHomeDials(day: nil, fixture: true) { _ in }
                GoopPair(spacing: 13) {
                    GoopMonitorCard(health: model.cached.map { HealthState($0.snapshot.day.vitals) }, loading: true) {}
                } trailing: {
                    GoopMonitorCard(strain: nil, loading: true) {}
                }.padding(.horizontal, 16).padding(.top, 22)
                heading("My Day", top: 37)
                GoopActivitiesCard(rows: [], loading: true) { _ in }.padding(.horizontal, 16).padding(.top, 18)
                heading("My Dashboard", top: 34)
                VStack(spacing: 10) {
                    ForEach([TrendMetricKey.hrv, .sleepPerformance, .hours, .restingHR, .steps]) { metric in GoopMetricRow(metric: metric, value: nil, windowDays: nil, tile: true) { model.push(.trend(metric: metric, end: model.selectedDate)) } }
                }.padding(.horizontal, 16).padding(.top, 14)
            }
        }
    }
    private func content(_ bundle: DayBundle) -> some View {
        VStack(spacing: 0) {
            GoopWordmark(size: 26, color: Goop.Color.bodyText).frame(width: 64, height: 64 / 3.75).padding(.top, 30).padding(.bottom, 22)
            GoopHomeDials(pending: model.sleepScores(on: bundle.day.date), updating: model.sleepScores(on: bundle.day.date, delayed: true), day: bundle.day, fixture: model.isFixture, dimmed: model.valuesOpacity < 1) { score in
                model.push(score == .sleep ? .sleep : score == .recovery ? .recovery : .strain)
            }
            GoopPair(spacing: 13) {
                GoopMonitorCard(health: HealthState(bundle.day.vitals), constants: bundle.day.scoreConstants, dimmed: model.valuesOpacity < 1) { model.tab = .health }
            } trailing: {
                GoopMonitorCard(strain: bundle.day.strain, dimmed: model.valuesOpacity < 1) { model.push(.strain) }
            }.padding(.horizontal, 16).padding(.top, 22)
            heading("My Day", top: 37)
            activitiesCard(bundle).padding(.horizontal, 16).padding(.top, 18)
            heading("My Dashboard", top: 34).padding(.bottom, 4)
            VStack(spacing: 10) {
                tile(.hrv, value: bundle.day.vitals.metrics.hrvRmssd, day: bundle.day)
                let scores = model.sleepScores(on: bundle.day.date)
                let sleep = SleepScore(bundle.day)
                tile(.sleepPerformance, value: scores.contains("sleep") ? nil : sleep.performance.value.map(Double.init),
                     status: scores.contains("sleep") && model.sleepScores(on: bundle.day.date, delayed: true).contains("sleep") ? "UPDATING" : nil,
                     day: bundle.day, comparisonKey: sleep.comparisonKey)
                tile(.hours, value: bundle.day.sleep.asleepMinutes.map(Double.init), day: bundle.day)
                tile(.restingHR, value: bundle.day.vitals.metrics.restingHr, day: bundle.day)
                tile(.steps, value: bundle.day.activity.steps.status == .available ? bundle.day.activity.steps.value : nil, hint: bundle.day.activity.steps.status == .available ? "" : ReasonText.metric(bundle.day.activity.steps.status), day: bundle.day)
            }.padding(.horizontal, 16).padding(.top, 10)
        }
    }
    private func activitiesCard(_ bundle: DayBundle) -> some View {
        let today = model.selectedDate == model.defaultDate
        let start: (() -> Void)? = today ? { model.openActivityPicker() } : nil
        let canAdd = today || AddDraft.days(defaultDate: model.defaultDate, limits: model.editLimits).contains(model.selectedDate)
        let add: (() -> Void)? = canAdd && model.activity.session == nil ? { model.openAddActivity(day: model.selectedDate) } : nil
        return GoopActivitiesCard(rows: model.activityRows(bundle.day), title: today ? "TODAY'S ACTIVITIES" : "ACTIVITIES", limit: 3, dimmed: model.valuesOpacity < 1, expand: { activities = true }, live: today ? model.activity : nil, start: start, add: add, action: open)
    }
    private func heading(_ text: String, top: CGFloat) -> some View {
        Text(text).goop(.heading).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, top).accessibilityAddTraits(.isHeader)
    }
    private func tile(_ metric: TrendMetricKey, value: VitalMetric, day: Day) -> some View {
        tile(metric, value: value.status == .available ? value.value : nil, hint: value.status == .available ? "" : ReasonText.metric(value.status), day: day)
    }
    private func tile(_ metric: TrendMetricKey, value: Double?, hint: String = "", status: String? = nil, day: Day, comparisonKey: String? = nil) -> some View {
        GoopMetricRow(metric: metric, value: value, mean: day.comparison?.metrics[comparisonKey ?? metric.comparisonKey]?.mean, windowDays: day.comparison?.windowDays, tile: true, hint: hint, status: status, dimmed: model.valuesOpacity < 1) {
            model.push(.trend(metric: metric, end: model.selectedDate))
        }
    }
    private func open(_ activity: GoopActivity) {
        switch activity.kind {
        case .sleep: model.push(.sleep)
        case .workout(let workout): model.push(.workout(id: workout.id, date: model.selectedDate))
        case .nap: break
        }
    }
}

private struct GoopHomeBanners: View {
    @Environment(AppModel.self) private var model
    @State private var dismissed: Set<String> = []
    var body: some View {
        VStack(spacing: 8) {
            if let cached = model.cached {
                let snapshot = cached.snapshot
                ForEach(flags, id: \.code) { flag in banner(flag.message, id: flag.code, symbol: "heart") }
                if let error = model.error { banner(error, id: "network", symbol: "arrow.clockwise") }
                if model.now.timeIntervalSince(cached.meta.fetchedAt) > 2 * 3600 {
                    GoopBanner(text: "Updated \(Format.relative(cached.meta.fetchedAt, now: model.now))")
                }
                if snapshot.freshness.collectorStale {
                    banner("Your Mac last collected data \(Format.relative(snapshot.freshness.collectedAt, now: model.now))", id: "collector", symbol: "arrow.clockwise")
                }
                if snapshot.freshness.bandSyncStale {
                    banner("Your band last synced \(Format.relative(snapshot.freshness.deviceLastSyncAt, now: model.now)). Open the Fitbit app to sync.", id: "device", symbol: "arrow.clockwise")
                }
            }
        }.padding(.horizontal, 16).padding(.top, hasVisibleBanner ? 12 : 0)
    }
    private var flags: [HealthFlag] {
        guard case .loaded(let bundle) = model.bundles[model.selectedDate] else { return [] }
        return bundle.day.healthFlags.filter { $0.severity == "attention" }
    }
    private var hasVisibleBanner: Bool {
        guard let cached = model.cached else { return false }
        return flags.contains { !dismissed.contains($0.code) }
            || (model.error != nil && !dismissed.contains("network"))
            || model.now.timeIntervalSince(cached.meta.fetchedAt) > 2 * 3600
            || (cached.snapshot.freshness.collectorStale && !dismissed.contains("collector"))
            || (cached.snapshot.freshness.bandSyncStale && !dismissed.contains("device"))
    }
    @ViewBuilder private func banner(_ text: String, id: String, symbol: String) -> some View {
        if !dismissed.contains(id) { GoopBanner(text: text, symbol: symbol, dismiss: { dismissed.insert(id) }) }
    }
}
