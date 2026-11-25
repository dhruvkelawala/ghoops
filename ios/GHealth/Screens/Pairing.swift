import SwiftUI
import GHealthCore

struct PairingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @FocusState private var pasting: Bool
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    GoopMark().fill(.white).frame(width: 72, height: 72)
                    GoopWordmark(size: 40, color: Goop.Color.bodyText).frame(width: 96, height: 96 / 3.75).padding(.top, 24)
                    Text("Pair with your Mac").goop(.heading).padding(.top, 28)
                    controls
                }.padding(.horizontal, 24).padding(.vertical, 24).frame(minHeight: geometry.size.height)
            }
        }.background(Goop.Gradient.homeBackground.ignoresSafeArea()).foregroundStyle(.white)
            .accessibilityElement(children: .contain).accessibilityIdentifier("pairing-screen")
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text("On your Mac, run ghoops pair. Then scan the code it shows.")
                .goop(.bodyMid).foregroundStyle(Goop.Color.text2).multilineTextAlignment(.center)
            GoopButton(title: "SCAN CODE", role: .primary, identifier: "pairing-scan") { model.openEnrolment() }
                .padding(.bottom, 12)
            PairingCodeField(text: $code, focused: $pasting)
            if let error = model.error { PairingIssue(message: error) }
            GoopButton(title: "CONTINUE", role: .outline, identifier: "pairing-continue") {
                pasting = false
                model.openEnrolment(pasted: code)
            }.disabled(code.isEmpty)
        }.padding(.top, 10).disabled(model.pairingInProgress)
    }
}

struct OldPairingLinkBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let message = model.paired && !model.invalidPairing
            ? "ghoops no longer opens pairing links. On your Mac, run ghoops pair, then scan its code in More › PAIR AGAIN."
            : "ghoops no longer opens pairing links. On your Mac, run ghoops pair, then tap SCAN CODE."
        GoopBanner(text: message, symbol: "info.circle", dismiss: { model.showsOldPairingLink = false })
            .accessibilityElement(children: .contain).accessibilityIdentifier("old-pairing-link")
    }
}
