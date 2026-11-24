import SwiftUI
import GHealthCore

struct ActivityPicker: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection = ActivitySport.all[0]
    private var recent: [Workout] {
        var seen = Set<String>()
        return Array(model.activity.recentWorkouts.sorted { $0.start > $1.start }.filter { workout in
            ["recorded", "goop"].contains(workout.kind) && workout.start >= model.activity.now.addingTimeInterval(-30 * 86400) && workout.start <= model.activity.now && ActivitySport.all.contains { sport in sport.id == workout.exerciseType } && seen.insert(workout.exerciseType ?? "").inserted
        }.prefix(2))
    }
    var body: some View {
        GoopTaskSheet(title: "START ACTIVITY", closeIdentifier: "activity-picker-close", commit: commit) {
            content
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("activity-picker")
        .onAppear { selection = recent.first.map { .sport($0.exerciseType ?? "BOXING") } ?? .all[0] }
    }
    private var commit: GoopCommit {
        GoopCommit(title: "START \(selection.name.uppercased())", symbol: "stopwatch", identifier: "activity-start") {
            let cycleDate = model.defaultDate
            Task { await model.activity.start(sport: selection, cycleDate: cycleDate) }
        }
    }
    private var content: some View {
        VStack(spacing: 0) {
            if let error = model.activity.error {
                GoopBanner(text: error, symbol: "exclamationmark.triangle", tone: .caution).padding(.top, 4).padding(.bottom, 12).accessibilityIdentifier("activity-start-error")
            }
            HeartRateBanner(state: model.activity.connection, select: model.activity.connect).padding(.top, 4)
            if let day = model.cached?.snapshot.day, let target = SessionTarget.make(day: day, sessionStart: model.now) {
                LiveTargetRow(projected: day.strain.value, low: target.low, high: target.high, caption: "DAY STRAIN", spokenCaption: "Day Strain", identifier: "start-target")
                    .padding(.top, 16)
            }
            GoopSearchField(prompt: "Search activities", text: $query, identifier: "activity-search").padding(.top, 14)
            if !recent.isEmpty {
                GoopSectionLabel(title: "RECENT").padding(.horizontal, 2).padding(.top, 18).padding(.bottom, 6)
                ForEach(recent, id: \.id) { w in row(.sport(w.exerciseType ?? "OTHER"), last: w.start) }
            }
            GoopSectionLabel(title: "ALL ACTIVITIES").padding(.horizontal, 2).padding(.top, recent.isEmpty ? 18 : 16).padding(.bottom, 6)
            ForEach(ActivitySport.all.filter { sport in !recent.contains { $0.exerciseType == sport.id } }) { row($0) }
        }
    }
    @ViewBuilder private func row(_ sport: ActivitySport, last: Date? = nil) -> some View {
        if query.isEmpty || sport.name.localizedCaseInsensitiveContains(query) {
            GoopChoiceRow(symbol: sport.symbol, title: sport.name.uppercased(), note: last.map { "Last: \($0.formatted(.dateTime.weekday(.abbreviated)))" },
                          selected: selection == sport, identifier: "activity-sport-\(sport.id)") { selection = sport }
        }
    }
}
