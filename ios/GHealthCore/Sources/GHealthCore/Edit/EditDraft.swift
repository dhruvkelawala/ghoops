import Foundation

public struct EditDraft: Sendable {
    public let workout: Workout
    public let heartRate: HeartRateBody
    public var sport: String?
    public var window: ActivityWindow
    public var notes: String { didSet { notes = EditNotes.capped(notes, max: limits?.notesMaxChars) } }
    public let priorWindow: ActivityWindow
    public let bandStrips: [WorkoutOriginal]
    public let limits: EditLimits?
    public let now: Date
    public let bounds: EditBounds
    private let saved: (previous: Workout?, next: Workout?)
    public var previous: Workout? { saved.previous.flatMap { offers($0) ? $0 : nil } }
    public var next: Workout? { saved.next.flatMap { offers($0) ? $0 : nil } }

    public init(workout: Workout, workouts: [Workout], heartRate: HeartRateBody, limits: EditLimits?, now: Date) {
        self.workout = workout; self.heartRate = heartRate; self.limits = limits; self.now = now
        bounds = workout.kind == "detected" ? EditBounds.name(workout, heartRate: heartRate, limits: limits, now: now) : EditBounds.edit(workout, heartRate: heartRate, limits: limits, now: now)
        sport = workout.exerciseType
        window = ActivityWindow(start: workout.start, end: workout.end)
        notes = EditNotes.capped(workout.notes ?? "", max: limits?.notesMaxChars)
        if workout.kind == "recorded", let original = workout.original {
            priorWindow = ActivityWindow(start: original.start, end: original.end)
        } else { priorWindow = window }
        bandStrips = (workout.kind == "recorded" ? workout.original.map { [$0] } ?? [] : []) + workout.merged.filter { $0.kind == "recorded" }
        saved = limits.map { Self.candidates(for: workout, workouts: workouts, gapMinutes: $0.mergeGapMinutes) } ?? (nil, nil)
        window = bounds.clamp(window, pauses: workout.pauses)
    }
    public var body: EditBody {
        let original = workout.original
        let sameSport = sport == original?.exerciseType || sport == workout.exerciseType && workout.edit?.exerciseType == nil
        let sameWindow = window.start == (original?.start ?? workout.start) && window.end == (original?.end ?? workout.end)
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return EditBody(exerciseType: sameSport ? nil : sport, start: sameWindow ? nil : window.start, end: sameWindow ? nil : window.end,
                        notes: note.isEmpty ? nil : note, mergeWith: workout.edit?.mergeWith ?? [])
    }
    public var hasChanges: Bool { body != EditBody(workout.edit) }
    public var deleteBody: EditBody { EditBody(workout.edit, hidden: true) }
    public var undoRequest: EditUndo { workout.edit.map { .put(EditBody($0)) } ?? .delete }
    public var restore: EditUndo { .delete }
    public func mergeBody(_ candidate: Workout) -> EditBody {
        var result = body
        result.start = min(window.start, candidate.start)
        result.end = max(window.end, candidate.end)
        if candidate.kind != "detected" && !result.mergeWith.contains(candidate.id) { result.mergeWith.append(candidate.id) }
        return result
    }
    public var estimate: WindowEstimate { WindowEstimator(heartRate: heartRate).estimate(start: window.start, end: window.end, pauses: workout.pauses) }
    public var prior: WindowEstimate { WindowEstimator(heartRate: heartRate).estimate(start: priorWindow.start, end: priorWindow.end, pauses: workout.pauses) }
    public func offers(_ candidate: Workout) -> Bool {
        guard let limits else { return false }
        let union = ActivityWindow(start: min(window.start, candidate.start), end: max(window.end, candidate.end))
        if candidate.kind == "detected" { return bounds.allows(union, pauses: workout.pauses) }
        return (workout.edit?.mergeWith ?? []).count < limits.mergeMaxIds
            && (candidate.edit?.mergeWith ?? []).isEmpty
            && EditBounds.edit(workout, heartRate: heartRate, limits: limits, now: now, merging: candidate).allows(union, pauses: workout.pauses)
    }
    public static func candidates(for target: Workout, workouts: [Workout], gapMinutes: Int) -> (previous: Workout?, next: Workout?) {
        guard target.kind != "detected" else { return (nil, nil) }
        let rows = workouts.filter { $0.id != target.id && $0.cycleDate == target.cycleDate && ["recorded", "goop", "detected"].contains($0.kind) }
        let previous = rows.filter { $0.start < target.start && target.start.timeIntervalSince($0.end) <= Double(gapMinutes) * 60 }.max { $0.start < $1.start }
        let next = rows.filter { $0.start >= target.start && $0.start.timeIntervalSince(target.end) <= Double(gapMinutes) * 60 }.min { $0.start < $1.start }
        return (previous, next)
    }
    public static func fetchSpan(for workout: Workout, workouts: [Workout], limits: EditLimits, now: Date) -> DateInterval {
        let candidates = candidates(for: workout, workouts: workouts, gapMinutes: limits.mergeGapMinutes)
        let entries = [workout] + [candidates.previous, candidates.next].compactMap { $0 }
        let starts = entries.flatMap { [$0.start, $0.original?.start ?? $0.start] + $0.merged.map(\.start) }
        let ends = entries.flatMap { [$0.end, $0.original?.end ?? $0.end] + $0.merged.map(\.end) }
        let shift = Double(limits.shiftMinutes) * 60
        var start = ActivityWindow.minute(starts.min()!.addingTimeInterval(-shift))
        var end = ActivityWindow.minute(min(now, ends.max()!.addingTimeInterval(shift)))
        let cap = Double(limits.heartRateSpanMaxMinutes) * 60
        if end.timeIntervalSince(start) > cap {
            let mid = workout.start.addingTimeInterval(workout.end.timeIntervalSince(workout.start) / 2)
            start = max(start, ActivityWindow.minute(min(mid.addingTimeInterval(-cap / 2), end.addingTimeInterval(-cap))))
            end = min(end, start.addingTimeInterval(cap))
        }
        return DateInterval(start: start, end: end)
    }
}
