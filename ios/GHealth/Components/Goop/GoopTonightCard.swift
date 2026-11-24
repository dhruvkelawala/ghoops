import SwiftUI
import GHealthCore

struct GoopTonightCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var pending = false
    var updating = false
    var plan: SleepPlan
    var dimmed = false
    var info: () -> Void

    var body: some View {
        GoopCard {
            HStack {
                Text("TONIGHT'S SLEEP").goop(.labelCard).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: info) {
                    GoopSymbol(name: "info.circle", size: 19, color: Goop.Color.iconMuted)
                        .frame(width: 24, height: 24).contentShape(Rectangle().inset(by: -10))
                }.accessibilityIdentifier("tonight-info").accessibilityLabel("How tonight's sleep is planned")
            }
            if pending {
                HStack { Text("—").goop(.valueSmall).foregroundStyle(Goop.Color.text2); Spacer(); GoopUpdatingValue(updating: updating) }.padding(.top, 16)
            } else if plan.status == .ok {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                layout {
                    key("NEED", value: GoopFormat.duration(plan.needMinutes), identifier: "tonight-need")
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    key("WAKE", value: GoopFormat.time(plan.wakeTarget), identifier: "tonight-wake")
                }.padding(.horizontal, 10).padding(.top, 16)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("GOAL").frame(maxWidth: .infinity, alignment: .leading)
                        Text("IN BED").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("BED BY").frame(maxWidth: .infinity, alignment: .trailing)
                    }.goop(.labelSmall).foregroundStyle(Goop.Color.textSoft).padding(.vertical, 5)
                    ForEach(plan.goals, id: \.pct) { goal in
                        HStack(spacing: 0) {
                            Text("\(goal.pct)%").foregroundStyle(Goop.Color.legendText).frame(maxWidth: .infinity, alignment: .leading)
                            Text(GoopFormat.duration(goal.inBedMinutes)).frame(maxWidth: .infinity, alignment: .trailing)
                            Text(GoopFormat.time(goal.bedtime)).frame(maxWidth: .infinity, alignment: .trailing)
                        }.goop(.valueSmall).foregroundStyle(Goop.Color.text1).padding(.vertical, 5)
                            .opacity(dimmed ? Goop.Opacity.stale : 1)
                            .accessibilityElement(children: .ignore).accessibilityLabel(SleepPlanText.goalAccessibility(goal))
                            .accessibilityIdentifier("tonight-goal-\(goal.pct)")
                    }
                }.padding(.vertical, 6).padding(.horizontal, 14)
                    .background(Goop.Color.legendFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusLegend)).padding(.top, 12)
            } else {
                GoopPlaceholder(text: SleepPlanText.placeholder(plan), alignment: .leading)
                    .padding(.top, 12).accessibilityIdentifier("tonight-placeholder")
            }
        }.buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityIdentifier("tonight-card")
    }

    private func key(_ title: String, value: String, identifier: String) -> some View {
        HStack(spacing: 4) {
            Text(title).goop(.labelSmall).foregroundStyle(Goop.Color.textSoft)
            Text(value).goop(.valueSmall).foregroundStyle(Goop.Color.text1)
                .opacity(dimmed ? Goop.Opacity.stale : 1).accessibilityIdentifier(identifier)
        }
    }
}
