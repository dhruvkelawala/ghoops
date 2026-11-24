import SwiftUI
import GHealthCore

struct GoopHealthScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoopDetailHeader(title: "HEALTH MONITOR")
                GoopDateControl(date: model.selectedDate, defaultDate: model.defaultDate, oldestDate: model.oldestDate) { model.selectedDate = $0 }.padding(.top, 4)
                GoopDayContent { bundle in content(bundle.day) }
            }
        }.contentMargins(.bottom, 84, for: .scrollContent).background(Goop.Gradient.homeBackground.ignoresSafeArea()).foregroundStyle(.white)
            .accessibilityElement(children: .contain).accessibilityIdentifier("health-screen")
    }
    private func content(_ day: Day) -> some View {
        VStack(spacing: 0) {
            GoopHealthStatusCard(state: HealthState(day.vitals), constants: day.scoreConstants).padding(.top, 22)
            ForEach(Array(day.healthFlags.enumerated()), id: \.offset) { _, flag in
                GoopBanner(text: flag.message, symbol: flag.severity == "attention" ? "heart" : "info.circle", symbolColor: flag.severity == "attention" ? Goop.Color.caution : Goop.Color.iconMuted).padding(.top, 12)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Overnight Vitals").goop(.heading).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if model.selectedDate == model.defaultDate, let sync = model.cached?.snapshot.freshness.deviceLastSyncAt {
                    Text("Synced \(GoopFormat.time(sync))").goop(.bodySmall).foregroundStyle(Goop.Color.iconMuted)
                }
            }.padding(.horizontal, 4).padding(.top, 30)
            VStack(spacing: 11) {
                GoopPair(spacing: 11) { vital("respiratory_rate", .respiratoryRate, "Respiratory rate", day: day) } trailing: { vital("spo2", .spo2, "Blood oxygen", day: day) }
                GoopPair(spacing: 11) { vital("resting_hr", .restingHR, "Resting HR", day: day) } trailing: { vital("hrv_rmssd", .hrv, "HRV", day: day) }
                GoopPair(spacing: 11) { vital("skin_temp_deviation", .skinTemp, "Skin temp vs usual", day: day) } trailing: { if !typeSize.isAccessibilitySize { Color.clear } }
            }.padding(.top, 12)
            GoopButton(title: "VIEW TRENDS") { model.push(.trend(metric: .hrv, end: model.selectedDate)) }.accessibilityIdentifier("view-trends").padding(.top, 14)
            Text("More Health Data").goop(.heading).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 30).padding(.bottom, 12).accessibilityAddTraits(.isHeader)
            extra("CARDIO FITNESS") {
                if let value = day.vo2Max.value {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(GoopFormat.number(value, decimals: 1)).goop(.valueSmall)
                        Text("ml/kg/min").goop(.unit).foregroundStyle(Goop.Color.textSoft)
                        if day.vo2Max.estimated == true { Text("estimated").goop(.bodySmall).foregroundStyle(Goop.Color.text2) }
                    }.opacity(model.valuesOpacity)
                } else { Text("Not available from your band yet").goop(.bodySmall).foregroundStyle(Goop.Color.text2) }
            }
            extra("IRREGULAR RHYTHM") {
                Text(rhythm).goop(.bodySmall).foregroundStyle(Goop.Color.textSoft)
            }.padding(.top, 10)
            Text("ghoops shows estimates and your own ranges. It does not diagnose. Talk to a clinician about health concerns.").goop(.bodySmall).foregroundStyle(Goop.Color.text2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20)
        }.padding(.horizontal, 16).padding(.bottom, 30)
    }
    private func vital(_ key: String, _ metric: TrendMetricKey, _ title: String, day: Day) -> some View {
        GoopVitalTile(key: key, metric: metric, title: title, vital: metric.vital(in: day.vitals)!, attention: day.vitals.inAttention(key), constants: day.scoreConstants, dimmed: model.valuesOpacity < 1) {
            model.push(.trend(metric: metric, end: model.selectedDate))
        }
    }
    private func extra<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).goop(.labelCard)
            Spacer(minLength: 0)
            content().multilineTextAlignment(.trailing)
        }.padding(16).frame(minHeight: 62).background(Goop.Gradient.tile, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusTile))
    }
    private var rhythm: String {
        guard let profile = model.cached?.snapshot.status.userResources.irnProfile else { return "Not set up in Fitbit" }
        return profile.status == "permission_missing" ? "Needs permission" : profile.enrolled == true ? "Enrolled" : "Not set up in Fitbit"
    }
}
