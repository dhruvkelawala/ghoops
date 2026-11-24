import SwiftUI
import GHealthCore

struct GoopEditValues: View {
    var value: WindowEstimate? = nil
    var prior: WindowEstimate? = nil
    var sleepValue: SleepWindowValues? = nil
    var sleepPrior: SleepWindowValues? = nil
    var showPrior = true
    var prefix = "edit"
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let sleepValue {
                column("ASLEEP", value: sleepValue.asleepMinutes.map(Double.init), prior: sleepPrior?.asleepMinutes.map(Double.init), color: Goop.Color.sleep, key: "asleep")
                column("IN BED", value: Double(sleepValue.timeInBedMinutes), prior: sleepPrior.map { Double($0.timeInBedMinutes) }, color: .white, key: "in-bed")
                column("EFFICIENCY", value: sleepValue.efficiencyPct.map(Double.init), prior: sleepPrior?.efficiencyPct.map(Double.init), color: .white, key: "efficiency")
            } else {
                column("STRAIN", value: value?.strain, prior: prior?.strain, color: Goop.Color.strain, key: "strain")
                column("DURATION", value: value?.elapsedMinutes, prior: prior?.elapsedMinutes, color: .white, key: "duration")
                column("AVERAGE HR", value: value?.avgHrBpm.map(Double.init), prior: prior?.avgHrBpm.map(Double.init), color: .white, key: "avg-hr")
            }
        }
    }
    private func column(_ title: String, value: Double?, prior: Double?, color: Color, key: String) -> some View {
        let decimals = key == "strain" ? 1 : 0
        let changed = value != nil && prior != nil && GoopFormat.rounded(value!, decimals: decimals) != GoopFormat.rounded(prior!, decimals: decimals)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).goop(.labelSmall).foregroundStyle(color)
            HStack(spacing: 6) {
                Text(text(value, key: key)).goop(.valueStat).foregroundStyle(value == nil ? Goop.Color.text2 : color).accessibilityIdentifier("\(prefix)-value-\(key)")
                if showPrior && changed { GoopSymbol(name: value! > prior! ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill", size: 8, color: Goop.Color.neutral, weight: .regular) }
            }
            if showPrior {
                Text(changed ? text(prior, key: key) : " ").goop(.compareRow).foregroundStyle(Goop.Color.text2)
                    .accessibilityIdentifier("\(prefix)-prior-\(key)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func text(_ value: Double?, key: String) -> String {
        if ["duration", "asleep", "in-bed"].contains(key) { return GoopFormat.duration(value.map { Int($0.rounded()) }) }
        if key == "efficiency" { return GoopFormat.percent(value) }
        return GoopFormat.number(value, decimals: key == "strain" ? 1 : 0)
    }
}
