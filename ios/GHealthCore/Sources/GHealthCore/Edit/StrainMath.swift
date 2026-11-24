import Foundation

public enum StrainMath {
    public static func strain(trimp: Double, scale: StrainScale) -> Double {
        // contract §5.4: Strain is 0 to 21
        rounded(min(21, 21 * log1p(trimp / scale.k) / log1p(scale.trimpCap / scale.k)), places: 1)
    }
    public static func zone(bpm: Double, rest: Double, maximum: Double, zones: ZoneFloors) -> Int {
        let h = (bpm - rest) / (maximum - rest)
        return zones.all.filter { h >= $0 }.count
    }
    public static func trimp(bpm: Double, rest: Double, maximum: Double, model: StrainModel) -> Double {
        let h = min(1, (bpm - rest) / (maximum - rest))
        guard h >= model.zonesHrr.z1 else { return 0 }
        return h * model.trimp.a * exp(model.trimp.b * h)
    }
    public static func confidence(covered: Int, expected: Int, cuts: CoverageCuts) -> Confidence? {
        guard expected > 0 else { return nil }
        let coverage = Double(covered) / Double(expected)
        return coverage >= cuts.high ? .high : coverage >= cuts.medium ? .medium : .low
    }
    public static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}
