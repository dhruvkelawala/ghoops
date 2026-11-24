#if DEBUG
import Foundation
import GHealthCore
import UIKit

extension AppModel {
    func configureSleepEditAPI() async {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-GHealthSleepEditFixture"), args.indices.contains(i + 1) { sleepEditFixture = args[i + 1] }
        guard fixtureSet == .sleepEdit || sleepEditFixture != nil else { return }
        let mode: FixtureEditAPI.MutationMode = switch sleepEditFixture {
        case "saving": .hold
        case "waiting": .offline
        case "reconnect": .offline
        case "rollback": .reject(.rejected)
        default: .answer
        }
        let api = FixtureEditAPI(state: fixtureSet == .sleepEdit ? "extended" : "unedited", mutationMode: mode, sleepEditing: true)
        fixtureEditAPI = api
        if sleepEditFixture == "reconnect" {
            // The Mac comes back once the app has been in the background, so the next activation's retry settles.
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                Task { await api.setMutationMode(.answer) }
            }
        }
        if var snapshot = try? await api.snapshot(), let meta = cached?.meta {
            if sleepEditFixture == "old" {
                snapshot.defaultDate = GoopFormat.addingDays(snapshot.status.editLimits?.horizonDays ?? 0, to: snapshot.sleep.date)
                snapshot.sleep.session?.editRange = nil
            }
            if sleepEditFixture == "no_stages" {
                snapshot.sleep.hypnogram?.segments = []
                snapshot.sleep.session?.editRange = nil
            }
            applyServerSnapshot(CachedSnapshot(snapshot: snapshot, meta: meta))
        }
    }
    func configureSleepEditState() async {
        guard fixtureSet == .sleepEdit || sleepEditFixture != nil, let sleep = cached?.snapshot.sleep else { return }
        selectedDate = sleep.date
        await loadDay(selectedDate)
        push(.sleep)
        if ["saving", "waiting", "reconnect", "rollback"].contains(sleepEditFixture), var draft = SleepEditDraft(sleep: sleep, limits: editLimits, now: now) {
            let args = ProcessInfo.processInfo.arguments
            let wake = args.firstIndex(of: "-GHealthSleepEditWake").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1].split(separator: ":").compactMap { Int($0) } : nil } ?? [7, 41]
            draft.moveEnd(to: GoopFormat.calendar.date(bySettingHour: wake[0], minute: wake[1], second: 0, of: sleep.wakeTime!)!)
            do { try await submit(ChangeBuilder.sleep(draft, serverURL: changeServerURL, now: .now)) }
            catch { self.error = error.localizedDescription }
        }
    }
}
#endif
