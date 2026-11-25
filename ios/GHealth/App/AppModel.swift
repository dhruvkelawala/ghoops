import SwiftUI
import GHealthCore
import WidgetKit

@MainActor @Observable
final class AppModel {
    let activity: ActivityController
    var cached: CachedSnapshot?
    var serverCached: CachedSnapshot?
    var serverBundles: [String: DayBundleState] = [:]
    var pending: [PendingChange] = []
    var changeMarkers: [UUID: ChangeMarker] = [:]
    var markerTask: Task<Void, Never>?
    var rollbacks: [RollbackNotice] = []
    var rollbackTargets: [UUID: [String]] = [:]
    var seenRollbacks: Set<UUID> = []
    var changeQueue: ChangeQueue?
    var sendAgain = false
    var changePass = UUID()
    var changeTask: Task<Void, Never>?
    var started = false
    var needsStartupData = true
    var errorContext: ErrorCopy.Context?
    let activityDirectory: URL
    var paired = false
    private var revokedMac: PairedMac?
    var savedMac: PairedMac? { credentials?.mac ?? revokedMac }
    var credentials: Credentials?
    private var verifiedPairing: Credentials?
    var canSendToMac: Bool { !invalidPairing && credentials?.samePairing(as: verifiedPairing) == true }
    var error: String?
    var invalidPairing = false
    var now = Date.now
    var showsOldPairingLink = false
    private(set) var pairingInProgress = false
    private(set) var enrolment: PairingFlow?
    private var enrolmentTask: Task<Void, Never>?
    private var enrolmentRequestsPaused = false
    var tab = GoopTab.home
    var homePath: [Route] = []
    var healthPath: [Route] = []
    var trendsPath: [Route] = []
    var morePath: [Route] = []
    var addDay: String?
    /// The workout whose page asks once for a rating when it opens (effort-rating-spec.md §3.3). Memory only.
    var ratingPrompt: String?
    var selectedDate = ""
    var bundles: [String: DayBundleState] = [:]
    var bundleRevision = UUID()
    var trendStore: TrendStore?
    var loading = false
    var activityUndo: ActivityUndo?
    var activityUndoTimer: Task<Void, Never>?
    let store: SnapshotStore
    private let pairing: PairingRepository
    #if DEBUG
    var fixtureEditAPI: FixtureEditAPI?
    var editFixture: String?
    var instantFixture: String?
    var sleepEditFixture: String?
    var parityFixture: String?
    var fixtureSet: FixtureSet?
    private var enrolmentFixture: EnrolmentFixture?
    private var enrolledFixtureMac: PairedMac?
    var livePreview: LivePreview?
    var widgetPreview = false
    var componentGallery = false
    var largestType = false
    var backgroundProbe = false
    var backgroundRequests = 0
    var backgroundRuns = 0
    var backgroundState = "not invoked"
    #endif

