import Foundation

public struct LiveEstimate: Sendable {
    public var strain: Double?
    public var trimp: Double?
    public var scale: StrainScale?
    public var average: Int?
    public var maximum: Int?
    public var zone: Int?
    public var zones: [Double]
    public var zones45Seconds: TimeInterval { (zones[4] + zones[5]) * 60 }
    public var zones45Minutes: Int? { strain == nil ? nil : Int(zones45Seconds / 60) }
    public var wholeZones: Zones { Zones(below: Int(zones[0]), z1: Int(zones[1]), z2: Int(zones[2]), z3: Int(zones[3]), z4: Int(zones[4]), z5: Int(zones[5])) }
}
public struct LiveEstimator: Sendable {
    public let restingHR: Double?
    public let maximumHR: Double?
    public let model: StrainModel?
    public init(restingHR: Double?, maximumHR: Double?, model: StrainModel?) {
        self.restingHR = restingHR; self.maximumHR = maximumHR; self.model = model
    }
    public var isAvailable: Bool {
        guard let restingHR, let maximumHR, maximumHR > restingHR, model != nil else { return false }
        return true
    }
    public func zone(bpm: Double) -> Int? {
        guard let rest = restingHR, let max = maximumHR, max > rest, let model else { return nil }
        return StrainMath.zone(bpm: bpm, rest: rest, maximum: max, zones: model.zonesHrr)
    }
    public func range(zone: Int) -> String {
        ZoneScale(rest: restingHR, maximum: maximumHR, zones: model?.zonesHrr)?.range(zone) ?? "—"
    }

    public func estimate(_ session: ActivitySession, now: Date) -> LiveEstimate {
        let until = session.end ?? now
        let active = session.samples.filter { $0.t <= until && session.isActive(at: $0.t) }
        let buckets = Dictionary(grouping: active) { Int(floor($0.t.timeIntervalSince1970 / 60)) }
        let means = buckets.mapValues { $0.reduce(0) { $0 + $1.bpm } / Double($0.count) }
        var out = LiveEstimate(strain: nil, trimp: nil, average: means.isEmpty ? nil : Int((means.values.reduce(0, +) / Double(means.count)).rounded()), maximum: active.map { Int($0.bpm.rounded()) }.max(), zone: session.samples.last.flatMap { zone(bpm: $0.bpm) }, zones: Array(repeating: 0, count: 6))
        guard let rest = restingHR, let max = maximumHR, max > rest, let model else { return out }
        out.scale = model.scale
        var trimp = 0.0
        let clock = session.state == .paused ? (session.pauses.last?.start ?? until) : until
        for (minute, mean) in means {
            let weight = min(1, Swift.max(0, (clock.timeIntervalSince1970 - Double(minute) * 60) / 60))
            let z = zone(bpm: mean)!
            out.zones[z] += weight
            trimp += StrainMath.trimp(bpm: mean, rest: rest, maximum: max, model: model) * weight
        }
        if !means.isEmpty { out.strain = StrainMath.strain(trimp: trimp, scale: model.scale); out.trimp = (trimp * 10).rounded() / 10 }
        return out
    }
    public func localActivity(_ session: ActivitySession, now: Date) -> LocalActivity {
        let estimate = estimate(session, now: now)
        let grouped = Dictionary(grouping: session.samples.filter { session.isActive(at: $0.t) }) { Int($0.t.timeIntervalSince1970 / 5) }
        let points = grouped.keys.sorted().map { key in
            HeartRatePoint(t: Date(timeIntervalSince1970: Double(key * 5)), bpm: Int((grouped[key]!.reduce(0) { $0 + $1.bpm } / Double(grouped[key]!.count)).rounded()))
        }
        return LocalActivity(upload: ActivityUpload(id: session.id, exerciseType: session.exerciseType, displayName: session.displayName, start: session.start, end: session.end ?? now, pauses: session.pauses, live: ActivityLiveValues(strainEstimate: estimate.strain, avgHrBpm: estimate.average, maxHrBpm: estimate.maximum, samples: session.samples.count)), cycleDate: session.cycleDate ?? session.target?.cycleDate, zonesMinutes: estimate.strain == nil ? nil : estimate.wholeZones, hrSeries: points, mac: session.mac)
    }
}
