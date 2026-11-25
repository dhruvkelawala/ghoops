import SwiftUI
import GHealthCore

struct SleepScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var info = false
    @State private var selected: GoopStage?
    @State private var editing = false
    private var pending: Bool { model.sleepScores(on: model.selectedDate).contains("sleep") }
    private var updating: Bool { model.sleepScores(on: model.selectedDate, delayed: true).contains("sleep") }
    var body: some View {
        let plan: SleepPlan? = if case .loaded(let bundle) = model.bundles[model.selectedDate] { bundle.day.sleepPlan } else { nil }
        GoopDetailPage(identifier: "sleep-screen", info: { info = true }) { bundle in
            let sleep = bundle?.sleep
            let hasSleep = sleep?.asleepMinutes != nil
            let score = bundle.map { SleepScore($0.day).performance }
            if let notice = model.rollbacks.first(where: { model.rollbackTargets[$0.id]?.contains("sleep-\(model.selectedDate)") == true }) {
                GoopRollbackBanner(notice: notice).padding(.horizontal, 16).padding(.top, 12).accessibilityIdentifier("change-rollback-banner")
            }
            if model.pending.contains(where: { $0.state == .waiting && $0.targets.contains("sleep-\(model.selectedDate)") }) {
                GoopBanner(text: "Saved on your phone. It will be sent to your Mac when it can be reached.", symbol: "arrow.triangle.2.circlepath", tone: .strain).padding(.horizontal, 16).padding(.top, 12).accessibilityIdentifier("change-waiting-banner")
            }
            GoopDetailDial(score: .sleep, value: pending ? nil : score?.value.map(Double.init), secondary: updating ? "UPDATING" : nil, level: pending ? nil : SleepLevel(score?.band), fixture: model.isFixture, dimmed: model.valuesOpacity < 1).padding(.top, 16)
            GoopNotchedCard {
                if bundle != nil {
                    contributor(.sleepPerformance, title: "HOURS VS. NEEDED", value: hasSleep ? sleep?.performance.value : nil, level: hasSleep ? SleepLevel(bundle?.day.sleep.performance.band) : nil, day: bundle?.day)
                    GoopDivider()
                    contributor(.consistency, value: hasSleep ? sleep?.consistency.value : nil, level: hasSleep ? SleepLevel(bundle?.day.sleep.consistency.band) : nil, day: bundle?.day)
                    GoopDivider()
                    contributor(.efficiency, value: hasSleep ? sleep?.efficiencyPct : nil, level: hasSleep ? SleepLevel(bundle?.day.sleep.efficiencyBand) : nil, day: bundle?.day)
                    GoopLegend(sleep: true, windowDays: nil)
                } else { GoopDayPlaceholder().frame(minHeight: 221) }
            }.padding(.horizontal, 16).padding(.top, 26)
            if let sleep {
                GoopInsightCard(text: Insights.sleep(sleep, pending: pending), actionTitle: "DIVE INTO MY SLEEP") { info = true }.padding(.horizontal, 16).padding(.top, 12)
                Text(model.selectedDate == model.defaultDate ? "Last Night's Sleep" : "Sleep").goop(.heading).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 30).padding(.bottom, 14).accessibilityAddTraits(.isHeader)
                sleepCard(sleep, day: bundle?.day).padding(.horizontal, 16)
                editEntry(sleep).padding(.horizontal, 16).padding(.top, 12)
                GoopNeedCard(pending: pending, updating: updating, sleep: sleep, comparison: bundle?.day.comparison, dimmed: model.valuesOpacity < 1) { info = true }.padding(.horizontal, 16).padding(.top, 12)
            } else {
                GoopCard { GoopDayPlaceholder() }.padding(.horizontal, 16).padding(.top, 12)
                Text("Sleep").goop(.heading).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 30).padding(.bottom, 14).accessibilityAddTraits(.isHeader)
                GoopCard(padding: 14, bottomPadding: 6) { GoopDayPlaceholder().frame(minHeight: 246) }.padding(.horizontal, 16)
                GoopCard { GoopDayPlaceholder() }.padding(.horizontal, 16).padding(.top, 12)
            }
            if let plan { GoopTonightCard(pending: pending, updating: updating, plan: plan, dimmed: model.valuesOpacity < 1) { info = true }.padding(.horizontal, 16).padding(.top, 12) }
        }.task {
            #if DEBUG
            if model.sleepEditFixture == "open" { editing = true }
            #endif
        }.sheet(isPresented: $editing) {
            if case .loaded(let bundle) = model.bundles[model.selectedDate], let draft = SleepEditDraft(sleep: bundle.sleep, limits: model.editLimits, now: model.now) { SleepEditSheet(draft: draft) }
        }.onChange(of: model.selectedDate) { selected = nil }
            .sheet(isPresented: $info) {
                if case .loaded(let bundle) = model.bundles[model.selectedDate] { SleepInfo(sleep: bundle.sleep, plan: plan, latest: model.selectedDate == model.defaultDate, pending: pending) }
                else { GoopSheet(title: "SLEEP") { GoopPlaceholder(text: "Needs a connection to your Mac") } }
            }
    }
    private func contributor(_ metric: TrendMetricKey, title: String? = nil, value: Int?, level: SleepLevel?, day: Day?) -> some View {
        let waiting = pending && metric != .efficiency
        return GoopMetricRow(metric: metric, title: title, value: waiting ? nil : value.map(Double.init), windowDays: day?.comparison?.windowDays, level: waiting ? nil : level, sleep: true, status: waiting && updating ? "UPDATING" : nil, dimmed: model.valuesOpacity < 1) { model.push(.trend(metric: metric, end: model.selectedDate)) }
    }
    private func editEntry(_ sleep: Sleep) -> some View {
        VStack(spacing: 0) {
            if !model.lockedWorkouts.contains("sleep-\(sleep.date)") {
                if sleep.session?.editRange != nil {
                    GoopButton(title: "EDIT SLEEP", identifier: "sleep-edit-open") { editing = true }
                } else if model.editLimits?.sleepMinMinutes != nil, sleep.session != nil {
                    if let days = model.editLimits?.horizonDays, sleep.date < GoopFormat.addingDays(-(days - 1), to: model.defaultDate) {
                        GoopFootnote(text: days == 1 ? "Only last night's sleep can be edited." : "Only nights from the last \(days) days can be edited.").accessibilityIdentifier("sleep-edit-horizon")
                    } else if sleep.hypnogram?.segments.isEmpty != false {
                        GoopFootnote(text: "This night has no sleep stages from your band, so ghoops can't edit it.").accessibilityIdentifier("sleep-edit-no-stages")
                    }
                }
                if sleep.session?.edit != nil, let google = sleep.session?.google {
                    GoopFootnote(text: "Edited in ghoops. Google Health has \(GoopFormat.time(google.start)) to \(GoopFormat.time(google.end)).").padding(.top, 12).accessibilityIdentifier("sleep-edited-footnote")
                }
            }
        }
    }
    private func sleepCard(_ sleep: Sleep, day: Day?) -> some View {
        GoopCard(padding: 14, bottomPadding: 6) {
            if sleep.asleepMinutes == nil {
                GoopPlaceholder(text: sleep.performance.status == .pending ? "Waiting for last night's sleep" : "No sleep recorded for this night")
            } else {
                GoopSleepChart(sleep: sleep, selected: selected, dimmed: model.valuesOpacity < 1)
                GoopDivider(card: true).padding(.top, 12).padding(.bottom, 4)
                let footer = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                footer {
                    GoopTypicalKey()
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    HStack {
                        Text("DURATION").goop(.labelSmall).foregroundStyle(Goop.Color.textSoft)
                        Text(GoopFormat.duration(sleep.timeInBedMinutes)).goop(.valueSmall).opacity(model.valuesOpacity)
                    }
                }.padding(.vertical, 8)
                ForEach(GoopStage.allCases.filter { $0 != .unstaged || (sleep.stages?.unstaged?.minutes ?? 0) > 0 }) { stage in
                    GoopStageRow(stage: stage, minutes: stage.data(sleep.stages)?.minutes, percent: stage.percent(sleep), typical: stage.typical(sleep.stageTypical), scale: scale(sleep), selected: selected == stage, dimmed: model.valuesOpacity < 1) { selected = selected == stage ? nil : stage }
                }
                GoopRestorativeRow(minutes: restorative(sleep), mean: day?.comparison?.metrics["restorative_minutes"]?.mean, dimmed: model.valuesOpacity < 1)
            }
        }
    }
    private func scale(_ sleep: Sleep) -> Double {
        let values = GoopStage.allCases.flatMap { stage in [stage.data(sleep.stages)?.minutes, stage.typical(sleep.stageTypical)?.highMinutes].compactMap { $0 } }
        return Double(max(1, values.max() ?? 1)) / 0.87
    }
    private func restorative(_ sleep: Sleep) -> Int? {
        guard let deep = sleep.stages?.deep.minutes, let rem = sleep.stages?.rem.minutes else { return nil }
        return deep + rem
    }
}

