import SwiftUI
import WidgetKit
import GHealthCore

struct LockScoresView: View {
    let data: WidgetData
    let family: WidgetFamily
    var metric: ScoreMetric = .recovery
    var line: LockExtraLine = .none
    var body: some View {
        Group {
            if let message = data.message {
                Text(message).goop(.bodyMid).multilineTextAlignment(.center).minimumScaleFactor(0.65)
            } else {
                switch family {
                case .accessoryCircular:
                    ZStack {
                        AccessoryWidgetBackground()
                        if metric.isHRV {
                            VStack(spacing: 0) {
                                Text(circularText).goop(.valueLock)
                                Text("HRV").goop(.labelLock).opacity(0.8)
                            }
                        } else if let score = metric.score {
                            ScoreRing(value: data.pastWake ? nil : data.value(score), maximum: score.maximum, color: .white, variant: .lock)
                            VStack(spacing: 0) {
                                Text(circularText).goop(.valueLock)
                                Text(score == .recovery ? "REC" : score.rawValue.uppercased()).goop(.labelLock).opacity(0.8)
                            }
                        }
                    }.opacity(data.stale ? Goop.Opacity.stale : 1)
                        .overlay(alignment: .bottomTrailing) { if data.stale { clock } }
                        .accessibilityElement(children: .ignore).accessibilityLabel((metric.isHRV ? "HRV, \(circularText) milliseconds" : "\(metric.score?.rawValue ?? "Recovery"), \(data.pastWake ? "—" : data.text(metric.score ?? .recovery))") + data.spoken)
                        .privacySensitive()
                case .accessoryRectangular:
                    VStack(spacing: line == .none ? 2 : 0) {
                        ForEach(GoopScore.allCases, id: \.self) { score in
                            scoreRow(score).frame(maxHeight: line == .none ? nil : .infinity)
                        }
                        if line != .none { extraRow.frame(maxHeight: .infinity) }
                    }
                default:
                    HStack(spacing: 4) {
                        if data.stale { clock }
                        if data.pastWake { Text("Scores from \(data.age)") }
                        else { Text("Sleep \(data.text(.sleep)) · Rec \(data.text(.recovery)) · Strain \(data.text(.strain))").monospacedDigit().opacity(data.stale ? Goop.Opacity.stale : 1) }
                    }.font(.caption).privacySensitive()
                }
            }
        }.foregroundStyle(.white).widgetAccentable().dynamicTypeSize(.large)
    }
    private func scoreRow(_ score: GoopScore) -> some View {
        HStack(spacing: 4) {
            Text(score.rawValue.uppercased()).goop(.labelLockRow)
            Spacer(minLength: 0)
            Text(data.text(score)).goop(.valueWidgetList).opacity(data.stale ? Goop.Opacity.stale : 1)
            if score == .sleep && data.stale {
                clock
                if data.pastWake { Text(data.age).goop(.captionWidget) }
            }
        }.privacySensitive()
    }
    /// The circular face has no room for a day, so scores from before a possible wake show a dash.
    private var circularText: String {
        if data.pastWake { return "—" }
        return metric.isHRV ? data.hrvText : data.text(metric.score ?? .recovery, percent: false)
    }
    private var extraRow: some View {
        HStack(spacing: 4) {
            Text(line == .hrv ? "HRV" : "BED BY").goop(.labelLockRow)
            Spacer(minLength: 0)
            Text(line == .hrv ? data.hrvText : data.bedtimeText).goop(.valueWidgetList).opacity(data.stale ? Goop.Opacity.stale : 1)
        }.accessibilityElement(children: .ignore).accessibilityLabel(line == .hrv ? "HRV, \(data.hrvText) milliseconds" : "Bed by \(data.bedtimeText)").privacySensitive()
    }
    private var clock: some View { Image(systemName: "clock").font(.system(size: 10)) }
}
