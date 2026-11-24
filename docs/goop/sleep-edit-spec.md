# ghoops: unstaged sleep time and editing sleep (issue #31)

Status: final. The lead approved it on 2026-11-19 (§13). The owner saw the mockups and answered §10 that day: extra time counts as sleep, marked `UNSTAGED`; `EDIT SLEEP` is a button under the night's card. Build S1 to S6 as written. Written 2026-11-19 against `main` at `dc1c4bd`. The build plan is [sleep-edit-plan.md](sleep-edit-plan.md). The mockup is [mockups/sleep-edit.html](mockups/sleep-edit.html), rendered per screen in `mockups/screens/sleep-edit-<key>.png`.

On 2026-11-19 the owner corrected a night in Google's app, moving its end later. ghoops then showed the longer window, time in bed and wake time. Sleep Performance didn't move and Sleep Efficiency fell. The owner also asked to edit sleep from ghoops itself.

The code matches `docs/v2/scores.md` §4.2. The spec never planned for a night whose window is longer than its stages. This spec fixes that in two parts that ship in order:

1. **Unstaged time (Mac, then the app's sleep card).** A rule for minutes inside a sleep window that no stage segment covers (§3). It fixes nights edited in Google's app with no other change.
2. **Edit sleep in ghoops (Mac and iPhone).** Change a night's bedtime and wake from the Sleep screen. The edit is stored on the Mac like an activity edit and is never written to Google (§4).

The owner's two questions are in §10. The spec is written to the recommended answers, and §10 says what changes for each other answer.

**Mockup keys.** The renders use example values in the style of the test data, not the fixture's.

| Key | Screen |
| --- | --- |
| `now` | Today: a night extended in Google's app; the stages stop early, the rest is empty and counts as awake |
| `sleep` | The same night under the rule: the `UNSTAGED` block and row, and `EDIT SLEEP` under the card |
| `entry-pencil` | The other answer to owner question 2: a pencil in the Sleep header |
| `edit` | The EDIT SLEEP task sheet with wake dragged later |
| `saving` | The Sleep screen right after SAVE SLEEP, with `UPDATING` |
| `edited` | Settled: the provenance footnote under `EDIT SLEEP` |
| `error` | The `NOT SAVED` banner after the Mac refused the edit |
| `old` | A night outside the horizon: the footnote in place of the button |

## 0. Precedence and decisions

This spec extends [scores.md](../v2/scores.md) §3.1 and §4, [contract.md](../v2/contract.md) §5.1.1, §5.5, §5.11 and §7.2, [data.md](../v2/data.md) "ghoops activities", [edit-limits-spec.md](edit-limits-spec.md), [instant-saves-spec.md](instant-saves-spec.md) and [DESIGN.md](../../DESIGN.md). Where they disagree, this spec wins for sleep. The plan updates each document in the step that changes the behaviour it describes.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | Minutes inside a sleep window that no stage segment covers are **unstaged**. They count as asleep and are reported separately as `stages.unstaged`. (Owner question 1.) | The person put them there: Google's edit screen or ghoops' says "I was asleep then". Counting them as awake punishes the correction, which is what the owner saw. §3.2 compares the three options. |
| D2 | Unstaged minutes are never drawn as a stage. The hypnogram draws them as one `stageUnstaged` block across the three sleep lanes, and the sleep card lists an `UNSTAGED` row. | ghoops counts the time but does not know its stage. Garmin draws added time as light sleep; that would fake a stage. |
| D3 | The rule applies to every uncovered stretch inside the window: at the start, at the end and in the middle. A night without any stage segment is left alone. **Changed in 2.3.1** (oss-data-audit row 1): only the start and end count; a gap between segments keeps Google's total (scores.md §4.2a). | One rule is easier to trust than three. 35 of 35 untouched nights on the owner's account have zero uncovered seconds, so the rule changes nothing until a window is longer than its stages. |
| D4 | The rule adds no engine number. `score_constants.sleep.unstaged_counts_as` (`"asleep"`) tells the app which words to use. | Provider boundaries sit on whole minutes, so no threshold is needed to ignore rounding (§1.2). |
| D5 | `score_version` becomes `2.3.0`. | Asleep minutes, efficiency, performance, need, debt and Recovery change for nights with unstaged time. |
| D6 | A ghoops sleep edit changes only the night's bedtime and wake. It is stored on the Mac in `activities-v2.enc` as a new `sleep_edits` array, keyed by the night's date. Google is never written to. | Like activity edits (edit-spec.md §5.1). The date is the stable key: Google may replace the record when a person edits it. |
| D7 | The entry point is an outline `EDIT SLEEP` button under the night's card on the Sleep screen. The Home sleep row keeps opening the Sleep screen. (Owner question 2.) | DESIGN.md already has full-width outline buttons below the content they act on, and the header's one right slot holds the info button. WHOOP edits a sleep from the sleep's own page (§2). |
| D8 | The edit sheet shows the night's hypnogram with draggable edges, Google's version as a strip, and three values with priors: `ASLEEP`, `IN BED`, `EFFICIENCY`. | The same pattern as the approved Edit Activity sheet (edit-spec.md §2.2). |
| D9 | A ghoops edit wins over later changes Google makes to the same night, while the two windows still overlap. The footnote always shows Google's current times, and `RESTORE GOOGLE'S VERSION` removes the edit. **(lead?)** | Google marks nothing as edited (§1.2). A person's later edit in Google's app and Google's own reprocessing look the same to ghoops, so "newest wins" would let reprocessing silently undo the owner's edit. |
| D10 | Moving wake moves the cycle boundary: the end of the previous day and the start of the night's day. The Mac recomputes both; the phone shows `—` with `UPDATING` for every score it cannot project (§4.6). | scores.md §3.1 already starts the day at the main sleep's wake. Instant-saves §5.4's "Day Strain, Recovery and Sleep never change with an edit" holds for activities only. |
| D11 | Limits come from the Mac: `status.edit_limits.sleep_min_minutes` (new, 60) and each night's `session.edit_range`, which already holds the horizon, the shift, `now`, midnight and the neighbouring sleeps and workouts. | The Mac's-Limits Rule. The phone keeps no copy. |
| D12 | Part 1 ships live: one Mac step and one app step. Part 2's app changes ship dark behind `GoopFeature.sleepEdit`. | AGENTS.md: a feature built over several commits ships dark. Part 1 is a fix that lands in one app step. |

Rejected:
- **Count unstaged time as awake** (Google's view, today). §3.2.
- **Estimate the unstaged stretch from heart rate.** §3.2.
- **Draw added time as light sleep** (Garmin). It invents a stage.
- **Shorten-only edits** (Oura). The owner's case is a night that ran longer.
- **Write the edit back to Google.** ghoops never calls a Google write route (data.md §1).
- **A pencil in the Sleep header.** It would take the info button's slot. Offered as the other answer to owner question 2.
- **Merging a nap into the night** (WHOOP's Merge Sleep). A follow-up (§12).

## 1. Facts this design relies on

### 1.1 Code

`A/` is `ios/GHealth/`, `C/` is `ios/GHealthCore/Sources/GHealthCore/`. Line numbers are at `dc1c4bd`.

- **Main sleep.** `score.New` picks one main sleep per London end date from the provider records (`internal/score/engine.go:56-88`, scores.md §4.1) and keeps it in `e.main`. Cycles, Strain, `default_date`, the planner and every sleep value read `e.main`.
- **Asleep minutes** come from `summary.minutesAsleep`, else the stage summary (`engine.go:171`, scores.md §4.2). Time in bed is the interval. Efficiency is asleep over the interval (`internal/score/sleep.go:152`).
- **Stages** come from `summary.stagesSummary` (`sleep.go:131-139`). The hypnogram copies `stages[]` unchanged and draws gaps as empty (`sleep.go:165-176`, scores.md §4.7).
- **Disturbances** count `AWAKE` segments that start after the window starts and end before it ends (`sleep.go:141-147`).
- **Cycle start** is the main sleep's end (`engine.go:128-130`).
- **Activity edits** live in `activities-v2.enc` under `activities.lock` (`internal/activities/edits.go`). The engine applies them in `effectiveWorkouts` (`internal/score/edits.go:102`). `status.edit_limits` comes from `activities.ReportedLimits()` (`internal/activities/limits.go`).
- **The sleep card** is `SleepScreen.sleepCard` (`A/Screens/SleepScreen.swift:46`): `GoopSleepChart`, the key row, four `GoopStageRow`s and `GoopRestorativeRow`. The detail header's right slot holds the info button (`A/Screens/GoopDetailSupport.swift:13`). `GoopDetailDial` has a `secondary` caption slot under its label (`A/Components/Goop/GoopCards.swift:59`), used today for `SO FAR`.
- **The Home sleep row** (`sleep-activity-link`, `A/Components/Goop/GoopActivities.swift:35`) pushes the Sleep screen.
- **No flag file.** `A/App/GoopFeature.swift` does not exist on `main`; A7 of #18 removed it.

### 1.2 The owner's data (counts-only reads, 2026-11-19)

Reads went through `~/.local/bin/ghealth sleep --json --date <D>` for the 40 dates ending today, piped straight into scripts that print counts and booleans.

| Question | Count |
| --- | --- |
| Dates with a main sleep | 36 of 40 |
| Type `STAGES`, processed true | 36 of 36 |
| Nights whose stages end more than 15 minutes before the window ends | 1 (the edited night) |
| Nights with an uncovered stretch at the start, or in the middle, over 1 minute | 0 |
| Untouched nights with any uncovered second inside the window | 0 of 35 |
| Untouched nights whose segment boundaries are whole minutes | 35 of 35 |
| Untouched nights whose asleep minutes equal the sum of light, deep and REM segments exactly | 35 of 35 |
| Segments overlapping each other, or outside the window | 0 |
| Stages status null | 1 of 36, the edited night |
| On the edited night: Google's `minutesAwake` equals awake segments plus the uncovered span | yes |
| On the edited night: the stage summary's `AWAKE` equals the awake segments alone | yes |
| On the edited night: asleep minutes equal light + deep + REM | yes |
| On the edited night: the band synced after the new wake time | no |
| On the edited night: heart-rate buckets cover at least half the uncovered span | no |
| Naps in the 40 dates | 7 (the sleep body has no nap segments, so nap gaps can't be checked) |

What this says:
- Google extends the window and adds the new span to `minutesAwake`. It keeps the original stages, the stage summary and `minutesAsleep`. It had not re-staged at the read.
- The band had not synced since the new wake, so the missing heart rate in the span says nothing yet about whether the owner was asleep. Whether Google re-stages the span after a sync is open (§12).
- A null stages status matched the edited night, 1 of 1. It is not documented, so the rule does not depend on it.

### 1.3 Strain and Day Heart Rate went blank

This part is expected and stays. The day starts at the main sleep's wake (scores.md §3.1). The edit moved wake later than the band's last sync, and an open cycle counts heart rate only up to the last sync (§3.4). So the new day had no covered minute: Strain was null with `no_heart_rate`, and the Day Heart Rate card had nothing to draw. Both fill in once the band syncs. The same happens after a ghoops edit that moves wake past the last sync (§4.6).

## 2. Research: how others handle an edited night

Read on 2026-11-19.

| Product | Extend a night? | What added time counts as | Re-stages? | Edit screen | Limits |
| --- | --- | --- | --- | --- | --- |
| **Google Health / Fitbit** | Yes: Sleep duration tile → the day → Edit → adjust bedtime and wake up time ([Track sleep][g-track]). | Awake. "If you extend your time asleep, you may find gaps at the start or end of your sleep stages, and some data won't be considered in coach analyses" ([sleep stages][g-stages]). The owner's data agrees (§1.2). | No, at least before the next sync. "may result in a recalculation of your Sleep Score" ([Sleep Score][g-score]). | Start and end times only. | Not stated. |
| **Garmin** | Yes, in Garmin Connect: the pencil next to Bed Time or Wake Time ([Garmin Sleep Tracking][garmin]). | Sleep. "If you edit your sleep time to include periods outside of your detected sleep, those periods will be displayed as light sleep." | No: shown as light sleep. "Editing sleep times older than 24 hours will update your sleep score but will not update sleep coach recommendations." | Pencil beside each time. | Sleep can be edited, not deleted. Manually added sleep "only provides sleep duration and does not generate sleep data or a sleep score." |
| **Oura** | No. "You can only shorten sleep periods, not extend them" ([Edit Bedtime and Wake-Up Time][oura], updated 2026-07-14). | n/a | n/a. "Adjusting your sleep timing will affect your Sleep and Readiness insights for that day." | Bedtime and wake-up time. | "Sleep data older than three days can no longer be edited." Edited periods "must be at least three hours long". |
| **WHOOP** | Yes: Overview → the sleep → Edit ([Activity and Sleep Detection][whoop-detect]). | Sleep, staged: "Sleep Stages (REM, Deep, Light) are generated for both auto-detected and manually logged sleep sessions." WHOOP has its own raw sensor data, so it can stage the time. The article does not say what happens to time added by an edit. | Yes, from WHOOP's own data. A split night raises a Merge Sleep notification that recalculates Recovery ([WHOOP Cycles][whoop-cycles], 2025-08-06). | A community answer says "There is an edit button about halfway down the page where you can adjust the times" ([community][whoop-community], 2025-06-02). Its screenshot was not opened: **unverified**. | Awake under 50 minutes keeps one session; over 50 minutes logs a nap. |

**What ghoops can and cannot copy.** WHOOP re-stages from raw sensor data; ghoops receives only Google's finished stages and per-minute heart rate (whoop-parity.md §1), so it cannot stage new time. Garmin counts added time as sleep but shows it as a stage it never measured. Google counts it as awake, which is the behaviour the owner flagged.

**Borrowed:**
- Garmin: added time counts as sleep. ghoops shows it as unstaged instead of light (D1, D2).
- WHOOP: the edit starts from the sleep itself (Overview → the sleep → Edit). The community answer that puts the button partway down the page is unverified, so D7 does not rest on it.
- WHOOP and the Edit Activity sheet: drag the edges on a chart.
- Oura and WHOOP: a minimum length for an edited sleep. ghoops uses 60 minutes, WHOOP's minimum for a detected sleep, through `edit_limits` (D11).
- Garmin's pencil beside the times: offered as the other answer to owner question 2.

**Not borrowed:** Oura's shorten-only rule; Garmin's light-sleep fill; WHOOP's re-staging (ghoops lacks the data); WHOOP's nap merge (follow-up, §12).

# Part 1. Unstaged time inside a sleep window (Mac)

## 3. The rule

### 3.1 Definitions

For a sleep session `s` (main sleep or nap):
- **Window** `W = [ws, we)`. It is Google's interval, unless a ghoops sleep edit applies to the night (§4.7). Then it is the edit's window.
- **Segments**: `s.stages[]` as Google sent them.
- **Covered**: the union of the segments intersected with `W`.
- **Unstaged spans**: the maximal stretches of `W` that are not covered. They exist only when `s` has at least one segment. Since 2.3.1 only the stretches at the start and end of `W` are unstaged, and they add only minutes Google's total does not already count; a gap between segments keeps Google's total (scores.md §4.2a, oss-data-audit row 1). A session with no segments has no unstaged spans: the rule leaves it alone.
- **Unstaged minutes**: the total length of the unstaged spans in minutes, rounded half away from zero. Google's boundaries and ghoops' edits are whole minutes, so the total is whole.
- **Clipped**: some segment reaches outside `W`. This happens only when a ghoops edit shortens the night.
- **Sleep segment types**: `LIGHT`, `DEEP`, `REM`, `ASLEEP`, as scores.md §4.2 sums them. `AWAKE` and `RESTLESS` are not asleep.

### 3.2 Three options

The brief asked for at least these three. The table uses the edited night of the mockup: Google detected 23:14 to 05:40 with 6:05 asleep, and the window now ends at 06:52 (72 unstaged minutes, need 8:12).

| | A. Count as asleep (recommended) | B. Count as awake (Google, today) | C. Estimate from heart rate |
| --- | --- | --- | --- |
| Asleep | 7:17 | 6:05 | anywhere from 6:05 to 7:17 |
| Efficiency | 95% | 80% | 80% to 95% |
| Performance | 89% | 74% | 74% to 89% |
| Trusts | the person's correction | the band's original detection | a heart-rate threshold ghoops would invent |
| Works when the band was off | yes | yes | no: no heart rate to read |
| New engine numbers | none | none | at least a heart-rate ratio and a coverage minimum |
| After Google re-stages the span | stages replace unstaged minutes on the next read | the same | the estimate and Google's stages disagree |
| A ghoops edit that extends wake | counts | only lowers efficiency | depends on heart rate that may not have synced |

**Recommended: A.**
- The window is the person's statement. Google's edit screen and ghoops' both ask for bedtime and wake, and moving wake later means "I was still asleep". Counting the time as awake turns a correction into a penalty: the owner's efficiency fell for a night they made longer.
- The commonest reason for a missing span is a band that was off, flat or loose. Then there is no heart rate to estimate from, so C fails exactly where it is needed. On the owner's night the band had not synced since the new wake (§1.2).
- C would be a sleep–wake classifier built on heart rate alone. ghoops has no motion data (whoop-parity.md §1). Quiet waking and light sleep look alike in heart rate, and the result would look like a measurement. It would also need new thresholds.
- A adds no number, so nothing needs tuning, and it computes at read time. If Google later stages the span, those minutes stop being unstaged on the next read, with no migration.
- B is the only option that makes a ghoops edit to wake pointless.

**Honest numbers.** scores.md §10 promises that ghoops never invents measurements. A does not: the unstaged minutes come from the person, not from a sensor, and ghoops shows them as unstaged everywhere stages appear. It never fills them with a stage or with heart rate. The README sentence gains one clause (§3.9). Where the "unstaged" marker shows is a lead decision (§11, item 2).

### 3.3 Computing a night

Order of operations, for night `D`:
1. **Select** the main sleep exactly as scores.md §4.1 does, from Google's records, using Google's asleep minutes and intervals. Neither the rule nor an edit ever changes which session is the main sleep.
2. **Apply the sleep edit** for `D`, if one is stored and applies (§4.7). It sets `W`.
3. **Compute** the night's values with the rule below.
4. **Cycles** use the night's effective wake `we` (scores.md §3.1).

Values, for a session with window `W`:

| Field | No segments | Segments, not clipped | Segments, clipped |
| --- | --- | --- | --- |
| `asleep_minutes` | scores.md §4.2, unchanged | §4.2's value + unstaged minutes; null when §4.2's value is null | round(seconds of sleep segment types inside `W` ÷ 60) + unstaged minutes |
| `stages.light/deep/rem/awake.minutes` and `.segments` | stage summary, unchanged | stage summary, unchanged | round(seconds of that type inside `W` ÷ 60); segments = segments of that type that intersect `W`. A type absent from the stage summary stays null. |
| `stages.unstaged` | `{minutes: null, segments: null, pct_of_asleep: null}` | `{minutes, segments: number of unstaged spans, pct_of_asleep}` | the same |
| `pct_of_asleep` (light, deep, REM, unstaged) | unchanged formula: `round(100 × minutes ÷ asleep, 1)` | the same, so light + deep + REM + unstaged ≈ 100 | the same |
| `time_in_bed_minutes` | `round(we − ws)` | the same | the same |
| `efficiency_pct` | `round(100 × asleep ÷ (we − ws))` | the same | the same |
| `minutes_to_fall_asleep` | Google's when `ws` equals Google's start, else null | the same | the same |
| `disturbances.awake_segments` | `AWAKE` segments inside `W` with start after `ws` and end before `we` | the same, after clipping to `W` | the same |
| `disturbances.short_awakenings` | short awakenings that intersect `W` | the same | the same |
| `bedtime`, `wake_time` | `ws`, `we` | the same | the same |

Two invariants, each with a vector (§3.10):
- **Untouched nights.** With no edit and no uncovered minute, every value equals today's.
- **No segments.** A night with `stages: []` keeps today's values. It is never treated as all unstaged.

A longer window can turn Google's last awake segment into a disturbance. That is right under the rule: the person woke, then slept on.

### 3.4 Where the change reaches

Every value below is computed from the store at read time, as today.

| Consumer | Effect |
| --- | --- |
| Sleep Performance (§4.5) | Uses the new asleep minutes. |
| Need (§4.4): debt on the next three nights | Uses each night's new asleep minutes. |
| Need: nap credit | Each nap's asleep minutes follow the rule (§3.6). The credit window ends at the main sleep's effective bedtime `ws`. |
| Recovery (§2) | Its sleep component is the new performance. |
| Consistency (§4.6) | Uses `ws` and `we`. Google's edit already moves them today. |
| Planner (§4.11) | Its medians use the new efficiency and latency. A null latency is skipped, as today. |
| Typical stage ranges (§4.10) | Use each night's stage minutes as computed above. Unstaged minutes never enter a range. |
| Comparison means (§11a), brief trends (§11b), `days` rows | Read the new `asleep_minutes`, `efficiency_pct`, `time_in_bed_minutes`, `restorative_minutes` and `sleep_performance`. |
| Restorative minutes | Deep + REM, unchanged in kind. |
| Overnight heart rate and HRV (§4.8) | Over `W`, as today. |
| Breathing rate by stage (§4.9) | Matched to Google's window, not `W`: it is Google's summary of Google's night. |
| Health flags, vitals, HRV, resting HR | Unchanged. They are Google's daily values. |

### 3.5 Heart rate and HRV in an unstaged stretch

They don't decide anything.
- The overnight heart-rate band keeps drawing whatever minutes exist across `W`, including the unstaged stretch. The person can see their heart rate there, and in the edit sheet it helps them place the edge (§4.2).
- Overnight HRV samples inside `W` keep showing. They are display only.
- Nightly HRV and resting HR, which Recovery uses, are Google's daily values. ghoops' window never changes them.

### 3.6 Naps

- The rule applies to naps too: a nap's asleep minutes are its §4.2 value plus its unstaged minutes. A nap that Google stored with a longer window than its stages then counts the same way as a night.
- No real nap could be checked: the sleep body carries no nap segments (§1.2). Pure vectors cover it.
- Naps are not editable in ghoops (§4.8).

### 3.7 The contract (part 1)

`schema_version` stays 2. Additive keys.

| Where | Change |
| --- | --- |
| §5.1 envelope | `score_version` is `"2.3.0"`. The table's stale `"2.1.0"` is corrected. |
| §5.1.1 `score_constants` | New row: `sleep.unstaged_counts_as`, string, `"asleep"`. "How minutes inside a sleep window with no stage count (scores.md §4.2a). Added on <date>. A Mac built before then omits it; a client treats it as unknown and leaves out the sentence that names it." |
| §5.5 sleep summary, `stages` | Gains `unstaged`: `{minutes: int?, segments: int?, pct_of_asleep: num? (1 dp)}`. `minutes` is null when the main sleep has no stage segments. |
| §5.5 `asleep_minutes` | "Includes unstaged minutes (scores.md §4.2a)." |
| §5.5 `sleep` body, `hypnogram` | Gains `unstaged: [{start: Time, end: Time}]`, sorted, `[]` when there are none or no segments. `segments` are Google's segments clipped to the window. |

### 3.8 scores.md

- §0: `score_version` 2.3.0. No new constant.
- New §4.2a "Unstaged time": §3.1 and §3.3 of this spec, word for word in substance, with the worked example of §3.10.
- §4.2: asleep, efficiency and time in bed point at §4.2a. §4.3: stages and disturbances point at §4.2a. §4.7: the hypnogram's `unstaged` spans; "gaps between segments are drawn as empty" becomes "uncovered stretches are reported in `unstaged` and drawn as the unstaged block".
- §4.1: one sentence: "Selection uses Google's records; ghoops sleep edits and §4.2a apply after it."

### 3.9 README and docs

- `README.md`, the philosophy paragraph (scores.md §10): after "missing data stays missing," add "time you add to a night counts as sleep without a stage and is shown that way,".
- `docs/goop/spec.md` §5.18 (the sleep chart) gains the unstaged block, and §8.4 (Sleep detail) gains the `UNSTAGED` row, in plan step S2.

### 3.10 Worked example and vectors

**Fixture night.** `store_full`'s night ending 2026-03-10: window 23:12 to 06:29, 22 segments ending 06:29, asleep 415, stage summary awake 22, light 214, deep 85, REM 116, latency 4, need 443, three disturbances. Today `sleep_full.json` has efficiency 95 and performance 94.

The new store `store_sleep_unstaged.json` (§7) is the same night as Google sends it after an edit to 07:41:

| Value | Today's code | With the rule |
| --- | --- | --- |
| Time in bed | 509 | 509 |
| Unstaged | — | 72, one span 06:29–07:41 |
| Asleep | 415 | 487 |
| Efficiency | round(81.53) = 82 | round(95.68) = 96 |
| Light, deep, REM % | 51.6, 20.5, 28.0 (of 415) | 43.9, 17.5, 23.8, unstaged 14.8 (of 487) |
| Disturbances (awake segments) | 4 | 4: the awake segment 06:23–06:29 is now inside the window |
| Performance, need 443 | 94 | min(100, round(109.93)) = 100 |
| Cycle 2026-03-10 starts | 07:41 | 07:41 |

The first column is what the owner saw: performance held, efficiency fell. Need stays 443 only if cycle 2026-03-09's Strain stays 11.2 once its end moves to 07:41. The added minutes are resting heart rate, under the 0.30 reserve floor, so they add no TRIMP. The golden confirms it.

**Pure vectors.** New file `fixtures/v2/sleep_edit/rule_cases.json`, envelope as scores.md §9 with `score_version` 2.3.0. Each case has `input` (`google: {start, end, asleep_minutes, stage_minutes: {light, deep, rem, awake}, stage_segments: {…}, minutes_to_fall_asleep}`, `segments[]`, `window: {start, end}`) and `expected` (`time_in_bed_minutes`, `asleep_minutes`, `efficiency_pct`, `minutes_to_fall_asleep`, `stages`, `unstaged: [{start, end}]`, `awake_segments`). Go (`internal/score`) and Swift (`SleepWindowRule`, §4.10) run the same file.

| Case | Window | Expected |
| --- | --- | --- |
| `untouched` | Google's 23:12–06:29 | today's values: asleep 415, in bed 437, efficiency 95, unstaged 0 |
| `no_segments` | Google's, `segments: []` | today's values; `stages.unstaged.minutes` null |
| `google_extended_end` | 23:12–07:41, segments end 06:29 | 487, 509, 96, unstaged 72 |
| `ghoops_extended_end` | edit 23:12–07:41 over Google's 23:12–06:29 | the same values as `google_extended_end` |
| `ghoops_shortened_end` | edit 23:12–05:59 | clipped: asleep 391, in bed 407, efficiency 96, light 190, awake 16, unstaged 0, latency 4 |
| `ghoops_earlier_start` | edit 22:40–06:29 | asleep 447, in bed 469, efficiency 95, unstaged 32 (22:40–23:12), latency null, awake segments 4 |
| `ghoops_later_start_extended_end` | edit 23:42–07:41 | clipped: light 188, awake 18, asleep 461, in bed 479, efficiency 96, unstaged 72, latency null |
| `middle_gap` | synthetic: light 00:00–01:00, deep 01:20–02:00, window 00:00–02:00, Google's asleep 100 | asleep 120, unstaged 20 (01:00–01:20), efficiency 100 |
| `classic_end_gap` | synthetic `CLASSIC` night with `ASLEEP`/`RESTLESS`/`AWAKE` segments and a 30-minute end gap | asleep = Google's + 30; light, deep and REM null; unstaged 30 |
| `nap_end_gap` | synthetic nap with a 20-minute end gap | asleep = Google's + 20 |
| `no_op_edit` | edit equal to Google's window | identical to `untouched` |

The `sleep_full.json` golden must not change apart from the version string and the new empty fields. That is the untouched invariant on a whole response.

### 3.11 The app (part 1)

| Where | Change |
| --- | --- |
| Models (GHealthCore) | `SleepStages.unstaged: SleepStage?`; `Hypnogram.unstaged: [Span]` (default `[]`); `ScoreConstants.Sleep.unstagedCountsAs: String?`. All optional, so an older Mac decodes. |
| `GoopSleepChart` | Draws each unstaged span as one block from the top of the REM lane to the bottom of the Deep lane (y 43.5 to 126.5 on the 246 chart), radius 4, filled `stageUnstaged`. It sits behind the stage blocks and gets no connectors. When the block is at least 64 pt wide, `UNSTAGED` is centred in it in `labelLane`, `laneLabel`. The heart-rate band is unchanged. Selecting the `UNSTAGED` row dims every other stage to 25%, as today; selecting another stage dims the block to 25%. |
| Stage rows | A fifth `GoopStageRow`, `UNSTAGED`, after REM, only when `stages.unstaged.minutes > 0`. Percentage `pct_of_asleep` in `textSoft` (as Awake), duration as the others, bar `stageUnstaged` on the hatched track, no typical box. Id `stage-unstaged`. The bar scale includes its minutes. |
| `GoopStage` | Gains `.unstaged` (lane none, colour `stageUnstaged`, title `UNSTAGED`). |
| Sleep info sheet, Night section | `Hours of sleep` gains the note `Includes <h:mm> without stages` when unstaged minutes are above 0. |
| Sleep info sheet, How this works | A footnote from `unstaged_counts_as`: `"asleep"` gives `Time in a night with no sleep stages counts as sleep. It shows as unstaged.` `"awake"` gives `Time in a night with no sleep stages counts as awake.` Missing: no sentence. |
| Accessibility | The chart descriptor lists each unstaged span as "Unstaged 05:40 to 06:52", value in minutes. The row reads "Unstaged, 16 percent, 1 hour 12 minutes". |
| Tokens | `Goop.Color.stageUnstaged` = `#4A6072` (§5). |

The dial, Home tiles, widgets and Trends show the Mac's numbers and carry no unstaged marker (lead decision, §11 item 2).

**Old app, new Mac.** Until the phone updates, it shows the new numbers with the old empty stretch in the hypnogram, and its four stage rows sum to less than 100%. Nothing contradicts. Install the Mac first, then the phone, as usual.

# Part 2. Edit sleep in ghoops

## 4. Editing a night

### 4.1 Entry point (`sleep`, owner question 2)

- **Where.** A full-width outline `GoopButton(title: "EDIT SLEEP", role: .outline)`, 12 below the sleep card on the Sleep screen, before the need card. Id `sleep-edit-open`.
- **When it shows**, all of these:
  - `GoopFeature.sleepEdit` is on;
  - the night's `session.edit_range` is non-null (§4.9), which means the Mac supports sleep edits, the night has stage segments and is inside the horizon;
  - no pending sleep change locks the night (§4.6).
- **When it doesn't, and nothing on screen says why** (The Mac's-Limits Rule), a footnote takes its place, `bodySmall`, `iconMuted`, 12 below the card:
  - outside the horizon: `Only nights from the last <n> days can be edited.`, or for `n == 1` `Only last night's sleep can be edited.` From `edit_limits.horizon_days`. Id `sleep-edit-horizon`.
  - no stage segments: `This night has no sleep stages from your band, so ghoops can't edit it.` Id `sleep-edit-no-stages`.
  - no `session.edit_range` key at all (an older Mac): nothing.
