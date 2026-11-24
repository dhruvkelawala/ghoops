import WidgetKit
import SwiftUI

struct ScoresWidget: Widget {
    let kind = "ScoresWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ScoresIntent.self, provider: ScoresProvider<ScoresIntent>()) { entry in
            HomeWidgetEntry(entry: entry).containerBackground(Goop.Color.widgetFill, for: .widget).widgetURL(URL(string: "ghealth://today"))
        }.configurationDisplayName("ghoops scores").description("Recovery, strain and sleep from your Mac")
            .supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}
struct HomeWidgetEntry: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family
    var body: some View { HomeScoresView(data: entry.data, medium: family == .systemMedium, metric: entry.metric) }
}
struct LockScoresWidget: Widget {
    let kind = "LockScoresWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LockScoresIntent.self, provider: ScoresProvider<LockScoresIntent>()) { entry in
            LockWidgetEntry(entry: entry).containerBackground(.clear, for: .widget).widgetURL(URL(string: "ghealth://today"))
        }.configurationDisplayName("ghoops Lock Screen scores").description("Recovery, strain and sleep at a glance")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
struct LockWidgetEntry: View {
    let entry: ScoresEntry
    @Environment(\.widgetFamily) private var family
    var body: some View { LockScoresView(data: entry.data, family: family, metric: entry.metric, line: entry.line) }
}
@main
struct GHealthWidgets: WidgetBundle {
    var body: some Widget { ScoresWidget(); LockScoresWidget(); GoopActivityWidget() }
}
