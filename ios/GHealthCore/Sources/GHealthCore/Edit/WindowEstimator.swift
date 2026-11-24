import Foundation

public struct WindowEstimate: Sendable {
    public var strain: Double?
    public var trimp: Double?
    public var avgHrBpm: Int?
    public var peakHrBpm: Int?
    public var zonesMinutes: Zones?
    public var hrCoverage: Double?
    public var elapsedMinutes: Double
    public var pausedMinutes: Int
    public var expected: Int
    public var covered: Int
}

public struct WindowEstimator: Sendable {
    public let heartRate: HeartRateBody
    public init(heartRate: HeartRateBody) { self.heartRate = heartRate }
    public func estimate(start: Date, end: Date, pauses: [ActivityPause] = []) -> WindowEstimate {
        let first = floor(start.timeIntervalSince1970 / 60) * 60
        let minutes = Dictionary(heartRate.minutes.map { (Int($0.t.timeIntervalSince1970), $0) }, uniquingKeysWith: { _, last in last })
        var covered: [HeartRateMinute] = []
        var expected = 0
        var paused = 0
        for t in stride(from: first, to: end.timeIntervalSince1970, by: 60) {
            let at = Date(timeIntervalSince1970: t)
            if pauses.contains(where: { at < ($0.end ?? end) && at.addingTimeInterval(60) > $0.start }) { paused += 1; continue }
            expected += 1
            if let minute = minutes[Int(t)] { covered.append(minute) }
        }
        var out = WindowEstimate(strain: nil, trimp: nil,
                                 avgHrBpm: covered.isEmpty ? nil : Int((covered.reduce(0) { $0 + $1.avgBpm } / Double(covered.count)).rounded()),
                                 peakHrBpm: covered.map(\.maxBpm).max(), zonesMinutes: nil,
                                 hrCoverage: expected > 0 ? StrainMath.rounded(Double(covered.count) / Double(expected), places: 2) : nil,
                                 elapsedMinutes: StrainMath.rounded(end.timeIntervalSince(start) / 60, places: 1), pausedMinutes: paused, expected: expected, covered: covered.count)
        guard !covered.isEmpty, let rest = heartRate.restingHrBpm, let max = heartRate.maxHrBpm, max > rest, let model = heartRate.scoreConstants?.strain else { return out }
        var zones = Array(repeating: 0, count: 6)
        var trimp = 0.0
        for minute in covered {
            zones[StrainMath.zone(bpm: minute.avgBpm, rest: Double(rest), maximum: Double(max), zones: model.zonesHrr)] += 1
            trimp += StrainMath.trimp(bpm: minute.avgBpm, rest: Double(rest), maximum: Double(max), model: model)
        }
        out.strain = StrainMath.strain(trimp: trimp, scale: model.scale)
        out.trimp = StrainMath.rounded(trimp, places: 1)
        out.zonesMinutes = Zones(below: zones[0], z1: zones[1], z2: zones[2], z3: zones[3], z4: zones[4], z5: zones[5])
        return out
    }
}