- **The Home sleep row** keeps pushing the Sleep screen. Rows never hold a second button, and the Sleep screen shows the night the edit changes. Editing takes two taps from Home.
- **Past nights.** The date control picks the night, as today; the button acts on the selected night.

### 4.2 The sheet (`edit`)

A `GoopTaskSheet` titled `EDIT SLEEP`, with × on the right (`sleep-edit-close`), large detent and grabber. Container id `sleep-edit`. Content padded 16, from the top:

1. **Values**, a `GoopEditValues` with three columns: `ASLEEP` (value in `sleep`), `IN BED` and `EFFICIENCY` (white). Ids `sleep-edit-value-asleep`, `-in-bed`, `-efficiency`. Each shows the value, a `neutral` triangle when the rounded value differs from the prior, and the prior beneath in `compareRow` `text2`. Efficiency is written `95%` in Sofia, as a percentage may be (The Two Voices Rule).
   - **Priors** are Google's version: the rule (§3.3) applied to Google's window.
   - **Values** are the rule applied to the sheet's window, computed on the phone by `SleepWindowRule` (§4.10). They match the Mac's numbers exactly.
2. **Chart** (`sleep-edit-chart`), 22 below: `GoopSleepWindowChart`, the hypnogram drawn as §5.18 of spec.md with these changes:
   - The visible range is the night's `edit_range`, so the graph ends where the Mac's limit is.
   - The window's dashed white edges are the handles (DESIGN.md, Charts with selection): 44 pt hit areas, a selection haptic on each minute step, ids `sleep-edit-handle-start`, `sleep-edit-handle-end`.
   - Inside the window: stages in their colours and the unstaged block.
   - Outside the window: Google's segments in `neutral` at 50%, and the heart-rate line in `neutral` at 50%.
   - Heart rate across the visible range comes from `GET /v2/heart-rate?start=&end=` over `edit_range` (it fits `heart_rate_span_max_minutes`), in 5-minute buckets as §4.8. While it loads or when the Mac can't be reached, the band area is empty and shows `Heart rate needs your Mac` in `bodySmall` `text2`. Everything else works.
   - Below the axis, Google's window as a strip: `typicalFill` with `typicalEdge` `[3,2]` sides, as the Edit Activity sheet's band strip.
