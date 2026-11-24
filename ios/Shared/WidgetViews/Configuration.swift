import AppIntents
import WidgetKit

protocol ScoresConfiguration: WidgetConfigurationIntent {
    var selectedMetric: ScoreMetric { get }
    var extraLine: LockExtraLine { get }
}

extension ScoresConfiguration {
    var extraLine: LockExtraLine { .none }
}

enum ScoreMetric: String, AppEnum {
    case recovery, strain, sleep, all
    case hrv
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Score"
    static let caseDisplayRepresentations: [ScoreMetric: DisplayRepresentation] = [.recovery: "Recovery", .strain: "Strain", .sleep: "Sleep", .all: "Sleep, Recovery, Strain", .hrv: "HRV"]
    var score: GoopScore? {
        switch self { case .recovery: .recovery; case .strain: .strain; case .sleep: .sleep; default: nil }
    }
    var isHRV: Bool { rawValue == "hrv" }
}

enum LockScoreMetric: String, AppEnum {
    case recovery, strain, sleep
    case hrv
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Score"
    static let caseDisplayRepresentations: [LockScoreMetric: DisplayRepresentation] = [.recovery: "Recovery", .strain: "Strain", .sleep: "Sleep", .hrv: "HRV"]
    var selectedMetric: ScoreMetric {
        switch self {
        case .recovery: .recovery
        case .strain: .strain
        case .sleep: .sleep
        case .hrv: .hrv
        }
    }
}

enum LockExtraLine: String, AppEnum {
    case none, hrv, bedtime
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Extra line"
    static let caseDisplayRepresentations: [LockExtraLine: DisplayRepresentation] = [.none: "None", .hrv: "HRV", .bedtime: "Bed by"]
}

struct ScoresIntent: ScoresConfiguration {
    static let title: LocalizedStringResource = "Scores"
    static let description = IntentDescription("Choose the score for your small widget")
    @Parameter(title: "Metric", default: .recovery) var metric: ScoreMetric
    var selectedMetric: ScoreMetric { metric }
}

struct LockScoresIntent: ScoresConfiguration {
    static let title: LocalizedStringResource = "Lock Screen scores"
    @Parameter(title: "Score", default: .recovery) var metric: LockScoreMetric
    var selectedMetric: ScoreMetric { metric.selectedMetric }
    @Parameter(title: "Extra line", default: .none) var line: LockExtraLine
    var extraLine: LockExtraLine { line }
    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .accessoryRectangular) {
            Summary("Lock Screen scores") { \.$line }
        } otherwise: {
            Summary("Lock Screen scores") { \.$metric }
        }
    }
}
