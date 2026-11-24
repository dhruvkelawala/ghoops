import SwiftUI
import GHealthCore

struct ActivitySportStep: View {
    @Binding var selection: String?
    var workout: Workout? = nil
    var currentSport: String? = nil
    var suggestion: WorkoutSuggestion? = nil
    var workouts: [Workout]
    var defaultDate: String
    var aliases: [String: String] = [:]
    var prefix = "edit"
    @State private var query = ""
    private var history: [Workout] {
        workouts.filter { $0.id != workout?.id && ["recorded", "goop"].contains($0.kind) && $0.cycleDate >= GoopFormat.addingDays(-29, to: defaultDate) }.sorted { $0.start > $1.start }
    }
    private var recent: [String] {
        var types: [String] = []
        if let suggestion { types.append(suggestion.exerciseType) }
        if workout?.kind != "detected", let currentSport { types.append(currentSport) }
        if workout?.kind == "recorded", let band = workout?.original?.exerciseType, band != currentSport { types.append(band) }
        for row in history {
            if let type = row.exerciseType, ActivitySport.all.contains(where: { $0.id == type }), !types.contains(type) { types.append(type) }
        }
        return Array(types.prefix(2))
    }
    var body: some View {
        VStack(spacing: 0) {
            GoopSearchField(prompt: "Search activities", text: $query, identifier: "\(prefix)-sport-search").padding(.top, 4)
            if !recent.isEmpty {
                GoopSectionLabel(title: "RECENT").padding(.top, 18).padding(.bottom, 6)
                ForEach(recent, id: \.self) { row($0, recent: true) }
            }
            GoopSectionLabel(title: "ALL ACTIVITIES").padding(.top, recent.isEmpty ? 18 : 16).padding(.bottom, 6)
            ForEach(ActivitySport.all.filter { !recent.contains($0.id) }) { row($0.id, recent: false) }
            if let original = workout?.original, workout?.kind == "recorded", let type = original.exerciseType, type != selection, aliases[type] == nil {
                (Text("Your band logs this as \(original.displayName ?? name(type)). To show every band \(original.displayName ?? name(type)) as \(name(selection)), set it once on your Mac with ") + Text("ghoops config").foregroundColor(Goop.Color.textSoft) + Text("."))
                    .goop(.bodySmall).foregroundStyle(Goop.Color.iconMuted).padding(.top, 18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    @ViewBuilder private func row(_ type: String, recent: Bool) -> some View {
        let isBand = workout?.kind == "recorded" && type == workout?.original?.exerciseType && type != currentSport
        let known = ActivitySport.all.first { $0.id == type }
        let title = known?.name ?? workout?.original?.displayName ?? "Workout"
        if query.isEmpty || title.localizedCaseInsensitiveContains(query) {
            let choice = GoopChoiceRow(symbol: known?.symbol ?? workout.map(GoopActivity.workoutSymbol) ?? "figure.mixed.cardio", title: title.uppercased(), note: recent ? note(type, band: isBand) : nil, selected: selection == type, identifier: isBand ? "\(prefix)-sport-band" : "\(prefix)-sport-\(type)") { selection = type }
            if type == suggestion?.exerciseType, let workout {
                choice.accessibilityLabel(SuggestionText.accessibility(sport: title, effortStart: workout.start))
            } else { choice }
        }
    }
    private func note(_ type: String, band: Bool) -> String? {
        if type == suggestion?.exerciseType, let workout { return SuggestionText.note(effortStart: workout.start) }
        if band { return "Band's label" }
        return history.first { $0.exerciseType == type }.map { "Last: \(ActivityTime.weekday($0.cycleDate, short: true))" }
    }
    private func name(_ type: String?) -> String { type.map { ActivitySport.sport($0).name } ?? "Activity" }
}
