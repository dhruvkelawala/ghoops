import Foundation
import Testing
@testable import GHealthCore

private let queueServer = "https://fixture.invalid:18780"
private let queueTime = Date(timeIntervalSince1970: 1_773_311_400)
private func queueDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("change-queue-\(UUID())") }
private func queueChange(_ id: String = "target") -> PendingChange {
    PendingChange(kind: .edit, request: .putEdit(id, EditBody(notes: id)), targets: [id], cycleDates: ["2026-03-10"], name: "Boxing", patch: WorkoutPatch(), serverURL: queueServer, createdAt: queueTime)
}
private func queueDeletion(edited: Bool = true) throws -> PendingChange {
    let snapshot: Snapshot = try fixture("edits/snapshot_\(edited ? "edited" : "unedited").json", as: Snapshot.self)
    return ChangeBuilder.delete(try #require(snapshot.workouts.workouts.first { $0.id == "7300000000000000101" }), serverURL: queueServer, now: queueTime)
}

@Test func queueRefusesSubmitUntilLoaded() async throws {
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    await #expect(throws: (any Error).self) { try await queue.submit(queueChange()) }
    #expect(try await queue.load().isEmpty)
    try await queue.submit(queueChange())
    #expect(await queue.changes.count == 1)
}

@Test func unreadQueueCannotLoseWaitingChanges() async throws {
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let saved = queueChange("saved")
    let writer = ChangeQueue(directory: directory, serverURL: queueServer)
    try await writer.load()
    try await writer.submit(saved)
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    let file = directory.appendingPathComponent("pending-changes.json")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    do {
        try await queue.load()
        Issue.record("Unread queue loaded")
    } catch {
        #expect((error as NSError).domain == NSCocoaErrorDomain)
        #expect((error as NSError).code == 257)
        let failure = SavedDataError(error, area: .changes)
        #expect(failure.message(protectedDataAvailable: false) == nil)
        #expect(failure.message(protectedDataAvailable: true) == "ghoops couldn't read your waiting changes on this phone. It will try again.")
    }
    await #expect(throws: (any Error).self) { try await queue.submit(queueChange("new")) }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    #expect(try await queue.load().map(\.id) == [saved.id])
    let next = queueChange("next")
    try await queue.submit(next)
    #expect(try await ChangeQueue(directory: directory, serverURL: queueServer).load().map(\.id) == [saved.id, next.id])
}

@Test func queueSubmitCanRetryAfterAProtectedWriteFails() async throws {
    let directory = queueDirectory()
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    let saved = queueChange("saved"), next = queueChange("next")
    try await queue.submit(saved)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    do {
        try await queue.submit(next)
        Issue.record("Protected queue write succeeded")
    } catch {
        let failure = try #require(error as? SavedDataError)
        #expect(failure.permissionDenied)
        #expect(failure.message(protectedDataAvailable: false) == nil)
        #expect(failure.localizedDescription == "ghoops couldn't read your waiting changes on this phone. It will try again.")
    }
    #expect(await queue.changes.map(\.id) == [saved.id])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try await queue.submit(next)
    #expect(try await ChangeQueue(directory: directory, serverURL: queueServer).load().map(\.id) == [saved.id, next.id])
}

private actor QueueAPI: EditAPI {
    enum Reply: Sendable { case answer(WorkoutEdit?), error(ClientError), unreadable }
    var replies: [Reply]
    var requests: [PendingChange.Request] = []
    var order: [String] = []
    var held = false
    private var entered: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    init(_ replies: [Reply] = [.answer(nil)], held: Bool = false) { self.replies = replies; self.held = held }
    func uploads() { order.append("uploads") }
    func waitForRequest() async { if requests.isEmpty { await withCheckedContinuation { entered = $0 } } }
    func resume() { held = false; release?.resume(); release = nil }
    private func answer(_ request: PendingChange.Request) async throws -> WorkoutEdit? {
        requests.append(request)
        order.append("mutation")
        if held {
            await withCheckedContinuation { continuation in
                release = continuation; entered?.resume(); entered = nil
            }
        }
        let reply = replies.isEmpty ? .answer(nil) : replies.removeFirst()
        switch reply {
        case .answer(let edit): return edit
        case .error(let error): throw error
        case .unreadable: throw MutationError.unreadableResponse
        }
    }
    func putSleepEdit(date: String, _ body: SleepEditBody) async throws -> SleepEdit? { _ = try await answer(.putSleepEdit(date, body)); return nil }
    func deleteSleepEdit(date: String) async throws { _ = try await answer(.deleteSleepEdit(date)) }
    func putEdit(id: String, _ body: EditBody) async throws -> WorkoutEdit? { try await answer(.putEdit(id, body)) }
    func deleteEdit(id: String) async throws { _ = try await answer(.deleteEdit(id)) }
    func putRating(id: String, _ body: RatingBody) async throws { _ = try await answer(.putRating(id, body)) }
    func putJournal(date: String, _ body: JournalBody) async throws -> JournalEntry? { _ = try await answer(.putJournal(date, body)); return nil }
    func postActivity(_ upload: ActivityUpload) async throws -> ActivityRecord {
        _ = try await answer(.postActivity(upload))
        return ActivityRecord(id: upload.id, exerciseType: upload.exerciseType, displayName: upload.displayName, start: upload.start, end: upload.end, pauses: upload.pauses, createdAt: queueTime)
    }
    func heartRate(date: String) throws -> HeartRateBody { throw ClientError.offline }
    func heartRate(start: Date, end: Date) throws -> HeartRateBody { throw ClientError.offline }
}

private actor QueueUpdates {
    var states: [[PendingChange.State]] = []
    func receive(_ result: ChangeQueue.DrainResult) { states.append(result.changes.map(\.state)) }
}

@Test func queueClassifiesMutationResultsAndKeepsAcceptedResponse() async throws {
    let cases: [(QueueAPI.Reply, PendingChange.State?, Bool)] = [
        (.answer(WorkoutEdit(notes: "Mac", updatedAt: queueTime)), .accepted, false),
        (.unreadable, .accepted, false),
        (.error(.rejected), nil, true), (.error(.notFound), nil, true), (.error(.conflict), nil, true),
        (.error(.http(400)), nil, true), (.error(.http(404)), nil, true), (.error(.http(409)), nil, true), (.error(.http(413)), nil, true),
        (.error(.unauthorized), .waiting, false), (.error(.rateLimited), .waiting, false),
        (.error(.http(429)), .waiting, false), (.error(.http(500)), .waiting, false),
        (.error(.storeUnavailable), .waiting, false), (.error(.offline), .waiting, false)
    ]
    for (reply, state, rollback) in cases {
        let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: queueServer, clock: { queueTime })
        try await queue.load()
        var change = try queueDeletion(); change.kind = .edit
        change.patch.upsert = [try #require(change.kept)]
        try await queue.submit(change)
        let result = try await queue.drain(api: QueueAPI([reply]), uploads: {})
        #expect(result.changes.first?.state == state)
        #expect(result.rollbacks.count == (rollback ? 1 : 0))
        if case .error(let error) = reply, state == .waiting { #expect(result.waitingError == error) }
        if case .answer(let edit) = reply { #expect(result.changes.first?.patch.upsert.first?.edit == edit) }
    }
    for reply in [QueueAPI.Reply.error(.notFound), .error(.http(404)), .unreadable] {
        let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: queueServer)
        try await queue.load()
        var restore = queueChange(); restore.request = .deleteEdit("target")
        try await queue.submit(restore)
        #expect(try await queue.drain(api: QueueAPI([reply]), uploads: {}).changes.first?.state == .accepted)
    }
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    var add = queueChange(); add.kind = .add
    add.request = .postActivity(try fixture("edits/requests/add.json", as: ActivityUpload.self))
    try await queue.submit(add)
    #expect(try await queue.drain(api: QueueAPI(), uploads: {}).changes.first?.state == .accepted)
}

@Test func queueRunsUploadsFirstSeriallyAndStopsAtWaiting() async throws {
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    let first = queueChange("first"), second = queueChange("second"), third = queueChange("third")
    for change in [first, second, third] { try await queue.submit(change) }
    let api = QueueAPI([.answer(nil), .error(.offline)], held: true)
    let updates = QueueUpdates()
    let pass = Task { try await queue.drain(api: api, uploads: { await api.uploads() }, onChange: { await updates.receive($0) }) }
    await api.waitForRequest()
    _ = try await queue.drain(api: api, uploads: { await api.uploads() })
    #expect(await api.requests.count == 1)
    await api.resume()
    let result = try await pass.value
    #expect(await api.order == ["uploads", "mutation", "mutation"])
    #expect(result.changes.map(\.state) == [.accepted, .waiting, .waiting])
    #expect(result.changes.map(\.attempts) == [1, 1, 0])
    #expect(await updates.states.contains([.accepted, .sending, .sending]))
    #expect(await updates.states.last == [.accepted, .waiting, .waiting])
    let retry = QueueAPI()
    let finished = try await queue.drain(api: retry, uploads: { await retry.uploads() })
    #expect(finished.changes.allSatisfy { $0.state == .accepted })
    let requests = await retry.requests
    #expect(requests.count == 2)
    if case .putEdit(let id, _) = requests[0] { #expect(id == "second") } else { Issue.record("Expected second first") }
    if case .putEdit(let id, _) = requests[1] { #expect(id == "third") } else { Issue.record("Expected third last") }
}

@Test func queueRefusalDropsOnlyLaterUnacceptedTargets() async throws {
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    var accepted = queueChange("shared"); accepted.state = .accepted; accepted.acceptedAt = queueTime
    let refused = queueChange("shared"), cascade = queueChange("shared"), separate = queueChange("other")
    for change in [accepted, refused, cascade, separate] { try await queue.submit(change) }
    let result = try await queue.drain(api: QueueAPI([.error(.conflict), .answer(nil)]), uploads: {})
    #expect(result.changes.map(\.id) == [accepted.id, separate.id])
    #expect(result.rollbacks.map(\.changeID) == [refused.id])
    #expect(result.refused.map(\.id) == [refused.id])
}

@Test func queueUndoCancelsUnsentAndWaitingWithoutRequest() async throws {
    for waiting in [false, true] {
        let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: queueServer)
        try await queue.load()
        var change = try queueDeletion(); if waiting { change.state = .waiting }
        try await queue.submit(change)
        #expect(try await queue.cancel(id: change.id))
        let api = QueueAPI()
        #expect(try await queue.drain(api: api, uploads: {}).changes.isEmpty)
        #expect(await api.requests.isEmpty)
    }
}

@Test func queueUndoDuringFlightRestoresImmediatelyAndSuppressesRefusals() async throws {
    for reply in [QueueAPI.Reply.answer(WorkoutEdit(updatedAt: queueTime)), .error(.conflict), .error(.offline)] {
        let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: queueServer)
        try await queue.load()
        let deletion = try queueDeletion()
        try await queue.submit(deletion)
        let later = queueChange("later")
        if case .error(.offline) = reply { try await queue.submit(later) }
        let api = QueueAPI([reply, .answer(deletion.kept?.edit)], held: true)
        let pass = Task { try await queue.drain(api: api, uploads: {}) }
        await api.waitForRequest()
        #expect(try await queue.cancel(id: deletion.id))
        #expect(await queue.changes.first?.patch.upsert.first?.id == deletion.kept?.id)
        await api.resume()
        let result = try await pass.value
        #expect(result.rollbacks.isEmpty)
        if case .answer = reply {
            #expect(result.changes.map(\.kind) == [.delete, .undo])
            #expect(result.changes.allSatisfy { $0.state == .accepted })
            let requests = await api.requests
            if case .putEdit(_, let body) = requests.last { #expect(body.precondition == .updatedAt(queueTime) && !body.hidden) }
            else { Issue.record("Missing Undo PUT") }
        } else if case .error(.offline) = reply {
            #expect(result.changes.map(\.id) == [later.id])
            #expect(result.changes.first?.state == .waiting)
            #expect(await api.requests.count == 1)
        } else {
            let count = await api.requests.count
            #expect(result.changes.isEmpty && count == 1)
        }
    }
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    let deletion = try queueDeletion()
    try await queue.submit(deletion)
    let api = QueueAPI([.answer(WorkoutEdit(updatedAt: queueTime)), .error(.conflict)], held: true)
    let pass = Task { try await queue.drain(api: api, uploads: {}) }
    await api.waitForRequest()
    #expect(try await queue.cancel(id: deletion.id))
    await api.resume()
    let result = try await pass.value
    let snapshot: Snapshot = try fixture("edits/snapshot_edited.json", as: Snapshot.self)
    #expect(result.rollbacks.first?.kind == .undo)
    #expect(!Overlay.apply(result.changes, to: snapshot).workouts.workouts.contains { $0.id == deletion.kept?.id })
}

@Test func queueAcceptedUndoReplaysUnreadableDeleteBeforeSending() async throws {
    for replay in [QueueAPI.Reply.answer(WorkoutEdit(updatedAt: queueTime)), .unreadable, .error(.conflict), .error(.http(503))] {
        let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: queueServer, clock: { queueTime })
        try await queue.load()
        let deletion = try queueDeletion()
        try await queue.submit(deletion)
        let first = try await queue.drain(api: QueueAPI([.unreadable]), uploads: {})
        #expect(!(try await queue.cancel(id: deletion.id)))
        let accepted = try #require(first.changes.first)
        try await queue.settle(acceptedBefore: queueTime)
        let undo = try #require(ChangeBuilder.undo(accepted, now: queueTime))
        try await queue.submit(undo)
        let api = QueueAPI([replay, .answer(deletion.kept?.edit)])
        let result = try await queue.drain(api: api, uploads: {})
        let requests = await api.requests
        if case .putEdit(let id, let body) = requests[0], case .putEdit(let wantedID, let wantedBody) = deletion.request {
            #expect(id == wantedID && body == wantedBody && body.precondition == wantedBody.precondition)
        } else { Issue.record("Missing exact delete replay") }
        switch replay {
        case .answer, .unreadable:
            #expect(requests.count == 2 && result.changes.first?.state == .accepted)
            if case .putEdit(_, let body) = requests[1] {
                let condition: EditPrecondition = if case .answer = replay { .updatedAt(queueTime) } else { .none }
                #expect(!body.hidden && body.precondition == condition)
            } else { Issue.record("Missing Undo after replay") }
        case .error(.conflict):
            #expect(requests.count == 1 && result.changes.isEmpty && result.rollbacks.first?.kind == .undo)
            #expect(result.rollbacks.first?.text == "Boxing changed on your Mac. It's back as it was.")
        default:
            #expect(requests.count == 1 && result.changes.first?.state == .waiting)
            #expect(result.changes.first?.replayBeforeUndo != nil)
            let retry = QueueAPI([.unreadable, .answer(nil)])
            #expect(try await queue.drain(api: retry, uploads: {}).changes.first?.state == .accepted)
            #expect(await retry.requests.count == 2)
        }
    }
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    var deletion = try queueDeletion(edited: false); deletion.state = .accepted
    try await queue.submit(try #require(ChangeBuilder.undo(deletion, now: queueTime)))
    #expect(try await queue.drain(api: QueueAPI([.error(.notFound)]), uploads: {}).changes.first?.state == .accepted)
}

@Test func queuePersistsEveryStateFiltersServerAndSettlesOnlyOlderAcceptance() async throws {
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    var sending = try queueDeletion(); sending.undoRequested = true
    var waiting = queueChange("waiting"); waiting.state = .waiting; waiting.attempts = 2
    var accepted = queueChange("accepted"); accepted.state = .accepted; accepted.acceptedAt = queueTime
    accepted.acceptedEdit = WorkoutEdit(notes: "Saved note", updatedAt: queueTime)
    var newer = queueChange("newer"); newer.state = .accepted; newer.acceptedAt = queueTime.addingTimeInterval(1)
    let undo = try #require(ChangeBuilder.undo(sending, now: queueTime))
    for change in [sending, waiting, accepted, newer, undo] { try await queue.submit(change) }
    let reloaded = ChangeQueue(directory: directory, serverURL: queueServer)
    let loaded = try await reloaded.load()
    #expect(loaded.map(\.id) == [sending.id, waiting.id, accepted.id, newer.id, undo.id])
    #expect(loaded.map(\.state) == [.sending, .waiting, .accepted, .accepted, .sending])
    #expect(loaded[0].undoRequested && loaded[0].kept?.id == sending.kept?.id && loaded[1].attempts == 2)
    #expect(loaded[2].acceptedEdit?.notes == "Saved note" && loaded[4].replayBeforeUndo != nil)
    try await reloaded.settle(acceptedBefore: queueTime)
    #expect(await reloaded.changes.map(\.id) == [sending.id, waiting.id, newer.id, undo.id])
    let other = ChangeQueue(directory: directory, serverURL: "https://other.invalid")
    #expect(try await other.load().isEmpty)
    let sameAgain = ChangeQueue(directory: directory, serverURL: queueServer)
    #expect(try await sameAgain.load().isEmpty)
    try await queue.clear()
    #expect(try await ChangeQueue(directory: directory, serverURL: queueServer).load().isEmpty)
}

@Test func queueClearWhileSendingDiscardsTheOldReply() async throws {
    let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let queue = ChangeQueue(directory: directory, serverURL: queueServer)
    try await queue.load()
    try await queue.submit(queueChange())
    let api = QueueAPI(held: true)
    let pass = Task { try await queue.drain(api: api, uploads: {}) }
    await api.waitForRequest()
    try await queue.clear()
    await api.resume()
    #expect(try await pass.value.changes.isEmpty)
    #expect(await queue.changes.isEmpty)
}

extension ClientTests {
    @Test func mutationDecodeFailuresRetainSuccessfulHTTPOutcome() async throws {
        for code in [200, 201, 204] {
            StubProtocol.state.set(code, Data("unreadable".utf8))
            await #expect(throws: MutationError.self) { _ = try await stubClient().putEdit(id: "target", EditBody()) }
            await #expect(throws: MutationError.self) { try await stubClient().deleteEdit(id: "target") }
            let upload: ActivityUpload = try fixture("edits/requests/add.json", as: ActivityUpload.self)
            await #expect(throws: MutationError.self) { _ = try await stubClient().postActivity(upload) }
        }
        StubProtocol.state.set(200, Data("unreadable".utf8))
        await #expect(throws: ClientError.incompatibleVersion) { _ = try await stubClient().status() }
    }
}

@Test func queueSendsJournalChangesAndRollsBackOnRefusal() async throws {
    let snapshot: Snapshot = try fixture("preview/snapshot_fresh.json")
    var draft = JournalDraft(journal: try #require(snapshot.journal), date: "2026-03-09")
    draft.answer("stress", true)
    for (reply, state, rollback) in [(QueueAPI.Reply.answer(nil), PendingChange.State?.some(.accepted), false), (.error(.offline), .waiting, false), (.error(.conflict), nil, true)] {
        let directory = queueDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChangeQueue(directory: directory, serverURL: queueServer, clock: { queueTime })
        try await queue.load()
        try await queue.submit(ChangeBuilder.journal(draft, serverURL: queueServer, now: queueTime))
        let api = QueueAPI([reply])
        let result = try await queue.drain(api: api, uploads: {})
        #expect(result.changes.first?.state == state)
        #expect(result.rollbacks.map(\.kind) == (rollback ? [.journal] : []))
        let requests = await api.requests
        guard case .putJournal(let date, let body) = requests.first else { Issue.record("no journal request"); continue }
        #expect(date == "2026-03-09" && body == draft.body)
        #expect(try await ChangeQueue(directory: directory, serverURL: queueServer).load().first?.journalPatch?.answers == (state == nil ? nil : draft.answers))
    }
}
