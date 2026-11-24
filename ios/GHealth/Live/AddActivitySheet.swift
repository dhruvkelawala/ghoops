import SwiftUI
import GHealthCore

struct AddActivitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let day: String
    @State private var draft: AddDraft?
    @State private var sportStep = false
    @State private var sportSelection: String?
    @State private var effortStep = false
    @State private var effortSelection: String?
    @State private var heartRates: [String: HeartRateBody] = [:]
    @State private var loadingDay: String?
    @State private var loadError: String?
    @State private var saveError: String?
    private var error: String? { loadError ?? saveError }
    private var loadFailed: Bool { loadError != nil }
    private var chosenSport: ActivitySport? { draft?.sport.map(ActivitySport.sport) }
    private var name: String { chosenSport?.name ?? "activity" }

    var body: some View {
        GoopTaskSheet(title: sportStep ? "SPORT" : effortStep ? "EFFORT" : "ADD ACTIVITY", back: sportStep || effortStep ? { sportStep = false; effortStep = false } : nil, closeIdentifier: "activity-add-close", commit: commit) {
            VStack(spacing: 0) {
                if let error { GoopBanner(text: error, symbol: "exclamationmark.triangle", tone: .caution).padding(.top, 4).padding(.bottom, 12).accessibilityIdentifier("add-error") }
                Group {
                    if sportStep {
                        ActivitySportStep(selection: $sportSelection, workouts: model.activity.recentWorkouts, defaultDate: model.defaultDate, prefix: "add")
                    } else if effortStep, let draft { effortContent(draft) }
                    else { addContent.padding(.top, 4) }
                }.disabled(loadFailed).opacity(loadFailed ? Goop.Opacity.disabled : 1)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("activity-add")
        .task {
            if draft == nil {
                draft = AddDraft(defaultDate: model.defaultDate, workouts: model.cached?.snapshot.workouts.workouts ?? [], now: model.now, limits: model.editLimits, day: day)
            }
            if draft?.heartRate == nil { await loadHeartRate() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active && loadFailed { Task { await loadHeartRate() } } }
    }
    private var commit: GoopCommit {
        if effortStep {
            let chosen = draft?.efforts.first { $0.id == effortSelection }
            return GoopCommit(title: "USE EFFORT", symbol: "heart", identifier: "add-effort-use", enabled: chosen != nil && !loadFailed, accessibilityLabel: "Use effort") {
                if let chosen { draft?.snap(to: chosen) }
                effortStep = false
            }
        }
        if sportStep {
            let chosen = sportSelection.map(ActivitySport.sport)
            return GoopCommit(title: "USE \(chosen?.name.uppercased() ?? "ACTIVITY")", symbol: chosen?.symbol ?? "checkmark", identifier: "add-sport-use", enabled: chosen != nil && !loadFailed, accessibilityLabel: "Use \(chosen?.name ?? "activity")") {
                draft?.sport = chosen?.id; sportStep = false
            }
        }
        return GoopCommit(title: "ADD \(name.uppercased())", symbol: "plus", identifier: "add-commit", enabled: chosenSport != nil && draft?.heartRate != nil && loadingDay == nil && !loadFailed, accessibilityLabel: "Add \(name)", action: add)
    }
    @ViewBuilder private var addContent: some View {
        if let draft {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Button { sportSelection = draft.sport; sportStep = true } label: {
                        GoopRow("SPORT", disclosure: .push) {
                            if draft.sport == nil { Text("Choose").goop(.bodySmall).foregroundStyle(Goop.Color.text2) }
                            else { GoopRowValue(text: name) }
                        }
                    }.accessibilityIdentifier("add-sport-row")
                    if draft.days.count == 1 { GoopRow("DAY", value: "Today") }
                    else { GoopRow("DAY", alignment: .center) { daySelector(draft) } }
                    if draft.efforts.isEmpty {
                        GoopRow("EFFORT") { Text("None found").goop(.bodySmall).foregroundStyle(Goop.Color.text2) }.accessibilityIdentifier("add-effort-row")
                    } else {
                        Button { effortSelection = draft.snapped?.id ?? draft.efforts.last?.id; effortStep = true } label: { GoopRow("EFFORT", value: draft.effortLabel, disclosure: .push) }.accessibilityIdentifier("add-effort-row")
                    }
                }
                GoopEditValues(value: loadingDay == nil ? draft.heartRate.map { WindowEstimator(heartRate: $0).estimate(start: draft.window.start, end: draft.window.end) } : nil, showPrior: false, prefix: "add").padding(.top, 24)
                Group {
                    if loadFailed { GoopPlaceholder(text: "Needs a connection to your Mac").frame(height: 216) }
                    else if loadingDay == nil, let hr = draft.heartRate {
                        GoopWindowChart(heartRate: hr, window: draft.window, bounds: draft.bounds, prefix: "add") { self.draft?.window = $0 }.id(draft.day)
                    } else { GoopLoading().frame(height: 216) }
                }.padding(.top, 22)
                Text(draft.hint).goop(.bodySmall).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                VStack(spacing: 8) {
                    GoopTimeRow("START", time: time(start: true), range: draft.bounds.startRange(end: draft.window.end), identifier: "add-start", date: ActivityTime.dateLabels(draft.window)?.start)
                    GoopTimeRow("END", time: time(start: false), range: draft.bounds.endRange(start: draft.window.start), identifier: "add-end", date: ActivityTime.dateLabels(draft.window)?.end)
                }.padding(.top, 24)
            }
        } else { GoopLoading() }
    }
    private func effortContent(_ draft: AddDraft) -> some View {
        VStack(spacing: 0) {
            GoopSectionLabel(title: "FOUND ON \(ActivityTime.weekday(draft.day).uppercased())").padding(.horizontal, 2).padding(.top, 4).padding(.bottom, 6)
            ForEach(draft.efforts, id: \.id) { effort in
                GoopChoiceRow(symbol: GoopActivity.workoutSymbol(effort), title: "\(GoopFormat.time(effort.start)) TO \(GoopFormat.time(effort.end))", note: GoopFormat.duration(Int(effort.end.timeIntervalSince(effort.start) / 60)), selected: effortSelection == effort.id, identifier: "add-effort-\(effort.id)") { effortSelection = effort.id }
            }
        }
    }
    private func daySelector(_ draft: AddDraft) -> some View {
        let labels = draft.days.map { ActivityTime.weekday($0, short: true).uppercased() }
        return GoopRangeSelector(options: labels, selection: Binding(get: { ActivityTime.weekday(self.draft?.day ?? draft.day, short: true).uppercased() }, set: { label in
            if let index = labels.firstIndex(of: label) { selectDay(draft.days[index]) }
        }), identifier: { "add-day-\(draft.days[labels.firstIndex(of: $0)!])" })
    }
    private func time(start: Bool) -> Binding<Date> {
        Binding(get: { start ? draft?.window.start ?? model.now : draft?.window.end ?? model.now }, set: { value in
            guard let draft = draft else { return }
            let date = ActivityTime.picker(value, within: draft.bounds.span)
            if start { self.draft?.window.moveStart(to: date, bounds: draft.bounds) }
            else { self.draft?.window.moveEnd(to: date, bounds: draft.bounds) }
        })
    }
    private func selectDay(_ day: String) {
        draft?.selectDay(day, heartRate: heartRates[day])
        Task { await loadHeartRate() }
    }
    private func loadHeartRate() async {
        guard let day = draft?.day else { return }
        if let cached = heartRates[day] { loadingDay = nil; draft?.load(cached); loadError = nil; return }
        loadingDay = day
        defer { if loadingDay == day { loadingDay = nil } }
        do {
            guard let api = model.editAPI else { throw ClientError.unauthorized }
            let hr = try await api.heartRate(date: day)
            heartRates[day] = hr
            if draft?.day == day { draft?.load(hr); loadError = nil }
        } catch { if draft?.day == day { loadError = ErrorCopy.message(error, context: .readHeartRate) } }
    }
    private func add() {
        guard let draft = draft, let hr = draft.heartRate else { return }
        guard let change = ChangeBuilder.add(draft, heartRate: hr, serverURL: model.changeServerURL, now: .now) else { return }
        Task {
            do {
                try await model.submit(change)
                saveError = nil
                dismiss()
                model.selectedDate = draft.day
                model.askRating(for: "goop-\(draft.id)")
                model.push(.workout(id: "goop-\(draft.id)", date: draft.day))
            } catch { self.saveError = ErrorCopy.message(error, context: .saveActivity, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) }
        }
    }
}
