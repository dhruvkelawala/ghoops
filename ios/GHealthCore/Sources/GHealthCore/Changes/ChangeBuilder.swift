import Foundation

public enum ChangeBuilder {
    public static func edit(_ draft: EditDraft, workouts: [Workout] = [], aliases: [String: String] = [:], serverURL: String, now: Date) -> PendingChange {
        put(.edit, draft: draft, body: draft.body, workouts: workouts, aliases: aliases, serverURL: serverURL, now: now)
    }

    public static func merge(_ draft: EditDraft, candidate: Workout, workouts: [Workout] = [], aliases: [String: String] = [:], serverURL: String, now: Date) -> PendingChange {
        var change = put(.merge, draft: draft, body: draft.mergeBody(candidate), workouts: workouts, aliases: aliases, serverURL: serverURL, now: now)
        if candidate.kind != "detected" {
            change.targets.append(candidate.id)
            var original = candidate.original ?? WorkoutOriginal(exerciseType: candidate.exerciseType, displayName: candidate.displayName, start: candidate.start, end: candidate.end)
            original.id = candidate.id; original.kind = candidate.kind
            change.patch.upsert[0].merged.append(original)
            change.patch.upsert[0].merged.sort { $0.start < $1.start }
        }
        change.patch = patch(remove: [candidate.id], upsert: change.patch.upsert, before: workouts + [draft.workout, candidate], rules: draft.heartRate.scoreConstants?.workouts)
        return change
    }

    public static func delete(_ workout: Workout, serverURL: String, now: Date) -> PendingChange {
        var body = EditBody(workout.edit, hidden: true)
        body.precondition = condition(workout)
        return PendingChange(kind: .delete, request: .putEdit(workout.id, body), targets: [workout.id], cycleDates: [workout.cycleDate], name: workout.displayName ?? "Activity", patch: patch(remove: [workout.id], before: [workout]), kept: workout, serverURL: serverURL, createdAt: now)
    }

    public static func undo(_ deletion: PendingChange, now: Date) -> PendingChange? {
        guard let kept = deletion.kept else { return nil }
        let request: PendingChange.Request
        if kept.edit != nil {
            var body = EditBody(kept.edit)
            body.precondition = deletion.acceptedEdit.map { .updatedAt($0.updatedAt) } ?? .none
            request = .putEdit(kept.id, body)
        } else { request = .deleteEdit(kept.id) }
        var change = PendingChange(kind: .undo, request: request, targets: [kept.id], cycleDates: [kept.cycleDate], name: kept.displayName ?? "Activity", patch: patch(upsert: [kept], before: [kept]), serverURL: deletion.serverURL, createdAt: now)
        change.profileId = deletion.profileId
        if kept.edit != nil && deletion.acceptedEdit == nil { change.replayBeforeUndo = deletion.request }
        return change
    }

    public static func restore(_ draft: EditDraft, workouts: [Workout] = [], aliases: [String: String] = [:], serverURL: String, now: Date) -> PendingChange {
        let workout = draft.workout
        let original = workout.original ?? WorkoutOriginal(exerciseType: workout.exerciseType, displayName: workout.displayName, start: workout.start, end: workout.end)
        let rows = ([original] + workout.merged).map { WorkoutProjection.restored(workout, original: $0, heartRate: draft.heartRate, aliases: aliases, now: now) }
        return PendingChange(kind: .restore, request: .deleteEdit(workout.id), targets: [workout.id] + workout.merged.compactMap(\.id), cycleDates: [workout.cycleDate], name: workout.displayName ?? "Activity", patch: patch(upsert: rows, before: workouts + [workout], rules: draft.heartRate.scoreConstants?.workouts), serverURL: serverURL, createdAt: now)
    }

    public static func name(_ draft: EditDraft, id: String, workouts: [Workout] = [], serverURL: String, now: Date) -> PendingChange {
        var upload = AddDraft.upload(id: id, sport: draft.sport ?? "OTHER", window: draft.window)
        upload.notes = draft.body.notes
        let row = WorkoutProjection.added(upload, cycleDate: draft.workout.cycleDate, heartRate: draft.heartRate, now: now)
        return PendingChange(kind: .name, request: .postActivity(upload), targets: [draft.workout.id, row.id], cycleDates: [row.cycleDate], name: upload.displayName, patch: patch(remove: [draft.workout.id], upsert: [row], before: workouts + [draft.workout], rules: draft.heartRate.scoreConstants?.workouts), serverURL: serverURL, createdAt: now)
    }

    public static func add(_ draft: AddDraft, heartRate: HeartRateBody, serverURL: String, now: Date) -> PendingChange? {
        guard let upload = draft.upload else { return nil }
        let row = WorkoutProjection.added(upload, cycleDate: draft.day, heartRate: heartRate, now: now)
        return PendingChange(kind: .add, request: .postActivity(upload), targets: [row.id], cycleDates: [draft.day], name: upload.displayName, patch: patch(upsert: [row], before: draft.workouts, rules: heartRate.scoreConstants?.workouts), serverURL: serverURL, createdAt: now)
    }

    /// A rating shows at once; it changes no score, so nothing is `UPDATING` (effort-rating-spec.md §3.4).
    public static func rate(_ workout: Workout, rpe: Int, serverURL: String, now: Date) -> PendingChange {
        var row = workout
        row.rpe = rpe
        return PendingChange(kind: .rate, request: .putRating(workout.id, RatingBody(rpe: rpe)), targets: [workout.id], cycleDates: [workout.cycleDate], name: workout.displayName ?? "Activity", patch: WorkoutPatch(upsert: [row]), serverURL: serverURL, createdAt: now)
    }

    private static func put(_ kind: PendingChange.Kind, draft: EditDraft, body: EditBody, workouts: [Workout], aliases: [String: String], serverURL: String, now: Date) -> PendingChange {
        var body = body
        body.precondition = condition(draft.workout)
        let window = ActivityWindow(start: body.start ?? draft.window.start, end: body.end ?? draft.window.end)
        let row = WorkoutProjection.project(draft.workout, body: body, window: window, heartRate: draft.heartRate, aliases: aliases, now: now)
        return PendingChange(kind: kind, request: .putEdit(draft.workout.id, body), targets: [draft.workout.id], cycleDates: [draft.workout.cycleDate], name: draft.workout.displayName ?? "Activity", patch: patch(upsert: [row], before: workouts + [draft.workout], rules: draft.heartRate.scoreConstants?.workouts), serverURL: serverURL, createdAt: now)
    }
    private static func condition(_ workout: Workout) -> EditPrecondition { workout.edit.map { .updatedAt($0.updatedAt) } ?? .noEdit }
    private static func patch(remove: [String] = [], upsert: [Workout] = [], before: [Workout], rules: WorkoutOverlap? = nil) -> WorkoutPatch {
        let replaced = Set(remove + upsert.map(\.id))
        let rows = before.filter { !replaced.contains($0.id) } + upsert
        let after = Set(OverlapRules.apply(rows, cycleDates: Set(upsert.map(\.cycleDate)), rules: rules).map(\.id))
        let changed = before.filter { replaced.contains($0.id) || !after.contains($0.id) } + upsert
        let updating = Array(Set(changed.filter { $0.category == "strength" }.map(\.cycleDate))).sorted()
        return WorkoutPatch(remove: remove, upsert: upsert, updating: updating)
    }
}
