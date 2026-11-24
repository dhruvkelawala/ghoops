import SwiftUI
import GHealthCore

struct RecoveryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var info = false
    private var pending: Set<String> { model.sleepScores(on: model.selectedDate) }
    private var updating: Set<String> { model.sleepScores(on: model.selectedDate, delayed: true) }
    var body: some View {
        GoopDetailPage(identifier: "recovery-screen", info: { info = true }) { bundle in
            let recovery = bundle?.day.recovery
            GoopDetailDial(score: .recovery, value: pending.contains("recovery") ? nil : recovery?.value.map(Double.init), band: recovery?.band, secondary: updating.contains("recovery") ? "UPDATING" : recovery?.calibrating == true ? "CALIBRATING" : nil, fixture: model.isFixture, dimmed: model.valuesOpacity < 1).padding(.top, 16)
            GoopNotchedCard {
                if bundle != nil {
                    contributor(.hrv, value: recovery?.inputs.hrvRmssdMs, day: bundle?.day)
                    GoopDivider()
                    contributor(.restingHR, value: recovery?.inputs.restingHrBpm.map(Double.init), day: bundle?.day)
                    GoopDivider()
                    contributor(.respiratoryRate, value: recovery?.inputs.respiratoryRateBpm, day: bundle?.day)
                    GoopDivider()
                    contributor(.sleepPerformance, value: recovery?.inputs.sleepPerformance.map(Double.init), day: bundle?.day)
                    GoopLegend(windowDays: bundle?.day.comparison?.windowDays)
                } else { GoopDayPlaceholder().frame(minHeight: 279) }
            }.padding(.horizontal, 16).padding(.top, 26)
            if let recovery {
                GoopInsightCard(text: Insights.recovery(recovery, pending: pending.contains("recovery")), actionTitle: "BREAK DOWN MY RECOVERY") { info = true }.padding(.horizontal, 16).padding(.top, 12)
                if recovery.calibrating || recovery.reason == .insufficientBaseline {
                    GoopCard {
                        Text("CALIBRATING").goop(.labelCard)
                        RecoveryCalibration(recovery: recovery).padding(.top, 10)
                    }.padding(.horizontal, 16).padding(.top, 12)
                }
            } else {
                GoopCard { GoopDayPlaceholder() }.padding(.horizontal, 16).padding(.top, 12)
            }
            if GoopFeature.journal, let journal = model.cached?.snapshot.journal, journal.covers(JournalText.journalDate(forRecovery: model.selectedDate)) {
                JournalSection(journal: journal, recoveryDate: model.selectedDate).padding(.horizontal, 16).padding(.top, 30)
            }
            GoopWeeklySection(metric: .recovery)
        }.sheet(isPresented: $info) {
            if case .loaded(let bundle) = model.bundles[model.selectedDate] { RecoveryInfo(day: bundle.day, pending: pending.contains("recovery")) }
            else { GoopSheet(title: "RECOVERY") { GoopPlaceholder(text: "Needs a connection to your Mac") } }
        }
    }
    private func contributor(_ metric: TrendMetricKey, value: Double?, day: Day?) -> some View {
        let waiting = metric == .sleepPerformance && pending.contains("sleep")
        return GoopMetricRow(metric: metric, value: waiting ? nil : value, mean: day?.comparison?.metrics[metric.comparisonKey]?.mean, windowDays: day?.comparison?.windowDays, status: waiting && updating.contains("sleep") ? "UPDATING" : nil, dimmed: model.valuesOpacity < 1) { model.push(.trend(metric: metric, end: model.selectedDate)) }
    }
}

private struct RecoveryCalibration: View {
    var recovery: Recovery
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GoopSheetRow(label: "Nights in your \(recovery.baseline.windowDays)-day baseline", value: String(recovery.calibration.nightsUsed))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Goop.Metric.radiusSegment).fill(Goop.Color.ringTrack)
                    RoundedRectangle(cornerRadius: Goop.Metric.radiusSegment).fill(Goop.Color.positive).frame(width: geometry.size.width * EngineText.calibrationFill(recovery.calibration))
                    if let tick = EngineText.calibrationTick(recovery.calibration) {
                        Rectangle().fill(.white).frame(width: 2).offset(x: geometry.size.width * tick - 1)
                    }
                }
            }.frame(height: 8).padding(.top, 2).accessibilityHidden(true)
            GoopFootnote(text: EngineText.calibrationNote(recovery.calibration)).padding(.top, 8)
        }
    }
}

private struct RecoveryInfo: View {
    let day: Day
    var pending = false
    private var recovery: Recovery { day.recovery }
    var body: some View {
        GoopSheet(title: "RECOVERY") {
            VStack(spacing: 0) {
                GoopSheetSection(title: "Breakdown") {
                    VStack(alignment: .leading, spacing: 10) {
                        GoopBreakdown {
                            ForEach(RecoveryExplain.base(recovery), id: \.id) { line in
                                let waiting = pending && ["recovery-sleep", "recovery-inputs"].contains(line.id)
                                GoopBreakdownRow(label: line.label, note: waiting ? nil : line.note, value: waiting ? "—" : line.value, identifier: line.id)
                            }
                            GoopBreakdownRule()
                            ForEach(RecoveryExplain.penalties(recovery), id: \.id) { line in GoopBreakdownRow(label: line.label, note: line.note, value: line.value, identifier: line.id) }
                            GoopBreakdownRule(strong: true)
                            GoopBreakdownTotal(label: "RECOVERY", spoken: "Recovery", value: pending ? "—" : recovery.value.map(String.init) ?? "—", result: true, identifier: "recovery-total")
                        }
                        GoopFootnote(text: EngineText.penaltyNote(day.scoreConstants))
                    }
                }
                GoopSheetSection(title: "Calibration") { RecoveryCalibration(recovery: recovery) }
                GoopSheetSection(title: "How this works") {
                    VStack(alignment: .leading, spacing: 12) {
                        GoopLevelHeader(scale: .recovery(day.scoreConstants))
                        GoopLevelScale(scale: .recovery(day.scoreConstants), current: pending ? nil : LevelScale.index(recovery.band), identifier: "scale-recovery").padding(.top, -8)
                        GoopFootnote(text: EngineText.comparisonNote(day.comparison))
                        GoopFootnote.recalculation
                        GoopFinePrint(text: "Score version \(day.scoreVersion ?? "—")")
                    }
                }
            }
        }
    }
}
