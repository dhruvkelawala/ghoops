import Foundation

public enum ErrorCopy {
    public enum Context: Sendable {
        case savedActivities, waitingChanges, refresh, pair, testConnection, unpair
        case syncChanges, undoActivity, readHeartRate, saveActivity, deleteActivity, saveSession, saveSleep, saveRating, saveJournal

        fileprivate var savedArea: SavedDataError.Area? {
            switch self {
            case .savedActivities, .refresh: .activities
            case .waitingChanges, .syncChanges: .changes
            default: nil
            }
        }

        fileprivate var sentence: String? {
            switch self {
            case .savedActivities: SavedDataError(area: .activities).errorDescription
            case .waitingChanges: SavedDataError(area: .changes).errorDescription
            case .refresh: "ghoops couldn't update your saved data on this phone. It will try again."
            case .pair: "ghoops couldn't save this pairing on this phone. Try pairing again."
            case .testConnection: "ghoops couldn't check the connection on your Mac. Try again."
            case .unpair: "ghoops couldn't remove this pairing on this phone. Try unpairing again."
            case .syncChanges: "ghoops couldn't finish syncing your changes on this phone. It will try again."
            case .undoActivity: "ghoops couldn't undo this activity change on this phone. Close and open the activity to check it."
            case .readHeartRate: "ghoops couldn't load heart rate on your Mac. Close and open this sheet to try again."
            case .saveActivity: "ghoops couldn't save this activity on this phone. Try again."
            case .deleteActivity: "ghoops couldn't delete this activity on this phone. Try again."
            case .saveSleep: "ghoops couldn't save this change to your sleep on this phone. Try again."
            case .saveRating: "ghoops couldn't save your rating on this phone. Try again."
            case .saveJournal: "ghoops couldn't save your journal answers on this phone. Try again."
            case .saveSession: "ghoops couldn't save your running activity on this phone. It will try again."
            }
        }
    }

    public static func message(_ error: Error, context: Context, protectedDataAvailable: Bool = true) -> String? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        if let saved = error as? SavedDataError { return saved.message(protectedDataAvailable: protectedDataAvailable) }
        if let area = context.savedArea, SavedDataError.isPermissionError(error) {
            return SavedDataError(error, area: area).message(protectedDataAvailable: protectedDataAvailable)
        }
        if let error = error as? ClientError { return error.errorDescription }
        if let error = error as? PairingError { return error.errorDescription }
        if let error = ClientError.transportError(error) { return error.errorDescription }
        if let area = context.savedArea, context == .savedActivities || context == .waitingChanges {
            return SavedDataError(error, area: area).message(protectedDataAvailable: protectedDataAvailable)
        }
        return context.sentence
    }
}
