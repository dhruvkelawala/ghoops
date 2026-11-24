import ActivityKit
import Foundation
import GHealthCore

struct GoopActivityAttributes: ActivityAttributes {
    typealias ContentState = ActivityContentState
    var id: String
    var exerciseType: String
    var displayName: String
    var start: Date

    init(session: ActivitySession) {
        id = session.id; exerciseType = session.exerciseType
        displayName = session.displayName; start = session.start
    }
}
