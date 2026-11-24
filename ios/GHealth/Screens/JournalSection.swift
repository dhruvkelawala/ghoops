import SwiftUI
import GHealthCore

/// Recovery detail's Journal section: the answers for the evening before this Recovery (journal-spec §8.1, §8.2).
struct JournalSection: View {
    @Environment(AppModel.self) private var model
    let journal: Journal
    let recoveryDate: String
    @State private var answering = false
    private var date: String { JournalText.journalDate(forRecovery: recoveryDate) }
    private var target: String { "journal-\(date)" }

    var body: some View {
        let answers = journal.entry(on: date)?.answers ?? [:]
        let status = model.changeStatus(for: target)
        VStack(spacing: 0) {
            Text("Journal").goop(.heading).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.bottom, 12).accessibilityAddTraits(.isHeader)
            GoopCard {
                HStack(spacing: 8) {
                    Text(GoopFormat.dateLabel(date, format: "EEE d MMM").uppercased()).goop(.labelCard).lineLimit(1)
                    Spacer(minLength: 8)
                    switch status {
                    case .waiting: Text("WAITING FOR MAC").goop(.labelMicro).foregroundStyle(Goop.Color.caution)
                    case .saving: Text("SAVING").goop(.labelMicro).foregroundStyle(Goop.Color.text2)
                    case nil: Text(JournalText.answered(journal, date: date)).goop(.labelSmall).foregroundStyle(Goop.Color.textSoft)
                    }
                }.accessibilityElement(children: .combine).accessibilityIdentifier("journal-status")
                VStack(spacing: 0) {
                    ForEach(journal.behaviours) { behaviour in
                        HStack(spacing: 12) {
                            Text(behaviour.name).goop(.bodyMid).foregroundStyle(Goop.Color.legendText)
                            Spacer(minLength: 0)
                            if let word = JournalText.answer(answers[behaviour.key]) {
                                Text(word).goop(.labelSmall)
                            } else {
                                Text("—").goop(.valueMid).foregroundStyle(Goop.Color.text2).accessibilityLabel("Not answered")
                            }
                        }.padding(.vertical, 7).accessibilityElement(children: .combine).accessibilityIdentifier("journal-answer-\(behaviour.key)")
                    }
                }.padding(.top, 8)
                GoopFootnote(text: JournalText.footnote).padding(.top, 10)
            }
            if status == .waiting {
                GoopBanner(text: "Saved on your phone. It will be sent to your Mac when it can be reached.", symbol: "arrow.triangle.2.circlepath", tone: .strain)
                    .padding(.top, 12).accessibilityIdentifier("journal-waiting-banner")
            } else if !model.lockedWorkouts.contains(target), EditLimits.editable(cycleDate: recoveryDate, defaultDate: model.defaultDate, limits: model.editLimits) {
                GoopButton(title: "ANSWER JOURNAL", identifier: "journal-open") { answering = true }.padding(.top, 12)
            }
        }
        .sheet(isPresented: $answering) { JournalSheet(journal: journal, date: date) }
    }
}

/// The JOURNAL task sheet: one YES / NO row per behaviour the Mac lists (journal-spec §8.3).
struct JournalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: JournalDraft
    @State private var saveError: String?

    init(journal: Journal, date: String) { _draft = State(initialValue: JournalDraft(journal: journal, date: date)) }

    var body: some View {
        GoopTaskSheet(title: "JOURNAL", commit: GoopCommit(title: "SAVE ANSWERS", symbol: "checkmark", identifier: "journal-save", enabled: draft.changed) { save() }) {
            VStack(alignment: .leading, spacing: 8) {
                GoopSectionLabel(title: GoopFormat.dateLabel(draft.date, format: "EEEE d MMMM").uppercased()).padding(.top, 4).padding(.bottom, 2)
                if let saveError { GoopBanner(text: saveError, symbol: "exclamationmark.triangle", tone: .caution) }
                ForEach(draft.behaviours) { behaviour in row(behaviour) }
            }
        }
    }

    private func row(_ behaviour: JournalBehaviour) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        let answer = Binding<String>(get: { JournalText.answer(draft.answers[behaviour.key]) ?? "" }, set: { draft.answer(behaviour.key, $0 == "YES") })
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(behaviour.name.uppercased()).goop(.labelCard).accessibilityLabel(behaviour.name)
                Text(behaviour.question).goop(.rowNote).foregroundStyle(Goop.Color.text2).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            GoopRangeSelector(options: ["YES", "NO"], selection: answer, identifier: { "journal-\(behaviour.key)-\($0.lowercased())" })
        }.padding(.vertical, 10).padding(.horizontal, 14).frame(minHeight: 60)
            .background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
    }

    private func save() {
        let change = ChangeBuilder.journal(draft, serverURL: model.changeServerURL, now: .now)
        Task {
            do { try await model.submit(change); dismiss() }
            catch { saveError = ErrorCopy.message(error, context: .saveJournal, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) }
        }
    }
}
