import SwiftUI
import GHealthCore

struct WorkoutScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var rating = false
    let id: String
    let date: String
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let workout {
                    header(workout)
                    if let notice = model.rollbacks.first(where: { model.rollbackTargets[$0.id]?.contains(id) == true }) {
                        GoopRollbackBanner(notice: notice).padding(.horizontal, 16).padding(.top, 12).accessibilityIdentifier("change-rollback-banner")
                    }
                    if model.pending.contains(where: { $0.state == .waiting && $0.targets.contains(id) }) {
                        GoopBanner(text: "Saved on your phone. It will be sent to your Mac when it can be reached.", symbol: "arrow.triangle.2.circlepath", tone: .strain)
                            .padding(.horizontal, 16).padding(.top, 12).accessibilityIdentifier("change-waiting-banner")
                    } else if let message = model.activity.message(for: workout, server: bundle?.workouts.first { $0.id == id }) {
                        GoopBanner(text: message, symbol: "arrow.triangle.2.circlepath", tone: .strain)
                            .padding(.horizontal, 16).padding(.top, 12).accessibilityIdentifier("activity-save-banner")
                    }
                    HStack(alignment: .top, spacing: 16) {
                        stat("ACTIVITY STRAIN", value: workout.strain, metric: .strain, workout: workout, color: Goop.Color.strain)
                        stat("AVERAGE HR", value: workout.avgHrBpm.map(Double.init), metric: .restingHR, workout: workout, color: .white)
                    }.padding(.top, 18).padding(.horizontal, 16).padding(.bottom, 4)
                    GoopWorkoutChart(workout: workout, dimmed: valuesOpacity < 1).padding(.top, 14).padding(.horizontal, 16)
                    HStack {
                        Text("MAX HR").goop(.labelSmall).foregroundStyle(Goop.Color.iconMuted)
                        Text(GoopFormat.number(workout.peakHrBpm.map(Double.init))).goop(.valueSmall).opacity(valuesOpacity)
                        Spacer()
                        Text("DURATION").goop(.labelSmall).foregroundStyle(Goop.Color.textSoft)
                        Text(GoopFormat.duration(Int(workout.elapsedMinutes.rounded()))).goop(.valueSmall).opacity(valuesOpacity)
                    }.padding(.top, 14).padding(.horizontal, 18).padding(.bottom, 4)
                    ratingRow(workout)
                    VStack(spacing: 0) { GoopZoneRows(zones: workout.zonesMinutes, resting: bundle?.day.strain.restingHrBpm, maximum: bundle?.day.strain.maxHrBpm, floors: bundle?.day.scoreConstants?.strain.zonesHrr, dimmed: valuesOpacity < 1) }.padding(.horizontal, 16)
                    if let notes = workout.notes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES").goop(.labelSmall).foregroundStyle(Goop.Color.iconMuted)
                            Text(notes).goop(.bodyMid).foregroundStyle(Goop.Color.bodyText).accessibilityIdentifier("workout-notes")
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 22).padding(.horizontal, 18)
                    }
                    footnote(workout).padding(.top, 16).padding(.horizontal, 18)
                    if saveMessage(workout) != nil {
                        GoopButton(title: "DELETE ACTIVITY", role: .destructive, identifier: "activity-delete") { deleting = true }
                            .padding(.horizontal, 16).padding(.bottom, 16)
                    }
                    if let deleteError { Text(deleteError).goop(.bodyMid).foregroundStyle(Goop.Color.caution).padding(16) }
                } else {
                    GoopDetailHeader(title: "WORKOUT", back: { dismiss() })
                    if case .loading = model.bundles[date] { GoopLoading() }
                    else { GoopPlaceholder(text: "Needs a connection to your Mac") }
                }
                Color.clear.frame(height: 30)
            }
            .sheet(isPresented: $rating) {
                if let workout { EffortRatingSheet(workout: workout).environment(model) }
            }
        }.background(Goop.Gradient.detailBackground.ignoresSafeArea()).foregroundStyle(.white)
            .accessibilityElement(children: .contain).accessibilityIdentifier("workout-screen")
            .toolbarVisibility(.hidden, for: .navigationBar, .tabBar).background(InteractivePopEnabler())
            .goopDestructiveAlert("Delete this activity?", isPresented: $deleting, verb: "Delete", message: "This removes it from ghoops on your phone and your Mac.") {
                guard let workout else { return }
                Task {
                    do {
                        try await model.activity.delete(workout: workout)
                        deleteError = nil
                        if let cached = model.serverCached { var snapshot = cached.snapshot; snapshot.workouts.workouts.removeAll { $0.id == id }; snapshot.day.workouts.removeAll { $0.id == id }; model.applyServerSnapshot(CachedSnapshot(snapshot: snapshot, meta: cached.meta)) }
                        dismiss()
                        await model.refresh()
                    } catch { deleteError = ErrorCopy.message(error, context: .deleteActivity, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) }
                }
            }
            .sheet(isPresented: $editing) {
                if let workout {
                    EditSheet(workout: workout, workouts: bundle?.workouts ?? []) { savedID in
                        if savedID != id { model.replaceWorkout(id: savedID, date: workout.cycleDate) }
                    }.environment(model)
                }
            }
            .task(id: "\(model.bundleRevision)-\(date)") { await model.loadDay(date) }
            .task {
                guard model.ratingPrompt == id else { return }
                model.ratingPrompt = nil
                try? await Task.sleep(for: .milliseconds(350))
                if let workout, canRate(workout) { rating = true }
            }
            #if DEBUG
            .task {
                if ["edit", "sport", "merge", "delete", "offline"].contains(model.editFixture ?? "") || model.parityFixture == "sport" {
                    try? await Task.sleep(for: .milliseconds(450)); editing = true
                }
            }
            #endif
    }
    private var bundle: DayBundle? {
        if case .loaded(let bundle) = model.bundles[date] { return bundle }
        return nil
    }
    private var valuesOpacity: Double { model.lockedWorkouts.contains(id) ? 1 : model.valuesOpacity }
    private var workout: Workout? { model.displayedWorkouts(bundle?.workouts ?? model.cached?.snapshot.workouts.workouts.filter { $0.cycleDate == date } ?? []).first { $0.id == id } }
    private func header(_ workout: Workout) -> some View {
        GoopWorkoutHeader(symbol: workout.exerciseType.flatMap { type in ActivitySport.all.first { $0.id == type }?.symbol } ?? GoopActivity.workoutSymbol(workout),
                          title: workout.category == "detected" ? "DETECTED EFFORT" : (workout.displayName ?? "Workout").uppercased(),
                          subtitle: "\(GoopFormat.time(workout.start)) to \(GoopFormat.time(workout.end))" + subtitleSuffix(workout),
                          back: { dismiss() }, trailing: canEdit(workout) ? .edit { editing = true } : nil)
    }
    private func stat(_ title: String, value: Double?, metric: TrendMetricKey, workout: Workout, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).goop(.labelSmall).foregroundStyle(color)
            HStack(spacing: 8) {
                let text = metric == .strain ? GoopFormat.number(value, decimals: 1) : GoopFormat.number(value)
                Text(text).goop(.valueStat).foregroundStyle(Goop.missing(text) ? Goop.Color.text2 : color)
                if let value, let mean = mean(workout, metric: metric) {
                    GoopChip(text: GoopFormat.number(abs(value - mean), decimals: metric == .strain ? 1 : 0), direction: GoopFormat.direction(value, mean: mean, metric: metric), metric: .strain)
                }
            }.opacity(valuesOpacity)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func mean(_ workout: Workout, metric: TrendMetricKey) -> Double? {
        let fetched = model.bundles.values.flatMap { state -> [Workout] in
            if case .loaded(let bundle) = state { return bundle.workouts }
            return []
        }
        let loaded = Dictionary(((model.cached?.snapshot.workouts.workouts ?? []) + fetched).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let values = loaded.values.filter { $0.id != workout.id && $0.category == workout.category }.compactMap { metric == .strain ? $0.strain : $0.avgHrBpm.map(Double.init) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    /// HOW HARD IT FELT (effort-rating-spec.md §3.1): a button while the session can be rated, its value after that.
    @ViewBuilder private func ratingRow(_ workout: Workout) -> some View {
        if showsRating(workout) {
            let value = workout.rpe.map(EffortScale.rowValue)
            let spoken = "How hard it felt, " + (workout.rpe.map(EffortScale.spoken) ?? "not rated")
            Group {
                if canRate(workout) {
                    Button { rating = true } label: {
                        GoopRow("HOW HARD IT FELT", disclosure: .push) {
                            if let value { GoopRowValue(text: value) } else { Text("Rate").goop(.bodySmall).foregroundStyle(Goop.Color.text2) }
                        }
                    }.buttonStyle(.plain).accessibilityLabel(spoken)
                } else if let value {
                    GoopRow("HOW HARD IT FELT", value: value).accessibilityElement(children: .ignore).accessibilityLabel(spoken)
                }
            }.accessibilityIdentifier("workout-rating-row").padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        }
    }
    private func showsRating(_ workout: Workout) -> Bool {
        GoopFeature.effortRating && EffortScale.supported(model.editLimits) && workout.kind != "detected"
            && model.activity.localEntry(workout.id)?.uploadState != .rejected
    }
    private func canRate(_ workout: Workout) -> Bool {
        showsRating(workout) && EditLimits.editable(cycleDate: workout.cycleDate, defaultDate: model.defaultDate, limits: model.editLimits) && workout.cycleDate <= model.defaultDate
    }
    private func saveMessage(_ workout: Workout) -> String? { model.activity.message(for: workout, server: bundle?.workouts.first { $0.id == id }) }
    private func canEdit(_ workout: Workout) -> Bool {
        EditLimits.editable(cycleDate: workout.cycleDate, defaultDate: model.defaultDate, limits: model.editLimits) && workout.cycleDate <= model.defaultDate && saveMessage(workout) == nil && !model.lockedWorkouts.contains(workout.id)
    }
    private func subtitleSuffix(_ workout: Workout) -> String {
        if model.changeStatus(for: workout.id) == .saving { return " · Saving to your Mac" }
        if workout.kind != "detected" && workout.edited == true { return " · Edited" }
        if workout.kind == "goop" { return workout.origin == "added" ? " · Added in ghoops" : " · Started in ghoops" }
        return ""
    }
    private func footnote(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let limits = model.editLimits,
               !EditLimits.editable(cycleDate: workout.cycleDate, defaultDate: model.defaultDate, limits: limits),
               workout.cycleDate <= model.defaultDate, saveMessage(workout) == nil, !model.lockedWorkouts.contains(workout.id) {
                Text(limits.horizonDays == 1 ? "Only today's activities can be edited." : "Only activities from the last \(limits.horizonDays) days can be edited.")
                    .accessibilityIdentifier("workout-edit-horizon")
            }
            if let provenance = provenance(workout) { Text(provenance).accessibilityIdentifier("workout-edited-footnote") }
            if ["combat", "strength", "detected"].contains(workout.category) || workout.kind == "detected" {
                GoopFootnote.wristHeartRate
            }
            Text("Zones use heart rate reserve (resting \(GoopFormat.number(bundle?.day.strain.restingHrBpm.map(Double.init))), max \(GoopFormat.number(bundle?.day.strain.maxHrBpm.map(Double.init)))). Change max HR on the Mac with ghoops config.")
            if workout.kind == "recorded", workout.edited != true, let provider = workout.provider {
                Text("Fitbit says: avg \(GoopFormat.number(provider.avgHrBpm.map(Double.init))) bpm · \(GoopFormat.number(provider.caloriesKcal)) kcal · \(GoopFormat.number(provider.activeZoneMinutes.map(Double.init))) active zone minutes.")
            }
            if let coverage = workout.hrCoverage, let confidence = workout.confidence, confidence != .high { Text("Based on \(GoopFormat.number(coverage * 100))% heart-rate coverage.") }
        }.goop(.bodySmall).foregroundStyle(Goop.Color.iconMuted).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func provenance(_ workout: Workout) -> String? {
        if workout.kind == "detected" { return "Not logged as a workout. ghoops found a stretch of high heart rate. Edit it to give it a sport." }
        guard let original = workout.original else { return nil }
        let name = original.displayName ?? original.exerciseType.map { ActivitySport.sport($0).name } ?? "Workout"
        let entry = "\(name), \(GoopFormat.time(original.start)) to \(GoopFormat.time(original.end))"
        if workout.edited == true {
            if workout.kind == "goop" { return "Edited in ghoops. First saved as \(entry)." }
            let merged = workout.merged.filter { $0.kind == "recorded" }.sorted { $0.start < $1.start }
            let entries = [entry] + merged.map { "\($0.displayName ?? "Workout"), \(GoopFormat.time($0.start)) to \(GoopFormat.time($0.end))" }
            return "Edited in ghoops. Google Health keeps the band's \(merged.isEmpty ? "version" : "versions"): \(entries.joined(separator: "; "))."
        }
        if workout.kind == "recorded", workout.exerciseType != original.exerciseType {
            return "Shown as \(workout.displayName ?? "Workout") by your ghoops config on the Mac. Google Health keeps the band's label: \(name)."
        }
        return nil
    }
}