private struct SleepInfo: View {
    let sleep: Sleep
    let plan: SleepPlan?
    let latest: Bool
    var pending = false
    @State private var goalPct = 100
    private var hasSleep: Bool { sleep.asleepMinutes != nil }
    var body: some View {
        GoopSheet(title: "SLEEP") {
            VStack(spacing: 0) {
                if pending {
                    GoopSheetSection(title: plan == nil ? "Need" : "Tonight") {
                        GoopFootnote(text: Insights.updating(plan == nil ? "Your sleep need" : "Tonight's plan")).accessibilityIdentifier("sleep-info-updating")
                    }
                } else if let plan { tonight(plan) } else {
                    GoopSheetSection(title: "Need") {
                        GoopBreakdown { need(total: sleep.need.totalMinutes, baseline: sleep.need.baselineMinutes, strain: sleep.need.previousCycleStrain == nil ? nil : sleep.need.strainExtraMinutes, debt: sleep.need.debtExtraMinutes, naps: sleep.need.napCreditMinutes, debtNightsUsed: sleep.need.debtNightsUsed) }
                    }
                }
                GoopSheetSection(title: latest ? "Last night" : "Night") { night }
                if let breathing = sleep.respiratoryRate {
                    GoopSheetSection(title: "Breathing rate") {
                        GoopStatCells(cells: [cell("FULL", "Full", breathing.fullBpm), cell("DEEP", "Deep", breathing.deepBpm), cell("LIGHT", "Light", breathing.lightBpm), cell("REM", "REM", breathing.remBpm)])
                    }
                }
                GoopSheetSection(title: "Overnight HRV") { GoopOvernightHRV(points: sleep.overnightHrv) }
                GoopSheetSection(title: "Naps") {
                    if sleep.naps.isEmpty { Text("No naps") }
                    VStack(spacing: 0) {
                        ForEach(Array(sleep.naps.enumerated()), id: \.offset) { _, nap in
                            GoopSheetRow(label: "\(GoopFormat.time(nap.start))–\(GoopFormat.time(nap.end))", note: "Asleep", value: GoopFormat.duration(nap.asleepMinutes))
                        }
                    }
                }
                GoopSheetSection(title: "How this works") { howItWorks }
            }
        }
    }

