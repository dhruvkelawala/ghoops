import Foundation

public enum WorkoutProjection {
    public static func project(_ base: Workout, body: EditBody, window: ActivityWindow, heartRate: HeartRateBody, aliases: [String: String] = [:], now: Date) -> Workout {
        var result = base
        let originalType = base.original?.exerciseType ?? base.exerciseType
        let type = body.exerciseType ?? originalType.map { base.kind == "recorded" ? aliases[$0] ?? $0 : $0 }
        result.exerciseType = type
        if let sport = ActivitySport.all.first(where: { $0.id == type }) { result.displayName = sport.name }
        else if type != base.exerciseType { result.displayName = base.original?.displayName ?? base.displayName }
        if type != base.exerciseType { result.category = ActivitySport.category(for: type ?? "OTHER") }
        result.start = window.start; result.end = window.end
        result.pauses = base.kind == "goop" ? base.pauses.compactMap { pause in
            let start = max(window.start, pause.start), end = min(window.end, pause.end ?? window.end)
            return start < end ? ActivityPause(start: start, end: end) : nil
        } : []
        let estimate = WindowEstimator(heartRate: heartRate).estimate(start: window.start, end: window.end, pauses: result.pauses)
        result.elapsedMinutes = estimate.elapsedMinutes; result.pausedMinutes = estimate.pausedMinutes
        result.activeMinutes = base.kind == "goop" ? estimate.elapsedMinutes - Double(estimate.pausedMinutes) : nil
        result.strain = estimate.strain; result.trimp = estimate.trimp; result.hrCoverage = estimate.hrCoverage
        result.avgHrBpm = estimate.avgHrBpm; result.peakHrBpm = estimate.peakHrBpm; result.zonesMinutes = estimate.zonesMinutes
        result.confidence = estimate.strain == nil ? nil : heartRate.scoreConstants.flatMap { StrainMath.confidence(covered: estimate.covered, expected: estimate.expected, cuts: $0.strain.coverage) }
        result.hrSeries = heartRate.minutes.filter { minute in
            minute.t >= ActivityWindow.minute(window.start) && minute.t < window.end
                && !result.pauses.contains { minute.t < ($0.end ?? window.end) && minute.t.addingTimeInterval(60) > $0.start }
        }.map { HeartRatePoint(t: $0.t, bpm: Int($0.avgBpm.rounded())) }
        result.notes = body.notes ?? (base.kind == "goop" && base.edit?.notes == nil ? base.notes : nil)
        let edited = body.exerciseType != nil || body.start != nil || body.end != nil || !body.mergeWith.isEmpty
        result.edit = edited || body.notes != nil || body.hidden ? WorkoutEdit(exerciseType: body.exerciseType, start: body.start, end: body.end, notes: body.notes, mergeWith: body.mergeWith, updatedAt: now) : nil
        result.edited = edited
        return result
    }

    public static func added(_ upload: ActivityUpload, cycleDate: String, heartRate: HeartRateBody, now: Date) -> Workout {
        var base = LocalActivity(upload: upload, cycleDate: cycleDate).workout()
        base.origin = "added"
        base.original = WorkoutOriginal(exerciseType: upload.exerciseType, displayName: upload.displayName, start: upload.start, end: upload.end)
        return project(base, body: EditBody(), window: ActivityWindow(start: upload.start, end: upload.end), heartRate: heartRate, now: now)
    }

    public static func restored(_ base: Workout, original: WorkoutOriginal, heartRate: HeartRateBody, aliases: [String: String], now: Date) -> Workout {
        var result = base
        result.id = original.id ?? base.id; result.kind = original.kind ?? base.kind
        let type = original.exerciseType.map { result.kind == "recorded" ? aliases[$0] ?? $0 : $0 }
        result.original = WorkoutOriginal(exerciseType: original.exerciseType, displayName: original.displayName, start: original.start, end: original.end)
        result.exerciseType = type; result.displayName = original.displayName
        result.category = ActivitySport.category(for: type ?? "OTHER")
        result.edit = nil; result.edited = false; result.notes = nil; result.merged = []
        if original.id != nil { result.provider = nil; result.source = result.kind == "goop" ? .goop : base.source }
        result = project(result, body: EditBody(), window: ActivityWindow(start: original.start, end: original.end), heartRate: heartRate, aliases: aliases, now: now)
        return result
    }
}