    init() {
        guard let group = SharedAppGroup.directory else {
            preconditionFailure("The App Group is unavailable. Check the iOS identity and signing entitlements.")
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let fixtureMode = ["-GHealthFixture", "-GHealthLiveFixture", "-GHealthWidgetPreview", "-GHealthEnrolmentFixture"].contains(where: args.contains)
        let activityDirectory = fixtureMode ? FileManager.default.temporaryDirectory.appendingPathComponent("activity-fixture-\(UUID())") : group
        #else
        let activityDirectory = group
        #endif
        self.activityDirectory = activityDirectory
        activity = ActivityController(directory: activityDirectory, defaultsSuiteName: activityDirectory == group ? SharedAppGroup.id : nil)
        let accessGroup = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as! String
        store = SnapshotStore(directory: group, pairedMac: {
            PairingRepository.current(accessGroup: accessGroup, suiteName: SharedAppGroup.id)?.mac
        })
        pairing = PairingRepository(suiteName: SharedAppGroup.id, accessGroup: accessGroup)
        #if DEBUG
        if let index = args.firstIndex(of: "-GHealthEnrolmentFixture") {
            fixtureSet = .unpaired
            if args.indices.contains(index + 1) {
                enrolmentFixture = EnrolmentFixture(rawValue: args[index + 1])
            }
        }
        if let i = args.firstIndex(of: "-GHealthWidgetPreview"), args.indices.contains(i + 1), let preview = LivePreview(rawValue: args[i + 1]) {
            fixtureSet = .fresh; widgetPreview = true; livePreview = preview
        }
        if args.contains("-GHealthLiveFixture") { fixtureSet = .fresh }
        backgroundProbe = args.contains("-GHealthBackgroundProbe")
        largestType = args.contains("-GHealthAccessibility5")
        for flag in ["-GHealthFixture", "-GHealthWidgetPreview", "-GHealthGallery"] {
            if let index = args.firstIndex(of: flag), args.indices.contains(index + 1), let set = FixtureSet(rawValue: args[index + 1]) {
                fixtureSet = set
                widgetPreview = flag == "-GHealthWidgetPreview"
                componentGallery = flag == "-GHealthGallery"
            }
        }
        #endif
    }

    func start() async {
        #if DEBUG
        if let fixtureSet {
            useFixture(fixtureSet)
            await configureActivity()
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-GHealthLiveFixture"), args.indices.contains(i + 1) { await activity.seedFixture(args[i + 1]) }
            if fixtureSet == .edit { await configureEditFixture() }
            if fixtureSet == .parity { await configureParityFixture() }
            await configureSleepEditAPI()
            await configureJournalAPI()
            await configureChanges()
            started = true
            if fixtureSet == .edit { await configureInstantFixture() }
            await configureSleepEditState()
            startSending()
            needsStartupData = false
            return
        }
        #endif
        await loadStartupData()
        await configureChanges()
        await configureActivity()
        started = true
        startSending()
    }

    private func loadStartupData() async {
        guard needsStartupData, UIApplication.shared.isProtectedDataAvailable else { return }
        do {
            try await store.prepareForBackup()
            try await pairing.migrateLegacy()
            credentials = try await pairing.credentials()
            paired = credentials != nil
            if let disk = try await store.load(), disk.meta.mac.matches(credentials?.mac) { applyServerSnapshot(disk) }
            needsStartupData = false
            clearError(.savedActivities)
        } catch ClientError.unauthorized {
            let mac = await pairing.deleteRevokedCache(from: store)
            showRevokedPairing(mac)
            needsStartupData = false
        } catch {
            reportError(error, context: .savedActivities)
        }
    }

    func protectedDataBecameAvailable() async {
        guard started, !isFixture, !enrolmentRequestsPaused else { return }
        await loadStartupData()
        await configureChanges()
        await bindActivity()
        await activity.retrySavedData()
        startSending()
    }

    func receive(_ url: URL) {
        switch (url.scheme, url.host) {
        case ("ghealth", "activity"): showActivity()
        case ("ghealth", "today"): showToday()
        case ("ghealth", "pair"): showsOldPairingLink = true
        default: break
        }
    }

    func pairingSwitchMessage(_ base: String, replacing newURL: URL? = nil) -> String {
        guard let mac = pairedMac, newURL?.absoluteString != mac.url else { return base }
        return PairingCopy.switchMessage(
            base: base,
            activities: activity.local.count(where: { $0.uploadState == .pending }),
            changes: pending.count(where: { $0.state != .accepted }),
            mac: mac.name,
            ifDifferentMac: newURL != nil
        )
    }

    var pairedMac: PairedMac? {
        guard paired else { return nil }
        return isFixture ? activity.mac : savedMac
    }

    var pairedAddress: String? {
        #if DEBUG
        if isFixture, enrolmentFixture != nil { return pairedMac?.url }
        #endif
        return savedMac?.url ?? cached?.meta.serverUrl
    }

    private func configureActivity() async {
        activity.onSaved = { [weak self] entry, ended in
            guard let self else { return }
            Task { @MainActor in
                if ended { self.askRating(for: "goop-\(entry.id)") }
                try? await Task.sleep(for: .milliseconds(350))
                self.showToday()
                self.selectedDate = entry.cycleDate
                self.push(.workout(id: "goop-\(entry.id)", date: entry.cycleDate))
            }
        }
        var mac = savedMac
        #if DEBUG
        if isFixture { mac = enrolledFixtureMac ?? (enrolmentFixture == nil ? Self.fixtureMac : EnrolmentFixture.originalMac) }
        #endif
        await activity.configure(day: cached?.snapshot.day, collectorMinutes: cached?.snapshot.status.collector.intervalMinutes, limits: cached?.snapshot.status.editLimits, mac: mac, api: nil, fixture: isFixture, now: now)
    }
    static let fixtureMac = PairedMac(url: "https://fixture.invalid", name: "Fixture Mac")
    private func bindActivity() async {
        let current = credentials
        activity.onProfileMismatch = { [weak self] in
            guard let self, current?.samePairing(as: self.credentials) == true else { return }
            self.invalidatePairing()
        }
        let api = canSendToMac && !enrolmentRequestsPaused ? current.map { client(for: $0) } : nil
        await activity.bind(savedMac, api: api)
    }

    func client(for credentials: Credentials) -> APIClient {
        credentials.client(onUnauthorized: { [weak self] in
            await self?.confirmedRevocation(of: credentials)
        })
    }

    private func confirmedRevocation(of rejected: Credentials) async {
        if rejected.samePairing(as: credentials) { showRevokedPairing(rejected.mac) }
        await pairing.recordRevocation(of: rejected, cache: store)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func showRevokedPairing(_ mac: PairedMac?) {
        credentials = nil
        revokedMac = mac
        paired = mac != nil
        invalidatePairing()
        applyServerSnapshot(nil)
        reportError(ClientError.unauthorized, context: .pair)
    }

    func invalidatePairing() {
        invalidPairing = true
        verifiedPairing = nil
        stopChangePass()
        Task { await bindActivity() }
    }

    private func acceptProfile(_ reported: String?, from current: Credentials) async throws {
        guard !enrolmentRequestsPaused, let saved = credentials, current.samePairing(as: saved) else { throw CancellationError() }
        var updated = saved
        if let profile = reported ?? saved.profileId, !canSendToMac || saved.profileId != profile {
            updated = try await pairing.stampProfile(profile, for: current)
            guard current.samePairing(as: credentials) else { throw CancellationError() }
            try await activity.stampProfile(for: updated.mac)
            try await changeQueue?.bind(to: updated.mac)
            if let changeQueue { pending = await changeQueue.changes }
        }
        guard current.samePairing(as: credentials) else { throw CancellationError() }
        credentials = updated
        verifiedPairing = updated
        invalidPairing = false
        await bindActivity()
    }
    func askRating(for id: String) {
        if GoopFeature.effortRating && EffortScale.supported(editLimits) { ratingPrompt = id }
    }
    func showActivity() {
        showToday()
        if activity.session != nil { activity.livePresented = true }
        else if let entry = activity.local.max(by: { $0.upload.end < $1.upload.end }) {
            selectedDate = entry.cycleDate
            push(.workout(id: "goop-\(entry.id)", date: entry.cycleDate))
        }
    }
    func openActivityPicker() {
        activity.openPicker(workouts: displayedWorkouts(cached?.snapshot.workouts.workouts ?? []))
        Task { await loadActivityHistory() }
    }
    func openAddActivity(day: String) {
        activity.recentWorkouts = displayedWorkouts(cached?.snapshot.workouts.workouts ?? [])
        Task { await loadActivityHistory() }
        addDay = day
    }
    func loadActivityHistory() async {
        guard !isFixture, !enrolmentRequestsPaused, let credentials else { return }
        if let history = try? await client(for: credentials).workouts(days: 30), !enrolmentRequestsPaused,
           credentials.samePairing(as: self.credentials), pending.isEmpty { activity.recentWorkouts = displayedWorkouts(history.workouts) }
    }
    func refresh() async {
        guard !enrolmentRequestsPaused else { return }
        defer { startSending() }
        #if DEBUG
        if let fixtureSet {
            if let fixtureEditAPI, let snapshot = try? await fixtureEditAPI.snapshot(), let meta = cached?.meta {
                applyServerSnapshot(CachedSnapshot(snapshot: snapshot, meta: meta))
            }
            if fixtureSet == .offline { reportError(ClientError.offline, context: .refresh) }
            else { clearError(.refresh) }
            return
        }
        #endif
        guard let credentials else { return }
        loading = true
        defer { loading = false }
        do {
            let fetched = try await SnapshotRefresher.shared.refresh(client: client(for: credentials), store: store)
            try await acceptProfile(fetched.snapshot.status.server.profileId, from: credentials)
            guard !enrolmentRequestsPaused, credentials.samePairing(as: self.credentials) else { return }
            applyServerSnapshot(fetched)
            now = .now
            clearError(.refresh)
            await activity.retryUploads()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            guard !enrolmentRequestsPaused, credentials.samePairing(as: self.credentials) else { return }
            reportError(error, context: .refresh)
            if (error as? ClientError)?.invalidatesPairing == true { invalidatePairing() }
        }
    }

    func becameActive() async {
        guard started, !enrolmentRequestsPaused else { return }
        #if DEBUG
        if fixtureSet != nil { startSending(); return }
        #endif
        if let current = credentials, await pairing.isRevoked(current), current.samePairing(as: credentials) {
            await confirmedRevocation(of: current)
            return
        }
        tick()
        await protectedDataBecameAvailable()
        if !canSendToMac || RefreshPolicy().needsRefresh(fetchedAt: cached?.meta.fetchedAt, trigger: .active) { await refresh() }
        else { await activity.retryUploads() }
    }

    func tick() {
        #if DEBUG
        if fixtureSet != nil { return }
        #endif
        now = .now
    }

    func backgroundRefresh() async -> Bool {
        guard !enrolmentRequestsPaused else { return false }
        #if DEBUG
        if let fixtureSet {
            backgroundRuns += 1
            guard fixtureSet != .offline, let cached else { backgroundState = "no fixture cache"; return false }
            do {
                backgroundRequests = try await FixtureTransport.refresh(cached)
                backgroundState = "completed"
                return true
            } catch { backgroundState = ErrorCopy.message(error, context: .refresh) ?? "cancelled"; return false }
        }
        #endif
        guard credentials != nil else { return false }
        await refresh()
        return !Task.isCancelled && error == nil
    }

    private func prepareToPair(with candidate: PairedMac, leaving previous: PairedMac?) async throws {
        if let previous { try await activity.stampProfile(for: previous) }
        try checkPairingMac(candidate)
    }

    private func checkPairingMac(_ candidate: PairedMac) throws {
        if let session = activity.session, session.blocksPairing(with: candidate) { throw PairingError.activityRunning }
    }

    private func useSavedPairing(leaving previous: PairedMac?) async throws {
        credentials = try await pairing.credentials()
        revokedMac = nil
        verifiedPairing = nil
        let sameProfile = previous?.matches(credentials?.mac) == true
        if previous != nil && !sameProfile { try await clearChanges() }
        else { await reloadChanges() }
        await bindActivity()
        paired = true
        await configureChanges()
        applyServerSnapshot(sameProfile ? serverCached : nil)
        invalidPairing = false
        error = nil
        errorContext = nil
    }

    func testConnection() async -> String {
        guard !enrolmentRequestsPaused else { return "" }
        #if DEBUG
        if let fixtureSet { return fixtureSet == .offline ? ErrorCopy.message(ClientError.offline, context: .testConnection) ?? "" : "200 · 0 ms" } // goop-lint: allow enginenumber: HTTP status and round-trip time
        #endif
        guard let credentials else { return ErrorCopy.message(ClientError.unauthorized, context: .testConnection) ?? "" }
        let start = Date.now
        do {
            let status = try await client(for: credentials).status()
            try await acceptProfile(status.server.profileId, from: credentials)
            startSending()
            return "200 · \(Int(Date.now.timeIntervalSince(start) * 1000)) ms" // goop-lint: allow enginenumber: HTTP status and round-trip time
        } catch {
            if !enrolmentRequestsPaused, (error as? ClientError)?.invalidatesPairing == true,
               credentials.samePairing(as: self.credentials) { invalidatePairing() }
            return ErrorCopy.message(error, context: .testConnection) ?? ""
        }
    }

    var unpairMessage: String {
        PairingCopy.unpairMessage(
            workouts: activity.waitingForCurrentMac,
            changes: pending.count(where: { $0.state != .accepted }),
            mac: pairedMac?.name ?? "your Mac"
        )
    }

    func unpair(deleteWorkouts: Bool = false) async {
        guard !pairingInProgress else { return }
        let mac = pairedMac
        if let session = activity.session, mac?.matches(session.mac) != true {
            error = PairingCopy.unpairDuringOtherWorkout
            errorContext = .unpair
            return
        }
        #if DEBUG
        if fixtureSet != nil { useFixture(.unpaired); return }
        #endif
        pairingInProgress = true
        enrolmentRequestsPaused = true
        defer {
            pairingInProgress = false
            startSending()
        }
        stopChangePass()
        await SnapshotRefresher.shared.cancel()
        await bindActivity()
        do {
            try await activity.clearForUnpair(discarding: deleteWorkouts ? mac : nil)
            try await clearChanges()
            try await pairing.unpair(clearing: store)
            paired = false
            credentials = nil
            revokedMac = nil
            verifiedPairing = nil
            enrolmentRequestsPaused = false
            await bindActivity()
            applyServerSnapshot(nil)
            homePath = []; healthPath = []; trendsPath = []; morePath = []
            tab = .home
            error = nil
            errorContext = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            enrolmentRequestsPaused = false
            await bindActivity()
            await configureChanges()
            reportError(error, context: .unpair)
        }
    }

    var editLimits: EditLimits? { cached?.snapshot.status.editLimits }
    var defaultDate: String { cached?.snapshot.defaultDate ?? "" }
    var oldestDate: String? { cached?.snapshot.status.store.oldestDate }
    var currentPath: [Route] {
        switch tab {
        case .home: homePath
        case .health: healthPath
        case .trends: trendsPath
        case .more: morePath
        }
    }
    var isFixture: Bool {
        #if DEBUG
        fixtureSet != nil
        #else
        false
        #endif
    }

    func showToday() {
        tab = .home
        homePath = []
        selectedDate = defaultDate
    }

    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .health: healthPath.append(route)
        case .trends: trendsPath.append(route)
        case .more: morePath.append(route)
        }
    }