    @ViewBuilder private func tonight(_ plan: SleepPlan) -> some View {
        if plan.status == .ok, let goal = plan.goals.first(where: { $0.pct == goalPct }) ?? plan.goals.first {
            GoopSheetSection(title: "Tonight", trailing: {
                GoopRangeSelector(options: plan.goals.map { "\($0.pct)%" }, selection: Binding(get: { "\(goalPct)%" }, set: { goalPct = Int($0.dropLast()) ?? 100 }), identifier: { "plan-goal-\($0.dropLast())" }, numeric: true)
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    GoopWindowBar(start: goal.bedtime, startLabel: "BED BY", end: plan.wakeTarget, endLabel: SleepPlanText.wakeLabel(plan),
                                  value: GoopFormat.duration(goal.inBedMinutes), unit: "IN BED", fill: Goop.Color.sleep, ink: Goop.Color.backgroundHomeBase,
                                  accessibility: "Bed by \(GoopFormat.time(goal.bedtime)), wake at \(GoopFormat.time(plan.wakeTarget)), \(GoopSpeech.duration(goal.inBedMinutes)) in bed")
                        .accessibilityIdentifier("plan-window")
                    GoopBreakdown {
                        need(total: plan.needMinutes, baseline: plan.needParts.baselineMinutes, strain: plan.needParts.cycleStrain == nil ? nil : plan.needParts.strainExtraMinutes, debt: plan.needParts.debtExtraMinutes, naps: plan.needParts.napCreditMinutes, debtNightsUsed: plan.needParts.debtNightsUsed)
                        GoopBreakdownRule()
                        GoopBreakdownRow(label: "\(goal.pct)% of need", value: GoopFormat.duration(SleepPlanText.asleepMinutes(plan, goal: goal)), identifier: "plan-asleep")
                        GoopBreakdownRow(label: "Usual time awake in bed", note: SleepPlanText.awakeNote(plan), value: "+" + GoopFormat.duration(SleepPlanText.awakeMinutes(plan, goal: goal)), identifier: "plan-awake")
                        GoopBreakdownRule(strong: true)
                        GoopBreakdownTotal(label: "TIME IN BED", spoken: "Time in bed", value: GoopFormat.duration(goal.inBedMinutes), result: true, identifier: "plan-in-bed")
                    }.padding(.top, 16)
                    GoopFootnote(text: SleepPlanText.footnote(plan)).padding(.top, 10)
                }
            }
        } else {
            GoopSheetSection(title: "Tonight") {
                VStack(alignment: .leading, spacing: 10) {
                    GoopBreakdown { need(total: plan.needMinutes, baseline: plan.needParts.baselineMinutes, strain: plan.needParts.cycleStrain == nil ? nil : plan.needParts.strainExtraMinutes, debt: plan.needParts.debtExtraMinutes, naps: plan.needParts.napCreditMinutes, debtNightsUsed: plan.needParts.debtNightsUsed) }
                    GoopFootnote(text: SleepPlanText.unavailable(plan))
                }
            }
        }
    }

