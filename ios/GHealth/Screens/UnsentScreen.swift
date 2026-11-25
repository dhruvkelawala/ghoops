import SwiftUI
import GHealthCore

struct UnsentScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false
    @State private var saving = false

    var body: some View {
        let held = model.activity.held
        ScrollView {
            VStack(spacing: 0) {
                GoopDetailHeader(title: "UNSENT", back: { dismiss() })
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error = model.activity.error { GoopBanner(text: error, symbol: "exclamationmark.circle") }
                        ForEach(Array(groups(held).enumerated()), id: \.offset) { index, rows in
                            group(rows, index: index)
                        }
                    }
                    GoopButton(title: "DISCARD ALL", role: .destructive, identifier: "unsent-discard") {
                        confirmDiscard = true
                    }
                }
                .disabled(saving)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .background(Goop.Gradient.detailBackground.ignoresSafeArea())
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain).accessibilityIdentifier("unsent-screen")
        .toolbarVisibility(.hidden, for: .navigationBar, .tabBar)
        .background(InteractivePopEnabler())
        .onChange(of: held.isEmpty) { _, empty in
            if empty { dismiss() }
        }
        .goopDestructiveAlert("Discard unsent activities?", isPresented: $confirmDiscard, verb: "Discard",
                              message: discardMessage(held.count)) {
            update { await model.activity.discardHeld(Set(held.map(\.id))) }
        }
    }

    private func groups(_ held: [LocalActivity]) -> [[LocalActivity]] {
        let newestFirst = held.sorted { $0.upload.end > $1.upload.end }
        let grouped = Dictionary(grouping: newestFirst) { row in
            row.mac.map { mac in mac.profile.map { "profile:\($0)" } ?? mac.url }
        }
        return grouped.values.sorted { $0[0].upload.end > $1[0].upload.end }
    }

    private func group(_ rows: [LocalActivity], index: Int) -> some View {
        let name = rows[0].mac?.name
        return VStack(alignment: .leading, spacing: 8) {
            GoopSectionLabel(title: name.map { "SAVED FOR \($0.uppercased())" } ?? "SAVED BEFORE THIS UPDATE")
            ForEach(rows.reversed()) { row in
                GoopRow(ActivitySport.sport(row.upload.exerciseType).name.uppercased(), value: dateAndTime(row.upload))
            }
            Text(name.map { "Sent when this iPhone is paired with \($0) again." } ?? "ghoops can't tell which Mac these were saved for.")
                .goop(.bodySmall).foregroundStyle(Goop.Color.text2)
            if let current = model.activity.mac?.name {
                GoopButton(title: "SEND TO \(current.uppercased())", role: .outline, identifier: "unsent-send-\(index)") {
                    update { await model.activity.adoptHeld(Set(rows.map(\.id))) }
                }
            }
        }
    }

    private func dateAndTime(_ activity: ActivityUpload) -> String {
        let day = GoopFormat.dateLabel(GoopFormat.dateKey(activity.start), format: "EEE d MMM")
        return "\(day) · \(GoopFormat.time(activity.start))–\(GoopFormat.time(activity.end))"
    }

    private func discardMessage(_ count: Int) -> String {
        let activities = count == 1 ? "activity is" : "activities are"
        return "\(count) \(activities) deleted from this iPhone. Nothing changes on any Mac."
    }

    private func update(_ action: @escaping () async -> Void) {
        saving = true
        Task {
            await action()
            saving = false
        }
    }
}
