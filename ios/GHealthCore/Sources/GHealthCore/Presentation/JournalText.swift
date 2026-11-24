import Foundation

/// Words for the Journal section (journal-spec §8.2). Counts come from the Mac's body.
public enum JournalText {
    public static let footnote = "About the day before this Recovery. Your answers stay on your Mac."
    /// `3 OF 5 ANSWERED`, or `NOT ANSWERED`, over the enabled behaviours.
    public static func answered(_ journal: Journal, date: String) -> String {
        let answers = journal.entry(on: date)?.answers ?? [:]
        let count = journal.behaviours.filter { answers[$0.key] != nil }.count
        return count == 0 ? "NOT ANSWERED" : "\(count) OF \(journal.behaviours.count) ANSWERED"
    }
    public static func answer(_ value: Bool?) -> String? { value.map { $0 ? "YES" : "NO" } }
    /// The journal date whose answers may affect the Recovery of `recoveryDate` (journal-spec §3).
    public static func journalDate(forRecovery recoveryDate: String) -> String { GoopFormat.addingDays(-1, to: recoveryDate) }
}
