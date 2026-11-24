import Foundation

public enum ActivitySessionState: String, Codable, Sendable { case running, paused, ended }
public enum ActivityHRState: String, Codable, Sendable { case live, reconnecting, none }
public struct ActivitySession: Codable, Sendable, Identifiable {
    public static let liveWindow: TimeInterval = 10
    /// The longest the phone records one session: its sample buffer and file. Not the Mac's limit (live-polish-spec D10).
    public static let recordingSpan: TimeInterval = 12 * 3600
    public var id: String
    public var exerciseType: String
    public var displayName: String
    public var start: Date
    public let cycleDate: String?
    public private(set) var end: Date?
    public private(set) var pauses: [ActivityPause] = []
    public private(set) var samples: [HeartRateSample] = []
    public private(set) var state: ActivitySessionState = .running
    public var updatedAt: Date
    public var target: SessionTarget?
    /// The Mac this session was started for; nil for sessions written before pairing isolation.
    public let mac: PairedMac?
    /// The Mac's shortest and longest active time, taken from `status.edit_limits` at start; nil when it sent none.
    public private(set) var activeMin: TimeInterval?
    public private(set) var activeMax: TimeInterval?
    public init(sport: ActivitySport, now: Date, cycleDate: String? = nil, limits: EditLimits? = nil, id: String = UUID().uuidString.lowercased(), mac: PairedMac? = nil) {
        self.id = id; exerciseType = sport.id; displayName = sport.name; start = Self.second(now); updatedAt = now; self.cycleDate = cycleDate; self.mac = mac
        activeMin = limits.map { Double($0.activeMinMinutes) * 60 }; activeMax = limits.map { Double($0.activeMaxMinutes) * 60 }
    }
    /// True when pairing with `url` would move this running session to a different Mac.
    public func blocksPairing(with url: String) -> Bool { mac?.url != url }
    public func elapsed(at now: Date) -> TimeInterval {
        let until = end ?? min(now, start.addingTimeInterval(Self.recordingSpan))
        return max(0, until.timeIntervalSince(start) - pausedTotal(at: until))
    }
    public func pausedTotal(at now: Date) -> TimeInterval {
        pauses.reduce(0) { $0 + max(0, min($1.end ?? now, now).timeIntervalSince($1.start)) }
    }
    public func hrState(at now: Date) -> ActivityHRState {
        guard let sample = samples.last else { return .none }
        return now.timeIntervalSince(sample.t) < Self.liveWindow ? .live : .reconnecting
    }
    public var liveUntil: Date? { samples.last?.t.addingTimeInterval(Self.liveWindow) }
    public func isActive(at date: Date) -> Bool {
        date >= start && date < (end ?? start.addingTimeInterval(Self.recordingSpan)) && !pauses.contains { date >= $0.start && date < ($0.end ?? .distantFuture) }
    }
    public mutating func append(_ sample: HeartRateSample) {
        guard state != .ended, sample.t >= start, sample.t < start.addingTimeInterval(Self.recordingSpan), (1...250).contains(sample.bpm), samples.last.map({ sample.t >= $0.t }) ?? true else { return }
        if let last = samples.last, Int(last.t.timeIntervalSince1970) == Int(sample.t.timeIntervalSince1970) { samples[samples.count - 1] = sample }
        else if samples.count < Int(Self.recordingSpan) { samples.append(sample) }
    }
    public mutating func pause(at now: Date) {
        guard state == .running else { return }
        pauses.append(ActivityPause(start: max(start, Self.second(now)))); state = .paused; updatedAt = now
    }
    public mutating func resume(at now: Date) {
        guard state == .paused else { return }
        pauses[pauses.count - 1].end = max(pauses[pauses.count - 1].start, Self.second(now)); state = .running; updatedAt = now
    }
    /// True when the Mac accepts this active time: at least its minimum, or one second when it sent none.
    public func savable(at now: Date) -> Bool {
        let active = elapsed(at: now)
        return activeMin.map { active >= $0 } ?? (active > 0)
    }
    /// True when a running session must end: the Mac's maximum active time or the recording span is reached.
    public func limitReached(at now: Date) -> Bool {
        guard state != .ended else { return false }
        return now.timeIntervalSince(start) >= Self.recordingSpan || activeMax.map { elapsed(at: now) >= $0 } ?? false
    }
    /// Ends the session at `now`, or earlier where a limit is reached. Returns whether it can be saved.
    @discardableResult public mutating func finish(at now: Date) -> Bool {
        guard state != .ended else { return savable(at: now) }
        var until = min(max(start, Self.second(now)), start.addingTimeInterval(Self.recordingSpan))
        if let activeMax { until = min(until, reaching(activeMax)) }
        pauses = pauses.filter { $0.start < until }.map { ActivityPause(start: $0.start, end: min($0.end ?? until, until)) }
        end = until; state = .ended; updatedAt = until
        return savable(at: until)
    }
    public mutating func enforceLimit(at now: Date) -> Bool {
        guard limitReached(at: now) else { return false }
        finish(at: now); return true
    }
    /// The moment active time reaches `active`; distant future while an open pause holds it below.
    private func reaching(_ active: TimeInterval) -> Date {
        var time = start, left = active
        for pause in pauses {
            let run = max(0, pause.start.timeIntervalSince(time))
            if run >= left { return time.addingTimeInterval(left) }
            left -= run
            guard let resumed = pause.end else { return .distantFuture }
            time = max(time, resumed)
        }
        return time.addingTimeInterval(left)
    }
    /// Uploads carry whole seconds, so session times do too (live-polish-spec D11).
    static func second(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) }
    private enum CodingKeys: String, CodingKey { case id, exerciseType, displayName, start, cycleDate, end, pauses, samples, state, updatedAt, target, mac, activeMin, activeMax }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); exerciseType = try c.decode(String.self, forKey: .exerciseType); displayName = try c.decode(String.self, forKey: .displayName)
        start = try c.decode(Date.self, forKey: .start); end = try c.decodeIfPresent(Date.self, forKey: .end)
        target = try c.decodeIfPresent(SessionTarget.self, forKey: .target)
        cycleDate = try c.decodeIfPresent(String.self, forKey: .cycleDate) ?? target?.cycleDate
        mac = try c.decodeIfPresent(PairedMac.self, forKey: .mac)
        activeMin = try c.decodeIfPresent(TimeInterval.self, forKey: .activeMin); activeMax = try c.decodeIfPresent(TimeInterval.self, forKey: .activeMax)
        pauses = try c.decode([ActivityPause].self, forKey: .pauses); state = try c.decode(ActivitySessionState.self, forKey: .state); updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        let deltas = try c.decode([[Double]].self, forKey: .samples)
        guard deltas.count <= Int(Self.recordingSpan), deltas.allSatisfy({ $0.count == 2 && $0[0] >= 0 && $0[0] < Self.recordingSpan && (1...250).contains($0[1]) }) else { throw DecodingError.dataCorruptedError(forKey: .samples, in: c, debugDescription: "Invalid session samples") }
        samples = deltas.map { HeartRateSample(t: start.addingTimeInterval($0[0]), bpm: $0[1]) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(exerciseType, forKey: .exerciseType); try c.encode(displayName, forKey: .displayName)
        try c.encode(start, forKey: .start); try c.encodeIfPresent(end, forKey: .end); try c.encode(pauses, forKey: .pauses); try c.encode(state, forKey: .state); try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(samples.map { [$0.t.timeIntervalSince(start), $0.bpm] }, forKey: .samples)
        try c.encodeIfPresent(target, forKey: .target)
        try c.encodeIfPresent(cycleDate, forKey: .cycleDate)
        try c.encodeIfPresent(mac, forKey: .mac)
        try c.encodeIfPresent(activeMin, forKey: .activeMin); try c.encodeIfPresent(activeMax, forKey: .activeMax)
    }
}
