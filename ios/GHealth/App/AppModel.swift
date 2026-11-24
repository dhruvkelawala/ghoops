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
    var credentials: Credentials?
    var error: String?
    var invalidPairing = false
    var now = Date.now
    var pendingURL: URL?
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
        let fixtureMode = ProcessInfo.processInfo.arguments.contains("-GHealthFixture") || ProcessInfo.processInfo.arguments.contains("-GHealthLiveFixture") || ProcessInfo.processInfo.arguments.contains("-GHealthWidgetPreview")
        let activityDirectory = fixtureMode ? FileManager.default.temporaryDirectory.appendingPathComponent("activity-fixture-\(UUID())") : group
        #else
        let activityDirectory = group
        #endif
        self.activityDirectory = activityDirectory
        activity = ActivityController(directory: activityDirectory)
        store = SnapshotStore(directory: group, pairedURL: { PairingRepository.pairedURL(suiteName: SharedAppGroup.id) })
        pairing = PairingRepository(
            suiteName: SharedAppGroup.id,
            tokens: KeychainTokenStore(accessGroup: Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as! String)
        )
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
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
            credentials = try await pairing.credentials()
            paired = credentials != nil
            if let disk = try await store.load(), disk.meta.serverUrl == credentials?.url.absoluteString { applyServerSnapshot(disk) }
            needsStartupData = false
            clearError(.savedActivities)
        } catch {
            reportError(error, context: .savedActivities)
        }
    }

    func protectedDataBecameAvailable() async {
        guard started, !isFixture else { return }
        await loadStartupData()
        await configureChanges()
        await bindActivity()
        await activity.retrySavedData()
        startSending()
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
        await activity.configure(day: cached?.snapshot.day, collectorMinutes: cached?.snapshot.status.collector.intervalMinutes, limits: cached?.snapshot.status.editLimits, mac: isFixture ? Self.fixtureMac : credentials?.mac, api: credentials.map { APIClient(baseURL: $0.url, token: $0.token) }, fixture: isFixture, now: now)
    }
    static let fixtureMac = PairedMac(url: "https://fixture.invalid", name: "Fixture Mac")
    private func bindActivity() async {
        await activity.bind(credentials?.mac, api: credentials.map { APIClient(baseURL: $0.url, token: $0.token) })
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
        guard !isFixture, let credentials else { return }
        if let history = try? await APIClient(baseURL: credentials.url, token: credentials.token).workouts(days: 30), self.credentials?.url == credentials.url, pending.isEmpty { activity.recentWorkouts = displayedWorkouts(history.workouts) }
    }
    func refresh() async {
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
        await bindActivity()
        await activity.retryUploads()
        guard let credentials else { return }
        loading = true
        defer { loading = false }
        do {
            let fetched = try await SnapshotRefresher.shared.refresh(client: APIClient(baseURL: credentials.url, token: credentials.token), store: store)
            guard self.credentials?.url == credentials.url else { return }
            applyServerSnapshot(fetched)
            now = .now
            clearError(.refresh)
            invalidPairing = false
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            guard self.credentials?.url == credentials.url else { return }
            reportError(error, context: .refresh)
            invalidPairing = (error as? ClientError) == .unauthorized
        }
    }

    func becameActive() async {
        guard started else { return }
        #if DEBUG
        if fixtureSet != nil { startSending(); return }
        #endif
        tick()
        await protectedDataBecameAvailable()
        await activity.retryUploads()
        if RefreshPolicy().needsRefresh(fetchedAt: cached?.meta.fetchedAt, trigger: .active) { await refresh() }
    }

    func tick() {
        #if DEBUG
        if fixtureSet != nil { return }
        #endif
        now = .now
    }

    func backgroundRefresh() async -> Bool {
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

    func pair(_ url: URL) async {
        #if DEBUG
        if fixtureSet != nil { error = "Pairing is disabled in fixture mode"; return }
        #endif
        do {
            let link = try PairingLink(url)
            if let session = activity.session, session.blocksPairing(with: link.url.absoluteString) { throw PairingError.activityRunning }
            try await pairing.pair(link)
            let previousURL = credentials?.url
            credentials = try await pairing.credentials()
            if let previousURL, previousURL != credentials?.url { try await clearChanges() }
            await bindActivity()
            paired = true
            await configureChanges()
            applyServerSnapshot(nil)
            invalidPairing = false
            error = nil
            errorContext = nil
            await refresh()
        } catch { reportError(error, context: .pair) }
    }

    func testConnection() async -> String {
        #if DEBUG
        if let fixtureSet { return fixtureSet == .offline ? ErrorCopy.message(ClientError.offline, context: .testConnection) ?? "" : "200 · 0 ms" } // goop-lint: allow enginenumber: HTTP status and round-trip time
        #endif
        guard let credentials else { return ErrorCopy.message(ClientError.unauthorized, context: .testConnection) ?? "" }
        let start = Date.now
        do {
            _ = try await APIClient(baseURL: credentials.url, token: credentials.token).status()
            if self.credentials?.url == credentials.url { invalidPairing = false }
            return "200 · \(Int(Date.now.timeIntervalSince(start) * 1000)) ms" // goop-lint: allow enginenumber: HTTP status and round-trip time
        } catch {
            if (error as? ClientError) == .unauthorized, self.credentials?.url == credentials.url { invalidPairing = true }
            return ErrorCopy.message(error, context: .testConnection) ?? ""
        }
    }

    func unpair() async {
        #if DEBUG
        if fixtureSet != nil { useFixture(.unpaired); return }
        #endif
        do {
            try await pairing.unpair()
            try await clearChanges()
            paired = false
            applyServerSnapshot(nil)
            credentials = nil
            await bindActivity()
            homePath = []; healthPath = []; trendsPath = []; morePath = []
            tab = .home
            error = nil
            errorContext = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch { reportError(error, context: .unpair) }
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
        guard serverBundles[date] == nil else { return }
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
        let client = APIClient(baseURL: credentials.url, token: credentials.token)
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
            if (error as? ClientError) == .unauthorized { invalidPairing = true }
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
        if !isFixture, let credentials { client = APIClient(baseURL: credentials.url, token: credentials.token) }
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
