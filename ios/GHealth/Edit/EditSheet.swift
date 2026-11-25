import SwiftUI
import GHealthCore

struct EditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let workout: Workout
    let workouts: [Workout]
    @State private var draft: EditDraft?
    @State private var sportStep = false
    @State private var mergeCandidate: Workout?
    @State private var selection: String?
    @State private var suggestion: WorkoutSuggestion?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var deleting = false
    @State private var restoring = false
    @State private var namingID = UUID().uuidString.lowercased()
    var onSaved: (String) -> Void
    private var error: String? { loadError ?? saveError }
    private var loadFailed: Bool { loadError != nil }
    private var sport: String { draft?.sport ?? workout.exerciseType ?? "OTHER" }
    private var name: String { ActivitySport.all.first { $0.id == sport }?.name ?? workout.displayName ?? "Activity" }
    private var window: ActivityWindow { draft?.window ?? ActivityWindow(start: workout.start, end: workout.end) }
    var body: some View {
        ScrollViewReader { proxy in
            GoopTaskSheet(title: sportStep ? "SPORT" : mergeCandidate != nil ? "MERGE" : "EDIT ACTIVITY", back: sportStep || mergeCandidate != nil ? { sportStep = false; mergeCandidate = nil } : nil, closeIdentifier: "edit-close", commit: commit) {
                VStack(spacing: 0) {
                    if let error { GoopBanner(text: error, symbol: "exclamationmark.triangle", tone: .caution).padding(.top, 4).padding(.bottom, 12).accessibilityIdentifier("edit-error") }
                    Group {
                        if sportStep {
                            ActivitySportStep(selection: $selection, workout: workout, currentSport: draft?.sport, suggestion: suggestion, workouts: model.activity.recentWorkouts, defaultDate: model.defaultDate, aliases: model.cached?.snapshot.scoreConfig?.sportAliases ?? [:])
                        } else if let draft, let mergeCandidate { mergeContent(draft, candidate: mergeCandidate) }
                        else { editContent }
                    }.disabled(loadFailed).opacity(loadFailed ? Goop.Opacity.disabled : 1)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("edit-sheet")
                .task {
                    await load()
                    #if DEBUG
                    if model.editFixture == "delete" {
                        try? await Task.sleep(for: .milliseconds(350))
                        proxy.scrollTo("edit-delete", anchor: .bottom)
                        try? await Task.sleep(for: .milliseconds(350))
                        deleting = true
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active && loadFailed { Task { await load() } } }
                .goopDestructiveAlert("Delete this activity?", isPresented: $deleting, verb: "Delete", message: "This removes \(name) from ghoops on your phone and your Mac." + (workout.kind == "recorded" ? " Google Health keeps the band's record." : "")) { mutate(.delete) }
                .alert("Restore the band's version?", isPresented: $restoring) {
                    Button("Cancel", role: .cancel) {}
                    Button("Restore") { mutate(.restore) }
                } message: { Text("This removes your edits and notes for \(name) from ghoops on your Mac. Anything merged into it comes back.") }
        }
    }
    private var commit: GoopCommit {
        if sportStep {
            let chosen = selection.flatMap { type in ActivitySport.all.first { $0.id == type } }
            let title = chosen?.name ?? workout.original?.displayName ?? "Activity"
            return GoopCommit(title: "USE \(title.uppercased())", symbol: chosen?.symbol ?? "checkmark", identifier: "edit-sport-use", enabled: selection != nil && !loadFailed, accessibilityLabel: "Use \(title)") {
                draft?.sport = selection; sportStep = false
            }
        }
        if mergeCandidate != nil {
            return GoopCommit(title: "MERGE INTO ONE \(name.uppercased())", symbol: "arrow.triangle.merge", identifier: "edit-merge-commit", enabled: !loadFailed, accessibilityLabel: "Merge into one \(name)") { mutate(.merge) }
        }
        let selected = workout.kind != "detected" || draft?.sport != nil
        return GoopCommit(title: "SAVE \(selected ? name.uppercased() : "ACTIVITY")", symbol: "checkmark", identifier: "edit-save", enabled: draft != nil && selected && (draft?.hasChanges == true || workout.kind == "detected") && !loadFailed, accessibilityLabel: "Save \(selected ? name : "activity")") { mutate(.save) }
    }
    private var editContent: some View {
        VStack(spacing: 0) {
            Button { selection = draft?.sport; sportStep = true } label: { GoopRow("SPORT", value: workout.kind == "detected" && draft?.sport == nil ? "Choose" : name, disclosure: .push) }.accessibilityIdentifier("edit-sport-row").padding(.top, 4)
            GoopEditValues(value: draft?.estimate, prior: draft?.prior).padding(.top, 24)
            GoopFootnote(text: "Editing changes this activity, not your Day Strain.").padding(.top, 8)
            Group {
                if let draft { GoopWindowChart(heartRate: draft.heartRate, window: draft.window, bounds: draft.bounds, originalWindows: originalWindows, bandStrips: draft.bandStrips, pauses: workout.pauses) { self.draft?.window = $0 } }
                else if loadFailed { GoopPlaceholder(text: "Needs a connection to your Mac").frame(height: 230) }
                else { GoopLoading().frame(height: 230) }
            }.padding(.top, 22)
            if workout.kind == "recorded", let original = workout.original { GoopBandLegend(times: "\(GoopFormat.time(original.start)) to \(GoopFormat.time(original.end))").padding(.top, 14) }
            Text("Drag a dashed edge, or set the times below.").goop(.bodySmall).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            VStack(spacing: 8) {
                if let draft {
                    GoopTimeRow("START", time: time(start: true), range: draft.bounds.startRange(end: window.end), identifier: "edit-start", date: ActivityTime.dateLabels(window)?.start)
                    GoopTimeRow("END", time: time(start: false), range: draft.bounds.endRange(start: window.start), identifier: "edit-end", date: ActivityTime.dateLabels(window)?.end)
                }
                if let previous = draft?.previous { mergeRow(previous, previous: true) }
                if let next = draft?.next { mergeRow(next, previous: false) }
            }.padding(.top, 24)
            GoopSectionLabel(title: "NOTES").padding(.top, 24).padding(.bottom, 6)
            GoopNotesField(text: Binding(get: { draft?.notes ?? workout.notes ?? "" }, set: { draft?.notes = $0 }), limit: draft?.limits?.notesMaxChars)
            Text(workout.kind == "recorded" ? "Edits stay on your Mac. Google Health keeps the band's record." : workout.kind == "goop" ? "Edits stay on your Mac." : "Saving adds this to ghoops on your Mac. Google Health is not changed.")
                .goop(.bodySmall).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 24)
            if workout.kind == "recorded" && workout.edit != nil { GoopButton(title: "RESTORE BAND'S VERSION", identifier: "edit-restore") { restoring = true }.accessibilityLabel("Restore band's version").padding(.top, 12) }
            if workout.kind != "detected" { GoopButton(title: "DELETE ACTIVITY", role: .destructive, identifier: "edit-delete") { deleting = true }.accessibilityLabel("Delete activity").id("edit-delete") }
            Color.clear.frame(height: 20)
        }
    }
    private func mergeRow(_ candidate: Workout, previous: Bool) -> some View {
        Button { mergeCandidate = candidate } label: { GoopRow(previous ? "MERGE WITH PREVIOUS" : "MERGE WITH NEXT", value: "\(candidate.displayName ?? "Detected effort") \(GoopFormat.time(candidate.start))", disclosure: .push) }.accessibilityIdentifier(previous ? "edit-merge-previous" : "edit-merge-next")
    }
    private var originalWindows: [ActivityWindow] {
        [ActivityWindow(start: workout.original?.start ?? workout.start, end: workout.original?.end ?? workout.end)] + workout.merged.map { ActivityWindow(start: $0.start, end: $0.end) }
    }
    private func mergeContent(_ draft: EditDraft, candidate: Workout) -> some View {
        let body = draft.mergeBody(candidate)
        let union = ActivityWindow(start: body.start!, end: body.end!)
        let strips = draft.bandStrips + (candidate.kind == "recorded" ? candidate.original.map { [$0] } ?? [] : [])
        let prior = candidate.start < workout.start
        return VStack(spacing: 0) {
            Text(mergeExplanation(candidate)).goop(.bodyMid).foregroundStyle(Goop.Color.legendText).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            GoopEditValues(value: WindowEstimator(heartRate: draft.heartRate).estimate(start: union.start, end: union.end, pauses: workout.pauses), prior: draft.estimate).padding(.top, 24)
            GoopWindowChart(heartRate: draft.heartRate, window: union, originalWindows: originalWindows + [ActivityWindow(start: candidate.start, end: candidate.end)], bandStrips: strips, editable: false) { _ in }.padding(.top, 22)
            if !strips.isEmpty { GoopBandLegend(title: strips.count > 1 ? "BAND'S VERSIONS" : "BAND'S VERSION").padding(.top, 14) }
            VStack(spacing: 8) {
                GoopRow("THIS ACTIVITY", value: "\(name), \(GoopFormat.time(window.start)) to \(GoopFormat.time(window.end))")
                GoopRow(prior ? "PREVIOUS ACTIVITY" : "NEXT ACTIVITY", value: "\(candidate.kind == "detected" ? "Detected effort" : candidate.displayName ?? "Activity"), \(GoopFormat.time(candidate.start)) to \(GoopFormat.time(candidate.end))")
            }.padding(.top, 24)
        }
    }
    private func mergeExplanation(_ candidate: Workout) -> String {
        let previous = candidate.start < workout.start
        let gap = Int((previous ? window.start.timeIntervalSince(candidate.end) : candidate.start.timeIntervalSince(window.end)) / 60)
        let times = "from \(GoopFormat.time(candidate.start)) to \(GoopFormat.time(candidate.end))"
        let between = gap <= 0 ? "" : gap == 1 ? " and the minute between" : " and the \(gap) minutes between"
        if candidate.kind == "detected" { return "Merging adds the effort ghoops found \(times)\(between)." }
        let activity = "\(candidate.displayName ?? "Activity") \(times)"
        if candidate.kind == "goop" { return "Merging adds \(activity), saved in ghoops\(between.isEmpty ? "" : "," + between)." }
        if workout.kind == "recorded" { return "The band split this session in two. Merging adds its \(activity)\(between)." }
        return "Merging adds \(activity)\(between)."
    }
    private func time(start: Bool) -> Binding<Date> {
        Binding(get: { start ? window.start : window.end }, set: { value in
            guard let bounds = draft?.bounds else { return }
            let date = ActivityTime.picker(value, within: bounds.span)
            if start { draft?.window.moveStart(to: date, bounds: bounds, pauses: workout.pauses) }
            else { draft?.window.moveEnd(to: date, bounds: bounds, pauses: workout.pauses) }
        })
    }
    private func load() async {
        guard draft == nil else { return }
        do {
            guard let api = model.editAPI else { throw ClientError.unauthorized }
            let limits = model.editLimits
            let hr: HeartRateBody
            if let limits {
                let fetch = EditDraft.fetchSpan(for: workout, workouts: workouts, limits: limits, now: model.now)
                hr = try await api.heartRate(start: fetch.start, end: fetch.end)
            } else { hr = try await api.heartRate(date: workout.cycleDate) }
            draft = EditDraft(workout: workout, workouts: workouts.filter { !model.lockedWorkouts.contains($0.id) }, heartRate: hr, limits: limits, now: model.now)
            model.activity.recentWorkouts = model.displayedWorkouts(model.cached?.snapshot.workouts.workouts ?? workouts)
            await model.loadActivityHistory()
            if workout.kind == "detected" {
                suggestion = workout.suggested
                draft?.sport = nil; selection = suggestion?.exerciseType; sportStep = true
            }
            loadError = nil
            #if DEBUG
            if model.editFixture == "sport" { selection = draft?.sport; sportStep = true }
            if model.editFixture == "merge" { mergeCandidate = draft?.next }
            #endif
        } catch { loadError = ErrorCopy.message(error, context: .readHeartRate) }
    }
    private enum Mutation { case save, merge, delete, restore }
    private func mutate(_ action: Mutation) {
        guard let draft else { return }
        let change: PendingChange
        let server = model.changeServerURL, now = Date.now
        let aliases = model.cached?.snapshot.scoreConfig?.sportAliases ?? [:]
        switch action {
        case .save:
            change = workout.kind == "detected" ? ChangeBuilder.name(draft, id: namingID, workouts: workouts, serverURL: server, now: now) : ChangeBuilder.edit(draft, workouts: workouts, aliases: aliases, serverURL: server, now: now)
        case .merge:
            guard let candidate = mergeCandidate else { return }
            change = ChangeBuilder.merge(draft, candidate: candidate, workouts: workouts, aliases: aliases, serverURL: server, now: now)
        case .delete: change = ChangeBuilder.delete(workout, serverURL: server, now: now)
        case .restore: change = ChangeBuilder.restore(draft, workouts: workouts, aliases: aliases, serverURL: server, now: now)
        }
        Task {
            do {
                try await model.submit(change)
                saveError = nil
                dismiss()
                if action == .delete {
                    model.returnHomeAfterDelete()
                    model.showActivityUndo(ActivityUndo(name: workout.displayName ?? "Activity", change: change))
                } else { onSaved(change.kind == .name ? change.patch.upsert.first?.id ?? workout.id : workout.id) }
            } catch { self.saveError = ErrorCopy.message(error, context: action == .delete ? .deleteActivity : .saveActivity, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) }
        }
    }
}
