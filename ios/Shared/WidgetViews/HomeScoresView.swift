import SwiftUI
import GHealthCore

struct HomeScoresView: View {
    let data: WidgetData
    var medium = false
    var metric: ScoreMetric = .recovery
    var body: some View {
        Group {
            if let message = data.message {
                VStack(spacing: 12) {
                    GoopMark().fill(.white.opacity(0.4)).frame(width: 28, height: 28)
                    Text(message).goop(.bodyMid).foregroundStyle(Goop.Color.text2).multilineTextAlignment(.center)
                }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if medium { mediumScores }
            else if metric.isHRV { HRVSmallView(data: data) }
            else if let score = metric.score {
                VStack(spacing: 9) {
                    ring(score, variant: .widgetSmall).privacySensitive()
                    Text(score.rawValue.uppercased()).goop(.labelWidget)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) { if data.stale { age.padding(10) } }
            } else { scoreList }
        }.foregroundStyle(Goop.Color.text1).dynamicTypeSize(.large)
    }
    private var scoreList: some View {
        VStack(spacing: 0) {
            ForEach(GoopScore.allCases, id: \.self) { score in
                HStack(spacing: 10) {
                    ring(score, variant: .widgetList)
                    Text(score.rawValue.uppercased()).goop(.labelWidgetSmall).frame(maxWidth: .infinity, alignment: .leading)
                    Text(data.text(score)).goop(.valueWidgetList).opacity(data.stale ? Goop.Opacity.stale : 1)
                }.frame(maxHeight: .infinity).privacySensitive()
            }
            if data.stale { age.frame(maxWidth: .infinity, alignment: .trailing) }
        }.padding(16)
    }
    private var mediumScores: some View {
        VStack(spacing: 10) {
            HStack {
                GoopWordmark(size: 14, color: Goop.Color.textSoft).frame(width: 40, height: 40 / 3.75)
                Spacer()
                HStack(spacing: 4) {
                    if data.stale { Image(systemName: "clock") }
                    Text(fetchLabel)
                }.goop(.tab).foregroundStyle(Goop.Color.iconMuted)
            }
            HStack(spacing: 0) {
                ForEach(GoopScore.allCases, id: \.self) { score in
                    VStack(spacing: 7) {
                        ring(score, variant: .widgetMedium).privacySensitive()
                        Text(score.rawValue.uppercased()).goop(.labelWidgetSmall)
                    }.frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }.padding(.top, 14).padding(.horizontal, 16).padding(.bottom, 12)
    }
    private var fetchLabel: String {
        guard let cached = data.cached else { return "" }
        return data.timeLabel + (cached.snapshot.status.device.batteryLevel.map { " · \($0)%" } ?? "")
    }
    private var age: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").foregroundStyle(Goop.Color.caution)
            Text(data.age).foregroundStyle(Goop.Color.text2)
        }.goop(.captionWidget)
    }
    private func ring(_ score: GoopScore, variant: ScoreRing.Variant) -> some View {
        ScoreRing(value: data.value(score), maximum: score.maximum, color: score.color(band: data.cached?.snapshot.day.recovery.band), variant: variant)
            .overlay {
                if variant != .widgetList {
                    VStack(spacing: 3) {
                        if variant == .widgetSmall { GoopWordmark(size: 14, color: Goop.Color.wordmarkDial).frame(width: 30, height: 30 / 3.75) }
                        ScoreText(value: data.value(score), percent: score != .strain, size: variant == .widgetSmall ? 30 : 24)
                    }
                }
            }.opacity(data.stale ? Goop.Opacity.stale : 1)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(score.rawValue), \(data.text(score))\(data.spoken)")
    }
}