3. **Legend**, 10 below: the 13×13 strip swatch, `GOOGLE'S VERSION` (`labelSmall`, `textSoft`) and Google's times on the right (`time`, `text2`): `23:14 to 05:40`.
4. **Hint** (`bodySmall`, `text2`): `Drag a dashed edge, or set the times below.`
5. **`BEDTIME` and `WAKE`**, 24 below: `GoopTimeRow`s, ids `sleep-edit-start`, `sleep-edit-end`. When bedtime and wake fall on different London dates, both rows show their date (`Wed 11 Mar`, `Thu 12 Mar`), as add-start-spec §3.4; ids `sleep-edit-start-date`, `sleep-edit-end-date`. The pickers grey out times outside the bounds (§4.10).
6. **Footnote** (`bodySmall`, `text2`), 24 below. Two sentences:
   - from `unstaged_counts_as`: `"asleep"` gives `Time you add has no sleep stages. ghoops counts it as sleep.`; `"awake"` gives `Time you add has no sleep stages. ghoops counts it as awake.`; missing gives nothing;
   - always: `Edits stay on your Mac. Google Health keeps its own times.`
7. **`RESTORE GOOGLE'S VERSION`** (outline, 12 below, `sleep-edit-restore`), only when a ghoops edit is stored for the night. It opens a centred system `.alert`: title `Restore Google's times?`, message `This removes your edit to this night from ghoops on your Mac.`, buttons `Cancel` and `Restore` (default role). Restore is not destructive, so there is no `zone5` button and no Delete.
8. **Commit**, pinned: `checkmark` + `SAVE SLEEP` (`sleep-edit-save`). Disabled at 40% when the sheet's window equals the night's effective window.