    func loadDay(_ date: String) async {
        guard !enrolmentRequestsPaused, serverBundles[date] == nil else { return }
        #if DEBUG
        if fixtureSet == .edit || fixtureSet == .parity || fixtureSet == .sleepEdit || sleepEditFixture != nil, let snapshot = serverCached?.snapshot {
            var day = snapshot.day
            day.date = date
            let workouts = snapshot.workouts.workouts.filter { $0.cycleDate == date }
            day.workouts = workouts
            serverBundles[date] = .loaded(DayBundle(day: day, sleep: snapshot.sleep, workouts: workouts))
            applyOverlay()
            return
        }
        #endif
        if isFixture { serverBundles[date] = .failed(ClientError.offline); applyOverlay(); return }
        guard let credentials else { serverBundles[date] = .failed(ClientError.unauthorized); applyOverlay(); return }
        let revision = bundleRevision
        serverBundles[date] = .loading
        applyOverlay()
        let client = self.client(for: credentials)
        do {
            async let day = client.day(date: date)
            async let sleep = client.sleep(date: date)
            async let workouts = client.workouts(from: date, to: date)
            let bundle = try await DayBundle(day: day, sleep: sleep, workouts: workouts.workouts)
            guard revision == bundleRevision else { return }
            serverBundles[date] = .loaded(bundle)
            applyOverlay()
        } catch {
            guard revision == bundleRevision else { return }
            serverBundles[date] = .failed(error)
            applyOverlay()
        }
    }
    func applyServerSnapshot(_ value: CachedSnapshot?, keepBundles: Bool = false) {
        let previousDate = serverCached?.snapshot.defaultDate
        serverCached = value
        if !keepBundles { bundleRevision = UUID(); serverBundles = [:] }
        trendStore = nil
        guard let snapshot = value?.snapshot else { selectedDate = ""; applyOverlay(); return }
        activity.updateRates(snapshot.day, collectorMinutes: snapshot.status.collector.intervalMinutes, limits: snapshot.status.editLimits)
        if previousDate != snapshot.defaultDate { selectedDate = snapshot.defaultDate }
        serverBundles[snapshot.defaultDate] = .loaded(DayBundle(day: snapshot.day, sleep: snapshot.sleep, workouts: snapshot.workouts.workouts.filter { $0.cycleDate == snapshot.defaultDate }))
        let client: any DaysFetching
        if !isFixture, let credentials { client = self.client(for: credentials) }
        else { client = OfflineDaysClient() }
        trendStore = TrendStore(defaultDate: snapshot.defaultDate, seed: snapshot.days.days, client: client)
        applyOverlay()
    }

