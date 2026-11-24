import SwiftUI
import GHealthCore

struct LiveTargetRow: View {
    var projected: Double?
    var low: Double
    var high: Double
    var caption = "EST. DAY STRAIN"
    var spokenCaption = "Estimated Day Strain"
    var identifier = "activity-target"
    private var within: Bool { projected.map { low <= $0 && $0 <= high } ?? false }
    private var accessibility: String {
        "\(spokenCaption), \(projected.map { GoopFormat.number($0, decimals: 1) } ?? "not available"). Target \(GoopFormat.number(low, decimals: 1)) to \(GoopFormat.number(high, decimals: 1))" + (within ? ", reached" : "")
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(GoopFormat.number(projected, decimals: 1)).goop(.valueLiveStat)
                    .foregroundStyle(projected == nil ? Goop.Color.text2 : Goop.Color.text1)
                    .accessibilityIdentifier(identifier == "activity-target" ? "\(identifier)-estimate" : "\(identifier)-value")
                Text(caption).goop(.labelStat).foregroundStyle(Goop.Color.iconMuted)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(Goop.Color.cardDivider).frame(width: 1, height: 40).accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("\(GoopFormat.number(low, decimals: 1))–\(GoopFormat.number(high, decimals: 1))").goop(.valueLiveStat)
                    .accessibilityIdentifier("\(identifier)-range")
                HStack(spacing: 5) {
                    if within {
                        GoopSymbol(name: "checkmark", size: 9, color: Goop.Color.positive, weight: .semibold)
                            .accessibilityHidden(false).accessibilityLabel("Reached")
                            .accessibilityIdentifier("\(identifier)-within")
                    }
                    Text("TARGET").goop(.labelStat).foregroundStyle(Goop.Color.iconMuted)
                }
            }.frame(maxWidth: .infinity)
        }.foregroundStyle(Goop.Color.text1)
            .accessibilityElement(children: .combine).accessibilityLabel(accessibility)
            .accessibilityIdentifier(identifier)
    }
}
