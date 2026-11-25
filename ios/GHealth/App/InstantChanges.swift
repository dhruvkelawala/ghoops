import SwiftUI
import GHealthCore

extension AppModel {
    var changeServerURL: String { savedMac?.url ?? serverCached?.meta.serverUrl ?? "https://fixture.invalid" }
    var lockedWorkouts: Set<String> { Set(pending.flatMap(\.targets)) }

    func configureChanges() async {
        guard savedMac != nil || isFixture && paired else { return }
        let queue = changeQueue ?? ChangeQueue(directory: activityDirectory, serverURL: changeServerURL, profileId: savedMac?.profile)
        changeQueue = queue
        guard !(await queue.isLoaded), UIApplication.shared.isProtectedDataAvailable else { return }
        do {
            try await queue.prepareForProtectedData()
            pending = try await queue.load()
            applyOverlay()
            clearError(.waitingChanges)
        } catch {
            reportError(error, context: .waitingChanges)
        }
    }

    func applyOverlay() {
        refreshChangeMarkers()
        cached = serverCached.map { CachedSnapshot(snapshot: Overlay.apply(pending, to: $0.snapshot), meta: $0.meta) }
        bundles = serverBundles.mapValues { state in
            guard case .loaded(let bundle) = state else { return state }
            let (day, workouts) = Overlay.apply(pending, date: bundle.day.date, day: bundle.day, workouts: bundle.workouts)
            return .loaded(DayBundle(day: day, sleep: Overlay.apply(pending, to: bundle.sleep), workouts: workouts))
        }
        activity.recentWorkouts = displayedWorkouts(cached?.snapshot.workouts.workouts ?? [])
    }

    func displayedWorkouts(_ workouts: [Workout]) -> [Workout] {
        ActivityMerge.workouts(server: workouts, local: activity.local.filter { !lockedWorkouts.contains("goop-\($0.id)") }, now: now)
    }

    func submit(_ change: PendingChange) async throws {
        guard let changeQueue else { throw SavedDataError(area: .changes) }
        do { try await changeQueue.submit(change) }
        catch { throw SavedDataError(error, area: .changes) }
        clearError(.waitingChanges)
        pending = await changeQueue.changes
        applyOverlay()
        startSending()
    }

