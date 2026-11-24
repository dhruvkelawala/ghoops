#if DEBUG
import SwiftUI
import GHealthCore

struct ComponentGallery: View {
    @Environment(AppModel.self) private var model
    @State private var selectedStage: GoopStage? = .deep
    @State private var tab = GoopTab.home
    @State private var metric = TrendMetricKey.hrv
    @State private var range = TrendWindow.Range.week
    @State private var search = ""
    @State private var galleryNotes = "Sparring, 6 rounds of 3 minutes."
    @State private var fullNotes = "Sparring, 6 rounds of 3 minutes. Good se"
    @State private var sleepDraft: SleepEditDraft?
    @State private var galleryWindow: ActivityWindow?
    @State private var galleryGoal = "100%"
    @State private var galleryDay = "WED"
    @State private var galleryLive = ActivityController(directory: FileManager.default.temporaryDirectory.appendingPathComponent("gallery-live-\(UUID())"))
    @State private var galleryTime = Date.distantPast
    var body: some View {
        ScrollView {
            if let snapshot = model.cached?.snapshot {
                gallery(snapshot).padding(16)
            } else { GoopLoading() }
        }.background(Goop.Gradient.homeBackground).foregroundStyle(Goop.Color.text1)
            .accessibilityIdentifier("component-gallery")
            .onAppear { if let snapshot = model.cached?.snapshot { galleryTime = snapshot.generatedAt; galleryLive.now = snapshot.generatedAt; galleryLive.session = ActivitySession(sport: .sport("BOXING"), now: snapshot.generatedAt, cycleDate: snapshot.defaultDate) } }
    }
    private func gallery(_ snapshot: Snapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            rings(snapshot)
            dials(snapshot)
            controls(snapshot)
            cards(snapshot)
            ForEach([false, true], id: \.self) { large in
                section(large ? "Instant saves accessibility 5" : "Instant saves") {
                    if let row = galleryActivities(snapshot).first(where: { if case .workout = $0.kind { true } else { false } }) {
                        ForEach(0..<3) { index in
                            var activity = row
                            let _ = activity.status = index == 0 ? nil : index == 1 ? .saving : .waiting
                            GoopActivityRow(activity: activity, action: {})
                        }
                    }
                    GoopMetricRow(metric: .strength, value: nil, windowDays: 30, status: "UPDATING", action: {})
                }.dynamicTypeSize(large ? .accessibility5 : .large)
            }
            section("Missing values") {
                GoopValueBlock(symbol: "figure.boxing", value: "7.9", fill: Goop.Color.strain)
                GoopValueBlock(symbol: "figure.boxing", value: "—", fill: Goop.Color.strain)
                GoopValueBlock(symbol: "heart", value: "—", fill: Goop.Color.strain, dashed: true)
                GoopValueBlock(symbol: "moon.fill", value: "—", fill: Goop.Color.sleep)
                GoopWindowBar(start: snapshot.day.cycle.start, startLabel: "WOKE", end: snapshot.generatedAt, endLabel: "COUNTED UNTIL", value: "—", unit: "HEART RATE RECORDED",
                              fill: Goop.Color.strain, ink: Goop.Color.text1, accessibility: "Heart rate recorded, no data")
                GoopMonitorCard(strain: nil, loading: true, action: {})
            }
            sleepComponents(snapshot)
            if let unstaged = try? FixtureLoader.load(.sleepUnstaged).cached?.snapshot.sleep {
                ForEach([DynamicTypeSize.large, .accessibility5], id: \.self) { size in
                    section(size.isAccessibilitySize ? "Unstaged sleep accessibility 5" : "Unstaged sleep") {
                        GoopCard(padding: 14) { GoopSleepChart(sleep: unstaged) }
                        GoopStageRow(stage: .unstaged, minutes: unstaged.stages?.unstaged?.minutes, percent: unstaged.stages?.unstaged?.pctOfAsleep, scale: 300, selected: false, action: {})
                        GoopCard(padding: 14) { GoopSleepChart(sleep: unstaged, selected: .unstaged) }
                        GoopStageRow(stage: .unstaged, minutes: unstaged.stages?.unstaged?.minutes, percent: unstaged.stages?.unstaged?.pctOfAsleep, scale: 300, selected: true, action: {})
                    }.dynamicTypeSize(size)
                }
            }
            if let sleep = try? FixtureLoader.load(.sleepEdit).cached?.snapshot.sleep,
               let initial = SleepEditDraft(sleep: sleep, limits: snapshot.status.editLimits, now: snapshot.generatedAt) {
                ForEach([DynamicTypeSize.large, .accessibility5], id: \.self) { size in
                    section(size.isAccessibilitySize ? "Sleep edit accessibility 5" : "Sleep edit") {
                        GoopSleepWindowChart(draft: sleepDraft ?? initial, heartRate: sleep.overnightHr) { sleepDraft = $0 }
                        GoopDetailDial(score: .sleep, value: nil, secondary: "UPDATING", fixture: true)
                    }.dynamicTypeSize(size).accessibilityIdentifier(size.isAccessibilitySize ? "gallery-sleep-edit-ax5" : "gallery-sleep-edit")
                }
            }
            chartComponents(snapshot)
            healthComponents(snapshot)
            editComponents
            ForEach([false, true], id: \.self) { large in
                section(large ? "Rating rows accessibility 5" : "Rating rows") {
                    ForEach([0, 6, 7], id: \.self) { rpe in
                        GoopChoiceRow(number: "\(rpe)", title: EffortScale.word(rpe)?.uppercased() ?? "", selected: rpe == 7, identifier: "gallery-rating-\(rpe)\(large ? "-ax5" : "")") {}
                            .accessibilityLabel(EffortScale.spoken(rpe))
                    }
                    GoopRow("HOW HARD IT FELT", value: EffortScale.rowValue(7), disclosure: .push)
                }.dynamicTypeSize(large ? .accessibility5 : .large)
            }
            states
            section("LiveTargetRow") {
                LiveTargetRow(projected: 12.0, low: 11.6, high: 14.6)
                GoopSectionLabel(title: "ACCESSIBILITY 5")
                LiveTargetRow(projected: 12.0, low: 11.6, high: 14.6).dynamicTypeSize(.accessibility5)
            }
            if let target = SessionTarget.make(day: snapshot.day, sessionStart: snapshot.generatedAt) {
                section("START target row") {
                    ForEach([false, true], id: \.self) { large in
                        LiveTargetRow(projected: snapshot.day.strain.value, low: target.low, high: target.high, caption: "DAY STRAIN", spokenCaption: "Day Strain", identifier: "start-target")
                            .dynamicTypeSize(large ? .accessibility5 : .large)
                    }
                }
            }
            if let plan = snapshot.day.sleepPlan {
                section("GoopTonightCard") {
                    GoopTonightCard(plan: plan) {}
                    GoopTonightCard(plan: unavailablePlan(plan)) {}
                    GoopSectionLabel(title: "ACCESSIBILITY 5")
                    GoopTonightCard(plan: plan) {}.dynamicTypeSize(.accessibility5)
                    GoopTonightCard(plan: unavailablePlan(plan)) {}.dynamicTypeSize(.accessibility5)
                }
            }
            ForEach([false, true], id: \.self) { large in
                section(large ? "Explanation sheet parts accessibility 5" : "Explanation sheet parts") { explainParts(snapshot) }
                    .dynamicTypeSize(large ? .accessibility5 : .large)
            }
            Text("Gallery complete").goop(.heading).accessibilityIdentifier("gallery-end")
        }
    }
    @ViewBuilder private func explainParts(_ snapshot: Snapshot) -> some View {
        let sleep = snapshot.sleep, need = sleep.need
        GoopWindowBar(start: sleep.bedtime, startLabel: "BEDTIME", end: sleep.wakeTime, endLabel: "WAKE", value: GoopFormat.duration(sleep.timeInBedMinutes),
                      unit: "IN BED", fill: Goop.Color.sleep, ink: Goop.Color.backgroundHomeBase, accessibility: "Gallery window")
        GoopBreakdown {
            GoopBreakdownTotal(label: "SLEEP NEEDED", spoken: "Sleep needed", value: GoopFormat.duration(need.totalMinutes))
            GoopNeedBar(baseline: need.baselineMinutes, strain: need.strainExtraMinutes, debt: need.debtExtraMinutes, naps: need.napCreditMinutes,
                        scale: Double(need.baselineMinutes + need.strainExtraMinutes + need.debtExtraMinutes)).padding(.vertical, 8)
            GoopNeedParts(baseline: need.baselineMinutes, strain: need.previousCycleStrain == nil ? nil : need.strainExtraMinutes, debt: need.debtExtraMinutes, naps: need.napCreditMinutes, debtNightsUsed: need.debtNightsUsed)
            GoopBreakdownRule()
            GoopBreakdownRow(label: "Usual time awake in bed", note: "92.5% efficiency · 6 min to fall asleep", value: "+0:45")
            GoopBreakdownRule(strong: true)
            GoopBreakdownTotal(label: "TIME IN BED", spoken: "Time in bed", value: "8:48", result: true)
        }
        GoopLevelHeader(scale: .hours(snapshot.day.scoreConstants))
        GoopLevelScale(title: "Hours vs. needed", value: "93%", scale: .hours(snapshot.day.scoreConstants), current: 2, identifier: "gallery-scale")
        GoopLevelScale(scale: .strain(snapshot.day.scoreConstants), current: 1, identifier: "gallery-scale-strain")
        GoopStatCells(cells: [.init(label: "FULL", spoken: "Full", value: "14.8", unit: "rpm"), .init(label: "DEEP", spoken: "Deep", value: "—", unit: "rpm"),
                              .init(label: "LIGHT", spoken: "Light", value: "14.9", unit: "rpm"), .init(label: "REM", spoken: "REM", value: "15.6", unit: "rpm")])
        GoopSheetRow(label: "Disturbances", note: "3 awake · 6 short", value: "9")
        GoopSheetRow(label: "Fell asleep in", value: "4", unit: "min")
        GoopRangeSelector(options: ["100%", "85%", "70%"], selection: $galleryGoal, identifier: { "gallery-goal-\($0)" }, numeric: true)
        GoopFootnote(text: "Usual values come from your last 12 nights.")
        GoopFinePrint(text: "Score version 2.0.0")
    }
    private func unavailablePlan(_ plan: SleepPlan) -> SleepPlan {
        var result = plan
        result.status = .unavailable
        return result
    }
    @ViewBuilder private var editComponents: some View {
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("Fixtures/edits"),
           let data = try? Data(contentsOf: directory.appendingPathComponent("heart_rate_tue.json")),
           let hr = try? JSONCoding.decoder().decode(HeartRateBody.self, from: data),
           let snapshotData = try? Data(contentsOf: directory.appendingPathComponent("snapshot_edited.json")),
           let snapshot = try? JSONCoding.decoder().decode(Snapshot.self, from: snapshotData),
           let workout = snapshot.workouts.workouts.first(where: { $0.id == "7300000000000000101" }) {
            let draft = EditDraft(workout: workout, workouts: snapshot.workouts.workouts, heartRate: hr, limits: snapshot.status.editLimits, now: snapshot.generatedAt)
            ForEach([false, true], id: \.self) { large in
                section(large ? "Edit components accessibility 5" : "Edit components") {
                    GoopRangeSelector(options: ["MON", "TUE", "WED", "THU"], selection: $galleryDay, identifier: { "gallery-day-\($0)" })
                    GoopEditValues(value: draft.estimate, prior: draft.prior)
                    GoopWindowChart(heartRate: hr, window: galleryWindow ?? draft.window, bandStrips: draft.bandStrips) { galleryWindow = $0 }
                    GoopNotesField(text: $galleryNotes, limit: draft.limits?.notesMaxChars, identifier: "gallery-notes")
                    GoopNotesField(text: $fullNotes, limit: 40, identifier: "gallery-notes-limit")
                }.dynamicTypeSize(large ? .accessibility5 : .large)
            }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).goop(.heading).accessibilityIdentifier("gallery-heading-\(title)")
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func rings(_ snapshot: Snapshot) -> some View {
        ForEach(Array(ScoreRing.Variant.allCases.enumerated()), id: \.offset) { index, variant in
            section("ScoreRing \(index + 1)") {
                if variant == .detail {
                    ScoreRing(value: 73, color: Goop.Color.recoveryHigh, variant: variant, fixture: true).frame(maxWidth: .infinity)
                    ScoreRing(value: nil, color: Goop.Color.recoveryHigh, variant: variant, fixture: true).frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 16) {
                        ScoreRing(value: 73, color: Goop.Color.recoveryHigh, variant: variant, fixture: true)
                        ScoreRing(value: nil, color: Goop.Color.recoveryHigh, variant: variant, fixture: true)
                    }
                }
            }
        }
    }
    private func dials(_ snapshot: Snapshot) -> some View {
        Group {
            section("Home dial row") {
                GoopHomeDials(day: snapshot.day, fixture: true) { _ in }.padding(.horizontal, -16)
                GoopHomeDials(day: nil, fixture: true) { _ in }.padding(.horizontal, -16)
            }
            ForEach(GoopScore.allCases, id: \.rawValue) { score in
                section("Detail dial \(score.rawValue)") {
                    GoopDetailDial(score: score, value: score == .recovery ? 73 : score == .strain ? 12.8 : 93, band: .high, strainBand: .moderate, secondary: score == .strain ? "SO FAR" : nil, level: .optimal, fixture: true).frame(maxWidth: .infinity)
                    GoopDetailDial(score: score, value: nil, level: nil, fixture: true).frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func controls(_ snapshot: Snapshot) -> some View {
        section("Date controls and Home header") {
            GoopDateControl(date: snapshot.defaultDate, defaultDate: snapshot.defaultDate, oldestDate: "2025-01-01") { _ in }
            GoopDateControl(date: "2026-03-09", defaultDate: snapshot.defaultDate, oldestDate: "2025-01-01") { _ in }
            GoopDateControl(date: snapshot.defaultDate, defaultDate: snapshot.defaultDate, oldestDate: nil) { _ in }
            GoopHomeHeader(date: snapshot.defaultDate, defaultDate: snapshot.defaultDate, oldestDate: "2025-01-01", battery: 72, select: { _ in }, more: {})
            GoopHomeHeader(date: snapshot.defaultDate, defaultDate: snapshot.defaultDate, oldestDate: "2025-01-01", battery: nil, select: { _ in }, more: {})
        }
    }
    private func cards(_ snapshot: Snapshot) -> some View {
        Group {
            section("Monitor cards") {
                ForEach(0..<4) { index in
                    GoopMonitorCard(health: healthState(snapshot, index: index), constants: snapshot.day.scoreConstants, action: {})
                }
                GoopMonitorCard(strain: snapshot.day.strain, action: {})
                GoopMonitorCard(strain: nil, action: {})
            }
            section("Activities") {
                GoopActivitiesCard(rows: galleryActivities(snapshot), expand: {}, action: { _ in })
                GoopActivitiesCard(rows: [], start: {}, add: {}, action: { _ in })
                GoopActivitiesCard(rows: [], start: {}, add: {}, action: { _ in }).dynamicTypeSize(.accessibility5)
                ForEach([false, true], id: \.self) { large in
                    GoopActivitiesCard(rows: [], live: galleryLive, start: {}, action: { _ in })
                        .dynamicTypeSize(large ? .accessibility5 : .large)
                    GoopActivitiesCard(rows: [], title: "ACTIVITIES", add: {}, action: { _ in })
                        .dynamicTypeSize(large ? .accessibility5 : .large)
                }
            }
            section("Dashboard comparisons") {
                GoopMetricRow(metric: .hrv, value: 56, mean: 52, windowDays: 30, tile: true, action: {})
                GoopMetricRow(metric: .hrv, value: 50, mean: 52, windowDays: 30, tile: true, action: {})
                GoopMetricRow(metric: .hrv, value: 52, mean: 52, windowDays: 30, tile: true, action: {})
                GoopMetricRow(metric: .hrv, value: nil, windowDays: 30, tile: true, action: {})
            }
            section("Notched Recovery contributors") {
                GoopNotchedCard {
                    GoopMetricRow(metric: .hrv, value: 56, mean: 52, windowDays: 30, action: {})
                    GoopDivider()
                    GoopMetricRow(metric: .restingHR, value: 56, mean: 55, windowDays: 30, action: {})
                    GoopDivider()
                    GoopMetricRow(metric: .respiratoryRate, value: 15.2, mean: 14.6, windowDays: 30, action: {})
                    GoopDivider()
                    GoopMetricRow(metric: .sleepPerformance, value: nil, windowDays: 30, action: {})
                    GoopLegend(windowDays: 30)
                }
            }
            section("Notched Sleep contributors") {
                GoopNotchedCard {
                    GoopMetricRow(metric: .sleepPerformance, title: "Hours vs. Needed", value: 93, windowDays: 30, level: .optimal, sleep: true, action: {})
                    GoopDivider()
                    GoopMetricRow(metric: .consistency, value: 79, windowDays: 30, level: .sufficient, sleep: true, action: {})
                    GoopDivider()
                    GoopMetricRow(metric: .efficiency, value: nil, windowDays: 30, sleep: true, action: {})
                    GoopLegend(sleep: true, windowDays: 30)
                }
            }
            section("Insight") {
                GoopInsightCard(text: Insights.recovery(snapshot.day.recovery), actionTitle: "BREAK DOWN MY RECOVERY", action: {})
            }
            section("Weekly Recovery and Strain") {
                GoopWeeklyCard(rows: weeklyRows(snapshot), metric: .recovery, end: snapshot.defaultDate, action: {})
                GoopWeeklyCard(rows: weeklyRows(snapshot), metric: .strain, end: snapshot.defaultDate, action: {})
                GoopCard { GoopPlaceholder(text: "Needs a connection to your Mac") }
            }
        }
    }
    private func sleepComponents(_ snapshot: Snapshot) -> some View {
        Group {
            section("Hatch and stage rows") {
                GoopHatchedBar(fraction: 0.55, color: Goop.Color.stageLight, typical: 0.4...0.6)
                GoopTypicalKey()
                ForEach(GoopStage.allCases.filter { $0 != .unstaged }) { stage in
                    GoopStageRow(stage: stage, minutes: stage.data(snapshot.sleep.stages)?.minutes, percent: stage.percent(snapshot.sleep), typical: stage.typical(snapshot.sleep.stageTypical), scale: 300, selected: selectedStage == stage) { selectedStage = selectedStage == stage ? nil : stage }
                }
                GoopStageRow(stage: .light, minutes: nil, percent: nil, scale: 300, selected: false, action: {})
                GoopRestorativeRow(minutes: 201, mean: 178)
                GoopRestorativeRow(minutes: nil, mean: nil)
            }
            section("E1 sleep chart") {
                GoopCard(padding: 14) { GoopSleepChart(sleep: snapshot.sleep) }
                GoopCard(padding: 14) { GoopSleepChart(sleep: classic(snapshot.sleep)) }
                GoopCard { GoopSleepChart(sleep: noSleep(snapshot.sleep)) }
            }
            section("Need card") {
                GoopNeedCard(sleep: withoutNapCredit(snapshot.sleep), comparison: snapshot.day.comparison, info: {})
                GoopNeedCard(sleep: snapshot.sleep, comparison: snapshot.day.comparison, info: {})
                GoopNeedCard(sleep: noSleep(snapshot.sleep), comparison: nil, info: {})
            }
            section("Workout zones and HR") {
                if let workout = snapshot.workouts.workouts.last {
                    GoopZoneRows(zones: workout.zonesMinutes, resting: snapshot.day.strain.restingHrBpm, maximum: snapshot.day.strain.maxHrBpm, floors: snapshot.day.scoreConstants?.strain.zonesHrr)
                    GoopWorkoutChart(workout: workout)
                    GoopWorkoutChart(workout: emptyHR(workout))
                }
            }
        }
    }
    private func chartComponents(_ snapshot: Snapshot) -> some View {
        Group {
            section("Trend controls") {
                GoopMetricPicker(metric: $metric)
                GoopAverage(metric: metric, mean: 56, prior: 52, range: range)
                GoopRangeSelector(range: $range)
                GoopRangeNavigation(window: TrendWindow(end: snapshot.defaultDate), oldestDate: snapshot.status.store.oldestDate, defaultDate: snapshot.defaultDate, previous: {}, next: {})
            }
            ForEach([TrendWindow.Range.week, .month], id: \.self) { range in
                section("Trend \(range.rawValue) line and bars") {
                    GoopTrendChart(rows: snapshot.days.days, metric: .hrv, window: TrendWindow(range: range, end: snapshot.defaultDate), typical: 42...63)
                    GoopTrendChart(rows: snapshot.days.days, metric: .recovery, window: TrendWindow(range: range, end: snapshot.defaultDate), typical: nil)
                }
            }
            section("6M gallery sample") {
                GoopTrendChart(rows: sampleRows(snapshot), metric: .hrv, window: TrendWindow(range: .sixMonths, end: snapshot.defaultDate), typical: nil)
                GoopTrendChart(rows: [], metric: .hrv, window: TrendWindow(end: snapshot.defaultDate), typical: nil)
            }
        }
    }
    private func healthComponents(_ snapshot: Snapshot) -> some View {
        Group {
            section("Vital chip states") {
                ForEach(0..<6) { index in
                    GoopVitalTile(key: "gallery-\(index)", metric: .respiratoryRate, title: "Respiratory Rate", vital: galleryVital(snapshot, index: index), attention: index == 1, constants: snapshot.day.scoreConstants, action: {})
                }
            }
            section("Health status") {
                GoopHealthStatusCard(state: HealthState(snapshot.day.vitals), constants: snapshot.day.scoreConstants)
                GoopHealthStatusCard(state: healthState(snapshot, index: 1), constants: snapshot.day.scoreConstants)
                GoopHealthStatusCard(state: healthState(snapshot, index: 0))
            }
        }
    }
    private var states: some View {
        Group {
            section("Buttons and banner") {
                GoopButton(title: "VIEW TRENDS", action: {})
                GoopButton(title: "PAIR", role: .primary, action: {})
                GoopBanner(text: "Your Mac last collected data 2 hours ago.", dismiss: {})
            }
            section("Tab bar") { GoopTabBar(selected: $tab) }
            section("Full-screen and loading states") {
                GoopFullState(title: "Needs a connection to your Mac", text: "This day isn't saved on your iPhone.", button: "BACK TO TODAY")
                GoopCard { GoopPlaceholder(text: "No data in this range") }
                GoopLoading()
            }
            section("GoopButton roles") {
                buttonRoles
                GoopSectionLabel(title: "ACCESSIBILITY 5")
                VStack(alignment: .leading, spacing: 16) { buttonRoles }.dynamicTypeSize(.accessibility5)
            }
            section("GoopBanner tones") {
                bannerTones
                GoopSectionLabel(title: "ACCESSIBILITY 5")
                VStack(alignment: .leading, spacing: 16) { bannerTones }.dynamicTypeSize(.accessibility5)
            }
            section("GoopTaskSheet") {
                taskSheets
                GoopSectionLabel(title: "ACCESSIBILITY 5")
                VStack(alignment: .leading, spacing: 16) { taskSheets }.dynamicTypeSize(.accessibility5)
            }
            if let snapshot = model.cached?.snapshot {
                section("GoopRow") {
                    rows(snapshot)
                    GoopSectionLabel(title: "ACCESSIBILITY 5")
                    VStack(alignment: .leading, spacing: 16) { rows(snapshot) }.dynamicTypeSize(.accessibility5)
                }
            }
            section("Headers") {
                headers
                GoopSectionLabel(title: "ACCESSIBILITY 5")
                VStack(alignment: .leading, spacing: 16) { headers }.dynamicTypeSize(.accessibility5)
            }
        }
    }
    private var buttonRoles: some View {
        Group {
            GoopButton(title: "VIEW TRENDS", action: {})
            GoopButton(title: "PAIR", role: .primary, action: {})
            GoopButton(title: "PAIR", role: .primary, busy: true, action: {})
            GoopButton(title: "DELETE ACTIVITY", role: .destructive, action: {})
        }
    }
    private var bannerTones: some View {
        Group {
            GoopBanner(text: "Too short to save.")
            GoopBanner(text: "Too short to save.", dismiss: {})
            GoopBanner(text: "Boxing deleted.", symbol: "trash", symbolColor: Goop.Color.iconMuted,
                       action: GoopBannerAction(title: "UNDO", identifier: "gallery-banner-undo", perform: {}))
            GoopBanner(text: "Saved on your phone. It will be sent to your Mac when it can be reached.", symbol: "arrow.triangle.2.circlepath", tone: .strain)
            GoopBanner(text: "Live heart rate 72 bpm", title: "FITBIT AIR CONNECTED", symbol: "antenna.radiowaves.left.and.right", tone: .positive)
            GoopBanner(text: "In Google Health, open Connections, choose your Fitbit Air and tap Share heart rate. You can still start; Strain will come from your band later.", title: "NO LIVE HEART RATE", symbol: "antenna.radiowaves.left.and.right", tone: .caution)
            GoopBanner(text: "Select the heart rate monitor you want to use.", title: "CHOOSE YOUR BAND", symbol: "antenna.radiowaves.left.and.right", tone: .muted) {
                Button("Band 1") {}.goop(.bodyMid).foregroundStyle(Goop.Color.text2)
                Button("Band 2") {}.goop(.bodyMid).foregroundStyle(Goop.Color.text2)
            }
        }
    }
    private var taskSheets: some View {
        Group {
            taskSheet()
            taskSheet(back: {})
            taskSheet(enabled: false)
            GoopSearchField(prompt: "Search activities", text: $search, identifier: "gallery-search")
        }
    }
    private func taskSheet(back: (() -> Void)? = nil, enabled: Bool = true) -> some View {
        GoopTaskSheet(title: back == nil ? "SAMPLE TASK" : "SPORT", back: back, closeIdentifier: "gallery-task-close",
                      commit: GoopCommit(title: back == nil ? "SAVE SAMPLE" : "USE SAMPLE", symbol: back == nil ? "checkmark" : "figure.boxing", identifier: "gallery-task-commit", enabled: enabled) {}) {
            VStack(spacing: 0) {
                GoopSectionLabel(title: "RECENT")
                GoopChoiceRow(symbol: "figure.boxing", title: "BOXING", note: "Last: Sat", selected: true, identifier: "gallery-choice-boxing", action: {})
                GoopChoiceRow(symbol: "figure.run", title: "RUNNING", selected: false, identifier: "gallery-choice-running", action: {})
            }
        }.frame(height: 420).background(Goop.Gradient.sheet).clipShape(RoundedRectangle(cornerRadius: Goop.Metric.radiusSheet))
    }
    private func rows(_ snapshot: Snapshot) -> some View {
        let start = GoopFormat.calendar.startOfDay(for: snapshot.generatedAt)
        return Group {
            GoopRow("PAIRED MAC", value: "Fixture Mac")
            GoopRow("SPORT", value: "Boxing", disclosure: .push)
            GoopRow("EFFORT", value: "18:04 to 19:04", disclosure: .push)
            GoopRow("DETAILS", value: "First line\nSecond line")
            GoopTimeRow("START", time: $galleryTime, range: start...start.addingTimeInterval(24 * 3600 - 60), identifier: "gallery-time-start")
            GoopTimeRow("START", time: $galleryTime, range: start...start.addingTimeInterval(24 * 3600 - 60), identifier: "gallery-time-date", date: GoopFormat.dateLabel(GoopFormat.dateKey(galleryTime), format: "EEE d MMM"))
        }
    }
    private var headers: some View {
        Group {
            GoopDetailHeader(title: "TODAY", back: {}, trailing: .info {})
            GoopDetailHeader(title: "TODAY", back: {}, trailing: .edit {})
            GoopWorkoutHeader(symbol: "figure.boxing", title: "BOXING", subtitle: "17:56 to 19:12", back: {})
            GoopWorkoutHeader(symbol: "figure.boxing", title: "BOXING", subtitle: "17:56 to 19:12", back: {}, trailing: .edit {})
        }
    }
    private func healthState(_ snapshot: Snapshot, index: Int) -> HealthState {
        var vitals = snapshot.day.vitals
        vitals.metricsWithRange = index == 0 ? 0 : 5
        vitals.monitorState = ["building", "attention", "outside", "within"][index]
        vitals.persistent = index == 1 ? ["resting_hr", "respiratory_rate"] : []
        vitals.adverse = index == 1 ? vitals.persistent : index == 2 ? ["respiratory_rate"] : []
        vitals.outsideRange = vitals.adverse
        return HealthState(vitals)
    }
    private func galleryVital(_ snapshot: Snapshot, index: Int) -> VitalMetric {
        var vital = snapshot.day.vitals.metrics.respiratoryRate
        vital.position = ["within", "above", "below", "no_baseline", "no_baseline", "above"][index]
        if index == 4 { vital.status = .permissionMissing; vital.value = nil }
        return vital
    }
    private func galleryActivities(_ snapshot: Snapshot) -> [GoopActivity] {
        var rows = GoopActivity.rows(day: snapshot.day)
        rows.insert(.init(id: "gallery-nap", kind: .nap, start: snapshot.generatedAt.addingTimeInterval(-3600), end: snapshot.generatedAt.addingTimeInterval(-1800), value: "0:30", name: "NAP", icon: "moon.fill", color: Goop.Color.sleep.opacity(0.6), accessible: "Nap, 30 minutes"), at: min(1, rows.count))
        if let detected = snapshot.workouts.workouts.first(where: { $0.category == "detected" }) {
            var day = snapshot.day; day.workouts = [detected]
            rows += GoopActivity.rows(day: day, workoutsOnly: true)
        }
        return rows.sorted { a, b in
            if case .sleep = a.kind { return true }
            if case .sleep = b.kind { return false }
            return a.start > b.start
        }
    }
    private func weeklyRows(_ snapshot: Snapshot) -> [DayRow] {
        var rows = snapshot.days.days
        if rows.count > 4 { rows[rows.count - 4].recovery = nil; rows[rows.count - 4].strain = nil }
        return rows
    }
    private func sampleRows(_ snapshot: Snapshot) -> [DayRow] {
        let dates = GoopFormat.dates(from: GoopFormat.addingDays(-179, to: snapshot.defaultDate), to: snapshot.defaultDate)
        return dates.enumerated().map { index, date in
            var row = snapshot.days.days[index % snapshot.days.days.count]
            row.date = date
            return row
        }
    }
    private func classic(_ sleep: Sleep) -> Sleep {
        var result = sleep
        result.session?.type = "CLASSIC"
        if let segments = result.hypnogram?.segments {
            result.hypnogram?.segments = segments.map { segment in var copy = segment; copy.stage = segment.stage == "awake" ? "restless" : "asleep"; return copy }
        }
        return result
    }
    private func noSleep(_ sleep: Sleep) -> Sleep {
        var result = sleep; result.asleepMinutes = nil; result.hypnogram = nil; result.performance.value = nil
        return result
    }
    private func withoutNapCredit(_ sleep: Sleep) -> Sleep {
        var result = sleep
        result.need.totalMinutes += result.need.napCreditMinutes
        result.need.napCreditMinutes = 0
        return result
    }
    private func emptyHR(_ workout: Workout) -> Workout { var result = workout; result.hrSeries = []; return result }
}
#endif
