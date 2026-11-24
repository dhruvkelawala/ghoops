import Foundation
import Testing
@testable import GHealthCore

private let journalServer = "https://fixture.invalid:18780"
private let journalNow = Date(timeIntervalSince1970: 1_773_153_000)

@Test func snapshotCarriesJournalAndOlderMacsOmitIt() throws {
    let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    let journal = try #require(snapshot.journal)
    #expect(journal.behaviours.count == 5 && journal.covers("2026-03-09") && !journal.covers("2026-03-11"))
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureRoot.appendingPathComponent("preview/snapshot_fresh.json"))) as? [String: Any])
    object.removeValue(forKey: "journal")
    let older = try JSONCoding.decoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(older.journal == nil)
}

@Test func draftKeepsHiddenAnswersAndSendsThePrecondition() throws {
    let journal: Journal = try fixture("journal/journal_basic.json")
    var draft = JournalDraft(journal: journal, date: "2026-03-09")
    #expect(!draft.changed)
    draft.answer("alcohol", true)
    #expect(draft.changed)
    #expect(draft.body.answers == ["alcohol": true, "sauna": true])
    #expect(draft.body.ifUpdatedAt == journal.entry(on: "2026-03-09")?.updatedAt)
    draft.answer("alcohol", false)
    #expect(!draft.changed)
    var fresh = JournalDraft(journal: journal, date: "2026-03-06")
    #expect(fresh.body == JournalBody(answers: [:], ifUpdatedAt: nil))
    fresh.answer("stress", true)
    #expect(fresh.body == JournalBody(answers: ["stress": true], ifUpdatedAt: nil))
}

@Test func journalPatchOverlaysOnlyItsDate() throws {
    let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    var draft = JournalDraft(journal: try #require(snapshot.journal), date: "2026-03-09")
    draft.answer("stress", true)
    let change = ChangeBuilder.journal(draft, serverURL: journalServer, now: journalNow)
    #expect(change.kind == .journal && change.targets == ["journal-2026-03-09"] && change.cycleDates.isEmpty && change.name == "Mon 9 Mar")
    let shown = Overlay.apply([change], to: snapshot)
    #expect(shown.journal?.entry(on: "2026-03-09")?.answers == ["alcohol": false, "sauna": true, "stress": true])
    #expect(shown.journal?.entry(on: "2026-03-08") == snapshot.journal?.entry(on: "2026-03-08"))
    #expect(shown.workouts.workouts.map(\.id) == snapshot.workouts.workouts.map(\.id))
    let cleared = JournalPatch(date: "2026-03-09", answers: [:], updatedAt: journalNow).apply(to: try #require(snapshot.journal))
    #expect(cleared.entry(on: "2026-03-09") == nil)
    let added = JournalPatch(date: "2026-03-06", answers: ["stress": false], updatedAt: journalNow).apply(to: try #require(snapshot.journal))
    #expect(added.entries.map(\.date) == added.entries.map(\.date).sorted())
}

@Test func journalWordsComeFromTheMacsList() throws {
    let journal: Journal = try fixture("journal/journal_basic.json")
    #expect(JournalText.answered(journal, date: "2026-03-09") == "1 OF 5 ANSWERED")
    #expect(JournalText.answered(journal, date: "2026-03-06") == "NOT ANSWERED")
    #expect(JournalText.answer(true) == "YES" && JournalText.answer(false) == "NO" && JournalText.answer(nil) == nil)
    #expect(JournalText.journalDate(forRecovery: "2026-03-01") == "2026-02-28")
    #expect(RollbackNotice(changeID: UUID(), kind: .journal, name: "Mon 9 Mar", error: .conflict).text == "Your journal for Mon 9 Mar changed on your Mac. Your answers are back as they were.")
    #expect(RollbackNotice(changeID: UUID(), kind: .journal, name: "Mon 9 Mar", error: .rejected).text == "Your Mac couldn't save your journal for Mon 9 Mar. Your answers are back as they were.")
}

@Test func fixtureAPIStoresJournalAnswersAndChecksThePrecondition() async throws {
    let api = FixtureEditAPI(directory: fixtureRoot.appendingPathComponent("preview"), journalEditing: true)
    let snapshot = try await api.snapshot()
    let stored = try #require(snapshot.journal?.entry(on: "2026-03-09"))
    await #expect(throws: ClientError.self) { _ = try await api.putJournal(date: "2026-03-09", JournalBody(answers: ["alcohol": true], ifUpdatedAt: nil)) }
    let entry = try await api.putJournal(date: "2026-03-09", JournalBody(answers: ["alcohol": true], ifUpdatedAt: stored.updatedAt))
    #expect(entry?.answers == ["alcohol": true])
    #expect(try await api.snapshot().journal?.entry(on: "2026-03-09")?.answers == ["alcohol": true])
    await #expect(throws: ClientError.self) { _ = try await api.putJournal(date: "2026-04-01", JournalBody(answers: ["alcohol": true], ifUpdatedAt: nil)) }
    let gone = try await api.putJournal(date: "2026-03-09", JournalBody(answers: [:], ifUpdatedAt: try #require(entry?.updatedAt)))
    #expect(gone == nil)
    #expect(try await api.snapshot().journal?.entry(on: "2026-03-09") == nil)
}