    #if DEBUG
    func useFixture(_ set: FixtureSet) {
        fixtureSet = set
        do {
            let fixture = try FixtureLoader.load(set)
            applyServerSnapshot(fixture.cached)
            paired = set != .unpaired
            now = fixture.now
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-GHealthClock"), args.indices.contains(i + 1),
               let clock = ISO8601DateFormatter().date(from: args[i + 1]) { now = clock }
            error = fixture.offline ? "Offline. Showing your saved data." : nil
            errorContext = nil
        } catch { reportError(error, context: .refresh) }
    }
    #endif

    func reportError(_ failure: Error, context: ErrorCopy.Context) {
        guard let message = ErrorCopy.message(failure, context: context, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) else {
            clearError(context)
            return
        }
        error = message
        errorContext = context
    }

    func clearError(_ context: ErrorCopy.Context) {
        guard errorContext == context else { return }
        error = nil
        errorContext = nil
    }

    var valuesOpacity: Double {
        guard let cached else { return 1 }
        return now.timeIntervalSince(cached.meta.fetchedAt) >= 6 * 3600 ? Goop.Opacity.stale : 1
    }
}

extension AppModel {
    func openEnrolment(pasted text: String? = nil) {
        guard started, !needsStartupData, enrolment == nil, !pairingInProgress else { return }
        let flow: PairingFlow
        #if DEBUG
        if let enrolmentFixture { flow = PairingFlow(transport: enrolmentFixture) }
        else { flow = PairingFlow() }
        #else
        flow = PairingFlow()
        #endif
        do {
            if let text { try flow.scan(text) }
            clearError(.pair)
            enrolment = flow
        } catch { reportError(error, context: .pair) }
    }

