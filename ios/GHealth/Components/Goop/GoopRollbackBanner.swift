import SwiftUI
import GHealthCore

struct GoopRollbackBanner: View {
    @Environment(AppModel.self) private var model
    let notice: RollbackNotice
    var body: some View {
        GoopBanner(text: notice.text, title: "NOT SAVED", symbol: "exclamationmark.triangle", tone: .caution,
                   dismiss: { model.dismissRollback(notice) })
    }
}
