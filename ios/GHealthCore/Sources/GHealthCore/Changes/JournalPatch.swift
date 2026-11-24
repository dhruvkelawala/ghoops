import Foundation

/// The JOURNAL sheet's working answers for one journal date (journal-spec §8.3).
public struct JournalDraft: Sendable, Equatable {
    public let date: String
    public let behaviours: [JournalBehaviour]
    public let stored: JournalEntry?
    /// Starts from every stored answer, including behaviours the sheet does not show, so a PUT keeps them.
    public private(set) var answers: [String: Bool]

    public init(journal: Journal, date: String) {
        self.date = date; behaviours = journal.behaviours; stored = journal.entry(on: date)
        answers = stored?.answers ?? [:]
    }
    public mutating func answer(_ key: String, _ value: Bool) { answers[key] = value }
    public var changed: Bool { answers != (stored?.answers ?? [:]) }
    public var body: JournalBody { JournalBody(answers: answers, ifUpdatedAt: stored?.updatedAt) }
}

/// The phone's answers for one date, shown over `snapshot.journal` until the Mac's copy arrives.
public struct JournalPatch: Codable, Sendable, Equatable {
    public var date: String
    public var answers: [String: Bool]
    public var updatedAt: Date
    public init(date: String, answers: [String: Bool], updatedAt: Date) { self.date = date; self.answers = answers; self.updatedAt = updatedAt }
    public func apply(to journal: Journal) -> Journal {
        var journal = journal
        journal.entries.removeAll { $0.date == date }
        if !answers.isEmpty { journal.entries.append(JournalEntry(date: date, answers: answers, updatedAt: updatedAt)) }
        journal.entries.sort { $0.date < $1.date }
        return journal
    }
}

extension ChangeBuilder {
    public static func journal(_ draft: JournalDraft, serverURL: String, now: Date) -> PendingChange {
        PendingChange(kind: .journal, request: .putJournal(draft.date, draft.body), targets: ["journal-\(draft.date)"], cycleDates: [],
                      name: GoopFormat.dateLabel(draft.date, format: "EEE d MMM"),
                      journalPatch: JournalPatch(date: draft.date, answers: draft.answers, updatedAt: now), serverURL: serverURL, createdAt: now)
    }
}