    @ViewBuilder private func need(total: Int, baseline: Int, strain: Int?, debt: Int, naps: Int, debtNightsUsed: Int) -> some View {
        GoopBreakdownTotal(label: "SLEEP NEEDED", spoken: "Sleep needed", value: GoopFormat.duration(total), identifier: "need-total")
        GoopNeedBar(baseline: baseline, strain: strain ?? 0, debt: debt, naps: naps, scale: Double(max(1, baseline + (strain ?? 0) + debt))).padding(.top, 10).padding(.bottom, 6)
        GoopNeedParts(baseline: baseline, strain: strain, debt: debt, naps: naps, debtNightsUsed: debtNightsUsed)
    }

    private var night: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sleep.bedtime != nil || sleep.wakeTime != nil {
                GoopWindowBar(start: sleep.bedtime, startLabel: "BEDTIME", end: sleep.wakeTime, endLabel: "WAKE",
                              value: GoopFormat.duration(sleep.timeInBedMinutes), unit: "IN BED", fill: Goop.Color.sleep, ink: Goop.Color.backgroundHomeBase,
                              accessibility: "Bedtime \(GoopFormat.time(sleep.bedtime)), wake \(GoopFormat.time(sleep.wakeTime)), \(GoopSpeech.duration(sleep.timeInBedMinutes)) in bed")
                    .accessibilityIdentifier("night-window").padding(.bottom, 8)
            }
            GoopSheetRow(label: "Hours of sleep", note: unstagedNote, value: GoopFormat.duration(sleep.asleepMinutes))
            GoopSheetRow(label: "Sleep needed", value: pending ? "—" : GoopFormat.duration(sleep.need.totalMinutes))
            GoopSheetRow(label: "Efficiency", value: GoopFormat.percent(sleep.efficiencyPct.map(Double.init)))
            GoopSheetRow(label: "Fell asleep in", value: sleep.minutesToFallAsleep.map(String.init) ?? "—", unit: "min")
            GoopSheetRow(label: "Disturbances", note: sleep.disturbances.map { "\($0.awakeSegments) awake · \($0.shortAwakenings) short" }, value: sleep.disturbances.map { String($0.total) } ?? "—")
        }
    }

    private var unstagedNote: String? {
        guard let minutes = sleep.stages?.unstaged?.minutes, minutes > 0 else { return nil }
        return "Includes \(GoopFormat.duration(minutes)) without stages"
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            let breakdown = SleepScore.breakdown(sleep, pending: pending)
            if let breakdown {
                compositeBreakdown(breakdown)
            } else {
                Text("Sleep Performance = time asleep ÷ sleep need, capped at 100%.") // goop-lint: allow enginenumber: schema: performance is 0 to 100, contract §5.5
            }
            GoopLevelHeader(scale: .hours(sleep.scoreConstants))
            let scored = hasSleep && !pending
            if breakdown != nil {
                let performance = SleepScore(sleep).performance
                scale("Sleep performance", scored ? performance.value : nil, .hours(sleep.scoreConstants), band: scored ? performance.band : nil, identifier: "scale-sleep-performance")
            }
            scale("Hours vs. needed", scored ? sleep.performance.value : nil, .hours(sleep.scoreConstants), band: scored ? sleep.performance.band : nil, identifier: "scale-hours")
            scale("Consistency", scored ? sleep.consistency.value : nil, .consistency(sleep.scoreConstants), band: scored ? sleep.consistency.band : nil, identifier: "scale-consistency")
            scale("Efficiency", hasSleep ? sleep.efficiencyPct : nil, .efficiency(sleep.scoreConstants), band: hasSleep ? sleep.efficiencyBand : nil, identifier: "scale-efficiency")
            GoopFootnote(text: "Awake % is a share of time in bed; the other stages are shares of time asleep. " + EngineText.typicalNote(sleep.stageTypical))
            GoopFootnote(text: "Sleep stages come from your band and are estimates.")
            switch sleep.scoreConstants?.sleep.unstagedCountsAs {
            case "asleep": GoopFootnote(text: "Time in a night with no sleep stages counts as sleep. It shows as unstaged.")
            case "awake": GoopFootnote(text: "Time in a night with no sleep stages counts as awake.")
            default: EmptyView()
            }
            GoopFootnote.recalculation
            GoopFinePrint(text: "Score version \(sleep.scoreVersion ?? "—")")
        }
    }

    @ViewBuilder private func compositeBreakdown(_ breakdown: SleepScore.Breakdown) -> some View {
        Text("Sleep Performance blends hours vs. needed, consistency and efficiency.")
        GoopBreakdown {
            ForEach(breakdown.lines, id: \.label) { line in
                GoopBreakdownRow(label: line.label, note: line.note, value: line.value)
            }
            GoopBreakdownRule(strong: true)
            GoopBreakdownTotal(label: "SLEEP PERFORMANCE", spoken: "Sleep performance", value: breakdown.total, result: true, identifier: "sleep-performance-total")
        }
        if let rule = breakdown.rule { GoopFootnote(text: rule) }
        GoopFootnote(text: "Set on your Mac with ghoops config. Without it, Sleep Performance is hours vs. needed.")
    }

    private func scale(_ title: String, _ value: Int?, _ scale: LevelScale, band: Band3?, identifier: String) -> some View {
        GoopLevelScale(title: title, value: value.map { "\($0)%" }, scale: scale, current: LevelScale.index(band), identifier: identifier)
    }

    private func cell(_ label: String, _ spoken: String, _ value: Double?) -> GoopStatCells.Cell {
        GoopStatCells.Cell(label: label, spoken: spoken + " breathing rate", value: value.map { GoopFormat.number($0, decimals: 1) } ?? "—", unit: "rpm")
    }
}

