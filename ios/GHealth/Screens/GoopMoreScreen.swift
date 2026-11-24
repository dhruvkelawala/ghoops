import SwiftUI
import GHealthCore

struct GoopMoreScreen: View {
    @Environment(AppModel.self) private var model
    @State private var connection: String?
    @State private var testing = false
    @State private var confirmUnpair = false
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoopDetailHeader(title: "MORE")
                VStack(spacing: 0) {
                    section("MAC") {
                        GoopRow("PAIRED MAC", value: model.credentials?.name ?? (model.isFixture ? "Fixture Mac" : "—"))
                        GoopRow("ADDRESS", value: model.credentials?.url.absoluteString ?? model.cached?.meta.serverUrl ?? "—").textSelection(.enabled)
                        GoopRow("LAST FETCH", value: model.cached.map { Format.relative($0.meta.fetchedAt, now: model.now) } ?? "never")
                        Button {
                            Task { testing = true; connection = await model.testConnection(); testing = false }
                        } label: {
                            GoopRow("TEST CONNECTION") {
                                if testing { ProgressView() }
                                if let connection { Text(connection).goop(.bodySmall).foregroundStyle(Goop.Color.textSoft).accessibilityIdentifier("connection-result") }
                            }
                        }.disabled(testing).accessibilityIdentifier("test-connection")
                    }
                    if let status = model.cached?.snapshot.status {
                        section("BAND") {
                            if status.device.status == "scope_missing" { warning("Band details need permission: run ghoops auth login on your Mac") }
                            else {
                                GoopRow("NAME", value: status.device.name ?? "Unavailable")
                                GoopRow("BATTERY", value: status.device.batteryLevel.map { "\($0)% · \(status.device.batteryStatus ?? "—")" } ?? "—")
                                GoopRow("LAST SYNCED", value: status.device.lastSyncAt.map { "Last synced to Fitbit \(Format.relative($0, now: model.now))" } ?? "Band sync time unavailable")
                            }
                        }
                        section("DATA COLLECTION") {
                            GoopRow("LAST COLLECTED", value: status.freshness.collectedAt.map { Format.relative($0, now: model.now) } ?? "never")
                            GoopRow("STATUS", value: status.freshness.lastCollectStatus)
                            GoopRow("SCHEDULE", value: status.collector.scheduleInstalled ? "Installed" : "Not installed")
                            GoopRow("CALIBRATION", value: status.calibration.status.capitalized)
                            if !status.auth.missingScopes.isEmpty { warning("Run ghoops auth login on your Mac to grant: " + status.auth.missingScopes.map(scope).joined(separator: ", ")) }
                        }
                        section("SCORES") {
                            GoopRow("SCORE VERSION", value: status.scoreVersion ?? "—")
                            GoopRow("MAX HR OVERRIDE", value: status.scoreConfig?.maxHrOverrideBpm.map { "\($0) bpm" } ?? "Default")
                            GoopRow("SLEEP BASE NEED", value: GoopFormat.duration(status.scoreConfig?.sleepBaseNeedMinutes))
                            GoopRow("TRIMP PROFILE", value: status.scoreConfig?.trimpProfile ?? "—")
                            caption("Change these with ghoops config set on your Mac")
                        }
                    }
                    section("ABOUT") {
                        GoopRow("VERSION", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        caption("Data stays on your Mac and this iPhone. ghoops is not a medical device.")
                        GoopRow("OPEN-SOURCE FONTS", value: "Sofia Sans Condensed and Nunito Sans, SIL Open Font License 1.1") // goop-lint: allow enginenumber: licence version
                    }
                    GoopButton(title: "UNPAIR", role: .destructive) { confirmUnpair = true }
                    #if DEBUG
                    section("DEVELOPER") {
                        Menu {
                            ForEach(FixtureSet.allCases, id: \.rawValue) { set in Button(set.rawValue) { model.useFixture(set) } }
                        } label: { GoopRow("FIXTURE MODE") { Text(model.fixtureSet?.rawValue ?? "Live").goop(.bodySmall).foregroundStyle(Goop.Color.textSoft) } }.accessibilityIdentifier("fixture-mode")
                    }
                    #endif
                }.padding(.horizontal, 16).padding(.bottom, 30)
            }
        }.contentMargins(.bottom, 84, for: .scrollContent)
            .background(Goop.Gradient.homeBackground.ignoresSafeArea()).foregroundStyle(.white).buttonStyle(.plain)
            .accessibilityElement(children: .contain).accessibilityIdentifier("more-screen")
            .goopDestructiveAlert("Unpair from your Mac?", isPresented: $confirmUnpair, verb: "Unpair", message: "This iPhone stops reading from your Mac until you pair again. Nothing is deleted on your Mac.") {
                Task { await model.unpair() }
            }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GoopSectionLabel(title: title).padding(.top, 26).padding(.bottom, 10)
            VStack(spacing: 8, content: content)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func warning(_ text: String) -> some View { Text(text).goop(.bodyMid).foregroundStyle(Goop.Color.caution).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker)) }
    private func caption(_ text: String) -> some View { Text(text).goop(.bodySmall).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading) }
    private func scope(_ name: String) -> String {
        switch name { case "profile": "Profile"; case "settings": "Settings"; case "irn": "Irregular rhythm"; case "location": "Location"; default: name }
    }
}
