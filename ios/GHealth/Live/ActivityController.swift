import Foundation
import GHealthCore
import Observation
import UIKit

@MainActor @Observable final class ActivityController {
    var session: ActivitySession? { get { saved.session } set { saved.session = newValue } }
    /// Saved activities for the paired Mac. Rows for another Mac, or for no known Mac, are in `held`.
    var local: [LocalActivity] { mac == nil ? [] : saved.local.filter { $0.mac == mac } }
    /// Unsent activities for another Mac or no known Mac. They are never sent automatically.
    var held: [LocalActivity] { saved.local.filter { $0.uploadState == .pending && $0.mac != mac } }
    private(set) var mac: PairedMac?
    var connection: HeartRateConnection = .searching
    var pickerPresented = false
    var livePresented = false
    var highlightEnd = false
    var tooShort = false
    var error: String? { get { saved.error } set { saved.error = newValue } }
    var now = Date.now
    var recentWorkouts: [Workout] = []
    /// Called after a session is saved; `ended` is true only when the person just ended it.
    var onSaved: ((LocalActivity, Bool) -> Void)?
    var appActive = true
    private var canSend = false
    var estimator = LiveEstimator(restingHR: nil, maximumHR: nil, model: nil)
    private let liveStatus = ActivityLiveStatus()
    private let store: ActivityStore
    private let saved: ActivityPersistence
    private var source: any HeartRateSource
    private var clock: Task<Void, Never>?
    private var lastSave = Date.distantPast
    private var retryAt: Date?
    private var fixtureDate: Date?
    private var fixtureStarted = Date.now
    private var fixture = false
    private var day: Day?
    private var collectorMinutes: Int?
    private var limits: EditLimits?