Closing with × or a swipe discards the changes, with no confirmation.

### 4.3 Saving (`saving`, `edited`)

A sleep edit is one more change in the pending-changes queue (instant-saves-spec §2). Kind `sleep`, target `sleep-<date>`.

| Moment | Screen |
| --- | --- |
| Tap | The sheet closes. The Sleep screen shows the new window at once: the hypnogram, `DURATION`, the stage rows and their percentages, `SLEEP EFFICIENCY`, and the info sheet's window bar, Hours of sleep and Efficiency. These come from `SleepWindowRule` and equal the Mac's. Every other value that depends on the night shows `—` with `UPDATING` (below). `EDIT SLEEP` is hidden (locked). |
| Saving (after 0.6 s) | The Home sleep row shows `SAVING` in its time slot. |
| Waiting | The Home sleep row shows `WAITING FOR MAC`. The Sleep screen shows the tinted strain banner under its header: `Saved on your phone. It will be sent to your Mac when it can be reached.` (`change-waiting-banner`). Home shows its waiting banner. |
| Settled | The Mac's bodies replace the projection. `EDIT SLEEP` is back. A footnote 12 below it (`bodySmall`, `iconMuted`) reads `Edited in ghoops. Google Health has <start> to <end>.` (`sleep-edited-footnote`), with Google's current window. It shows whenever the night has a stored edit that applies. |
| Rolled back | Google's window and values are back, and a `NOT SAVED` banner shows (§4.5). |

