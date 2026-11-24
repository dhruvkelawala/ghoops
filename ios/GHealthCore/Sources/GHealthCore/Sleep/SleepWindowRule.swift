import Foundation

public struct SleepGoogle: Codable, Sendable {
    public var start: Date
    public var end: Date
    public var asleepMinutes: Int?
    public var minutesToFallAsleep: Int?
    public var stageMinutes: [String: Int?]
    public var stageSegments: [String: Int?]
    public var window: ActivityWindow { ActivityWindow(start: start, end: end) }
}

public struct SleepWindowValues: Codable, Sendable {
    public var timeInBedMinutes: Int
    public var asleepMinutes: Int?
    public var efficiencyPct: Int?
    public var minutesToFallAsleep: Int?
    public var stages: SleepStages
    public var unstaged: [Span]
    public var awakeSegments: Int
    @DefaultEmpty public var segments: [SleepSegment]
}

/// scores.md §4.2a. Uncovered time at the window's edges is unstaged sleep, less any of it Google's
/// total already counts. A gap between two segments adds nothing: Google's total has already decided it.
public enum SleepWindowRule {
    static let sleepStages: Set<String> = ["light", "deep", "rem", "asleep"]
    static func minutes(_ seconds: Double) -> Int { Int((seconds / 60).rounded()) }

    public static func values(google: SleepGoogle, segments: [SleepSegment], window: ActivityWindow) -> SleepWindowValues {
        var clipped = false
        var seconds: [String: Double] = [:], counts: [String: Int] = [:]
        var kept: [SleepSegment] = [], spans: [Span] = []
        var sleepSeconds = 0.0, googleSleepSeconds = 0.0, awake = 0
        for var segment in segments {
            segment.stage = segment.stage.lowercased()
            if sleepStages.contains(segment.stage) { googleSleepSeconds += segment.end.timeIntervalSince(segment.start) }
            clipped = clipped || segment.start < window.start || segment.end > window.end
            segment.start = max(segment.start, window.start); segment.end = min(segment.end, window.end)
            guard segment.start < segment.end else { continue }
            kept.append(segment)
            let duration = segment.end.timeIntervalSince(segment.start)
            seconds[segment.stage, default: 0] += duration
            counts[segment.stage, default: 0] += 1
            if sleepStages.contains(segment.stage) { sleepSeconds += duration }
            if segment.stage == "awake", segment.start > window.start, segment.end < window.end { awake += 1 }
        }
        kept.sort { $0.start < $1.start }
        var asleep = google.asleepMinutes
        var unstaged = SleepStage()
        if !segments.isEmpty {
            var cursor = window.start, gapSeconds = 0.0
            for (i, segment) in kept.enumerated() {
                if cursor < segment.start, i == 0 { spans.append(Span(start: cursor, end: segment.start)) }
                else if cursor < segment.start { gapSeconds += segment.start.timeIntervalSince(cursor) }
                cursor = max(cursor, segment.end)
            }
            if cursor < window.end { spans.append(Span(start: cursor, end: window.end)) }
            let edge = minutes(spans.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }), gaps = minutes(gapSeconds)
            // Minutes of Google's total that no sleep segment explains lie in its uncovered time: in the gaps first, then at the edges.
            let unexplained = google.asleepMinutes.map { max(0, $0 - minutes(googleSleepSeconds)) } ?? 0
            let inGaps = min(gaps, unexplained)
            var added = edge
            if clipped { asleep = minutes(sleepSeconds) + inGaps + edge }
            else if let total = asleep { added = max(0, edge - (unexplained - inGaps)); asleep = total + added }
            unstaged = SleepStage(minutes: added, segments: spans.count)
        }
        let duration = window.end.timeIntervalSince(window.start) / 60
        if let value = asleep, value < 0 || Double(value) > duration { asleep = nil } // the inputs don't reconcile with the window
        func percent(_ minutes: Int?) -> Double? {
            guard let minutes, let asleep, asleep > 0 else { return nil }
            return (1000 * Double(minutes) / Double(asleep)).rounded() / 10
        }
        func stage(_ key: String) -> SleepStage {
            var minutes = google.stageMinutes[key] ?? nil
            var count = google.stageSegments[key] ?? nil
            if google.stageMinutes.keys.contains(key), clipped {
                minutes = Self.minutes(seconds[key, default: 0]); count = counts[key, default: 0]
            }
            return SleepStage(minutes: minutes, segments: count, pctOfAsleep: key == "awake" ? nil : percent(minutes))
        }
        unstaged.pctOfAsleep = percent(unstaged.minutes)
        return SleepWindowValues(timeInBedMinutes: Int(duration.rounded()), asleepMinutes: asleep,
                                 efficiencyPct: duration > 0 ? asleep.map { Int((100 * Double($0) / duration).rounded()) } : nil,
                                 minutesToFallAsleep: window.start == google.start ? google.minutesToFallAsleep : nil,
                                 stages: SleepStages(light: stage("light"), deep: stage("deep"), rem: stage("rem"), awake: stage("awake"), unstaged: unstaged),
                                 unstaged: spans, awakeSegments: awake, segments: kept)
    }
}
