import Foundation

public struct ZoneScale: Sendable {
    private let edges: [Int]
    public init?(rest: Double?, maximum: Double?, zones: ZoneFloors?) {
        guard let rest, let maximum, let zones, maximum > rest else { return nil }
        edges = zones.all.map { Int(ceil(rest + $0 * (maximum - rest))) }
    }
    public func range(_ zone: Int) -> String {
        guard (0...5).contains(zone) else { return "—" }
        if zone == 0 { return "<\(edges[0])" }
        if zone == 5 { return "\(edges[4])+" }
        return "\(edges[zone - 1])–\(edges[zone] - 1)"
    }
}