**`UPDATING`.** While the change is in the list, these show `—` in `text2` with `UPDATING` in `labelMicro`, in the place their comparison or caption sits:
- for night `D`: the Sleep dial (`secondary: "UPDATING"`, as `SO FAR`), `HOURS VS. NEEDED`, `SLEEP CONSISTENCY`, the need card's values and the Tonight card;
- Recovery for `D` (Home dial, Recovery screen);
- Day Strain for `D` and `D − 1` (Home dial, Strain screen). A live session's own estimate is unchanged.

The dials and rows stay tappable. Trends are not overlaid, as instant-saves §5.4. The usual round trip at home is under a second, so most of the time none of this shows.

**Settling** re-reads the snapshot and every loaded day bundle from `D − 1` to `D + 3`: the boundary moves `D − 1`, and the night's asleep minutes feed the next three nights' debt.

### 4.4 Restore Google's version

`Restore` sends `DELETE /v2/sleep-edits/<date>` as a queued change with the same moments as §4.3. Afterwards the night shows Google's window, and the provenance footnote is gone.

There is no Undo banner: nothing is destroyed. Re-editing the night is the way back.

### 4.5 Errors, in ghoops' own words (`error`, `old`)

| Case | What the owner sees |
| --- | --- |
| The Mac refuses (400, 413) | `NOT SAVED` caution banner on the Sleep screen and Home: `Your Mac couldn't save the change to your sleep on <Wkd d Mon>. It's back as it was.` |
| The night changed on the Mac (404, 409) | `NOT SAVED`: `Your sleep on <Wkd d Mon> changed on your Mac. It's back as it was.` |
| The Mac can't be reached | The change waits (§4.3). |
| Heart rate can't load in the sheet | The band area reads `Heart rate needs your Mac`. Nothing else changes. |
| The night is outside the horizon, or has no stages | The footnote in place of `EDIT SLEEP` (§4.1). |

| An unexpected error on the phone | #24's `ErrorCopy` with a new `Save sleep edit` context: `ghoops couldn't save this change to your sleep on this phone. Try again.` The sheet's heart-rate read uses #24's existing "Load heart rate for Edit or Add" sentence in the band area. |

`<Wkd d Mon>` is the night's date (its wake date), for example `Thu 12 Mar`. Banners follow instant-saves §6.2 and §6.4: id `change-rollback-banner` on the page, `change-rollback-banner-<n>` on Home, a dismiss ×, and a VoiceOver announcement. iOS's own error text never shows.

### 4.6 What the phone projects and locks

- **Patch.** The change stores the projected sleep summary and hypnogram for `D`: `bedtime`, `wake_time`, `time_in_bed_minutes`, `asleep_minutes`, `efficiency_pct`, `efficiency_band` (from `score_constants`), `stages` (minutes and percentages, unstaged included) and `hypnogram` (segments, unstaged, outside). It also stores the list of `updating` dates: `D − 1` for Strain and `D` for the rest.
- **Lock.** While any change names `sleep-<D>`, `EDIT SLEEP` is hidden on that night.
- **What the phone doesn't project.** Performance needs the need, whose strain part reads the previous cycle, whose end the edit moves. Consistency, Recovery and Day Strain need the Mac's engine. Disturbances and latency are left as they were until settled.
- **Workouts and days.** The Mac refuses a window that overlaps a workout (§4.8), so extending a night never swallows one. A workout can still change day in one case: it started inside Google's night, and the edit ends the night before it. The cycle rule then puts it in the night's day, which is right, since the person was awake for it. The phone's projection doesn't move rows between days; the row moves when the change settles. A live session and an added activity keep the day the phone gave them until the Mac answers (DESIGN.md, Today).

### 4.7 Data model

`activities-v2.enc` gains a top-level array. `version` stays 1; older readers ignore unknown keys.

```json
"sleep_edits": [
  { "date": "2026-03-12", "start": "2026-03-11T23:14:00Z", "end": "2026-03-12T06:52:00Z",
    "updated_at": "2026-03-12T09:31:00Z" } ]
```

