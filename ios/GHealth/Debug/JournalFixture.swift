#if DEBUG
import Foundation
import GHealthCore

extension AppModel {
    /// `-GHealthJournalFixture answer|waiting|rollback` gives `fresh` a fixture Mac that stores journal answers.
    func configureJournalAPI() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-GHealthJournalFixture"), args.indices.contains(i + 1) else { return }
        let mode: FixtureEditAPI.MutationMode = switch args[i + 1] {
        case "waiting": .offline
        case "rollback": .reject(.rejected)
        default: .answer
        }
        let api = FixtureEditAPI(mutationMode: mode, journalEditing: true)
        fixtureEditAPI = api
        if let snapshot = try? await api.snapshot(), let meta = cached?.meta {
            applyServerSnapshot(CachedSnapshot(snapshot: snapshot, meta: meta))
        }
    }
}
#endif
