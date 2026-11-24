import Foundation

public struct WorkoutSuggestion: Codable, Sendable {
    public var exerciseType: String
    public var displayName: String
    public var matches: Int
    public var windowDays: Int
}
