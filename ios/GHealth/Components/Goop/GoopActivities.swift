import SwiftUI
import GHealthCore

struct GoopActivity: Identifiable {
    enum Kind { case sleep, nap, workout(Workout) }
    enum Status { case saving, waiting }
    var id: String
    var kind: Kind
    var start: Date
    var end: Date
    var value: String
    var name: String
    var icon: String
    var color: Color
    var status: Status?
    var projected = false
    var dashed = false
    var accessible: String

    static func rows(day: Day, workoutsOnly: Bool = false) -> [GoopActivity] {
        var rows: [GoopActivity] = []
        if !workoutsOnly {
            for (index, nap) in day.sleep.naps.enumerated() {
                let minutes = Int((nap.end.timeIntervalSince(nap.start) / 60).rounded())
                rows.append(.init(id: "nap-row-\(index)", kind: .nap, start: nap.start, end: nap.end, value: GoopFormat.duration(minutes), name: "NAP", icon: "moon.fill", color: Goop.Color.sleep.opacity(0.6), accessible: "Nap, \(GoopSpeech.duration(minutes)), \(GoopFormat.time(nap.start)) to \(GoopFormat.time(nap.end))"))
            }
        }
        rows += day.workouts.map { workout in
            let detected = workout.category == "detected"
            let name = detected ? "Detected effort" : workout.displayName ?? "Workout"
            return .init(id: "workout-link-\(workout.id)", kind: .workout(workout), start: workout.start, end: workout.end, value: GoopFormat.number(workout.strain, decimals: 1), name: name.uppercased(), icon: workoutSymbol(workout), color: Goop.Color.strain, dashed: detected, accessible: "\(name), strain \(workout.strain == nil ? "no data" : GoopFormat.number(workout.strain, decimals: 1)), \(GoopFormat.time(workout.start)) to \(GoopFormat.time(workout.end))")
        }
        rows.sort { $0.start > $1.start }
        if !workoutsOnly, let start = day.sleep.bedtime, let end = day.sleep.wakeTime {
            rows.insert(.init(id: "sleep-activity-link", kind: .sleep, start: start, end: end, value: GoopFormat.duration(day.sleep.timeInBedMinutes), name: "SLEEP", icon: "moon.fill", color: Goop.Color.sleep, accessible: "Sleep, \(GoopSpeech.duration(day.sleep.timeInBedMinutes)) in bed, \(GoopFormat.time(start)) to \(GoopFormat.time(end))"), at: 0)
        }
        return rows
    }
    static func workoutSymbol(_ workout: Workout) -> String {
        switch workout.category {
        case "combat": "figure.boxing"
        case "strength": "figure.strengthtraining.traditional"
        case "walking": "figure.walk"
        case "detected": "heart"
        case "cardio": ["BIKING", "OUTDOOR_BIKE", "STATIONARY_BIKE", "SPINNING"].contains(workout.exerciseType) ? "figure.outdoor.cycle" : ["SWIMMING", "SWIMMING_POOL"].contains(workout.exerciseType) ? "figure.pool.swim" : "figure.run"
        default: workout.exerciseType == "YOGA" ? "figure.yoga" : "clock"
        }
    }
}

struct GoopActivityRow: View {
    var activity: GoopActivity
    var dimmed = false
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            switch activity.kind {
            case .nap: row.accessibilityElement(children: .ignore).accessibilityLabel(accessible)
            default: Button(action: action) { row }.buttonStyle(.plain).accessibilityLabel(accessible)
            }
        }.accessibilityIdentifier(activity.id)
    }
    private var accessible: String {
        switch activity.status {
        case .saving: activity.accessible + ", saving to your Mac"
        case .waiting: activity.accessible + ", waiting for your Mac"
        case nil: activity.accessible
        }
    }
    private var row: some View {
        HStack(spacing: 0) {
            GoopValueBlock(symbol: activity.icon, value: activity.value, fill: activity.color, dashed: activity.dashed, valueOpacity: dimmed && !activity.projected ? Goop.Opacity.stale : 1)
            Text(activity.name).goop(.labelActivity).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 17)
            if let status = activity.status {
                Text(status == .saving ? "SAVING" : "WAITING FOR MAC").goop(.labelMicro).foregroundStyle(status == .saving ? Goop.Color.text2 : Goop.Color.caution).frame(maxWidth: 76).padding(.horizontal, 4)
            } else if !typeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 0) { Text(GoopFormat.time(activity.start)); Text(GoopFormat.time(activity.end)) }.goop(.time).foregroundStyle(Goop.Color.text2).padding(.horizontal, 8)
            }
            RoundedRectangle(cornerRadius: Goop.Metric.radiusHairline).fill(activity.color).frame(width: 2, height: 26).accessibilityHidden(true)
        }.padding(.horizontal, 9).frame(minHeight: 58).background(Goop.Color.activityRow, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusActivities))
    }
}

