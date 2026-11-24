import Foundation

public enum SleepLevel: String, Sendable, CaseIterable {
    case poor = "Poor", sufficient = "Sufficient", optimal = "Optimal"
    public init?(_ band: Band3?) {
        switch band {
        case .high: self = .optimal
        case .medium: self = .sufficient
        case .low: self = .poor
        default: return nil
        }
    }
    public var color: GoopColorRole { self == .optimal ? .positive : self == .poor ? .caution : .neutral }
    public var segments: Int { self == .optimal ? 3 : self == .sufficient ? 2 : 1 }
}

/// The names, ranges and colours drawn on a score's explanation scale.
public struct LevelScale: Sendable {
    public enum Tone: Sendable { case caution, neutral, positive, recoveryLow, recoveryMedium, recoveryHigh, strain }
    public struct Band: Sendable, Equatable {
        public var name: String
        public var range: String
        public var tone: Tone
    }
    public var bands: [Band]

    public static func index(_ band: Band3?) -> Int? {
        switch band { case .low: 0; case .medium: 1; case .high: 2; default: nil }
    }
    public static func index(_ band: StrainBand?) -> Int? {
        switch band { case .light: 0; case .moderate: 1; case .strenuous: 2; case .allOut: 3; default: nil }
    }
    public static func recovery(_ constants: ScoreConstants?) -> LevelScale {
        let ranges = ranges(constants?.recovery.bands, percent: false)
        return LevelScale(bands: [
            Band(name: "LOW", range: ranges[0], tone: .recoveryLow),
            Band(name: "MEDIUM", range: ranges[1], tone: .recoveryMedium),
            Band(name: "HIGH", range: ranges[2], tone: .recoveryHigh)
        ])
    }
    public static func strain(_ constants: ScoreConstants?) -> LevelScale {
        let ranges: [String]
        if let edges = constants?.strain.bands {
            ranges = ["0–\(number(edges.moderate - 0.1))", "\(number(edges.moderate))–\(number(edges.strenuous - 0.1))",
                      "\(number(edges.strenuous))–\(number(edges.allOut - 0.1))", "\(number(edges.allOut))–21"]
        } else { ranges = Array(repeating: "—", count: 4) }
        return LevelScale(bands: zip(["LIGHT", "MODERATE", "STRENUOUS", "ALL OUT"], ranges).map { Band(name: $0, range: $1, tone: .strain) })
    }
    public static func hours(_ constants: ScoreConstants?) -> LevelScale { sleep(constants?.sleep.performanceBands) }
    public static func consistency(_ constants: ScoreConstants?) -> LevelScale { sleep(constants?.sleep.consistencyBands) }
    public static func efficiency(_ constants: ScoreConstants?) -> LevelScale { sleep(constants?.sleep.efficiencyBands) }

    private static func sleep(_ edges: Band3Edges?) -> LevelScale {
        let ranges = ranges(edges, percent: true)
        return LevelScale(bands: [
            Band(name: "POOR", range: ranges[0], tone: .caution),
            Band(name: "SUFFICIENT", range: ranges[1], tone: .neutral),
            Band(name: "OPTIMAL", range: ranges[2], tone: .positive)
        ])
    }
    private static func ranges(_ edges: Band3Edges?, percent: Bool) -> [String] {
        guard let edges else { return Array(repeating: "—", count: 3) }
        let suffix = percent ? "%" : ""
        return ["0–\(edges.medium - 1)\(suffix)", "\(edges.medium)–\(edges.high - 1)\(suffix)", "\(edges.high)–100\(suffix)"]
    }
    private static func number(_ value: Double) -> String { GoopFormat.number(value, decimals: value.rounded() == value ? 0 : 1) }
}

public struct HealthState: Sendable {
    public enum Kind: String, Sendable { case building, within, outside, attention }
    public let kind: Kind
    public let within: Int
    public let total: Int
    private let valuesNeeded: Int?
    public init(_ vitals: Vitals) {
        valuesNeeded = vitals.valuesNeeded
        total = vitals.metricsWithRange
        within = total - vitals.outsideRange.count
        if let state = vitals.monitorState {
            kind = Kind(rawValue: state) ?? .outside
        } else {
            kind = total == 0 ? .building : !vitals.outsideRange.isEmpty ? .outside : .within
        }
    }
    public var title: String { kind == .building ? "BUILDING BASELINE" : kind == .within ? "WITHIN RANGE" : "OUTSIDE RANGE" }
    public var color: GoopColorRole { kind == .attention ? .caution : kind == .within ? .healthOK : .neutral }
    public var subline: String { kind == .building ? "No ranges yet" : "\(within)/\(total) Metrics" }
    public var sentence: String {
        if kind == .building {
            return valuesNeeded.map { "ghoops needs \($0) nights to learn your ranges." } ?? "ghoops is still learning your ranges."
        }
        return "\(within)/\(total) overnight metrics in your typical range"
    }
}
