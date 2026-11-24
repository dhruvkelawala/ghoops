import Foundation
import GHealthCore

struct ChangeMarker {
    var change: PendingChange
    var savingAt: Date?
    var updatingAt: Date?
}

extension AppModel {
    func refreshChangeMarkers() {
        markerTask?.cancel()
        let clock = Date.now
        let current = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
        var markers = changeMarkers
        for change in pending {
            if markers[change.id] == nil { markers[change.id] = ChangeMarker(change: change) }
        }
        var deadlines: [Date] = []
        for (id, var marker) in markers {
            let present = current[id] != nil
            if let change = current[id] { marker.change = change }
            var change = marker.change
            if !present { change.state = .accepted }
            let saving = change.state != .waiting && ChangeTiming.markerVisible(change: change, now: clock, shownAt: marker.savingAt)
            marker.savingAt = saving ? marker.savingAt ?? clock : nil
            let hasUpdating = !change.patch.updating.isEmpty || change.sleepPatch != nil
            let updating = hasUpdating && ChangeTiming.markerVisible(change: change, now: clock, shownAt: marker.updatingAt, untilSettled: present)
            marker.updatingAt = updating ? marker.updatingAt ?? clock : nil
            if present {
                let delay = change.createdAt.addingTimeInterval(ChangeTiming.markerDelay)
                if delay > clock && (change.state == .sending || hasUpdating) { deadlines.append(delay) }
            }
            for shown in [marker.savingAt, marker.updatingAt].compactMap({ $0 }) {
                let minimum = shown.addingTimeInterval(ChangeTiming.markerMinimum)
                if minimum > clock { deadlines.append(minimum) }
            }
            markers[id] = present || saving || updating ? marker : nil
        }
        changeMarkers = markers
        if let next = deadlines.min() {
            markerTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow))) }
                catch { return }
                self?.refreshChangeMarkers()
            }
        }
    }

    func changeStatus(for id: String) -> GoopActivity.Status? {
        if pending.contains(where: { $0.state == .waiting && $0.targets.contains(id) }) { return .waiting }
        if changeMarkers.values.contains(where: { $0.savingAt != nil && $0.change.targets.contains(id) }) { return .saving }
        return activity.localEntry(id)?.uploadState == .pending ? .waiting : nil
    }

    func sleepScores(on date: String, delayed: Bool = false) -> Set<String> {
        let shown = changeMarkers.values.filter { $0.updatingAt != nil }.map(\.change)
        let changes = delayed ? shown : pending + shown
        var scores = Set<String>()
        for patch in changes.compactMap(\.sleepPatch) {
            if patch.date == date { scores.formUnion(["sleep", "recovery"]) }
            if patch.updating.contains(date) { scores.insert("strain") }
        }
        return scores
    }

    func strengthUpdating(on date: String) -> Bool {
        changeMarkers.values.contains { $0.updatingAt != nil && $0.change.patch.updating.contains(date) }
    }

    func activityRows(_ original: Day, workoutsOnly: Bool = false) -> [GoopActivity] {
        var day = original
        day.workouts = displayedWorkouts(day.workouts).filter { $0.cycleDate == day.date }
        return GoopActivity.rows(day: day, workoutsOnly: workoutsOnly).map { row in
            var row = row
            if case .sleep = row.kind { row.status = changeStatus(for: "sleep-\(day.date)") }
            if case .workout(let workout) = row.kind {
                row.status = changeStatus(for: workout.id)
                row.projected = lockedWorkouts.contains(workout.id)
            }
            return row
        }
    }

    func dismissRollback(_ notice: RollbackNotice) { rollbacks.removeAll { $0.id == notice.id } }
}