| Field | Type | Rule |
| --- | --- | --- |
| `date` | Date | The night: the London date of Google's main-sleep end. One edit per date. |
| `start`, `end` | Time | The edited window, whole minutes, both required. |
| `updated_at` | Time | Set on write. A PUT equal to the stored edit leaves it unchanged. |

- **Applies** when night `D` has a main sleep (§4.1 of scores.md) whose Google window overlaps `[start, end)`. Otherwise the edit is an **orphan**: kept, ignored, listed with `applies: false`. That covers Google removing the night or replacing it with a different session; if the night comes back, the edit applies again.
- **Normalisation.** A PUT whose window equals Google's current window removes the stored edit.
- **Retention.** Dropped 400 days after `updated_at` on the next write, as activity edits.
- **Lock.** Written under `activities.lock`, atomically with the rest of the file.

### 4.8 Routes, validation and CLI

**`PUT /v2/sleep-edits/<date>`.** Body: `start`, `end` required; optional `if_updated_at` (instant-saves §8.2 semantics: absent no check, null expects no stored edit, a time expects that `updated_at`). Unknown keys are ignored.

**Lookup** (404 `not_found`):
- `date` is not `YYYY-MM-DD`, is after `default_date`, or is before `default_date − (horizon_days − 1)`;
- night `date` has no main sleep;
- the main sleep has no stage segments.

**Validation** (400 `invalid_request`, `Invalid edit field: <field>.`):

