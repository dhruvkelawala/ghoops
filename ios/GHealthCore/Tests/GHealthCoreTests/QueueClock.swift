import Foundation
import Synchronization

final class QueueClock: Sendable {
    private let instant: Mutex<Date>

    init(_ date: Date) { instant = Mutex(date) }
    func now() -> Date { instant.withLock { $0 } }
    func advance(by seconds: TimeInterval) { instant.withLock { $0.addTimeInterval(seconds) } }
}
