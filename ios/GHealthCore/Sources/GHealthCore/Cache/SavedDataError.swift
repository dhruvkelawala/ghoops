import Foundation

public struct SavedDataError: Error, LocalizedError, Sendable {
    public enum Area: Sendable { case activities, changes }
    private let area: Area
    public let permissionDenied: Bool

    public init(_ error: Error? = nil, area: Area) {
        self.area = area
        permissionDenied = error.map(Self.isPermissionError) ?? false
    }

    public var errorDescription: String? {
        switch area {
        case .activities: "ghoops couldn't read its saved activities on this phone. It will try again."
        case .changes: "ghoops couldn't read your waiting changes on this phone. It will try again."
        }
    }

    public func message(protectedDataAvailable: Bool) -> String? {
        protectedDataAvailable ? errorDescription : nil
    }

    public static func isPermissionError(_ error: Error) -> Bool {
        if let saved = error as? SavedDataError { return saved.permissionDenied }
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }
}
