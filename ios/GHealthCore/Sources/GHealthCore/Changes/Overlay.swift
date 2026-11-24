import Foundation

public enum Overlay {
    public static func apply(_ changes: [PendingChange], to snapshot: Snapshot) -> Snapshot {
        var result = snapshot
        result.workouts.workouts = apply(changes, workouts: snapshot.workouts.workouts, rules: snapshot.day.scoreConstants?.workouts) { snapshot.workouts.from <= $0 && $0 <= snapshot.workouts.to }
        result.day.workouts = apply(changes, workouts: snapshot.day.workouts, rules: snapshot.day.scoreConstants?.workouts) { $0 == snapshot.day.date }
        result.sleep = apply(changes, to: result.sleep)
        for patch in changes.compactMap(\.sleepPatch) where patch.date == result.day.date { result.day.sleep = patch.apply(to: result.day.sleep) }
        result.journal = snapshot.journal.map { journal in changes.compactMap(\.journalPatch).reduce(journal) { $1.apply(to: $0) } }
        return result
    }
    public static func apply(_ changes: [PendingChange], date: String, day: Day, workouts: [Workout]) -> (Day, [Workout]) {
        var day = day
        day.workouts = apply(changes, workouts: day.workouts, rules: day.scoreConstants?.workouts) { $0 == date }
        for patch in changes.compactMap(\.sleepPatch) where patch.date == date { day.sleep = patch.apply(to: day.sleep) }
        return (day, apply(changes, workouts: workouts, rules: day.scoreConstants?.workouts) { $0 == date })
    }
    public static func apply(_ changes: [PendingChange], to sleep: Sleep) -> Sleep {
        changes.compactMap(\.sleepPatch).reduce(sleep) { $1.apply(to: $0) }
    }
    private static func apply(_ changes: [PendingChange], workouts: [Workout], rules: WorkoutOverlap?, includes: (String) -> Bool) -> [Workout] {
        var rows = workouts
        var dates = Set<String>()
        for change in changes where change.kind != .sleep && change.kind != .journal {
            dates.formUnion(change.cycleDates.filter(includes))
            rows.removeAll { change.patch.remove.contains($0.id) }
            for workout in change.patch.upsert where includes(workout.cycleDate) {
                rows.removeAll { $0.id == workout.id }
                rows.append(workout)
            }
        }
        return OverlapRules.apply(rows, cycleDates: dates, rules: rules).sorted { $0.start < $1.start }
    }
}

public enum OverlapRules {
    public static func apply(_ workouts: [Workout], cycleDates: Set<String>, rules: WorkoutOverlap?) -> [Workout] {
        guard let rules else { return workouts }
        let recorded = workouts.filter { $0.kind == "recorded" }
        let goop = workouts.filter { $0.kind == "goop" }
        let hidden = Set(recorded.filter { row in
            cycleDates.contains(row.cycleDate) && goop.contains { other in
                other.cycleDate == row.cycleDate && !absorbed(row, other)
                    && overlap(row, other) > 0
                    && overlap(row, other) >= rules.recordedHiddenOverlap * min(row.end.timeIntervalSince(row.start), other.end.timeIntervalSince(other.start))
            }
        }.map(\.id))
        let windows = workouts.filter { !hidden.contains($0.id) && ["recorded", "goop"].contains($0.kind) }
        return workouts.filter { row in
            if hidden.contains(row.id) { return false }
            guard row.kind == "detected", cycleDates.contains(row.cycleDate) else { return true }
            let covered = windows.filter { $0.cycleDate == row.cycleDate && !absorbed(row, $0) }.reduce(0) { $0 + overlap(row, $1) }
            return covered < rules.effortHiddenOverlap * row.end.timeIntervalSince(row.start)
        }
    }
    private static func absorbed(_ a: Workout, _ b: Workout) -> Bool { a.edit?.mergeWith.contains(b.id) == true || b.edit?.mergeWith.contains(a.id) == true }
    private static func overlap(_ a: Workout, _ b: Workout) -> TimeInterval { max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start))) }
}
