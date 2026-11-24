import Foundation

public protocol EditAPI: Sendable {
    func putSleepEdit(date: String, _ body: SleepEditBody) async throws -> SleepEdit?
    func deleteSleepEdit(date: String) async throws
    func putEdit(id: String, _ body: EditBody) async throws -> WorkoutEdit?
    func deleteEdit(id: String) async throws
    func heartRate(date: String) async throws -> HeartRateBody
    func heartRate(start: Date, end: Date) async throws -> HeartRateBody
    func postActivity(_ activity: ActivityUpload) async throws -> ActivityRecord
    func putRating(id: String, _ body: RatingBody) async throws
    func putJournal(date: String, _ body: JournalBody) async throws -> JournalEntry?
}

/// The body of `PUT /v2/ratings/<id>`.
public struct RatingBody: Codable, Sendable, Equatable {
    public var rpe: Int
    public init(rpe: Int) { self.rpe = rpe }
}

public struct WorkoutRating: Codable, Sendable, Equatable {
    public var id: String
    public var rpe: Int
    public var updatedAt: Date
}

public struct RatingResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var id: String
    public var rating: WorkoutRating?
}

public enum EditPrecondition: Sendable, Equatable {
    case none, noEdit, updatedAt(Date)
}

public struct EditBody: Codable, Sendable, Equatable {
    public var exerciseType: String?
    public var start: Date?
    public var end: Date?
    public var notes: String?
    public var hidden: Bool
    public var mergeWith: [String]
    public var precondition: EditPrecondition
    public init(exerciseType: String? = nil, start: Date? = nil, end: Date? = nil, notes: String? = nil, hidden: Bool = false, mergeWith: [String] = [], precondition: EditPrecondition = .none) {
        self.exerciseType = exerciseType; self.start = start; self.end = end
        self.notes = notes; self.hidden = hidden; self.mergeWith = mergeWith; self.precondition = precondition
    }
    public init(_ edit: WorkoutEdit?, hidden: Bool = false) {
        self.init(exerciseType: edit?.exerciseType, start: edit?.start, end: edit?.end, notes: edit?.notes, hidden: hidden, mergeWith: edit?.mergeWith ?? [])
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.exerciseType == rhs.exerciseType && lhs.start == rhs.start && lhs.end == rhs.end
            && lhs.notes == rhs.notes && lhs.hidden == rhs.hidden && lhs.mergeWith == rhs.mergeWith
    }
    private enum CodingKeys: String, CodingKey { case exerciseType, start, end, notes, hidden, mergeWith, ifUpdatedAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseType = try c.decodeIfPresent(String.self, forKey: .exerciseType)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        hidden = try c.decode(Bool.self, forKey: .hidden)
        mergeWith = try c.decode([String].self, forKey: .mergeWith)
        if !c.contains(.ifUpdatedAt) { precondition = .none }
        else if try c.decodeNil(forKey: .ifUpdatedAt) { precondition = .noEdit }
        else { precondition = .updatedAt(try c.decode(Date.self, forKey: .ifUpdatedAt)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(exerciseType, forKey: .exerciseType)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(notes, forKey: .notes)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(mergeWith, forKey: .mergeWith)
        switch precondition {
        case .none: break
        case .noEdit: try c.encodeNil(forKey: .ifUpdatedAt)
        case .updatedAt(let date): try c.encode(date, forKey: .ifUpdatedAt)
        }
    }
}

public struct EditResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var id: String
    public var edit: WorkoutEdit?
}

public enum EditUndo: Sendable, Equatable {
    case put(EditBody)
    case delete
}