    init(directory: URL) {
        store = ActivityStore(directory: directory)
        saved = ActivityPersistence(store: store)
        source = BluetoothHeartRateSource()
        bindSource()
    }
    var estimate: LiveEstimate? { session.map { estimator.estimate($0, now: now) } }
    var elapsed: String { Self.time(session?.elapsed(at: now) ?? 0) }
    static func time(_ seconds: TimeInterval) -> String {
        let n = max(0, Int(seconds)); return String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60)
    }
    func configure(day: Day?, collectorMinutes: Int?, limits: EditLimits?, mac: PairedMac?, api: (any ActivityAPI)?, fixture: Bool, now: Date) async {
        self.fixture = fixture
        await bind(mac, api: api)
        updateRates(day, collectorMinutes: collectorMinutes, limits: limits)
        if fixture {
            fixtureDate = now; fixtureStarted = .now; self.now = now
            #if DEBUG
            source.stop(); source = FixtureHeartRateSource(series: [72]); bindSource()
            #endif
        } else {
            await retrySavedData()
        }
        await updateLiveStatus()
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.tick()
            }
        }
    }
    /// Ties uploads, deletes and new sessions to one pairing. `nil` means unpaired.
    func bind(_ mac: PairedMac?, api: (any ActivityAPI)?) async {
        self.mac = mac
        canSend = mac != nil && api != nil
        await store.bind(mac, api: api)
    }
    func retrySavedData() async {
        guard !fixture, await saved.restore(now: now, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) else { return }
        if let restored = session, restored.state == .ended { await finishRestored(restored) }
        if session != nil { source.start() }
    }
    /// Keeps the Mac's numbers for the next session: rates for the estimate and `status.edit_limits` for its length.
    func updateRates(_ day: Day?, collectorMinutes: Int?, limits: EditLimits?) {
        self.collectorMinutes = collectorMinutes
        self.limits = limits
        self.day = day
        estimator = LiveEstimator(restingHR: day?.strain.restingHrBpm.map(Double.init), maximumHR: day?.strain.maxHrBpm.map(Double.init), model: day?.scoreConstants?.strain)
    }
    func openPicker(workouts: [Workout]) {
        guard session == nil else { livePresented = true; return }
        recentWorkouts = workouts; pickerPresented = true; source.start()
    }
    func closePicker() { if session == nil { source.stop() } }
    func connect(id: UUID) { source.connect(id: id) }
    func start(sport: ActivitySport, cycleDate: String) async {
        guard session == nil else { return }
        await retrySavedData()
        guard await saved.start(makeSession(sport: sport, start: now, cycleDate: cycleDate), now: now, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) else { return }
        pickerPresented = false; livePresented = true; source.start()
        await persist()
    }
    func togglePause() async {
        guard var s = session else { return }
        if s.state == .paused { s.resume(at: now) } else { s.pause(at: now) }
        session = s; await persist()
    }
    func finish() async {
        guard var s = session else { return }
        let save = s.finish(at: now)
        if save {
            let entry = estimator.localActivity(s, now: now)
            do {
                try await store.save(entry, now: now)
                saved.local = try await store.activities(now: now)
                error = nil
                try await store.clearSession()
                if !fixture { await liveStatus.end(session: s, estimate: estimator.estimate(s, now: now), now: now, saved: true) }
                source.stop(); session = nil; livePresented = false
                onSaved?(entry, true)
                await retryUploads()
            } catch { savedDataFailed(error, context: .saveActivity) }
        } else {
            do { try await store.clearSession() } catch { savedDataFailed(error); return }
            if !fixture { await liveStatus.end(session: s, estimate: estimator.estimate(s, now: now), now: now, saved: false) }
            source.stop(); session = nil; livePresented = false; tooShort = true
            Task { [weak self] in try? await Task.sleep(for: .seconds(4)); self?.tooShort = false }
        }
    }
    func retryUploads() async {
        guard !fixture, canSend else { return }
        do {
            let failed = try await store.retry(now: now)
            saved.local = try await store.activities(now: now)
            retryAt = failed ? now.addingTimeInterval(30) : nil
            error = nil
        } catch { savedDataFailed(error); retryAt = now.addingTimeInterval(30) }
    }
    func delete(workout: Workout) async throws {
        let id = workout.id.replacingOccurrences(of: "goop-", with: "")
        do {
            if !fixture {
                guard canSend else { throw ClientError.unauthorized }
                try await store.deleteOnMac(id: id, now: now)
            } else { try await store.delete(id: id, now: now) }
        } catch {
            if SavedDataError.isPermissionError(error) { throw SavedDataError(error, area: .activities) }
            throw error
        }
        saved.local.removeAll { $0.id == id }
        error = nil
    }
    func removeLocal(id: String) async throws {
        let uuid = id.hasPrefix("goop-") ? String(id.dropFirst(5)) : id
        do { try await store.delete(id: uuid, now: now) }
        catch {
            if SavedDataError.isPermissionError(error) { throw SavedDataError(error, area: .activities) }
            throw error
        }
        saved.local.removeAll { $0.id == uuid }
        error = nil
    }
    func merged(_ workouts: [Workout]) -> [Workout] { ActivityMerge.workouts(server: workouts, local: local, now: now) }
    func localEntry(_ id: String) -> LocalActivity? { local.first { "goop-\($0.id)" == id } }
    func message(for workout: Workout, server: Workout?) -> String? {
        guard let local = localEntry(workout.id) else { return nil }
        if let server, local.isFinal(server, now: now) { return nil }
        switch local.uploadState {
        case .pending: return "Saved on your phone. It will be sent to your Mac when it can be reached."
        case .uploaded: return EngineText.uploadedNote(collectorMinutes: collectorMinutes)
        case .rejected: return "Your Mac could not save this activity."
        }
    }
    private func bindSource() {
        source.onState = { [weak self] in self?.connection = $0 }
        source.onSample = { [weak self] sample in
            guard let self, var s = self.session else { return }
            if !self.fixture { self.now = sample.t }
            s.append(HeartRateSample(t: self.now, bpm: sample.bpm)); self.session = s
            Task { await self.tick() }
        }
    }
    private func tick() async {
        now = fixtureDate.map { $0.addingTimeInterval(Date.now.timeIntervalSince(fixtureStarted)) } ?? .now
        if let s = session {
            if s.limitReached(at: now) { await finish() }
            else if now.timeIntervalSince(lastSave) >= 15 { await persist() }
        }
        await updateLiveStatus()
        if let retryAt, now >= retryAt, !fixture, appActive { await retryUploads() }
    }
    func persist() async {
        await updateLiveStatus()
        guard let session else { return }
        await saveSession(session)
    }
    private func saveSession(_ session: ActivitySession) async {
        do { try await store.saveSession(session, now: now); lastSave = now; error = nil }
        catch { savedDataFailed(error, context: .saveSession) }
    }
    private func savedDataFailed(_ failure: Error, context: ErrorCopy.Context = .savedActivities) {
        saved.failed(failure, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable, context: context)
    }
    private func updateLiveStatus() async {
        guard var session else { return }
        let estimate = estimator.estimate(session, now: now)
        let projected = session.target?.projected(liveTrimp: estimate.trimp, scale: estimate.scale)
        let reached = session.target?.update(projected: projected) ?? false
        self.session = session
        if reached {
            await saveSession(session)
            if appActive { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        if !fixture { await liveStatus.update(session: session, estimate: estimate, now: now, targetReached: reached) }
    }
    private func makeSession(sport: ActivitySport, start: Date, cycleDate: String?) -> ActivitySession {
        var session = ActivitySession(sport: sport, now: start, cycleDate: cycleDate, limits: limits, mac: mac)
        session.target = day.flatMap { SessionTarget.make(day: $0, sessionStart: start) }
        return session
    }
    private func finishRestored(_ s: ActivitySession) async {
        if s.savable(at: now) {
            do { try await store.save(estimator.localActivity(s, now: now), now: now); saved.local = try await store.activities(now: now) }
            catch { savedDataFailed(error); return }
        }
        await liveStatus.end(session: s, estimate: estimator.estimate(s, now: now), now: now, saved: s.savable(at: now))
        do { try await store.clearSession(); session = nil; error = nil } catch { savedDataFailed(error) }
    }
    #if DEBUG
    func seedFixture(_ name: String) async {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/live"), let data = try? Data(contentsOf: url), let seed = try? JSONDecoder().decode(LiveSeed.self, from: data) else { return }
        var s = makeSession(sport: .sport(seed.sport), start: now.addingTimeInterval(-seed.startOffset), cycleDate: day?.date)
        for (i, bpm) in seed.bpm.enumerated() { s.append(.init(t: s.start.addingTimeInterval(Double(i)), bpm: bpm)) }
        if name == "paused" { s.pause(at: s.start.addingTimeInterval(760)) }
        if name.hasPrefix("ended_") {
            s.finish(at: now)
            var entry = estimator.localActivity(s, now: now)
            entry.uploadState = name == "ended_estimate" ? .uploaded : .pending
            saved.local = [entry]; try? await store.save(entry, now: now); onSaved?(entry, false)
        } else {
            session = s; livePresented = true
            source.stop(); source = FixtureHeartRateSource(series: name == "no_hr" || name == "stale" ? [] : [seed.bpm.last ?? 72] + Array(seed.bpm.suffix(59))); bindSource(); source.start()
        }
    }
    private struct LiveSeed: Decodable { var sport: String; var startOffset: Double; var bpm: [Double] }
    #endif
}
