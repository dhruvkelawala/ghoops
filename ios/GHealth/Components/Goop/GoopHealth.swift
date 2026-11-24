import SwiftUI
import GHealthCore

struct GoopVitalTile: View {
    var key: String
    var metric: TrendMetricKey
    var title: String
    var vital: VitalMetric
    var attention = false
    var constants: ScoreConstants?
    var dimmed = false
    var action: () -> Void
    private var color: Color {
        vital.status != .available || vital.position == "no_baseline" ? Goop.Color.textSoft : vital.position == "within" ? Goop.Color.positive : attention ? Goop.Color.caution : Goop.Color.textSoft
    }
    private var chipFill: Color { vital.position == "within" && vital.status == .available ? Goop.Color.vitalChipFill : attention && vital.status == .available ? Goop.Color.caution.opacity(0.12) : Goop.Color.neutral.opacity(0.15) }
    private var ranged: Bool { vital.status == .available && vital.position != "no_baseline" && vital.rangeLow != nil && vital.rangeHigh != nil }
    private var chip: String {
        if vital.status != .available { return ReasonText.metric(vital.status) }
        guard ranged, let low = vital.rangeLow, let high = vital.rangeHigh else { return "Building baseline" }
        return "\(rangeNumber(low)) – \(rangeNumber(high))"
    }
    private func rangeNumber(_ value: Double) -> String {
        metric == .skinTemp ? GoopFormat.temperature(value) : GoopFormat.number(value, decimals: metric.decimals)
    }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) { GoopSymbol(name: metric.icon, size: 15); Text(title.uppercased()).goop(.labelTiny).foregroundStyle(Goop.Color.vitalTitle).lineLimit(2) }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric == .spo2 ? GoopFormat.number(vital.status == .available ? vital.value : nil) : metric.display(vital.status == .available ? vital.value : nil)).goop(.valueVital)
                    if !metric.unit.isEmpty { Text(metric.unit).goop(.unit).foregroundStyle(Goop.Color.text2) }
                }.padding(.top, 12).opacity(dimmed ? Goop.Opacity.stale : 1)
                Spacer(minLength: 7)
                HStack(spacing: 6) {
                    if vital.status == .available, ["within", "above", "below"].contains(vital.position) {
                        GoopSymbol(name: vital.position == "within" ? "checkmark" : vital.position == "above" ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill", size: vital.position == "within" ? 10 : 8, color: color, weight: .semibold)
                    }
                    Text(chip).goop(ranged ? .valueChip : .chip)
                }.foregroundStyle(color).padding(.vertical, 3).padding(.horizontal, 8).background(chipFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusChip))
            }.frame(maxWidth: .infinity, minHeight: 97, maxHeight: .infinity, alignment: .leading).padding(.top, 13).padding(.horizontal, 13).padding(.bottom, 12).background(Goop.Gradient.tile, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusTile))
        }.buttonStyle(.plain).accessibilityIdentifier("vital-\(key)").accessibilityLabel(accessible)
    }
    private var accessible: String {
        let unit = metric == .respiratoryRate ? "breaths per minute" : metric == .restingHR ? "beats per minute" : metric == .spo2 ? "percent" : metric.unit
        let position = vital.position.map { "\($0) " } ?? ""
        let state = vital.status != .available ? ReasonText.metric(vital.status) : vital.position == "no_baseline" ? "building baseline" : "\(position)typical range \(metric.display(vital.rangeLow)) to \(metric.display(vital.rangeHigh))"
        let suffix = attention ? ", " + HealthText.attentionSpoken(constants) : ""
        return "\(title), \(vital.status == .available ? (metric == .spo2 ? GoopFormat.number(vital.value) : metric.display(vital.value)) + " " + unit : "no data"), \(state)\(suffix)"
    }
}

struct GoopHealthStatusCard: View {
    var state: HealthState
    var constants: ScoreConstants?
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Goop.Metric.radiusBadge).fill(Goop.color(state.color).opacity(0.15))
                if state.kind == .building { Text("—").goop(.valueSmall).foregroundStyle(Goop.missing("—") ? Goop.Color.text2 : Goop.color(state.color)) }
                else { GoopSymbol(name: state.kind == .within ? "checkmark" : "heart", size: 16, color: Goop.color(state.color), weight: state.kind == .within ? .semibold : .light) }
            }.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title).goop(.labelStage).foregroundStyle(Goop.color(state.color))
                Text(state.sentence).goop(.bodyMid).foregroundStyle(Goop.Color.monitorSub)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(Goop.Gradient.monitor, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusMonitor))
            .accessibilityElement(children: .ignore).accessibilityIdentifier("health-status")
            .accessibilityLabel("\(state.title), \(state.sentence)" + (state.kind == .attention ? ", " + HealthText.attentionSpoken(constants) : ""))
    }
}
