import SwiftUI
import GHealthCore

/// HOW HARD IT FELT: one session's rating, 0 to 10 (effort-rating-spec.md §3.2).
struct EffortRatingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var selection: Int?
    @State private var saveError: String?

    var body: some View {
        GoopTaskSheet(title: "HOW HARD IT FELT", closeIdentifier: "rating-close", commit: commit) {
            VStack(spacing: 0) {
                if let saveError { GoopBanner(text: saveError, symbol: "exclamationmark.triangle", tone: .caution).padding(.top, 4).padding(.bottom, 12).accessibilityIdentifier("rating-error") }
                Text("How hard was the whole session?").goop(.bodyMid).foregroundStyle(Goop.Color.legendText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(EffortScale.values, id: \.self) { rpe in
                        GoopChoiceRow(number: "\(rpe)", title: EffortScale.word(rpe)?.uppercased() ?? "", selected: selection == rpe, identifier: "rating-\(rpe)") { selection = rpe }
                            .accessibilityLabel(EffortScale.spoken(rpe))
                    }
                }.padding(.top, 12)
                Text("Your rating stays on your Mac. It doesn't change Strain.").goop(.bodySmall).foregroundStyle(Goop.Color.text2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("rating-sheet")
        .onAppear { if selection == nil { selection = workout.rpe } }
    }

    private var commit: GoopCommit {
        GoopCommit(title: "SAVE RATING", symbol: "checkmark", identifier: "rating-save", enabled: selection != nil && selection != workout.rpe, accessibilityLabel: "Save rating") { save() }
    }

    private func save() {
        guard let rpe = selection else { return }
        let change = ChangeBuilder.rate(workout, rpe: rpe, serverURL: model.changeServerURL, now: .now)
        Task {
            do {
                try await model.submit(change)
                saveError = nil
                dismiss()
            } catch { saveError = ErrorCopy.message(error, context: .saveRating, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) }
        }
    }
}
