import SwiftUI
import GHealthCore

struct HeartRateBanner: View {
    var state: HeartRateConnection
    var select: (UUID) -> Void
    var body: some View {
        GoopBanner(text: message, title: title, symbol: symbol, tone: tone) {
            if case .denied = state { Link("Settings", destination: URL(string: UIApplication.openSettingsURLString)!).goop(.bodyMid).foregroundStyle(tone.ink) }
            if case .choosing(let devices) = state { ForEach(devices) { device in Button(device.name) { select(device.id) }.goop(.bodyMid).foregroundStyle(tone.ink) } }
        }.accessibilityIdentifier("heart-rate-banner")
    }
    private var tone: GoopBannerTone {
        switch state { case .connected: .positive; case .searching, .choosing: .muted; default: .caution }
    }
    private var symbol: String {
        switch state { case .connected: "antenna.radiowaves.left.and.right"; case .poweredOff, .denied: "antenna.radiowaves.left.and.right.slash"; default: "antenna.radiowaves.left.and.right" }
    }
    private var title: String {
        switch state {
        case .searching: "LOOKING FOR YOUR BAND"
        case .connected(let name, _): "\(name.uppercased()) CONNECTED"
        case .notFound: "NO LIVE HEART RATE"
        case .poweredOff: "BLUETOOTH IS OFF"
        case .denied: "BLUETOOTH NOT ALLOWED"
        case .choosing: "CHOOSE YOUR BAND"
        }
    }
    private var message: String {
        switch state {
        case .searching: "Keep your Fitbit Air close to your phone."
        case .connected(_, let bpm): HeartRateBannerText.connected(bpm: bpm)
        case .notFound: "In Google Health, open Connections, choose your Fitbit Air and tap Share heart rate. You can still start; Strain will come from your band later."
        case .poweredOff: "Turn on Bluetooth to see live heart rate."
        case .denied: "Allow Bluetooth for ghoops in Settings."
        case .choosing: "Select the heart rate monitor you want to use."
        }
    }
}
