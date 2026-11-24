import Foundation

public enum ChangeTiming {
    public static let markerDelay: TimeInterval = 0.6
    public static let markerMinimum: TimeInterval = 0.5
    public static let retryInterval: TimeInterval = 30
    public static let rollbackLimit = 3

    public static func markerVisible(change: PendingChange, now: Date, shownAt: Date?, untilSettled: Bool = false) -> Bool {
        if let shownAt, now.timeIntervalSince(shownAt) < markerMinimum { return true }
        return (untilSettled || change.state != .accepted) && now.timeIntervalSince(change.createdAt) >= markerDelay
    }

    public static func waitingText(count: Int) -> String {
        count == 1 ? "1 change is waiting for your Mac. It will be saved when your Mac can be reached." // goop-lint: allow enginenumber: a count of one
            : "\(count) changes are waiting for your Mac. They will be saved when your Mac can be reached."
    }
}
