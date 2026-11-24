import Foundation

public struct SleepPatch: Codable, Sendable {
    public var date: String
    public var window: ActivityWindow
    public var values: SleepWindowValues
    public var efficiencyBand: Band3?
    public var hypnogram: Hypnogram
    public var updating: [String]

    public init(_ draft: SleepEditDraft) {
        date = draft.sleep.date; window = draft.window; values = draft.values
        if let edges = draft.sleep.scoreConstants?.sleep.efficiencyBands, let pct = values.efficiencyPct {
            efficiencyBand = pct >= edges.high ? .high : pct >= edges.medium ? .medium : .low
        }
        hypnogram = draft.sleep.hypnogram!
        hypnogram.start = window.start; hypnogram.end = window.end
        hypnogram.segments = values.segments; hypnogram.unstaged = values.unstaged
        let window = draft.window
        hypnogram.outside = draft.segments.flatMap { segment -> [SleepSegment] in
            var parts: [SleepSegment] = []
            if segment.start < window.start { parts.append(SleepSegment(start: segment.start, end: min(window.start, segment.end), stage: segment.stage)) }
            if segment.end > window.end { parts.append(SleepSegment(start: max(window.end, segment.start), end: segment.end, stage: segment.stage)) }
            return parts
        }
        updating = [GoopFormat.addingDays(-1, to: date), date]
    }
    public func apply(to sleep: Sleep) -> Sleep {
        guard sleep.date == date else { return sleep }
        var sleep = sleep
        sleep.bedtime = window.start; sleep.wakeTime = window.end
        sleep.timeInBedMinutes = values.timeInBedMinutes; sleep.asleepMinutes = values.asleepMinutes
        sleep.efficiencyPct = values.efficiencyPct; sleep.efficiencyBand = efficiencyBand; sleep.stages = values.stages
        sleep.hypnogram = hypnogram; sleep.session?.start = window.start; sleep.session?.end = window.end
        return sleep
    }
    public func apply(to sleep: SleepSummary) -> SleepSummary {
        var sleep = sleep
        sleep.bedtime = window.start; sleep.wakeTime = window.end
        sleep.timeInBedMinutes = values.timeInBedMinutes; sleep.asleepMinutes = values.asleepMinutes
        sleep.efficiencyPct = values.efficiencyPct; sleep.efficiencyBand = efficiencyBand; sleep.stages = values.stages
        return sleep
    }
}

extension ChangeBuilder {
    public static func sleep(_ draft: SleepEditDraft, restore: Bool = false, serverURL: String, now: Date) -> PendingChange {
        var draft = draft
        if restore { draft.window = draft.google.window }
        let date = draft.sleep.date
        return PendingChange(kind: .sleep, request: restore ? .deleteSleepEdit(date) : .putSleepEdit(date, draft.body),
                             targets: ["sleep-\(date)"], cycleDates: (-1...3).map { GoopFormat.addingDays($0, to: date) },
                             name: GoopFormat.dateLabel(date, format: "EEE d MMM"), sleepPatch: SleepPatch(draft), serverURL: serverURL, createdAt: now)
    }
}
