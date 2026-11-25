import SwiftUI
import GHealthCore

struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    let flow: PairingFlow
    @State private var code = ""
    @State private var issue: String?
    @State private var cameraFailed = false
    @State private var replace = false
    @FocusState private var pasting: Bool

    var body: some View {
        switch flow.step {
        case .scan:
            GoopTaskSheet(title: "SCAN CODE", closeIdentifier: "pairing-close") {
                VStack(alignment: .leading, spacing: 12) {
                    if PairingScanner.available && !cameraFailed {
                        PairingScanner(receive: scan, unavailable: { cameraFailed = true })
                            .aspectRatio(1.25, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
                            .overlay { GoopSymbol(name: "viewfinder", size: 190, color: Goop.Color.text1).allowsHitTesting(false).accessibilityHidden(true) }
                        caption(PairingCopy.scanHint)
                    } else {
                        PairingCodeField(text: $code, focused: $pasting)
                        GoopButton(title: "CONTINUE", role: .outline, identifier: "pairing-continue") {
                            pasting = false
                            _ = scan(code)
                        }.disabled(code.isEmpty)
                    }
                    if let issue { PairingIssue(message: issue) }
                }.padding(.top, 14)
            }
        case .check(let code):
            checkAddress(code)
        case .redeeming:
            GoopTaskSheet(title: "CHECK ADDRESS", closeIdentifier: "pairing-close") {
                ProgressView().padding(.top, 14)
            }
        case .waiting(let digits):
            GoopTaskSheet(title: "CONFIRM ON MAC", closeIdentifier: "pairing-close") {
                VStack(alignment: .leading, spacing: 14) {
                    Text(PairingCopy.compareCode).goop(.bodyMid)
                    Text(digits).goop(.valueAverage).accessibilityIdentifier("pairing-verification-code")
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusLegend))
                    HStack(spacing: 10) {
                        ProgressView().tint(Goop.Color.textSoft)
                        Text("Waiting for your Mac").goop(.bodySmall).foregroundStyle(Goop.Color.textSoft)
                    }.frame(maxWidth: .infinity)
                    caption(PairingCopy.verificationHint)
                }.padding(.top, 14)
            }
        case .done:
            EmptyView()
        case .failed(let error, let verifying):
            GoopTaskSheet(title: verifying ? "CONFIRM ON MAC" : "CHECK ADDRESS", closeIdentifier: "pairing-close") {
                if (error as? PairingError)?.endsEnrolment != true,
                   let message = ErrorCopy.message(error, context: .pair) {
                    PairingIssue(message: message).padding(.top, 14)
                }
            }
        }
    }

    private func checkAddress(_ code: PairingCode) -> some View {
        let current = model.pairedMac.flatMap { URL(string: $0.url) }
        let differentURL = current.map { $0 != code.origin } ?? false
        let commit = GoopCommit(title: "PAIR WITH THIS MAC", symbol: "checkmark", identifier: "pairing-confirm", enabled: !model.pairingInProgress) {
            if differentURL { replace = true }
            else { model.confirmEnrolment(flow) }
        }
        let address = "\(code.host), port \(code.port)"
        return GoopTaskSheet(title: "CHECK ADDRESS", back: model.pairingInProgress ? nil : { flow.scanAgain() },
                             closeIdentifier: "pairing-close", commit: commit) {
            VStack(alignment: .leading, spacing: 14) {
                if differentURL, let current, let host = current.host {
                    addressRows("PAIRED NOW", host: host, port: current.port ?? 443)
                }
                addressRows("MAC IN THE CODE", host: code.host, port: code.port)
                caption(PairingCopy.addressHint)
            }.padding(.top, 14)
        }.goopDestructiveAlert(
            "Replace the current pairing?", isPresented: $replace, verb: "Replace pairing",
            message: model.pairingSwitchMessage("This iPhone switches to \(address). Nothing is deleted on your Mac.", replacing: code.origin)
        ) { model.confirmEnrolment(flow) }
    }

    private func scan(_ text: String) -> Bool {
        do {
            try flow.scan(text)
            issue = nil
            return true
        } catch {
            issue = ErrorCopy.message(error, context: .pair)
            return false
        }
    }

    private func addressRows(_ title: String, host: String, port: Int) -> some View {
        VStack(spacing: 8) {
            GoopSectionLabel(title: title)
            GoopRow("ADDRESS", value: host)
            GoopRow("PORT", value: String(port))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).goop(.bodySmall).foregroundStyle(Goop.Color.text2)
    }
}

struct PairingCodeField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 8) {
            Text("OR PASTE THE CODE FROM YOUR MAC").goop(.labelCard).foregroundStyle(Goop.Color.iconMuted)
                .multilineTextAlignment(.center)
            TextField("", text: $text, prompt: Text("GHOOPS1 …").foregroundStyle(Goop.Color.text3))
                .goop(.bodyMid).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                .focused(focused).accessibilityLabel("Pairing code").accessibilityIdentifier("pairing-code")
                .padding(14).frame(minHeight: 50)
                .background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
        }
    }
}

struct PairingIssue: View {
    let message: String
    var body: some View {
        Text(message).goop(.bodyMid).foregroundStyle(Goop.Color.caution)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("pairing-issue")
    }
}
