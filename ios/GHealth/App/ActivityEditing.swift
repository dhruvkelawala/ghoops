import Foundation
import GHealthCore

struct ActivityUndo {
    var name: String
    var change: PendingChange
    var text: String { "\(name) deleted." }
}

extension AppModel {
    var editAPI: (any EditAPI)? {
        #if DEBUG
        if let fixtureEditAPI { return fixtureEditAPI }
        #endif
        return credentials.map { client(for: $0) }
    }
    func replaceWorkout(id: String, date: String) {
        let route = Route.workout(id: id, date: date)
        switch tab {
        case .home: homePath = Array(homePath.dropLast()) + [route]
        case .health: healthPath = Array(healthPath.dropLast()) + [route]
        case .trends: trendsPath = Array(trendsPath.dropLast()) + [route]
        case .more: morePath = Array(morePath.dropLast()) + [route]
        }
    }
    func returnHomeAfterDelete() {
        tab = .home
        homePath = []; healthPath = []; trendsPath = []; morePath = []
    }
    func showActivityUndo(_ undo: ActivityUndo) {
        expireActivityUndo()
        activityUndo = undo
        #if DEBUG
        if editFixture == "undo" || instantFixture == "delete-waiting" { return }
        #endif
        activityUndoTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) }
            catch { return }
            self?.expireActivityUndo()
        }
    }
    func expireActivityUndo() {
        activityUndoTimer?.cancel()
        activityUndoTimer = nil
        activityUndo = nil
    }
    func undoActivity() {
        guard let undo = activityUndo, let queue = changeQueue else { return }
        expireActivityUndo()
        let deletion = undo.change
        Task {
            do {
                if try await queue.cancel(id: deletion.id) {
                    pending = await queue.changes
                    applyOverlay()
                } else {
                    let accepted = await queue.changes.first { $0.id == deletion.id } ?? deletion
                    if let change = ChangeBuilder.undo(accepted, now: .now) { try await submit(change) }
                }
                clearError(.undoActivity)
            } catch { reportError(error, context: .undoActivity) }
        }
    }
    #if DEBUG
    func configureParityFixture() async {
        fixtureEditAPI = FixtureEditAPI(parity: true)
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-GHealthParityFixture"), args.indices.contains(i + 1) { parityFixture = args[i + 1] }
        guard parityFixture == "sport", let effort = cached?.snapshot.workouts.workouts.first(where: { $0.id == "effort-2026-03-09T19:40:00Z" }) else { return }
        selectedDate = effort.cycleDate
        await loadDay(effort.cycleDate)
        push(.workout(id: effort.id, date: effort.cycleDate))
    }
    func configureEditFixture() async {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-GHealthEditFixture"), args.indices.contains(i + 1) { editFixture = args[i + 1] }
        if let i = args.firstIndex(of: "-GHealthInstantFixture"), args.indices.contains(i + 1) { instantFixture = args[i + 1] }
        if instantFixture != nil { return }
        let key = editFixture ?? "detail"
        let state = key == "unedited" ? "unedited" : key == "alias" ? "alias" : key == "undo" ? "deleted" : key == "rated" ? "rated" : "edited"
        let mode: FixtureEditAPI.MutationMode
        let value = args.firstIndex(of: "-GHealthMutationMode").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        switch value {
        case "hold": mode = .hold
        case "offline": mode = .offline
        case "offline-once": mode = .offlineOnce
        case "reject-404": mode = .reject(.notFound)
        case "reject-409": mode = .reject(.conflict)
        case "reject-400": mode = .reject(.rejected)
        default: mode = .answer
        }
        let limitsValue = args.firstIndex(of: "-GHealthEditLimits").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let limits: FixtureEditAPI.LimitsFixture = limitsValue == "odd" ? .odd : limitsValue == "none" ? .none : .mac
        let api = FixtureEditAPI(state: state, offline: key == "offline", mutationMode: mode, limits: limits)
        fixtureEditAPI = api
        if let snapshot = try? await api.snapshot(), let meta = cached?.meta { applyServerSnapshot(CachedSnapshot(snapshot: snapshot, meta: meta)) }
        if key == "undo" {
            let draftAPI = FixtureEditAPI(state: "edited")
            if let workout = try? await draftAPI.snapshot().workouts.workouts.first(where: { $0.id == "7300000000000000101" }) {
                var deletion = ChangeBuilder.delete(workout, serverURL: changeServerURL, now: .now)
                deletion.state = .accepted
                deletion.acceptedEdit = workout.edit
                showActivityUndo(ActivityUndo(name: "Boxing", change: deletion))
            }
            return
        }
        if key == "add" {
            openAddActivity(day: "2026-03-11")
            return
        }
        let effort = cached?.snapshot.workouts.workouts.first { $0.kind == "detected" && $0.cycleDate == defaultDate }
        let date = key == "effort" ? defaultDate : key == "old" ? "2026-03-07" : "2026-03-10"
        selectedDate = date
        await loadDay(date)
        let id = key == "effort" ? effort?.id ?? "" : key == "old" ? "7300000000000000100" : key == "ask" ? "7300000000000000102" : "7300000000000000101"
        if key == "ask" { askRating(for: id) }
        push(.workout(id: id, date: date))
    }
    #endif
}
