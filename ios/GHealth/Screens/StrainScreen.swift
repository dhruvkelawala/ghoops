import SwiftUI
import GHealthCore

struct StrainScreen: View {
    @Environment(AppModel.self) private var model
    @State private var info = false
    var body: some View {
        GoopDetailPage(identifier: "strain-screen", info: { info = true }) { bundle in
            let day = bundle?.day
            let strain = day?.strain
            GoopDetailDial(score: .strain, value: model.sleepScores(on: model.selectedDate).contains("strain") ? nil : strain?.value, strainBand: strain?.band, secondary: model.sleepScores(on: model.selectedDate, delayed: true).contains("strain") ? "UPDATING" : strain?.status == .inProgress ? "SO FAR" : nil, fixture: model.isFixture, dimmed: model.valuesOpacity < 1).padding(.top, 16)
            GoopNotchedCard {
                if bundle != nil {
                    contributor(.zones13, value: strain?.zonesMinutes.map { Double($0.z1 + $0.z2 + $0.z3) }, day: day)
                    GoopDivider()
                    contributor(.zones45, value: strain?.zonesMinutes.map { Double($0.z4 + $0.z5) }, day: day)
                    GoopDivider()
                    contributor(.strength, value: day?.strengthMinutes.map(Double.init), day: day)
                    GoopFootnote(text: "Workouts recorded or started as strength.").padding(.horizontal, 14).padding(.bottom, 12)
                    GoopDivider()
                    contributor(.steps, value: day.flatMap { $0.activity.steps.status == .available ? $0.activity.steps.value : nil }, day: day)
                    GoopLegend(windowDays: bundle?.day.comparison?.windowDays)
                } else { GoopDayPlaceholder().frame(minHeight: 279) }
            }.padding(.horizontal, 16).padding(.top, 26)
            if let day {
                GoopInsightCard(text: Insights.strain(day.strain, workouts: day.workouts, isToday: model.selectedDate == model.defaultDate, target: day.strainTarget, recoveryBand: day.recovery.band, constants: day.scoreConstants, pending: model.sleepScores(on: model.selectedDate).contains("strain")), actionTitle: "EXPLORE MY STRAIN") { info = true }.padding(.horizontal, 16).padding(.top, 12)
                GoopActivitiesCard(rows: model.activityRows(day, workoutsOnly: true), title: model.selectedDate == model.defaultDate ? "TODAY'S ACTIVITIES" : "ACTIVITIES", dimmed: model.valuesOpacity < 1, emptyText: "No workouts yet") { row in
                    if case .workout(let workout) = row.kind { model.push(.workout(id: workout.id, date: model.selectedDate)) }
                }.padding(.horizontal, 16).padding(.top, 30)
            } else {
                GoopCard { GoopDayPlaceholder() }.padding(.horizontal, 16).padding(.top, 12)
                GoopCard { GoopDayPlaceholder() }.padding(.horizontal, 16).padding(.top, 30)
            }
            GoopWeeklySection(metric: .strain)
        }.sheet(isPresented: $info) {
            if case .loaded(let bundle) = model.bundles[model.selectedDate] { StrainInfo(day: bundle.day, pending: model.sleepScores(on: model.selectedDate).contains("strain")) }
            else { GoopSheet(title: "DAY STRAIN") { GoopPlaceholder(text: "Needs a connection to your Mac") } }
        }
    }
    private func contributor(_ metric: TrendMetricKey, value: Double?, day: Day?) -> some View {
        GoopMetricRow(metric: metric, value: value, mean: day?.comparison?.metrics[metric.comparisonKey]?.mean, windowDays: day?.comparison?.windowDays, hint: metric == .steps ? day.map { ReasonText.metric($0.activity.steps.status) } ?? "" : "", status: metric == .strength && model.strengthUpdating(on: model.selectedDate) ? "UPDATING" : nil, dimmed: model.valuesOpacity < 1) { model.push(.trend(metric: metric, end: model.selectedDate)) }
    }
}

private struct StrainInfo: View {
    let day: Day
    var pending = false
    private var strain: Strain { day.strain }
    var body: some View {
        GoopSheet(title: "DAY STRAIN") {
            VStack(spacing: 0) {
                GoopSheetSection(title: "Coverage") {
                    VStack(alignment: .leading, spacing: 10) {
                        let end = day.isCurrentCycle ? strain.coverageUntil : day.cycle.end ?? strain.coverageUntil
                        let coverage = strain.hrCoverage.map { GoopFormat.percent($0 * 100) } ?? "—"
                        GoopWindowBar(start: day.cycle.start, startLabel: StrainExplain.startLabel(day.cycle), end: end, endLabel: day.isCurrentCycle ? "COUNTED UNTIL" : "DAY ENDED",
                                      value: coverage, unit: "HEART RATE RECORDED", fill: Goop.Color.strain, ink: Goop.Color.text1,
                                      accessibility: "From \(GoopFormat.time(day.cycle.start)) to \(GoopFormat.time(end)), heart rate recorded \(coverage)")
                            .accessibilityIdentifier("strain-window")
                        if strain.confidence == .low { GoopFootnote(text: "Low data: too little heart rate was recorded to trust this score.") }
                    }
                }
                GoopSheetSection(title: "Zones") {
                    VStack(spacing: 10) {
                        VStack(spacing: 0) { GoopZoneRows(zones: strain.zonesMinutes, resting: strain.restingHrBpm, maximum: strain.maxHrBpm, floors: day.scoreConstants?.strain.zonesHrr) }
                        GoopFootnote.wristHeartRate
                    }.foregroundStyle(Goop.Color.text1)
                }
                GoopSheetSection(title: "Heart rate") {
                    VStack(alignment: .leading, spacing: 10) {
                        GoopStatCells(cells: [
                            GoopStatCells.Cell(label: StrainExplain.maxSource(strain.maxHrSource), spoken: "Max heart rate", value: strain.maxHrBpm.map(String.init) ?? "—", unit: "bpm"),
                            GoopStatCells.Cell(label: StrainExplain.restingSource(strain.restingHrSource), spoken: "Resting heart rate", value: strain.restingHrBpm.map(String.init) ?? "—", unit: "bpm")
                        ])
                        if strain.maxHrSource == "age_predicted_profile" {
                            GoopFootnote(text: "Age-based maximums can be well off for one person. Set yours on the Mac.")
                        }
                    }
                }
                GoopSheetSection(title: "How this works") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Day Strain turns the time and intensity of your heart rate above rest into a log scale.")
                        GoopFootnote(text: "Strain uses Banister's published heart-rate formula, on a scale ghoops set from public examples. It isn't WHOOP's Strain.")
                        GoopLevelHeader(scale: .strain(day.scoreConstants))
                        GoopLevelScale(scale: .strain(day.scoreConstants), current: pending ? nil : LevelScale.index(strain.band), identifier: "scale-strain").padding(.top, -8)
                        GoopFootnote(text: EngineText.comparisonNote(day.comparison))
                        GoopFootnote.recalculation
                        GoopFinePrint(text: "Score version \(day.scoreVersion ?? "—")")
                    }
                }
            }
        }
    }
}