struct GoopActivitiesCard: View {
    var rows: [GoopActivity]
    var title = "TODAY'S ACTIVITIES"
    var limit: Int? = nil
    var dimmed = false
    var loading = false
    var emptyText = "No activities yet"
    var expand: (() -> Void)? = nil
    var live: ActivityController? = nil
    var start: (() -> Void)? = nil
    var add: (() -> Void)? = nil
    var action: (GoopActivity) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).goop(.labelCard)
                Spacer()
                if !rows.isEmpty, let expand {
                    Button(action: expand) { GoopSymbol(name: "arrow.down.left.and.arrow.up.right", size: 16).frame(width: 28, height: 24).contentShape(Rectangle().inset(by: -10)) }.accessibilityIdentifier("activities-expand").accessibilityLabel("Show all activities")
                }
            }.padding(.horizontal, 4)
            if let live, live.session != nil { GoopLiveRow(activity: live).padding(.top, 12) }
            if loading { GoopLoading() }
            else if rows.isEmpty { Text(emptyText).goop(.bodyMid).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12) }
            else { ForEach(Array(rows.prefix(max(0, (limit ?? rows.count) - (live?.session == nil ? 0 : 1))))) { row in GoopActivityRow(activity: row, dimmed: dimmed) { action(row) }.padding(.top, 12) } }
            if let live, live.session != nil, start != nil {
                entryButton(title: "END \(live.session?.displayName.uppercased() ?? "ACTIVITY")", symbol: "stop.fill", identifier: "activity-end-open", spoken: "End \(live.session?.displayName ?? "activity")", ending: true) {
                    live.highlightEnd = true; live.livePresented = true
                }.padding(.top, 12)
            } else if let add, let start {
                ViewThatFits(in: .horizontal) {
                    GoopEqualPair(spacing: 12) { entryPair(add: add, start: start) }
                    VStack(spacing: 12) { entryPair(add: add, start: start) }
                }.padding(.top, 12)
            } else if let add {
                addButton(add).padding(.top, 12)
            } else if let start {
                startButton(start).padding(.top, 12)
            }
        }.padding(.top, 16).padding(.horizontal, 13).padding(.bottom, 13).background(Goop.Color.activitiesFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusActivities)).buttonStyle(.plain)
    }
    private func entryPair(add: @escaping () -> Void, start: @escaping () -> Void) -> some View {
        Group { addButton(add); startButton(start) }
    }
    private func addButton(_ action: @escaping () -> Void) -> some View {
        entryButton(title: "ADD ACTIVITY", symbol: "plus", identifier: "activity-open-add", spoken: "Add activity", action: action)
    }
    private func startButton(_ action: @escaping () -> Void) -> some View {
        entryButton(title: "START ACTIVITY", symbol: "stopwatch", identifier: "activity-open-picker", spoken: "Start activity", action: action)
    }
    private func entryButton(title: String, symbol: String, identifier: String, spoken: String, ending: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                GoopSymbol(name: symbol, size: ending ? 12 : 15, color: ending ? Goop.Color.zone5 : .white)
                Text(title).goop(.labelCard).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 40)
                .background(Goop.Color.activityRow, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusButton))
                .overlay { if ending { RoundedRectangle(cornerRadius: Goop.Metric.radiusButton).strokeBorder(Goop.Color.zone5.opacity(0.33), lineWidth: 1) } }
        }.accessibilityIdentifier(identifier).accessibilityLabel(spoken)
    }
}

enum GoopSpeech {
    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return "no data" }
        let hours = minutes / 60
        return (hours == 0 ? "" : "\(hours) \(hours == 1 ? "hour" : "hours") ") + "\(minutes % 60) minutes"
    }
}