    func cancelEnrolment() {
        guard enrolment != nil else { return }
        enrolmentTask?.cancel()
        enrolment = nil
    }

    func confirmEnrolment(_ flow: PairingFlow) {
        guard enrolment === flow, !pairingInProgress, case .check(let code) = flow.step else { return }
        #if DEBUG
        if isFixture, enrolmentFixture == nil {
            enrolment = nil
            error = "Pairing is disabled in fixture mode"
            errorContext = .pair
            return
        }
        #endif
        if let session = activity.session, session.mac?.profile == nil,
           session.blocksPairing(with: PairedMac(url: code.origin.absoluteString, name: "")) {
            enrolment = nil
            reportError(PairingError.activityRunning, context: .pair)
            return
        }
        pairingInProgress = true
        enrolmentRequestsPaused = true
        enrolmentTask = Task { await runEnrolment(flow) }
    }

    private func runEnrolment(_ flow: PairingFlow) async {
        defer {
            pairingInProgress = false
            enrolmentTask = nil
            startSending()
        }
        stopChangePass()
        await SnapshotRefresher.shared.cancel()
        if !isFixture { await bindActivity() }
        let previous = savedMac
        do {
            try await flow.confirm(deviceName: UIDevice.current.name, checkMac: checkPairingMac) { record in
                #if DEBUG
                if isFixture {
                    enrolledFixtureMac = record.mac
                    useFixture(.fresh)
                    await configureActivity()
                    return
                }
                #endif
                try await prepareToPair(with: record.mac, leaving: previous)
                if let previous { try await changeQueue?.bind(to: previous) }
                try await pairing.save(record)
                try await useSavedPairing(leaving: previous)
            }
            enrolment = nil
            enrolmentRequestsPaused = false
            await refresh()
        } catch {
            enrolmentRequestsPaused = false
            if !isFixture { await bindActivity() }
            guard enrolment === flow else { return }
            if (error as? PairingError)?.endsEnrolment == true {
                enrolment = nil
                reportError(error, context: .pair)
            }
        }
    }
}

extension PairingError {
    var endsEnrolment: Bool {
        switch self {
        case .enrolmentExpired, .enrolmentDeclined, .activityRunning: true
        default: false
        }
    }
}
