import Foundation
import Observation

@MainActor @Observable public final class ActivityPersistence {
    public var session: ActivitySession?
    public var local: [LocalActivity] = []
    public var error: String?
    private var needsRead = true
    private let store: ActivityStore

    public init(store: ActivityStore) { self.store = store }

    @discardableResult public func restore(now: Date, protectedDataAvailable: Bool) async -> Bool {
        guard needsRead, protectedDataAvailable else { return false }
        do {
            try await store.prepareForProtectedData()
            local = try await store.activities(now: now)
            if session == nil { session = try await store.restoreSession(now: now) }
            needsRead = false
            error = nil
            return true
        } catch { failed(error, protectedDataAvailable: protectedDataAvailable); return false }
    }

    public func start(_ proposed: ActivitySession, now: Date, protectedDataAvailable: Bool) async -> Bool {
        _ = await restore(now: now, protectedDataAvailable: protectedDataAvailable)
        guard !needsRead else { return false }
        do {
            if session == nil { session = try await store.startSession(proposed, now: now) }
            error = nil
            return true
        } catch { failed(error, protectedDataAvailable: protectedDataAvailable); return false }
    }

    public func failed(_ failure: Error, protectedDataAvailable: Bool, context: ErrorCopy.Context = .savedActivities) {
        guard protectedDataAvailable else { error = nil; return }
        let saved = SavedDataError(failure, area: .activities)
        error = ErrorCopy.message(saved.permissionDenied ? saved : failure, context: context)
    }
}
