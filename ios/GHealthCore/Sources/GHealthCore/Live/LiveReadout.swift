import Foundation

/// What a live surface shows for heart rate and zone (live-hr-spec §3).
public struct LiveReadout: Equatable, Sendable {
    public enum Heart: Equatable, Sendable { case live, lost, none }
    public enum Status: Equatable, Sendable { case zone(Int), zoneUnknown, reconnecting, noHeartRate }
    public let heart: Heart
    /// The reading shown; nil exactly when `heart == .none`.
    public let bpm: Int?
    /// The zone the meter lights; nil when unknown or when `heart == .none`.
    public let zone: Int?

    public init(bpm: Int?, zone: Int?, hr: ActivityHRState, isStale: Bool = false) {
        heart = hr == .none || bpm == nil ? .none : hr == .reconnecting || isStale ? .lost : .live
        self.bpm = heart == .none ? nil : bpm
        self.zone = heart == .none ? nil : zone
    }

    public init(session: ActivitySession, estimate: LiveEstimate?, now: Date) {
        self.init(bpm: session.samples.last.map { Int($0.bpm.rounded()) }, zone: estimate?.zone, hr: session.hrState(at: now))
    }

    public var value: String { bpm.map(String.init) ?? "—" }
    public var showsUnit: Bool { bpm != nil }
    public var dimmed: Bool { heart == .lost }
    public var status: Status {
        switch heart {
        case .none: .noHeartRate
        case .lost: .reconnecting
        case .live: zone.map(Status.zone) ?? .zoneUnknown
        }
    }
    public var statusText: String {
        switch status {
        case .zone, .zoneUnknown: zoneText
        case .reconnecting: "RECONNECTING"
        case .noHeartRate: "NO HR"
        }
    }
    public var statusSpoken: String {
        switch status {
        case .zone, .zoneUnknown: zoneSpoken
        case .reconnecting: "Reconnecting"
        case .noHeartRate: "No heart rate"
        }
    }
    public var zoneText: String { zone.map { "ZONE \($0)" } ?? "ZONE —" }
    public var zoneSpoken: String { zone.map { "Zone \($0)" } ?? "Zone unknown" }
    public var chipText: String { heart == .live ? "LIVE" : statusText }
    public var chipSpoken: String { heart == .live ? "Live" : statusSpoken }
    public var spoken: String {
        guard let bpm else { return "No heart rate" }
        return "\(bpm) bpm" + (dimmed ? ", reconnecting" : "")
    }
}
