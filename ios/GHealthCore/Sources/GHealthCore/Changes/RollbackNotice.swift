import Foundation

public struct RollbackNotice: Sendable, Identifiable {
    public var changeID: UUID
    public var kind: PendingChange.Kind
    public var name: String
    public var error: ClientError
    public var id: UUID { changeID }
    public init(changeID: UUID, kind: PendingChange.Kind, name: String, error: ClientError) {
        self.changeID = changeID; self.kind = kind; self.name = name; self.error = error
    }
    public var text: String {
        let changed: Bool
        switch error {
        case .notFound, .conflict, .http(404), .http(409): changed = true
        default: changed = false
        }
        switch kind {
        case .sleep:
            let reason = changed ? "Your sleep on \(name) changed on your Mac." : "Your Mac couldn't save the change to your sleep on \(name)."
            return reason + " It's back as it was."
        case .name:
            let reason = changed ? "The detected effort changed on your Mac." : "Your Mac couldn't save the detected effort as \(name)."
            return reason + " It's back as it was."
        case .add: return "Your Mac couldn't add \(name). Nothing was added."
        case .rate where !changed: return "Your Mac couldn't save your rating for \(name). It's back as it was."
        case .journal:
            let reason = changed ? "Your journal for \(name) changed on your Mac." : "Your Mac couldn't save your journal for \(name)."
            return reason + " Your answers are back as they were."
        default:
            let reason = changed ? "\(name) changed on your Mac." : "Your Mac couldn't save the change to \(name)."
            return reason + " It's back as it was."
        }
    }
}
