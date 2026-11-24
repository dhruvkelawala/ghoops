import SwiftUI
import GHealthCore

struct HRVSmallView: View {
    let data: WidgetData
    private var vital: VitalMetric? { data.hrv }
    private var ranged: Bool { vital?.status == .available && ["within", "above", "below"].contains(vital?.position) && vital?.rangeLow != nil && vital?.rangeHigh != nil }
    private var color: Color { !ranged ? Goop.Color.textSoft : vital?.position == "within" ? Goop.Color.positive : data.hrvAttention ? Goop.Color.caution : Goop.Color.textSoft }
    private var chipFill: Color { ranged && vital?.position == "within" ? Goop.Color.vitalChipFill : ranged && data.hrvAttention ? Goop.Color.caution.opacity(0.12) : Goop.Color.neutral.opacity(0.15) }
    private var chipText: String {
        guard vital?.status == .available else { return ReasonText.metric(vital?.status ?? .missing) }
        guard ranged else { return "Building baseline" }
        return "\(GoopFormat.number(vital?.rangeLow)) – \(GoopFormat.number(vital?.rangeHigh))"
    }
    var body: some View {
        VStack(spacing: 9) {
            VStack(spacing: 3) {
                GoopWordmark(size: 14, color: Goop.Color.wordmarkDial).frame(width: 30, height: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(data.hrvText).goop(.scoreWidgetSmall).foregroundStyle(data.hrvText == "—" ? Goop.Color.text2 : Goop.Color.text1)
                    if data.hrvText != "—" { Text("ms").goop(.unit).foregroundStyle(Goop.Color.text2) }
                }.opacity(data.stale ? Goop.Opacity.stale : 1)
                HStack(spacing: 5) {
                    if ranged {
                        Image(systemName: vital?.position == "within" ? "checkmark" : vital?.position == "above" ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: vital?.position == "within" ? 9 : 7, weight: .semibold))
                    }
                    Text(chipText).goop(ranged ? .valueChip : .chip)
                }.fixedSize().foregroundStyle(color).padding(.vertical, 3).padding(.horizontal, 8)
                    .background(chipFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusChip))
                    .padding(.top, 3).opacity(data.stale ? Goop.Opacity.stale : 1)
            }.frame(height: 100)
            Text("HRV").goop(.labelWidget)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if data.stale {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").foregroundStyle(Goop.Color.caution)
                        Text(data.age).foregroundStyle(Goop.Color.text2)
                    }.goop(.captionWidget).padding(10)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel(accessible)
    }
    private var accessible: String {
        let state = vital?.status != .available ? ReasonText.metric(vital?.status ?? .missing) : ranged ? "\(vital?.position ?? "within") typical range \(GoopFormat.number(vital?.rangeLow)) to \(GoopFormat.number(vital?.rangeHigh))" : "building baseline"
        return "HRV, \(data.hrvText) milliseconds, \(state)\(data.spoken)"
    }
}
