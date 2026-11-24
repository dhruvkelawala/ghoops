import SwiftUI
import GHealthCore

struct PairingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var link = ""
    @State private var busy = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    GoopMark().fill(.white).frame(width: 72, height: 72)
                    GoopWordmark(size: 40, color: Goop.Color.bodyText).frame(width: 96, height: 96 / 3.75).padding(.top, 24)
                    Text("Pair with your Mac").goop(.heading).padding(.top, 28)
                    Text("On the Mac, run ghoops pair, then scan the code with the Camera app, or paste the link below.").goop(.bodyMid).foregroundStyle(Goop.Color.text2).multilineTextAlignment(.center).padding(.top, 10)
                    TextField("", text: $link, prompt: Text("ghealth://pair?…").foregroundStyle(Goop.Color.text3), axis: .vertical)
                        .goop(.bodyMid).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityLabel("Pairing link")
                        .padding(14).frame(minHeight: 50).background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker)).padding(.top, 24)
                    GoopButton(title: "PAIR", role: .primary, busy: busy, action: pair).disabled(busy || link.isEmpty).opacity(busy || link.isEmpty ? Goop.Opacity.disabled : 1).padding(.top, 12)
                    if let error = model.error { Text(error).goop(.bodyMid).foregroundStyle(Goop.Color.caution).padding(.top, 12) }
                }.padding(.horizontal, 24).padding(.vertical, 24).frame(minHeight: geometry.size.height)
            }
        }.background(Goop.Gradient.homeBackground.ignoresSafeArea()).foregroundStyle(.white)
            .accessibilityElement(children: .contain).accessibilityIdentifier("pairing-screen")
    }
    private func pair() {
        guard let url = URL(string: link) else { model.error = PairingError.invalidLink.errorDescription; return }
        if model.paired { model.pendingURL = url }
        else { Task { busy = true; await model.pair(url); busy = false } }
    }
}
