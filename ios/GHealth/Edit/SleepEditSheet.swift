import SwiftUI
import GHealthCore

struct SleepEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: SleepEditDraft
    @State private var heartRate: [HeartRatePoint] = []
    @State private var heartRateMessage: String? = "Heart rate needs your Mac"
    @State private var saveError: String?
    @State private var restoring = false
    var body: some View {
        GoopTaskSheet(title: "EDIT SLEEP", closeIdentifier: "sleep-edit-close", commit: GoopCommit(title: "SAVE SLEEP", symbol: "checkmark", identifier: "sleep-edit-save", enabled: draft.hasChanges) { save() }) {
            VStack(spacing: 0) {
                if let saveError { GoopBanner(text: saveError, symbol: "exclamationmark.triangle", tone: .caution).padding(.bottom, 12) }
                GoopEditValues(sleepValue: draft.values, sleepPrior: draft.prior, prefix: "sleep-edit")
                GoopSleepWindowChart(draft: draft, heartRate: heartRate, heartRateMessage: heartRateMessage) { draft = $0 }.padding(.top, 22)
                GoopBandLegend(title: "GOOGLE'S VERSION", times: "\(GoopFormat.time(draft.google.start)) to \(GoopFormat.time(draft.google.end))").padding(.top, 10)
                Text("Drag a dashed edge, or set the times below.").goop(.bodySmall).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                VStack(spacing: 8) {
                    GoopTimeRow("BEDTIME", time: time(start: true), range: draft.bounds.startRange(end: draft.window.end), identifier: "sleep-edit-start", date: ActivityTime.dateLabels(draft.window)?.start)
                    GoopTimeRow("WAKE", time: time(start: false), range: draft.bounds.endRange(start: draft.window.start), identifier: "sleep-edit-end", date: ActivityTime.dateLabels(draft.window)?.end)
                }.padding(.top, 24)
                Text(footnote).goop(.bodySmall).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 24)
                if draft.sleep.session?.edit != nil {
                    GoopButton(title: "RESTORE GOOGLE'S VERSION", identifier: "sleep-edit-restore") { restoring = true }.padding(.top, 12)
                }
                Color.clear.frame(height: 20)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("sleep-edit")
            .task { await loadHeartRate() }
            .alert("Restore Google's times?", isPresented: $restoring) {
                Button("Cancel", role: .cancel) {}
                Button("Restore") { save(restore: true) }
            } message: { Text("This removes your edit to this night from ghoops on your Mac.") }
    }
    private var footnote: String {
        let counts: String = switch draft.sleep.scoreConstants?.sleep.unstagedCountsAs {
        case "asleep": "Time you add has no sleep stages. ghoops counts it as sleep. "
        case "awake": "Time you add has no sleep stages. ghoops counts it as awake. "
        default: ""
        }
        return counts + "Edits stay on your Mac. Google Health keeps its own times."
    }
    private func time(start: Bool) -> Binding<Date> {
        Binding(get: { start ? draft.window.start : draft.window.end }, set: { value in
            let date = ActivityTime.picker(value, within: draft.bounds.span)
            if start { draft.moveStart(to: date) } else { draft.moveEnd(to: date) }
        })
    }
    private func loadHeartRate() async {
        do {
            guard let api = model.editAPI else { return }
            let body = try await api.heartRate(start: draft.bounds.span.start, end: draft.bounds.span.end)
            let buckets = Dictionary(grouping: body.minutes) { floor($0.t.timeIntervalSince1970 / 300) * 300 }
            heartRate = buckets.map { time, minutes in HeartRatePoint(t: Date(timeIntervalSince1970: time), bpm: Int((minutes.map(\.avgBpm).reduce(0, +) / Double(minutes.count)).rounded())) }.sorted { $0.t < $1.t }
            heartRateMessage = heartRate.isEmpty ? "Heart rate needs your Mac" : nil
        } catch {
            heartRateMessage = (error as? ClientError) == .offline || (error as? ClientError) == .unauthorized ? "Heart rate needs your Mac" : ErrorCopy.message(error, context: .readHeartRate)
        }
    }
    private func save(restore: Bool = false) {
        let change = ChangeBuilder.sleep(draft, restore: restore, serverURL: model.changeServerURL, now: .now)
        Task {
            do { try await model.submit(change); dismiss() }
            catch { saveError = ErrorCopy.message(error, context: .saveSleep, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable) }
        }
    }
}