    func startSending() {
        guard started, !pairingInProgress, isFixture || canSendToMac, let queue = changeQueue, let api = editAPI else { return }
        if changeTask != nil { sendAgain = true; return }
        let pass = changePass
        changeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if changePass == pass {
                    changeTask = nil
                    if sendAgain { sendAgain = false; startSending() }
                }
            }
            guard await queue.isLoaded else { return }
            do {
                let result = try await queue.drain(api: api, uploads: { [weak self] in await self?.activity.retryUploads() }, onChange: { [weak self] result in
                    await self?.receiveChanges(result, pass: pass)
                })
                receiveChanges(result, pass: pass)
                guard changePass == pass, isFixture || canSendToMac else { return }
                let settled = try await settleAccepted()
                clearError(.syncChanges)
                if settled { sendAgain = true }
            } catch {
                if changePass == pass {
                    reportError(error, context: .syncChanges)
                    if (error as? ClientError)?.invalidatesPairing == true { invalidatePairing() }
                }
            }
        }
    }

    func receiveChanges(_ result: ChangeQueue.DrainResult, pass: UUID) {
        guard changePass == pass else { return }
        clearError(.waitingChanges)
        if result.waitingError?.invalidatesPairing == true { invalidatePairing() }
        pending = result.changes
        if let deletion = activityUndo?.change, let updated = pending.first(where: { $0.id == deletion.id }) { activityUndo?.change = updated }
        applyOverlay()
        for change in result.refused where !seenRollbacks.contains(change.id) {
            rollbackTargets[change.id] = change.targets
            if change.kind == .delete, activityUndo?.change.id == change.id { expireActivityUndo() }
            for tab in [GoopTab.home, .health, .trends, .more] { repairRoute(after: change, tab: tab) }
        }
        for notice in result.rollbacks where seenRollbacks.insert(notice.id).inserted {
            rollbacks.insert(notice, at: 0)
            UIAccessibility.post(notification: .announcement, argument: notice.text)
        }
        rollbacks = Array(rollbacks.prefix(ChangeTiming.rollbackLimit))
    }

    @discardableResult func settleAccepted() async throws -> Bool {
        guard let queue = changeQueue else { return false }
        let accepted = pending.filter { $0.state == .accepted }
        guard !accepted.isEmpty else { return false }
        let cutoff = Date.now
        let revision = bundleRevision, pass = changePass
        let dates = Set(accepted.flatMap(\.cycleDates)).filter { date in
            if case .loaded = serverBundles[date] { return date != defaultDate }
            return false
        }
        let snapshot: CachedSnapshot
        var loaded: [String: DayBundle] = [:]
        #if DEBUG
        if let fixtureEditAPI, let meta = serverCached?.meta {
            let body = try await fixtureEditAPI.snapshot()
            snapshot = CachedSnapshot(snapshot: body, meta: meta)
            for date in dates {
                var day = body.day; day.date = date
                day.workouts = body.workouts.workouts.filter { $0.cycleDate == date }
                loaded[date] = DayBundle(day: day, sleep: body.sleep, workouts: day.workouts)
            }
        } else {
            (snapshot, loaded) = try await readAccepted(dates: dates)
        }
        #else
        (snapshot, loaded) = try await readAccepted(dates: dates)
        #endif
        guard pass == changePass else { return false }
        if revision == bundleRevision { for (date, bundle) in loaded { serverBundles[date] = .loaded(bundle) } }
        for id in Set(accepted.flatMap(\.targets)) where id.hasPrefix("goop-") { try await activity.removeLocal(id: id) }
        guard pass == changePass else { return false }
        try await queue.settle(acceptedBefore: cutoff)
        guard pass == changePass else { return false }
        pending = await queue.changes
        applyServerSnapshot(snapshot, keepBundles: true)
        return true
    }

    private func readAccepted(dates: Set<String>) async throws -> (CachedSnapshot, [String: DayBundle]) {
        guard let credentials else { throw ClientError.unauthorized }
        let pass = changePass
        let client = self.client(for: credentials)
        async let snapshot = client.snapshotData()
        let loaded = try await withThrowingTaskGroup(of: (String, DayBundle).self) { group in
            for date in dates {
                group.addTask {
                    async let day = client.day(date: date)
                    async let sleep = client.sleep(date: date)
                    async let workouts = client.workouts(from: date, to: date)
                    return try await (date, DayBundle(day: day, sleep: sleep, workouts: workouts.workouts))
                }
            }
            var results: [String: DayBundle] = [:]
            for try await (date, bundle) in group { results[date] = bundle }
            return results
        }
        let data = try await snapshot
        guard pass == changePass else { throw CancellationError() }
        return try await (store.save(data, from: credentials.mac, fetchedAt: .now), loaded)
    }

    private func repairRoute(after change: PendingChange, tab: GoopTab) {
        var path: [Route]
        switch tab {
        case .home: path = homePath
        case .health: path = healthPath
        case .trends: path = trendsPath
        case .more: path = morePath
        }
        guard case .workout(let id, let date) = path.last,
              change.targets.contains(id),
              !(cached?.snapshot.workouts.workouts.contains { $0.id == id } ?? false),
              !bundles.values.contains(where: { if case .loaded(let bundle) = $0 { return bundle.workouts.contains { $0.id == id } }; return false }) else { return }
        path.removeLast()
        if change.kind == .name, let effort = change.patch.remove.first { path.append(.workout(id: effort, date: date)) }
        switch tab {
        case .home: homePath = path
        case .health: healthPath = path
        case .trends: trendsPath = path
        case .more: morePath = path
        }
    }

    func stopChangePass() {
        changePass = UUID(); sendAgain = false
        changeTask?.cancel(); changeTask = nil
    }

    func reloadChanges() async {
        stopChangePass()
        await changeQueue?.suspend()
        changeQueue = nil
    }

    func clearChanges() async throws {
        stopChangePass()
        try await changeQueue?.clear()
        changeQueue = nil; pending = []; rollbacks = []; rollbackTargets = [:]
        markerTask?.cancel(); markerTask = nil; changeMarkers = [:]
        expireActivityUndo()
        applyOverlay()
    }
}
