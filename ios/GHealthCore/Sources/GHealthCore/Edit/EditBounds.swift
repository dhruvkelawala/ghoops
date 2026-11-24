import Foundation

public struct EditBounds: Sendable, Equatable {
    public var span: DateInterval
    public var activeMin: TimeInterval
    public var activeMax: TimeInterval?
    public var originals: [ActivityWindow]
    public var covers: [ActivityWindow]

    public init(span: DateInterval, activeMin: TimeInterval, activeMax: TimeInterval?, originals: [ActivityWindow], covers: [ActivityWindow]) {
        self.span = span; self.activeMin = activeMin; self.activeMax = activeMax
        self.originals = originals; self.covers = covers
    }
    public static func edit(_ workout: Workout, heartRate: HeartRateBody, limits: EditLimits?, now: Date, merging candidate: Workout? = nil) -> EditBounds {
        var originals = [ActivityWindow(start: workout.original?.start ?? workout.start, end: workout.original?.end ?? workout.end)] + workout.merged.map { ActivityWindow(start: $0.start, end: $0.end) }
        var covers = workout.merged.map { ActivityWindow(start: $0.start, end: $0.end) }
        if let candidate, candidate.kind != "detected" {
            originals.append(ActivityWindow(start: candidate.original?.start ?? candidate.start, end: candidate.original?.end ?? candidate.end))
            covers.append(ActivityWindow(start: candidate.start, end: candidate.end))
        }
        var start = heartRate.start, end = min(heartRate.end, now)
        if let limits {
            let shift = Double(limits.shiftMinutes) * 60
            start = max(start, originals.map(\.start).min()!.addingTimeInterval(-shift))
            end = min(end, originals.map(\.end).max()!.addingTimeInterval(shift))
        }
        return rounded(start: start, end: end, window: ActivityWindow(start: workout.start, end: workout.end), limits: limits, originals: originals, covers: covers)
    }
    public static func name(_ effort: Workout, heartRate: HeartRateBody, limits: EditLimits?, now: Date) -> EditBounds {
        var start = heartRate.start, end = min(heartRate.end, now)
        if let limits {
            let shift = Double(limits.shiftMinutes) * 60
            start = max(start, effort.start.addingTimeInterval(-shift), limits.earliestStart(now: now))
            end = min(end, effort.end.addingTimeInterval(shift))
        }
        return rounded(start: start, end: end, window: ActivityWindow(start: effort.start, end: effort.end), limits: limits, originals: [], covers: [])
    }
    public static func add(day: DateInterval, window: ActivityWindow, limits: EditLimits?, now: Date) -> EditBounds {
        rounded(start: max(day.start, limits?.earliestStart(now: now) ?? day.start), end: min(day.end, now), window: window, limits: limits, originals: [], covers: [])
    }
    public func latestStart(end: Date) -> Date {
        var latest = end.addingTimeInterval(-activeMin)
        if let last = originals.filter({ $0.start < end }).map(\.end).max() { latest = min(latest, ActivityWindow.ceilMinute(last).addingTimeInterval(-60)) }
        if let first = covers.map(\.start).min() { latest = min(latest, ActivityWindow.minute(first)) }
        return max(span.start, latest)
    }
    public func earliestEnd(start: Date) -> Date {
        var earliest = start.addingTimeInterval(activeMin)
        if let first = originals.filter({ $0.end > start }).map(\.start).min() { earliest = max(earliest, ActivityWindow.minute(first).addingTimeInterval(60)) }
        if let last = covers.map(\.end).max() { earliest = max(earliest, ActivityWindow.ceilMinute(last)) }
        return min(span.end, earliest)
    }
    public func startRange(end: Date) -> ClosedRange<Date> { span.start...max(span.start, latestStart(end: end)) }
    public func endRange(start: Date) -> ClosedRange<Date> { min(span.end, earliestEnd(start: start))...span.end }
    public func clipped(to visible: DateInterval, window: ActivityWindow) -> EditBounds {
        let start = max(span.start, visible.start), end = min(span.end, visible.end)
        guard start < end, end.timeIntervalSince(start) >= activeMin, activeMax.map({ $0 >= activeMin }) ?? true else {
            return Self.fixed(window, originals: originals, covers: covers)
        }
        var result = self
        result.span = DateInterval(start: start, end: end)
        return result
    }
    public func allows(_ window: ActivityWindow, pauses: [ActivityPause]) -> Bool {
        let active = window.activeSeconds(pauses: pauses)
        return window.start >= span.start && window.end <= span.end && active >= activeMin
            && (activeMax.map { active <= $0 } ?? true)
            && (originals.isEmpty || originals.contains { window.start < $0.end && window.end > $0.start })
            && covers.allSatisfy { window.start <= $0.start && window.end >= $0.end }
    }
    public func clamp(_ window: ActivityWindow, pauses: [ActivityPause]) -> ActivityWindow {
        guard !allows(window, pauses: pauses) else { return window }
        var result = window
        result.moveStart(to: window.start, bounds: self, pauses: pauses)
        result.moveEnd(to: window.end, bounds: self, pauses: pauses)
        return result
    }
    private static func rounded(start: Date, end: Date, window: ActivityWindow, limits: EditLimits?, originals: [ActivityWindow], covers: [ActivityWindow]) -> EditBounds {
        let start = ActivityWindow.ceilMinute(start), end = ActivityWindow.minute(end)
        let activeMin = limits.map { Double($0.activeMinMinutes) * 60 } ?? 60
        let activeMax = limits.map { Double($0.activeMaxMinutes) * 60 }
        guard start < end, end.timeIntervalSince(start) >= activeMin, activeMax.map({ $0 >= activeMin }) ?? true else {
            return fixed(window, originals: originals, covers: covers)
        }
        return EditBounds(span: DateInterval(start: start, end: end), activeMin: activeMin, activeMax: activeMax, originals: originals, covers: covers)
    }
    private static func fixed(_ window: ActivityWindow, originals: [ActivityWindow], covers: [ActivityWindow]) -> EditBounds {
        let span = DateInterval(start: window.start, end: max(window.start, window.end))
        return EditBounds(span: span, activeMin: span.duration, activeMax: span.duration, originals: originals, covers: covers)
    }
}
