#if DEBUG
import Foundation
import GHealthCore

extension AppModel {
    func configureInstantFixture() async {
        guard let key = instantFixture,
              let directory = Bundle.main.resourceURL?.appendingPathComponent("Fixtures/edits") else { return }
        do {
            let state = ["saving", "waiting", "rollback"].contains(key) ? "unedited" : "edited"
            let mode: FixtureEditAPI.MutationMode = switch key {
            case "saving", "updating": .hold
            case "rollback": .reject(.notFound)
            default: .offline
            }
            let api = FixtureEditAPI(state: state, mutationMode: mode)
            fixtureEditAPI = api
            let snapshot = try await api.snapshot()
            if let meta = cached?.meta { applyServerSnapshot(CachedSnapshot(snapshot: snapshot, meta: meta)) }
            let workouts = snapshot.workouts.workouts
            let workout = workouts.first { $0.id == "7300000000000000101" }!
            let change: PendingChange
            if key == "delete-waiting" {
                change = ChangeBuilder.delete(workout, serverURL: changeServerURL, now: .now)
            } else if key == "home-waiting" {
                let upload = try JSONCoding.decoder().decode(ActivityUpload.self, from: Data(contentsOf: directory.appendingPathComponent("requests/name.json")))
                let effort = workouts.first { $0.kind == "detected" && $0.start == upload.start }!
                let hr = try await api.heartRate(start: upload.start, end: upload.end)
                var draft = EditDraft(workout: effort, workouts: workouts, heartRate: hr, limits: editLimits, now: now)
                draft.sport = upload.exerciseType
                draft.window = ActivityWindow(start: upload.start, end: upload.end)
                change = ChangeBuilder.name(draft, id: upload.id, workouts: workouts, serverURL: changeServerURL, now: .now)
            } else {
                let file = key == "updating" ? "edit_strength" : "edit"
                let body = try JSONCoding.decoder().decode(EditBody.self, from: Data(contentsOf: directory.appendingPathComponent("requests/\(file).json")))
                let hr = try await api.heartRate(start: body.start!, end: body.end!)
                var draft = EditDraft(workout: workout, workouts: workouts, heartRate: hr, limits: editLimits, now: now)
                draft.sport = body.exerciseType
                draft.window = ActivityWindow(start: body.start!, end: body.end!)
                draft.notes = body.notes ?? ""
                change = ChangeBuilder.edit(draft, workouts: workouts, aliases: snapshot.scoreConfig?.sportAliases ?? [:], serverURL: changeServerURL, now: .now)
            }
            try await submit(change)
            if key == "delete-waiting" {
                showActivityUndo(ActivityUndo(name: workout.displayName ?? "Activity", change: change))
            }
            if ["saving", "waiting", "updating"].contains(key) {
                selectedDate = "2026-03-10"
                await loadDay(selectedDate)
                if key == "updating" { push(.strain) }
                else { push(.workout(id: workout.id, date: selectedDate)) }
            }
            if key == "saving" || key == "updating" { try await Task.sleep(for: .seconds(0.7)) }
        } catch { self.error = error.localizedDescription }
    }
}
#endif
