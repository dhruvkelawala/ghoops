import Foundation

public struct SleepEditRange: Codable, Sendable {
    public var earliestStart: Date
    public var latestEnd: Date
}

public struct SleepEdit: Codable, Sendable {
    public var start: Date
    public var end: Date
    public var updatedAt: Date
}

public struct SleepEditBody: Codable, Sendable {
    public var start: Date
    public var end: Date
    public var ifUpdatedAt: Date?
    public init(start: Date, end: Date, ifUpdatedAt: Date?) {
        self.start = start; self.end = end; self.ifUpdatedAt = ifUpdatedAt
    }
    private enum CodingKeys: String, CodingKey { case start, end, ifUpdatedAt }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end)
        try c.encode(ifUpdatedAt, forKey: .ifUpdatedAt)
    }
}

public struct SleepEditResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var date: String
    public var sleepEdit: SleepEdit?
}

public struct SleepEditBounds: Sendable {
    public let range: SleepEditRange
    public let google: ActivityWindow
    public let minimum: TimeInterval
    public let current: ActivityWindow
    public init(range: SleepEditRange, minimumMinutes: Int, google: ActivityWindow, current: ActivityWindow, now: Date) {
        self.range = SleepEditRange(earliestStart: ActivityWindow.ceilMinute(range.earliestStart), latestEnd: ActivityWindow.minute(min(now, range.latestEnd)))
        self.google = google; minimum = Double(minimumMinutes) * 60; self.current = current
    }
    private var usable: Bool { range.latestEnd.timeIntervalSince(range.earliestStart) >= minimum }
    public func startRange(end: Date) -> ClosedRange<Date> {
        guard usable else { return current.start...current.start }
        let upper = min(end.addingTimeInterval(-minimum), google.end.addingTimeInterval(-60))
        return range.earliestStart <= upper ? range.earliestStart...upper : current.start...current.start
    }
    public func endRange(start: Date) -> ClosedRange<Date> {
        guard usable else { return current.end...current.end }
        let lower = max(start.addingTimeInterval(minimum), google.start.addingTimeInterval(60))
        return lower <= range.latestEnd ? lower...range.latestEnd : current.end...current.end
    }
    public var span: DateInterval { DateInterval(start: range.earliestStart, end: max(range.earliestStart, range.latestEnd)) }
}

public struct SleepEditDraft: Sendable {
    public let sleep: Sleep
    public let google: SleepGoogle
    public let bounds: SleepEditBounds
    public var window: ActivityWindow
    public let segments: [SleepSegment]
    public init?(sleep: Sleep, limits: EditLimits?, now: Date) {
        guard let session = sleep.session, let google = session.google, let range = session.editRange,
              let minimum = limits?.sleepMinMinutes, minimum > 0, let hypnogram = sleep.hypnogram else { return nil }
        self.sleep = sleep; self.google = google
        window = ActivityWindow(start: session.start, end: session.end)
        bounds = SleepEditBounds(range: range, minimumMinutes: minimum, google: google.window, current: window, now: now)
        var full: [SleepSegment] = []
        for segment in (hypnogram.segments + (hypnogram.outside ?? [])).sorted(by: { $0.start < $1.start }) {
            if let last = full.last, last.end == segment.start, last.stage == segment.stage,
               segment.start == hypnogram.start || segment.start == hypnogram.end {
                full[full.count - 1].end = segment.end
            } else { full.append(segment) }
        }
        segments = full
    }
    public var hasChanges: Bool { window.start != sleep.session?.start || window.end != sleep.session?.end }
    public var body: SleepEditBody { SleepEditBody(start: window.start, end: window.end, ifUpdatedAt: sleep.session?.edit?.updatedAt) }
    public var values: SleepWindowValues { SleepWindowRule.values(google: google, segments: segments, window: window) }
    public var prior: SleepWindowValues { SleepWindowRule.values(google: google, segments: segments, window: google.window) }
    public mutating func moveStart(to date: Date) {
        let range = bounds.startRange(end: window.end)
        window.start = min(range.upperBound, max(range.lowerBound, ActivityWindow.minute(date)))
    }
    public mutating func moveEnd(to date: Date) {
        let range = bounds.endRange(start: window.start)
        window.end = min(range.upperBound, max(range.lowerBound, ActivityWindow.minute(date)))
    }
}
