import Foundation

/// The Mac's `journal` body (journal-spec §6.1). The owner's private answers; never shown to agents.
public struct Journal: Codable, Sendable, Equatable {
    public var kind: String
    public var generatedAt: Date
    public var defaultDate: String
    public var from: String
    public var to: String
    public var behaviours: [JournalBehaviour]
    public var entries: [JournalEntry]

    public func entry(on date: String) -> JournalEntry? { entries.first { $0.date == date } }
    public func covers(_ date: String) -> Bool { from <= date && date <= to }
}

public struct JournalBehaviour: Codable, Sendable, Equatable, Identifiable {
    public var key: String
    public var name: String
    public var question: String
    public var id: String { key }
    public init(key: String, name: String, question: String) { self.key = key; self.name = name; self.question = question }
}

public struct JournalEntry: Codable, Sendable, Equatable {
    public var date: String
    public var answers: [String: Bool]
    public var updatedAt: Date
    public init(date: String, answers: [String: Bool], updatedAt: Date) { self.date = date; self.answers = answers; self.updatedAt = updatedAt }
}

/// `PUT /v2/journal/<date>`. `ifUpdatedAt` is always sent: null means the phone expects no entry.
public struct JournalBody: Codable, Sendable, Equatable {
    public var answers: [String: Bool]
    public var ifUpdatedAt: Date?
    public init(answers: [String: Bool], ifUpdatedAt: Date?) { self.answers = answers; self.ifUpdatedAt = ifUpdatedAt }
    private enum CodingKeys: String, CodingKey { case answers, ifUpdatedAt }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(answers, forKey: .answers); try c.encode(ifUpdatedAt, forKey: .ifUpdatedAt)
    }
}

public struct JournalEntryResponse: Codable, Sendable {
    public var schemaVersion: Int
    public var kind: String
    public var date: String
    public var entry: JournalEntry?
}
