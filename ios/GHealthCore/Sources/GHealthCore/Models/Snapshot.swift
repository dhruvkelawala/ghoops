import Foundation

public struct Snapshot: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var source: String
    public var scoreVersion: String?
    public var generatedAt: Date
    public var timezone: String
    public var scoreConfig: ScoreConfig?
    public var syntheticFixture: Bool?
    public var freshness: Freshness
    public var defaultDate: String
    public var status: Status
    public var day: Day
    public var sleep: Sleep
    public var days: Days
    public var workouts: Workouts
    /// journal-spec §6.4; nil from a Mac without the journal.
    public var journal: Journal?
}
