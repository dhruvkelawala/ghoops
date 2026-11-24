import SwiftUI
import GHealthCore

extension LiveReadout {
    var heartColor: Color { heart == .none ? Goop.Color.text2 : Goop.Color.zone5 }
    var valueColor: Color { heart == .none ? Goop.Color.text2 : Goop.Color.text1 }
    var opacity: Double { dimmed ? Goop.Opacity.stale : 1 }
    var statusColor: Color {
        switch status {
        case .zone(let z): Goop.zones[z]
        case .reconnecting: Goop.Color.caution
        default: Goop.Color.text2
        }
    }
    var zoneColor: Color { zone.map { Goop.zones[$0] } ?? Goop.Color.text2 }
    var chipColor: Color {
        switch heart {
        case .live: Goop.Color.positive
        case .lost: Goop.Color.caution
        case .none: Goop.Color.text2
        }
    }
}

struct ActivityZoneMeter: View {
    var zone: Int?
    var marker = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { z in
                RoundedRectangle(cornerRadius: Goop.Metric.radiusMark)
                    .fill(z <= (zone ?? 0) ? Goop.zones[z] : Goop.Color.plotGrid)
                    .frame(height: 8)
                    .shadow(color: z == zone ? Goop.zones[z].opacity(0.5) : .clear, radius: 6)
                    .overlay {
                        if marker, z == zone {
                            Circle().fill(.white).frame(width: 16, height: 16)
                                .overlay { Circle().strokeBorder(Goop.Color.liveActivityFill, lineWidth: 3) }
                        }
                    }
            }
        }.accessibilityLabel(zone.map { "Zone \($0)" } ?? "Zone unknown")
    }
}

struct GoopActivityTimer: View {
    var attributes: GoopActivityAttributes
    var state: GoopActivityAttributes.ContentState
    var body: some View {
        Group {
            if let elapsed = state.elapsed {
                Text(Self.time(elapsed))
            } else {
                let start = attributes.start.addingTimeInterval(state.pausedTotal)
                Text(timerInterval: start...max(start, attributes.start.addingTimeInterval(ActivitySession.recordingSpan)), countsDown: false)
            }
        }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }
    private static func time(_ seconds: Double) -> String {
        let n = max(0, Int(seconds))
        return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%d:%02d", n / 60, n % 60)
    }
}

struct GoopLiveActivityView: View {
    var attributes: GoopActivityAttributes
    var state: GoopActivityAttributes.ContentState
    var showZone = true
    var isStale = false
    var identifier = "live-activity-view"
    var body: some View {
        let readout = state.readout(isStale: isStale)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 20)).foregroundStyle(readout.heartColor)
                    Text(readout.value).goop(.valueLiveActivityHR).foregroundStyle(readout.valueColor)
                    if readout.showsUnit { Text("bpm").goop(.legend).foregroundStyle(Goop.Color.iconMuted).padding(.top, 12) }
                }.opacity(readout.opacity)
                    .accessibilityElement(children: .ignore).accessibilityLabel(readout.spoken)
                    .accessibilityIdentifier("live-activity-bpm")
                Spacer(minLength: 8)
                VStack(spacing: 1) {
                    HStack(spacing: 7) {
                        Image(systemName: "stopwatch").font(.system(size: 16)).foregroundStyle(Goop.Color.strainLight)
                        GoopActivityTimer(attributes: attributes, state: state).goop(.valueLiveStat).frame(width: 62)
                    }
                    if state.isPaused { Text("PAUSED").goop(.labelTimerPill) }
                }.padding(.vertical, 7).padding(.horizontal, 13).background(Goop.Color.strain.opacity(0.165), in: Capsule())
            }.frame(height: 48)
            if showZone {
                ActivityZoneMeter(zone: readout.zone, marker: true).opacity(readout.opacity).padding(.top, 14)
                    .accessibilityIdentifier("live-activity-zone-meter")
            }
            if showZone || readout.status == .reconnecting || readout.status == .noHeartRate {
                Text(readout.statusText).goop(.labelTiny).foregroundStyle(readout.statusColor).padding(.top, 7)
                    .accessibilityLabel(readout.statusSpoken).accessibilityIdentifier("live-activity-status")
            }
            Group {
                if let low = state.targetLow, let high = state.targetHigh {
                    HStack(spacing: 0) {
                        targetStat("STRAIN", value: GoopFormat.number(state.strainEstimate, decimals: 1), color: Goop.Color.strainLight)
                        Rectangle().fill(Goop.Color.plotGrid).frame(width: 1, height: 23)
                        targetStat("EST. DAY STRAIN", value: GoopFormat.number(state.dayStrain, decimals: 1))
                        Rectangle().fill(Goop.Color.plotGrid).frame(width: 1, height: 23)
                        targetStat("TARGET", value: "\(GoopFormat.number(low, decimals: 1))–\(GoopFormat.number(high, decimals: 1))", reached: state.targetWithin == true)
                    }
                } else {
                    HStack(spacing: 0) {
                        stat("STRAIN", value: GoopFormat.number(state.strainEstimate, decimals: 1), color: Goop.Color.strainLight)
                        HStack(spacing: 16) {
                            Rectangle().fill(Goop.Color.plotGrid).frame(width: 1, height: 23)
                            GoopWordmark(size: 14, color: Goop.Color.textSoft).frame(width: 54, height: 54 / 3.75)
                            Rectangle().fill(Goop.Color.plotGrid).frame(width: 1, height: 23)
                        }
                        stat("AVG HR", value: state.avgHR.map(String.init) ?? "—", color: .white)
                    }
                }
            }.padding(.top, 10)
        }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14).foregroundStyle(.white)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
    private func targetStat(_ label: String, value: String, color: Color = Goop.Color.text1, reached: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text(value).goop(.valueLiveStat).foregroundStyle(value == "—" ? Goop.Color.text2 : color).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                if reached { Image(systemName: "checkmark").font(.system(size: 8, weight: .semibold)).foregroundStyle(Goop.Color.positive) }
                Text(label).goop(.labelMicro).foregroundStyle(Goop.Color.iconMuted)
            }
        }.frame(maxWidth: .infinity)
    }
    private func stat(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value).goop(.scoreWidgetMedium).foregroundStyle(value == "—" ? Goop.Color.text2 : color)
            Text(label).goop(.labelMicro).foregroundStyle(Goop.Color.iconMuted)
        }.frame(maxWidth: .infinity)
    }
}

struct GoopIslandLeading: View {
    var readout: LiveReadout
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").foregroundStyle(readout.heartColor)
            Text(readout.value).goop(.valueIsland).foregroundStyle(readout.valueColor)
        }.opacity(readout.opacity)
            .accessibilityElement(children: .ignore).accessibilityLabel(readout.spoken)
            .accessibilityIdentifier("live-island-bpm")
    }
}

struct GoopIslandMinimal: View {
    var readout: LiveReadout
    var body: some View {
        Image(systemName: "heart.fill").foregroundStyle(readout.heartColor).opacity(readout.opacity)
            .accessibilityLabel(readout.chipSpoken).accessibilityIdentifier("live-island-minimal")
    }
}