| Field | Fails when |
| --- | --- |
| `body` | not a JSON object |
| `start` / `end` | missing or null; not RFC 3339; not on a whole minute; `start ≥ end` |
| `end` | after `now + 5 min`; its London date differs from `date` (the night keeps its date, and wake stays inside London day `date`, so cycles never overlap) |
| `start` / `end` | outside `[Google start − shift_minutes, Google end + shift_minutes]` |
| `start` | the window doesn't overlap Google's window |
| `duration` | `end − start` under `sleep_min_minutes` |
| `start` / `end` | the window overlaps another sleep session (another night's effective window or a nap), or a visible recorded or ghoops workout. Field `start` when the neighbour is earlier, `end` when later. |

**Conflicts** (409 `conflict`, `This night changed on your Mac.`): `if_updated_at` doesn't match. Checked after "the normalised body equals the stored edit", as instant-saves §8.2.

**Response 200:** envelope, `kind: "sleep_edit"`, `date`, `sleep_edit`: the stored object, or null when normalisation removed it.

**`DELETE /v2/sleep-edits/<date>`:** 200 with `sleep_edit: null`; 404 when nothing is stored. No horizon check, as activity Restore.

**Transport.** `/v2/sleep-edits/<date>` takes `PUT` and `DELETE`; a 405 sets `Allow: PUT, DELETE`. No query string; a DELETE body is `invalid_request`. `/v2/sleep-edits` and `/v2/sleep-edits/` are `not_found`. Logs carry method, path, status and duration only.

**CLI**, same code path, schema-2 JSON:

| Command | Effect | `kind` |
| --- | --- | --- |
| `ghoops sleep edit --date D [--start T] [--end T]` | Stores the window; an omitted end keeps the current effective value. | `sleep_edit` |
| `ghoops sleep restore --date D` | As DELETE. | `sleep_edit` |
| `ghoops sleep edits [--days N]` | Stored sleep edits updated within N days (default 30), each with `applies`. | `sleep_edits` |

`ghoops sleep [--date D] [--json]` keeps reading: the parser treats `edit`, `restore` and `edits` as subcommands only as the first argument.

**What never happens.** No Google write route is called. `collect` never touches `sleep_edits`.

### 4.9 Contract and limits (part 2)

| Where | Change |
| --- | --- |
| §5.1 `kind` list | Gains `sleep_edit`, `sleep_edits`. |
| §5.5 `sleep` body, `session` | `start`, `end` are the effective window. New: `google: {start: Time, end: Time, asleep_minutes: int?, minutes_to_fall_asleep: int?, stage_minutes: {light, deep, rem, awake: int?}, stage_segments: {light, deep, rem, awake: int?}}`: Google's night before any edit or rule. `edit: {start, end, updated_at}` or null. `edit_range: {earliest_start: Time, latest_end: Time}` or null. |
| §5.5 `hypnogram` | New `outside: [{start, end, stage}]`: the parts of Google's segments outside the window. `[]` without an edit. |
| §5.11 `edit_limits` | New `sleep_min_minutes`: int, the shortest edited sleep window, inclusive. `shift_minutes` gains: "For a sleep edit, the original window is Google's window for the night." |
| §7.2 | The routes of §4.8 and an "Edits to sleep" paragraph. |
| §6 | `conflict` gains the sleep message; `invalid_request` lists the sleep fields. |

**`edit_range`**, computed per read for the main sleep of night `D`. Null when the night is outside the horizon, has no stage segments, or has no main sleep.
- `earliest_start` = the latest of: Google start − `shift_minutes`; the end of the latest sleep session or visible workout that ends at or before Google's start.
- `latest_end` = the earliest of: Google end + `shift_minutes`; the start of the earliest sleep session that starts at or after Google's end; the start of the earliest visible workout that starts after Google's start (a workout inside Google's night caps wake at its start); local midnight ending London day `D`; `now`.

The phone applies the minimum length and the overlap rule itself (§4.10). The range is a view at read time; the Mac still validates every PUT.

`ReportedLimits().SleepMinMinutes` is the constant `SleepMinMinutes = 60` in `internal/activities`.

### 4.10 GHealthCore

- **`SleepWindowRule`** (`C/Sleep/SleepWindowRule.swift`, pure): §3.3 for one session, from `session.google`, Google's full segment list (`hypnogram.segments` plus `hypnogram.outside`) and a window. It passes every case in `rule_cases.json`.
- **`SleepEditBounds`** (pure): from `edit_range`, `sleep_min_minutes`, Google's window and the phone's `now`.
  - start ∈ `[earliest_start, min(end − sleep_min, Google end − 1 min)]`;
  - end ∈ `[max(start + sleep_min, Google start + 1 min), min(latest_end, now)]`.
  - It never traps: an empty range collapses to the current window, as `EditBounds` (edit-limits-spec §5.4).
  - Without `sleep_min_minutes` the sheet is not offered (the Mac predates sleep edits).
- **`SleepEditDraft`**: the window, bounds, values and priors; `hasChanges`; the request body with `if_updated_at` from `session.edit?.updatedAt` (null when no edit).
- **Changes.** `PendingChange.Kind.sleep` with the patch of §4.6, target `sleep-<date>`, `cycleDates` `D − 1 … D + 3`, the rollback copy of §4.5 and the `updating` dates. Replays are safe: PUT replaces, and a DELETE of a missing edit counts as accepted (instant-saves §2.4).
- **`FixtureEditAPI`** answers the two sleep routes in fixture mode.

## 5. DESIGN.md changes

Plan step S2 applies items 1–4 and S5 applies 5–7, word for word. Line numbers are at `dc1c4bd`.

1. **Frontmatter, `colors`**, after `stageREM: "#AC58EF"` (line 32): `stageUnstaged: "#4A6072"`.
2. **Colors → Data scales, line 518.** Old:

   > - **Sleep stages** (`stageAwake`, `stageLight`, `stageDeep`, `stageREM`): used in the hypnogram, stage rows and the restorative swatch.

   New:

   > - **Sleep stages** (`stageAwake`, `stageLight`, `stageDeep`, `stageREM`): used in the hypnogram, stage rows and the restorative swatch. `stageUnstaged` marks time inside a night that has no stage: the hypnogram's unstaged block and the `UNSTAGED` row (The Unstaged Rule).
3. **After The Amber Is A Pattern Rule (line 532), a new named rule:**

   > **The Unstaged Rule.** Time inside a night that no stage covers is drawn as one `stageUnstaged` block from the REM lane to the Deep lane and listed as an `UNSTAGED` row. It is never drawn in a stage's colour, never left as empty space, and never filled with a guessed stage.
4. **Components → Charts (line 650).** Old: `` `GoopSleepChart` `` New: `` `GoopSleepChart` (with the unstaged block) ``.
5. **Components → Charts.** After `GoopSleepChart`, add `` `GoopSleepWindowChart` (the hypnogram with draggable window edges, in `SleepEditSheet`) ``. **Components → Modal (line 648):** after `AddActivitySheet` (ADD task sheet), add `` `SleepEditSheet` (EDIT SLEEP task sheet) ``.
6. **Buttons → Outline (line 672).** Old: `Examples are VIEW TRENDS, TRY AGAIN and BACK TO TODAY.` New: `Examples are VIEW TRENDS, TRY AGAIN, BACK TO TODAY, EDIT SLEEP under the Sleep screen's night card, and RESTORE GOOGLE'S VERSION.`
7. **Charts with selection → "Minimal extension for picking a time window (provisional)" (line 807).** Add a last bullet:

   > - On the sleep chart (`GoopSleepWindowChart`), stage blocks and the heart-rate line outside the window use `neutral` at 50%, and Google's window is a typical-range strip under the axis.

No other rule changes. The edit sheet uses an existing task sheet, outline buttons, time rows, the typical-range strip and the dashed window edges; the button sits below the content it acts on.

## 6. Other documents

| Document | Change | Step |
| --- | --- | --- |
| `docs/goop/spec.md` §16 | "sleep editing" leaves the out-of-scope list, with a pointer here. **Done in this spec's commit.** | now |
| `docs/goop/spec.md` §5.18, §8.4 | The unstaged block and the `UNSTAGED` row. | S2 |
| `docs/goop/spec.md` §8.4 | `EDIT SLEEP`, the footnotes, the provenance line. | S6 |
| `docs/v2/scores.md` | §3.7–§3.8 above; §3.1: "`main_sleep(D).interval.endTime`" becomes "the main sleep's effective wake (sleep-edit-spec §3.3)". | S1, S3 |
| `docs/v2/contract.md` | §3.7 and §4.9 above; §3 CLI rows. | S1, S3 |
| `docs/v2/data.md` "ghoops activities" | The `sleep_edits` array, orphans, normalisation, retention. | S3 |
| `docs/goop/instant-saves-spec.md` §5.4 | "Day Strain, Recovery and Sleep never change with an edit" gains "activity". Sleep edits follow sleep-edit-spec §4.3. | S4 |
| `fixtures/v2/README.md` | The new store, goldens and books. | S1, S3 |
| `README.md` | §3.9. | S1 |
| `.agents/skills/verify-ios/features/` | A new `edit-sleep.md`. | S6 |

## 7. Fixtures

**Store for part 1.** `fixtures/v2/inputs/store_sleep_unstaged.json`, written by a new `scripts/sleep_fixture_store.py` from `store_full.json`. Only the night ending 2026-03-10 changes:

```json
{ "data_type": "sleep", "stream": "reconciled", "date": "2026-03-10", "synthetic_fixture": true,
  "data_point": { "sleep": {
    "interval": { "startTime": "2026-03-09T23:12:00Z", "endTime": "2026-03-10T07:41:00Z",
                  "startUtcOffset": "0s", "endUtcOffset": "0s" },
    "type": "STAGES",
    "metadata": { "mainSleep": true, "processed": true, "stagesStatus": null, "nap": false },
    "summary": { "minutesAsleep": "415", "minutesAwake": "94", "minutesInSleepPeriod": "509",
                 "minutesToFallAsleep": "4", "minutesAfterWakeUp": "6",
                 "stagesSummary": [ { "type": "AWAKE", "minutes": "22", "count": "5" },
                                    { "type": "LIGHT", "minutes": "214", "count": "9" },
                                    { "type": "DEEP", "minutes": "85", "count": "3" },
                                    { "type": "REM", "minutes": "116", "count": "5" } ] },
    "stages": [ "…the same 22 segments, the last AWAKE 06:23–06:29…" ],
    "shortAwakenings": [ "…the same 6…" ] } } }
```

The shape matches the owner's night: type `STAGES`, segments ending 72 minutes before the window, Google's awake total grown by exactly the uncovered span (22 + 72), asleep and the stage summary unchanged, stages status null.

**Goldens it drives** (`now` 2026-03-10T14:30Z as the others):

| Golden | Command | Checks |
| --- | --- | --- |
| `fixtures/v2/sleep_unstaged.json` | `sleep --date 2026-03-10` | §3.10's right column; `hypnogram.unstaged` = one span 06:29–07:41 |
| `fixtures/v2/day_unstaged.json` | `day --date 2026-03-10` | the same sleep summary; Recovery's sleep component; cycle start 07:41 |
| `fixtures/v2/days_unstaged.json` | `days --from 2026-03-04 --to 2026-03-10` | the 2026-03-10 row's asleep, efficiency and performance |

**Books for part 2** (`fixtures/v2/sleep_edit/`, read over `store_full`, `now` 2026-03-10T14:30Z): `book_extended.json` (2026-03-10, 23:12–07:41), `book_shortened.json` (23:12–05:59), `book_earlier.json` (22:40–06:29), `book_orphan.json` (2026-03-05, a date with no main sleep). Goldens `sleep_edit/sleep_extended.json` and so on. `sleep_extended.json` must equal `sleep_unstaged.json` in every sleep value; only `session.google`, `session.edit` and `edit_range` differ. Request vectors for PUT validation go in `sleep_edit/requests/`.

**Neighbours.** `store_full`'s nap (15:10–15:40 on 2026-03-09) and its kickboxing hour (12:00 on 2026-03-10) are more than `shift_minutes` from the night, so the shift check would refuse first. The neighbour cases need neighbours inside the shift:
- `fixtures/v2/inputs/store_sleep_neighbours.json`, from the same script (`--variant neighbours`): `store_full` plus a `CLASSIC` nap 2026-03-09 21:30–22:30Z (asleep 50). Only validation vectors read it.
- `sleep_edit/book_neighbours.json`: a ghoops Walking activity 2026-03-10 07:30–08:00Z.
- `sleep_edit/book_inside_workout.json`: a ghoops Walking activity 2026-03-10 05:00–05:30Z, inside Google's night.

| Case | Request or read | Expected |
| --- | --- | --- |
| `edit_range` with both neighbours | `sleep --date 2026-03-10` | `earliest_start` 22:30, `latest_end` 07:30 |
| start overlaps the nap | PUT 22:15–06:29 | 400 `start` |
| end overlaps the walk | PUT 23:12–07:45 | 400 `end` |
| `edit_range` with the inside walk | `sleep --date 2026-03-10` | `latest_end` 05:00 |
| end before the inside walk | PUT 23:12–04:55 | 200; the walk's `cycle_date` moves from 2026-03-09 to 2026-03-10 |

**App.**
- `FixtureSet.sleepUnstaged` (`sleep_unstaged`): `snapshot_fresh` with `sleep` and `day` replaced by the two goldens above.
- `FixtureSet.sleepEdit` (`sleep_edit`): the same with `book_extended` applied, for the saved state.
- `-GHealthSleepEditFixture open|saving|waiting|rollback|old|no_stages`, Debug only, with `FixtureEditAPI` modes as instant-saves §11.

Under the hard rules, every value is synthetic.

### 7.1 Goldens that change

From `grep -rl` over `fixtures/v2` at `dc1c4bd`:

| Class | Files | Change |
| --- | --- | --- |
| Version string | 38 files carrying `"score_version": "2.2.0"` (89 occurrences) | `2.3.0`. Files at 2.0.0 or 2.1.0 (`preview/*` and the `scores/*` vectors) keep their own envelopes, as today. |
| New empty fields | 16 files with a sleep `stages` object (`day_*`, `sleep_full`, `edits/snapshot_*`, `parity/snapshot`, `preview/snapshot_*`) | `stages.unstaged`: `minutes` 0 where the main sleep has stage segments (`sleep_full`, for one), null where it has none |
| | 13 files with a `hypnogram` | `unstaged: []`; in part 2 also `outside: []` |
| | 35 files with `score_constants` | `sleep.unstaged_counts_as: "asleep"` |
| | 12 files with a `session` | part 2: `google`, `edit: null`, `edit_range` |
| | 14 files with `edit_limits` | part 2: `sleep_min_minutes: 60` |
| Values | none of the existing goldens | No existing fixture night has uncovered time. The new goldens above carry every value change. |

## 8. Tests

The plan lists each with its step. In summary:
- **Go.** The rule vectors; the untouched invariant on `sleep_full.json`; the three new goldens; the books and their goldens; PUT validation (every row of §4.8), lookup, 409, normalisation, orphans, idempotent replay, CLI parity, `edit_range` around a nap, a workout, a workout inside Google's night, midnight and `now`; cycles move with an edit (Day Strain of both days changes; a workout inside Google's night moves to the night's day when the edit ends the night before it).
- **GHealthCore.** `SleepWindowRule` against `rule_cases.json`; `SleepEditBounds` (minimum length, overlap, `now`, collapse without trapping); `SleepEditDraft`; the `sleep` change kind (patch, lock, rollback copy, settle dates); decoding against an older Mac.
- **UI.** The unstaged block and row on `sleep_unstaged`; `EDIT SLEEP` and its footnotes; the sheet's handles, rows, values and restore alert; saving, waiting and rollback; accessibility at AX5. The full suite passes with its one skip by design.

## 9. Dark launch

- **Part 1** has no flag. S1 is a score change on the Mac; S2 is one app step.
- **Part 2.** Create `ios/GHealth/App/GoopFeature.swift`:

  ```swift
  enum GoopFeature {
      #if DEBUG
      static let sleepEdit = true
      #else
      static let sleepEdit = false
      #endif
  }
  ```

  The only runtime gate is `SleepScreen` deciding whether to draw `EDIT SLEEP` and its footnotes. Nothing below it reads the flag. The routes and CLI land early, unflagged, because the app doesn't call them yet (AGENTS.md). S6 deletes the flag, and the file if nothing else uses it.

## 10. Owner questions

Each is one decision. The recommendation comes first, and the spec is written to it.

1. **When a night is longer than its sleep stages, count the extra time as sleep? Recommended: yes, as sleep, shown as `UNSTAGED`** (mockup `sleep`).
   - It is time you said you were asleep, by moving the end in Google's app or in ghoops. Your Sleep Performance and efficiency go up with it.
   - **As awake** (mockup `now`, today's behaviour, Google's way): efficiency falls for a night you made longer, and performance doesn't move. Editing wake in ghoops would only ever lower efficiency. If chosen: `unstaged_counts_as` is `"awake"`, asleep stays Google's, and the block and row stay (the time still has no stage). §3.3's asleep column drops "+ unstaged minutes".
   - **Estimated from heart rate:** not built. It fails when the band was off, which is the usual reason for missing stages, and it would need new thresholds. If chosen, a separate spec is needed before part 1.
2. **Where should EDIT SLEEP be? Recommended: an outline button under the night's card** (mockup `sleep`, at the bottom).
   - It sits next to the stages it changes and needs no new design rule.
   - **A pencil in the Sleep header** in place of the (i) (mockup `entry-pencil`), like the workout page. The Sleep info sheet still opens from DIVE INTO MY SLEEP and the need card's (i). If chosen: §4.1 moves the entry to `GoopDetailHeader(trailing: .edit)` on the Sleep screen only, and DESIGN.md's header note says the Sleep screen trades its info button for the pencil.

## 11. Decisions for the lead

Each is written into the spec as recommended. **(lead?)** marks the ones to check.

1. **Middle gaps count like edge gaps** (D3). None exist in 36 nights. **(lead?)** The alternative is to count only start and end gaps, leaving a middle gap as awake on the theory that it is data loss.
2. **Where "unstaged" shows** (D2): the hypnogram, the `UNSTAGED` row and the info sheet's Hours of sleep note. Not on the dial, Home tiles, widgets or Trends. **(lead?)**
3. **A ghoops edit wins over Google's later changes** while the windows overlap (D9). **(lead?)** The alternative stores Google's window at save time and drops the ghoops edit when Google's window changes. Google's reprocessing would then undo the owner's edit without a word.
4. **The key is the night's date** (§4.7), not Google's record name, which may change when a person edits the night.
5. **Reuse `horizon_days` and `shift_minutes`; add `sleep_min_minutes` = 60** (D11). 60 is WHOOP's minimum for a detected sleep; Oura's is three hours.
6. **No sleep window may overlap a workout** (§4.8), so extending a night never swallows one. Ending a night before a workout that sat inside Google's night moves that workout to the night's day (§4.6).
7. **Naps follow the rule but are not editable**, and a night's window stops at a nap (§4.8). Merging a nap into the night is a follow-up.
8. **The sheet opens without the Mac**; only its heart-rate band needs it (§4.2). Edit Activity needs the Mac because its values come from heart rate; sleep values don't.
9. **Priors in the sheet are Google's version** (§4.2), as recorded activities use the band's version.
10. **`EDIT SLEEP` acts on the selected night**, so past nights in the horizon are editable from the date control.

## 12. Open questions

These could not be settled from the code, the docs or a counts-only read.

1. **Does Google re-stage the added span after the band syncs?** At the read the band had not synced since the new wake. The lead's re-read after a sync answers it. Either way the rule holds: staged minutes stop being unstaged on the next read.
2. **Start gaps, middle gaps and nap gaps** have no real example (0 of 36 nights; the sleep body has no nap segments). They are covered by pure vectors only.
3. **Does Google keep the record's name after a person's edit?** Unknown, which is why the key is the date.
4. **How does Google report a sleep logged by hand with no band data?** Not checked and not relied on. A night without segments keeps today's values.
5. **Nap merge** (WHOOP's Merge Sleep): a follow-up issue if the owner wants it.

## 13. Lead review (2026-11-19)

The lead approves D1 to D12 and every §11 decision as written. The three marked **(lead?)**:

1. **Middle gaps count like edge gaps.** Accepted. None of 36 nights has one, and one rule is easier to explain than three. If Google ever starts leaving middle gaps for data loss, a counts-only read will show it, and this can be revisited with a `score_version` bump.
2. **"Unstaged" shows on the sleep card and the info sheet only.** Accepted. The dials, tiles, widgets and Trends show a score, not stages; the place that explains a night's stages is where the marker belongs.
3. **A ghoops edit wins over Google's later changes while the windows overlap.** Accepted. Google marks nothing as edited, so "newest wins" could undo the owner's edit without a word. The footnote always shows Google's current times, and Restore is one tap.

Open question 1 (does Google re-stage after a sync) does not block the build: the rule gives the right answer either way. The lead re-reads the owner's night after the band syncs and records the answer in `acceptance.md`.

The owner questions in §10 go to the owner one at a time, with the mockups. The build starts once their answers are recorded here and in the status line.

### Lead answer during S3 (2026-11-19)

The implementer stopped S3 on one question: §7's parity rule (`sleep_extended.json` equals `sleep_unstaged.json` in every sleep value) fails on three raw Google fields, because the two source fixtures differ there.

**Decision: these stay Google's raw values.** `session.type`, `processed`, `stages_status`, `minutes_awake`, `minutes_after_wake_up` and `minutes_in_sleep_period` report what Google sent for the night, untouched by the rule (§3) or by a ghoops edit (§4). Only `session.start` and `session.end` are the effective window. contract.md §5.5 says so in S3. The parity assertion compares every computed value and excludes these six fields, along with `session.google`, `session.edit` and `edit_range`. No screen shows them.

### Owner answers (2026-11-19)

1. Extra time in a night: **as sleep, marked `UNSTAGED`** (the recommended answer, mockup `sleep`).
2. Entry point: **the `EDIT SLEEP` button under the night's card** (the recommended answer, mockup `sleep`).

The spec is written to both answers, so nothing in it changes.

[g-track]: https://support.google.com/googlehealth/answer/14236407
[g-stages]: https://support.google.com/googlehealth/answer/14236712
[g-score]: https://support.google.com/googlehealth/answer/14236513
[garmin]: https://support.garmin.com/en-US/?faq=mBRMf4ks7XAQ03qtsbI8J6
[oura]: https://support.ouraring.com/hc/en-us/articles/360025445994-Edit-Bedtime-and-Wake-Up-Time
[whoop-detect]: https://support.whoop.com/s/article/Automatic-and-Manual-Activity-Detection
[whoop-cycles]: https://support.whoop.com/s/article/WHOOP-Cycles
[whoop-community]: https://www.community.whoop.com/t/how-do-i-adjust-my-hours-of-sleep/2351
