import Foundation

public struct Workouts: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var freshness: Freshness
    public var from: String
    public var to: String
    @DefaultEmpty public var workouts: [Workout]
}

public struct Workout: Codable, Sendable {
    public var suggested: WorkoutSuggestion?
    public var original: WorkoutOriginal?
    public var edit: WorkoutEdit?
    public var edited: Bool?
    @DefaultEmpty public var merged: [WorkoutOriginal] = []
    public var notes: String?
    public var rpe: Int?
    public var origin: String?
    @DefaultEmpty public var pauses: [ActivityPause] = []
    public var pausedMinutes: Int?
    public var kind: String
    public var id: String
    public var exerciseType: String?
    public var displayName: String?
    public var category: String
    public var cycleDate: String
    public var start: Date
    public var end: Date
    public var elapsedMinutes: Double
    public var activeMinutes: Double?
    public var strain: Double?
    public var trimp: Double?
    public var hrCoverage: Double?
    public var confidence: Confidence?
    public var avgHrBpm: Int?
    public var peakHrBpm: Int?
    public var zonesMinutes: Zones?
    public var provider: WorkoutProvider?
    public var source: WorkoutSource?
    public var hasGps: Bool
    @DefaultEmpty public var hrSeries: [HeartRatePoint]
}

public struct WorkoutProvider: Codable, Sendable {
    public var avgHrBpm: Int?
    public var caloriesKcal: Double?
    public var activeZoneMinutes: Int?
}

public enum WorkoutSource: Codable, Sendable {
    case goop
    case provider(recordingMethod: String?, platform: String?, formFactor: String?)
    private enum CodingKeys: String, CodingKey { case recordingMethod, platform, formFactor }
    public init(from decoder: any Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self), value == "goop" { self = .goop; return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = .provider(recordingMethod: try c.decodeIfPresent(String.self, forKey: .recordingMethod), platform: try c.decodeIfPresent(String.self, forKey: .platform), formFactor: try c.decodeIfPresent(String.self, forKey: .formFactor))
    }
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .goop: var c = encoder.singleValueContainer(); try c.encode("goop")
        case .provider(let method, let platform, let form):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(method, forKey: .recordingMethod); try c.encodeIfPresent(platform, forKey: .platform); try c.encodeIfPresent(form, forKey: .formFactor)
        }
    }
}

public struct WorkoutOriginal: Codable, Sendable, Equatable {
    public var id: String?
    public var kind: String?
    public var exerciseType: String?
    public var displayName: String?
    public var start: Date
    public var end: Date
}

public struct WorkoutEdit: Codable, Sendable, Equatable {
    public var exerciseType: String?
    public var start: Date?
    public var end: Date?
    public var notes: String?
    @DefaultEmpty public var mergeWith: [String] = []
    public var updatedAt: Date
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.exerciseType == rhs.exerciseType && lhs.start == rhs.start && lhs.end == rhs.end
            && lhs.notes == rhs.notes && lhs.mergeWith == rhs.mergeWith && lhs.updatedAt == rhs.updatedAt
    }
}