private struct GoopOvernightHRV: View {
    let points: [HRVPoint]
    var body: some View {
        Group {
            if points.isEmpty { GoopPlaceholder(text: "No overnight HRV recorded") }
            else {
                Canvas { context, size in
                    let sorted = points.sorted { $0.t < $1.t }
                    let low = sorted.map(\.rmssdMs).min()!, high = sorted.map(\.rmssdMs).max()!
                    let start = sorted.first!.t, duration = max(1, sorted.last!.t.timeIntervalSince(start))
                    for index in 0..<4 {
                        let y = Double(index) * size.height / 3
                        GoopPlot.line(context: context, from: CGPoint(x: 0, y: y), to: CGPoint(x: size.width, y: y), color: Goop.Color.plotGrid)
                    }
                    let marks = sorted.map { CGPoint(x: $0.t.timeIntervalSince(start) / duration * size.width, y: size.height - 8 - ($0.rmssdMs - low) / max(1, high - low) * (size.height - 16)) }
                    context.stroke(GoopPlot.path(marks), with: .color(Goop.Color.trendLine), lineWidth: 1.6)
                    for mark in marks {
                        let circle = Path(ellipseIn: CGRect(x: mark.x - 3, y: mark.y - 3, width: 6, height: 6))
                        context.fill(circle, with: .color(Goop.Color.dotHole))
                        context.stroke(circle, with: .color(Goop.Color.trendLine), lineWidth: 1.8)
                    }
                }.frame(height: 120)
                    .accessibilityChartDescriptor(ChartAccessibility(title: "Overnight HRV", xTitle: "Time", unit: "ms", categories: points.map { GoopFormat.time($0.t) }, series: [.init(name: "HRV", continuous: true, values: points.map { (GoopFormat.time($0.t), $0.rmssdMs) })]))
            }
        }
    }
}
