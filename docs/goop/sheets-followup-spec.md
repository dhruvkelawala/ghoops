# ghoops: explanation sheets follow-up (issue #10)

Status: approved. The lead approved it on 2026-11-16 with the changes in §9, and the owner approved the mockup the same day. Written 2026-11-16 against `main` at `fe726a0`. The build plan is [sheets-followup-plan.md](sheets-followup-plan.md). The mockup is [mockups/sheets-followup.html](mockups/sheets-followup.html).

Issue #8 redesigned the ⓘ explanation sheets ([sheets.html](mockups/sheets.html), approved 2026-11-16). Two problems remain:

1. The Recovery sheet's BREAKDOWN multiplies each input by weights the app hard-codes. The Mac's engine keeps its own copy, and the contract does not send them, so a change on the Mac would leave the rows no longer adding up to the score.
2. Some value strings put words or letters in Sofia, the number font. That breaks the Two Voices Rule in [DESIGN.md](../../DESIGN.md).

This spec fixes both. Any screen not named below stays as it is.

## 0. Precedence and decisions

This spec extends [contract.md](../v2/contract.md) §5.3, [scores.md](../v2/scores.md) §0 and §2.3, and [DESIGN.md](../../DESIGN.md) (The Two Voices Rule and The Numbers-In-Rows Rule). Where they disagree, this spec wins. The plan updates those documents in the step that changes the behaviour they describe.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | The engine sends the weights it used in a new `recovery.components.weights` object. | The weights only matter when there is a score, and `components` is exactly the object that exists when there is one. One Go struct reaches every body that carries Recovery (`day`, `snapshot`, the edits and parity snapshots). |
| D2 | The app keeps no copy of the weights. Against a Mac that does not send them, the three input rows show `—` and one extra row carries `weighted_base`. | The app never invents a number. The extra row keeps the breakdown adding up to the score, so the sheet stays honest on any Mac. |
| D3 | A Sofia string holds a number and nothing else. A unit becomes its own Nunito text after the number, and a range is written as numbers (`0–69%`). | This one rule decides every hit in §3. The app already sets units this way in four places (`GoopStatCells`, `GoopWindowBar`, the vital tiles, the live heart rate). The Recovery and Strain scales already write their ranges as numbers, so the Sleep scales now match them. |
| D4 | A number inside a label, row note, chip phrase or sentence stays in that text's Nunito style. | The approved `sheets.html` sets its notes and labels this way ("56 ms · usual 52 · 55% weight", "100% of need"). Splitting 12pt notes into alternating fonts would be noisy and hard to read. DESIGN.md says so explicitly from now on. |
| D5 | The Sleep sheet's 100% / 85% / 70% selector moves to Sofia. | It is the reverse case, a number in Nunito. The approved mockup draws these options in Sofia. |
| D6 | A new goop-lint rule, `sofiaword`, fails `make check` when a string literal with a letter reaches Sofia text. | The owner's rule is to fix every instance and make the fix hold next time. A lint catches the next literal; Core tests catch the computed strings. |

Rejected for D3: mixed runs in one label, such as Nunito "under" followed by Sofia "70%". The Sleep scales would then read differently from the Recovery and Strain scales beside them. It would also need a new mixed-run component with baseline alignment between faces of different sizes. And it would leave units, the most common hit, without a rule.

No owner decision is needed. The visible text changes in three places (the Sleep scale ranges, the old-Mac Recovery row and the selector's font). The lead approves them as product calls (§8).

## 1. Facts this design relies on

- `RecoveryExplain.weights` (`ios/GHealthCore/Sources/GHealthCore/Presentation/SleepPlanText.swift:50`) copies `WeightHRV`, `WeightRestingHR` and `WeightSleep` (`internal/score/constants.go:21-23`). The engine uses them at `internal/score/recovery.go:63`.
- `v2report` serialises `score.Recovery` directly (`internal/v2report/types.go:29`), so a new field on `score.Components` reaches every body.
- Consumers ignore unknown keys. Adding a key keeps `schema_version: 2` (contract.md line 10).
- `score_version` changes only when a score changes (scores.md §0). Reporting the weights changes no score, so it stays `2.1.0`.
- Sleep performance, consistency and efficiency are integers from 0 to 100. Performance is `min(100, …)` (scores.md §4.5), consistency is clamped to 0–100 (§4.6), and efficiency is asleep time over time in bed. So `85–100%` is a complete top band.
- The app decodes JSON with snake-case conversion, so `resting_hr` decodes to `restingHr` (as `resting_hr_score` does today).
- In the fresh preview fixture, Recovery is 73 with `hrv_score` 76.5, `resting_hr_score` 50.7, `sleep_score` 93, `weighted_base` 75.5, and penalties 2.3 and 0.0.

## 2. Recovery weights

### 2.1 Contract field (contract.md §5.3)

`components` gains `weights`, directly after `weighted_base`:

| Field | Type | Rule |
| --- | --- | --- |
| `weights` | object | `{hrv: num, resting_hr: num, sleep: num}`, 2 dp, summing to 1.00. These are the factors this score's `weighted_base` used (scores.md §2.3). It is present whenever `components` is present. |

Example, from `fixtures/v2/day_full.json` (scores.md §2.6):

```json
"components": {
  "hrv_z": 0.72,
  "hrv_score": 76.5,
  "resting_hr_z": -0.02,
  "resting_hr_score": 50.7,
  "sleep_score": 94,
  "weighted_base": 75.7,
  "weights": { "hrv": 0.55, "resting_hr": 0.2, "sleep": 0.25 },
  "respiratory_rate_z": 1.46,
  "respiratory_rate_penalty": 2.3,
  "skin_temp_z": 0.75,
  "skin_temp_penalty": 0.0,
  "optional_missing": []
}
```

Add this note under the §5.3 table: "`weights` was added on <date of step F1>. A Mac built before then omits it. A client must treat a missing `weights` as unknown and must not substitute its own values."

### 2.2 Engine (Go)

- `internal/score/types.go` gets a new type, and `Components` gets a `Weights` field directly after `Base`:

  ```go
  type RecoveryWeights struct {
  	HRV       float64 `json:"hrv"`
  	RestingHR float64 `json:"resting_hr"`
  	Sleep     float64 `json:"sleep"`
  }
  ```

  The field is `Weights RecoveryWeights `json:"weights"``.
- `internal/score/recovery.go` builds `w := RecoveryWeights{HRV: WeightHRV, RestingHR: WeightRestingHR, Sleep: WeightSleep}` once. It computes `base := w.HRV*hs + w.RestingHR*rs + w.Sleep*(*in.Sleep)` and sets `Weights: w` in the `Components` literal. The reported weights and the weights used are then the same value.
- The constants and their values do not change, and neither does `score_version`.

### 2.3 App (GHealthCore)

`Models/Recovery.swift` gets a new type, and `RecoveryComponents` gets `public var weights: RecoveryWeights?` directly after `weightedBase`. It is nil when the Mac predates the field.

```swift
/// The factors the Mac's engine used for this score (contract §5.3).
public struct RecoveryWeights: Codable, Sendable, Equatable {
    public var hrv: Double
    public var restingHr: Double
    public var sleep: Double
}
```

`Presentation/SleepPlanText.swift`:
- Delete `RecoveryExplain.weights`. No other weight literal may exist in `ios/`.
- `BreakdownLine` gains `public var id: String` as its first property. The ids are `recovery-hrv`, `recovery-resting-hr`, `recovery-sleep`, `recovery-inputs`, `recovery-breathing` and `recovery-skin`.
- `RecoveryExplain.base(_:)` takes the weights from `recovery.components?.weights` and returns rows by state:

  | State | Base rows' note | Base rows' value | Extra row after them |
  | --- | --- | --- | --- |
  | `components` and `weights` present | measured, usual, then ` · NN% weight` with NN = `Int((weight * 100).rounded())` | `"+" + GoopFormat.number(score * weight, decimals: 1)` | none |
  | `components` present, `weights` nil (older Mac) | measured and usual only | `—` | `recovery-inputs`: label `HRV, resting HR and sleep`, note `Update ghoops on your Mac to see each part`, value `"+" + GoopFormat.number(weightedBase, decimals: 1)` |
  | `components` nil (no score) | measured and usual only | `—` | none |

  The measured and usual parts of each note are unchanged.
- `RecoveryExplain.penalties(_:)` is unchanged apart from the ids.

`ios/GHealth/Screens/RecoveryScreen.swift:71` and `:73` iterate `id: \.id` and pass `identifier: line.id` to `GoopBreakdownRow`. Nothing else on the screen changes.

### 2.4 Against an older Mac

The phone can be ahead of the Mac. With `weights` absent, the BREAKDOWN reads like this (fresh fixture values):

| Row | Note | Value |
| --- | --- | --- |
| HRV | 56 ms · usual 52 | — |
| Resting heart rate | 56 bpm · usual 56 | — |
| Sleep performance | 93% | — |
| HRV, resting HR and sleep | Update ghoops on your Mac to see each part | +75.5 |
| Breathing rate | 15.2 rpm · usual 14.6 | −2.3 |
| Skin temperature | +0.2 °C from usual | 0.0 |
| RECOVERY | | 73 |

The shown parts still add up: 75.5 − 2.3 − 0.0 = 73.2, which rounds to 73. A snapshot the phone cached before the update decodes the same way until the next refresh. The Mac can be updated before or after the phone, and every combination is safe.

## 3. Words out of the number font

### 3.1 The rule

The DESIGN.md text in §4 is the rule. In short:
- A Sofia string contains only digits, spaces and the signs `. , : % + − – — <`.
- A unit is a separate Nunito `Text` after the number on the same baseline. When the value is `—`, the unit is left out.
- A range is written as numbers.
- A word that stands where a number would goes in the Nunito style for that slot.

### 3.2 The sweep

The sweep checked every `.goop(…)` call that sets one of the 31 Sofia styles (those with `sofia: true` in `ios/Shared/Goop/GoopTokens.swift`), every `GoopPlot.text` call without `nunito: true`, and every `value:` passed to a component that draws it in Sofia. It covered `ios/GHealth`, `ios/Shared` and `ios/GHealthWidgets` at `fe726a0`. Hits:

| # | Where (path:line) | Shows | Before | After |
| --- | --- | --- | --- | --- |
| T1 | `ios/GHealthCore/Sources/GHealthCore/Presentation/Levels.swift:56`, `:58`, drawn at `ios/GHealth/Components/Goop/GoopExplain.swift:194` (`valueTiny`) | Sleep sheet, HOW THIS WORKS: Hours vs. needed, Consistency, Efficiency | `under 70%`, `70–84%`, `85% +` | `0–69%`, `70–84%`, `85–100%`. Built as `"0–\(s - 1)%"`, `"\(s)–\(o - 1)%"`, `"\(o)–100%"` from the cuts `s` and `o`. Consistency becomes `0–59%`, `60–79%`, `80–100%`; Efficiency becomes `0–84%`, `85–89%`, `90–100%`. |
| T2 | `ios/GHealth/Screens/SleepScreen.swift:161`, drawn at `ios/GHealth/Screens/GoopDetailSupport.swift:101` (`valueMid`) | Sleep sheet, LAST NIGHT, "Fell asleep in" | `4 min` in Sofia | `4` in `valueMid`, then `min` in `unitSmall` `text2` |
| T3 | `ios/GHealth/Components/Goop/GoopExplain.swift:221` (`GoopStatCells` at accessibility sizes, through `GoopSheetRow`) | Sleep sheet breathing rate; Strain sheet heart rate | `14.8 rpm`, `187 bpm` in Sofia | `14.8` then `rpm`; `187` then `bpm` (`GoopSheetRow` unit) |
| T4 | `ios/GHealth/Components/Goop/GoopSleepComponents.swift:162` (`valueTiny`) | Zone rows: Strain sheet ZONES and the workout page | `168+ BPM` in Sofia | `168+` in `valueTiny`, then `BPM` in `unitSmall`, spacing 2, both `textSoft`, both dimmed together |
| T5 | `ios/GHealth/Live/LiveActivityScreen.swift:57` (`valueZoneRange`) | Live screen, under ZONE 4 | `148–167 BPM`, or `— BPM` when the range is unknown | the range in `valueZoneRange`, then `BPM` in `unitSmall`, both `iconMuted`; `BPM` is left out when the range is `—` |
| T6 | `ios/GHealth/Live/LiveActivityScreen.swift:92` (`axis`) | Live screen, ten-minute heart-rate chart | `−10 MIN` and `NOW` in Sofia | `−10` in `axis`, then `MIN` in `labelLane`, both `chevronDial`; `NOW` in `labelLane` |
| T7 | `ios/GHealth/Components/Goop/GoopHealth.swift:37`, text from `:17-18` (`valueChip`) | Health tab vital tiles before a baseline, or without data | `Building baseline`, `No data`, `Needs permission` and the other `ReasonText.metric` words in Sofia | `chip` (Nunito) when the chip holds words; `valueChip` only for the numeric range. This mirrors `ios/Shared/WidgetViews/HRVSmallView.swift:28`. |
| T8 | `ios/GHealth/Components/Goop/GoopTrendComponents.swift:178` (`GoopPlot.text`, Sofia 11) | Trends, month view, date labels | `Feb 9` in Sofia | `nunito: true` (weight 500), size and colour unchanged, like the weekday labels at `:174` |
| T9 | `ios/GHealth/Components/Goop/GoopTrendComponents.swift:190` (`GoopPlot.text`, Sofia 11) | Trends, 6-month view, month labels | `Feb` in Sofia | `nunito: true` (weight 500), size and colour unchanged |

The reverse case, a number in Nunito, came up twice during the sweep:

| # | Where | Shows | Decision |
| --- | --- | --- | --- |
| R1 | `ios/GHealth/Screens/SleepScreen.swift:116`, drawn at `ios/GHealth/Components/Goop/GoopTrendComponents.swift:48` (`labelSegment`) | Sleep sheet TONIGHT selector `100%` `85%` `70%` | Fix (D5). `GoopRangeSelector` gains `numeric: Bool = false` as the last parameter of `init(options:selection:identifier:numeric:)`. When it is true, the option text uses `valueSmall` and keeps its colours and frame. `SleepScreen.swift:116` passes `numeric: true`. |
| R2 | `ios/GHealth/Components/Goop/GoopControls.swift:54` (`battery`, Nunito 13) | Home header band battery `85%` | Not drift, and not changed. The battery is device status, not a measured number, and the approved `goop.html` draws it in Nunito. §4 now says so (lead, 2026-11-16). |

Checked and clean:
- the breakdown values (durations, signed points);
- `GoopNeedCard` and `GoopNeedParts`, and `GoopTonightCard`;
- `GoopWindowBar`, whose unit is already `labelMicro`;
- `GoopStatCells` at default sizes, and `GoopLevelScale` titles;
- `GoopValue`, `GoopAverage` and the vital tile values, whose units are already Nunito;
- `ScoreText`;
- the Home, Lock Screen and HRV widgets;
- the Live Activity and Dynamic Island, `LiveTargetRow` and `GoopLiveRow`;
- `WorkoutScreen`, `GoopEditValues` and `GoopActivities`;
- every chart value and time label.

Allowed under D4 and not changed:
- breakdown notes ("56 ms · usual 52 · 55% weight", "92.5% efficiency · 6 min to fall asleep");
- labels ("100% of need", "ZONE 5", "Nights in your 42-day baseline");
- footnotes;
- `GoopChip` phrases ("12% vs. prior week");
- "Synced 14:08".

### 3.3 Component changes

- **`GoopSheetRow`** (`ios/GHealth/Screens/GoopDetailSupport.swift:90`) gains `var unit: String? = nil` after `value`. The value side becomes `HStack(alignment: .firstTextBaseline, spacing: 2) { value in valueMid; if unit != nil and value != "—", the unit in unitSmall text2 }`. The value keeps its colour rule (`text2` for `—`, otherwise `text1`). The row keeps `.accessibilityElement(children: .combine)`.
- **T2**: `GoopSheetRow(label: "Fell asleep in", value: sleep.minutesToFallAsleep.map(String.init) ?? "—", unit: "min")`.
- **T3**: `GoopSheetRow(label: cell.spoken, value: cell.value, unit: cell.unit)`.
- **T4, T5, T6**: each unit or word becomes its own `Text` inside an `HStack(alignment: .firstTextBaseline, spacing: 2)`, styled as the T4–T6 rows of §3.2 say. Colour and opacity sit on the `HStack`, so the number and the unit dim together. In T6 the outer `HStack` keeps its `Spacer()` between the left label and `NOW`, and `NOW` keeps its current colour.
- **T7**: add `private var ranged: Bool { vital.status == .available && vital.position != "no_baseline" && vital.rangeLow != nil && vital.rangeHigh != nil }`. `chip` returns the numeric range exactly when `ranged` is true. The chip `Text` uses `.goop(ranged ? .valueChip : .chip)`.
- **ComponentGallery** (`ios/GHealth/Debug/ComponentGallery.swift`, `explainParts`) adds two items:
  - after the Disturbances row, `GoopSheetRow(label: "Fell asleep in", value: "4", unit: "min")`;
  - after that, `GoopRangeSelector(options: ["100%", "85%", "70%"], selection: $galleryGoal, identifier: { "gallery-goal-\($0)" }, numeric: true)`, with `@State private var galleryGoal = "100%"`.

  Both appear at default size and at accessibility 5, like the other parts.

## 4. DESIGN.md text

Replace The Two Voices Rule paragraph (DESIGN.md line 553) with:

> **The Two Voices Rule.** Every measured number (scores, bpm, minutes, strain, percentages, chart values) is Sofia Sans Condensed 750. Words are Nunito Sans. A number in Nunito or a word in Sofia is drift. Three cases need care:
> - **A Sofia string is a number and nothing else.** It holds digits, spaces and the signs `. , : % + − – — <`, never a letter. Write a range as numbers: `0–69%`, not `under 70%`. A unit is its own Nunito text after the number on the same baseline, for example `unitSmall` after `valueMid` or a smaller value, `unit` after `valueVital` and `unitLarge` after `valueAverage`. Leave the unit out when the value is `—`. `GoopStatCells`, `GoopSheetRow` and the vital tiles show the pattern. A word that stands where a number would, such as "Building baseline" in a vital chip, takes that slot's Nunito style (`chip`).
> - **A number inside words keeps the words' voice.** Labels, row notes, chip phrases and sentences are Nunito even when they hold a number: "ZONE 5", "100% of need", "56 ms · usual 52 · 55% weight", "7 nights to start". Never split them into Sofia and Nunito runs.
> - **Status text is Nunito.** The band battery (`85%`) and "Synced 14:08" describe the device and the sync, not a measurement.
> - **Dates, and clock times in rows and footers, are Nunito.** Weekday, day and month labels on charts use `axisDay`, `axisDayNumber` or Nunito Canvas text. Clock times in activity rows and footers use `time`. A clock time shown as a value, such as the ends of a `GoopWindowBar` or Tonight's wake, stays Sofia.
>
> The goop lint's `sofiaword` rule fails `make check` when a string literal with a letter reaches Sofia text.

In The Numbers-In-Rows Rule, "Score bands" bullet (line 704), replace "with their ranges under them in `valueTiny`." with "with their ranges under them in `valueTiny`, written as numbers only (`0–69%`, `70–84%`, `85–100%`)."

In Sheets and modals, info sheet bullets (line 690):
- Replace "and a white Sofia 17 value right-aligned." with "and a white Sofia 17 value right-aligned, with an optional `unitSmall` `text2` unit after it."
- After "such as the Sleep sheet's 100% / 85% / 70% `GoopRangeSelector`", add: "Its options are numbers, so it passes `numeric: true` and sets them in `valueSmall`."

In Do's and Don'ts → Don't, add after the "Don't write a calculation…" line: "**Don't** put a word, unit or letter in a Sofia string. Write ranges as numbers and set units in Nunito beside the number (The Two Voices Rule)."

## 5. Documents to update

| Document | Change | Step |
| --- | --- | --- |
| `docs/v2/contract.md` §5.3 | the `components` row gains `weights: {hrv, resting_hr, sleep} (num, 2 dp, sum 1.00)` after `weighted_base`, plus the note in §2.1 | F1 |
| `docs/v2/scores.md` §2.3 | the base line becomes `base = w_hrv × hrv_score + w_rhr × rhr_score + w_sleep × sleep_score`, followed by: "`(w_hrv, w_rhr, w_sleep)` are `WeightHRV`, `WeightRestingHR` and `WeightSleep` (0.55, 0.20, 0.25). The engine reports them in `components.weights` (contract §5.3), and the app reads them from there." | F1 |
| `docs/v2/scores.md` §0 | the weights row's "Used in" becomes "§2.3; reported in `components.weights`" | F1 |
| `fixtures/v2/README.md` | a "Recovery weights" section describing §6 | F2 |
| `DESIGN.md` | §4 | F3 |
| `docs/goop/acceptance.md` | one section per step | every step |

## 6. Fixtures

- **Go goldens.** `$GO test ./internal/v2report -update-goldens` regenerates 12 files. They are `day_full.json`, `day_full_config.json`, `day_calibrating.json`, `parity/snapshot.json` and the 8 `edits/snapshot_*.json`. Each must change only by gaining `weights` objects. If the diff shows anything else, stop and report it to the lead.
- **Score vectors.** In `fixtures/v2/scores/recovery.json`, add `"weights": {"hrv": 0.55, "resting_hr": 0.2, "sleep": 0.25}` after `weighted_base` in the 7 cases whose `expected.components` is not null. Edit them by hand: these vectors are hand-written, and the vector test compares them as a subset.
- **Preview fixtures.** `scripts/goop_preview_fixtures.py` gains one pass. In every body, any dict whose `components` value is a dict with `weighted_base` and no `weights` gets `weights` inserted after `weighted_base` (use `insert_after`). The value is copied from `fixtures/v2/day_full.json` `recovery.components.weights`, so Python holds no copy of the constants. Run the script once. `snapshot_fresh.json` and `snapshot_stale.json` change only by those insertions.
- **New `fixtures/v2/recovery/`** (synthetic, hand-made, with a top-level `"synthetic_fixture": true` that the decoders ignore). Both start from `day.recovery` of `preview/snapshot_fresh.json`:
  - `weights_40_30_30.json`: weights `{hrv: 0.4, resting_hr: 0.3, sleep: 0.3}`, `weighted_base` 73.7, `value` 71, `band` `high`; everything else is unchanged. Check: 0.4×76.5 + 0.3×50.7 + 0.3×93 = 73.71; 73.7 − 2.3 − 0.0 = 71.4, which rounds to 71. With today's weights the rows would add up to 73.2, so a test that passes on this file shows the app read the fixture's weights.
  - `no_weights.json`: `day.recovery` as it is before F2 adds weights, with no `weights` key. This stands in for an older Mac.
- **App bundle.** `ios/project.yml`'s "Copy debug fixtures" phase adds `mkdir -p ".../Fixtures/recovery"` and `cp "$SRCROOT"/../fixtures/v2/recovery/*.json ".../Fixtures/recovery/"`, in the same form as the `parity` lines.
- **Fixture sets** (`ios/GHealthCore/Sources/GHealthCore/Fixtures/FixtureLoader.swift`) gain `recoveryWeights = "recovery_weights"` and `recoveryNoWeights = "recovery_no_weights"`. Both load `snapshot_fresh` and then replace `snapshot.day.recovery` with `recovery/weights_40_30_30` or `recovery/no_weights`. With `recovery_weights`, Home shows 71 while the trend rows still hold 73 for that day. The two fixture sets exist only to test the sheet, so this mismatch is accepted. Record it in the fixture README.

## 7. Tests

**Go** (`make check`):
- The vector test pins `weights` through the updated `scores/recovery.json`.
- `TestRecoveryReportsTheWeightsItUsed` (new, `internal/score`). For each recovery vector case with components, run `ComputeRecovery` and check two things. The reported weights sum to 1 within 1e-9. And `w.HRV×hrv_score + w.RestingHR×resting_hr_score + w.Sleep×sleep_score`, from the reported numbers, is within 0.1 of `weighted_base`. It fails if the formula and the report ever use different weights.
- The regenerated goldens and `TestFixtureBodiesPreserveEveryKey` cover the bodies and the preview files.

**Python** (`make check`):
- `scripts/goop_preview_fixtures_test.py`:
  - add `'weights'` to the keys `remove_parity` pops, so the script must re-insert them;
  - assert that `after['day']['recovery']['components']['weights']` equals `day_full.json`'s weights for both snapshots.
- `scripts/goop_lint_test.py` covers the `sofiaword` rule (below).

**Lint rule `sofiaword`** (`scripts/goop_lint.py`):
- **Sofia styles.** Read the set of Sofia style names from `ios/Shared/Goop/GoopTokens.swift`: each line matching `case \.(\w+): GoopTextStyle\(` that also contains `sofia: true`. If the file is missing, the set is empty.
- **What counts.** One finding per string literal that still contains an ASCII letter after its `\( … )` interpolations are removed (one level of nested parentheses inside an interpolation). The literal must sit in one of these places on the line:
  1. before a `.goop(…)` call whose argument names a Sofia style, counting from the end of the previous `.goop(…)` call on the line, or from the line start;
  2. in the arguments of `GoopPlot.text(` before `context:`, on a line without `nunito: true`;
  3. in the `value:` argument of `GoopSheetRow(`, `GoopBreakdownRow(`, `GoopBreakdownTotal(`, `GoopLevelScale(`, `GoopWindowBar(` or `GoopStatCells.Cell(`. The argument runs from `value:` up to the next `, <identifier>:`, or up to a `)` that ends the line or is followed by `.` or `}`.
- **Running it.** The rule plugs into the existing loop. The output line is `<path>:<line>: sofiaword: <text>`, and the existing `// goop-lint: allow sofiaword: <reason>` marker exempts a line. It uses no baseline entry, because after F3 it has 0 findings. Run against `fe726a0` (a probe in this design run), it reports exactly 7 findings: T2, T4, T5, T6 (two literals), T8 and T9. T1, T3 and T7 build their strings at run time; the Core tests and screenshots cover those.
- **Lint tests.** `setUp` writes a minimal `ios/Shared/Goop/GoopTokens.swift` with `case .valueMid` and `case .axis` (`sofia: true`), and `case .unitSmall` and `case .labelLane` (`sofia: false`). `test_each_rule_fires_once` gains the sample `"sofiaword": 'Text("4 min").goop(.valueMid)'`. A new table test checks these lines in `ios/GHealth/Sample.swift`:

  | Line | Findings |
  | --- | --- |
  | `Text(range + " BPM").goop(.valueMid)` | 1 |
  | `HStack { Text("−10 MIN"); Text("NOW") }.goop(.axis)` | 2 |
  | `GoopPlot.text(GoopFormat.dateLabel(d, format: "MMM d"), context: c, x: 0, y: 0, size: 11, color: k)` | 1 |
  | `GoopSheetRow(label: "Fell asleep in", value: m.map { "\($0) min" } ?? "—")` | 1 |
  | `Text(value).goop(.valueMid); Text("BPM").goop(.unitSmall)` | 0 |
  | `Text("\(low)–\(high)").goop(.valueMid).accessibilityIdentifier("scale-hours")` | 0 |
  | `GoopPlot.text("HR", context: c, x: 0, y: 0, size: 10.5, color: k, nunito: true)` | 0 |
  | `GoopSheetRow(label: "Fell asleep in", value: "4", unit: "min")` | 0 |
  | `GoopBreakdownRow(label: "HRV", value: line.value, identifier: "recovery-hrv")` | 0 |

**GHealthCore** (`make ios-core-test`), in `ParityTests.swift`:
- `recoveryBreakdownAddsUpToTheScore` (fresh). Update the expected lines with their ids; the values stay `+42.1`, `+10.1`, `+23.3`, `−2.3` and `0.0`. Replace the `components = nil` tail as follows. With `components.weights = nil`, `base` returns four lines, the last being `recovery-inputs` with value `+75.5`, and the first three have `—` values and no "weight" in their notes. With `components = nil`, `base` returns three `—` lines, as today.
- `recoveryBreakdownUsesTheMacsWeights` (new). It decodes `recovery/weights_40_30_30.json`. The base lines must be HRV `56 ms · usual 52 · 40% weight` `+30.6`, Resting heart rate `56 bpm · usual 56 · 30% weight` `+15.2`, and Sleep performance `93% · 30% weight` `+27.9`. Parsing every value (`+` dropped, `−` as minus, `—` skipped) and summing gives a total that rounds to `value` 71.
- `recoveryBreakdownWithoutWeightsStillAddsUp` (new). It decodes `recovery/no_weights.json` and checks that the values sum to 73.2 and round to `value` 73.
- `levelScalesPlaceValuesInTheirBand`. The expected ranges become the T1 strings. Every index check stays.
- `valueStringsHoldOnlyNumbers` (new). Every `range` of the five `LevelScale`s, and every `value` from `RecoveryExplain.base` and `.penalties` for the three fixtures above, matches `^[0-9 .,:%+\u{2212}\u{2013}\u{2014}<]+$`.

**UI** (`ios/GHealthUITests/GHealthUITests.swift`):
- `testExplanationSheets` (fresh) adds these assertions:
  - `scale-hours` label equals `Hours vs. needed, 93%. Poor 0–69%, Sufficient 70–84%, Optimal 85–100%. Today: Optimal`;
  - on the Recovery sheet, `recovery-hrv` has label `HRV, 56 ms · usual 52 · 55% weight` and value `+42.1`;
  - `recovery-resting-hr` has value `+10.1`, and `recovery-sleep` has value `+23.3`;
  - `recovery-inputs` does not exist.
- `testRecoveryWeightsFromMac` (new) runs two launches:
  - **`recovery_weights`.** `recovery-link` label is `Recovery, 71 percent, high`. Open the Recovery sheet. `recovery-hrv`, `recovery-resting-hr` and `recovery-sleep` have the labels and values of the Core test above (for example `HRV, 56 ms · usual 52 · 40% weight` and `+30.6`). `recovery-breathing` is `−2.3`, `recovery-skin` is `0.0`, `recovery-total` is `71`, and `recovery-inputs` does not exist. Capture `recovery-weights-sheet`.
  - **`recovery_no_weights`.** `recovery-hrv` has label `HRV, 56 ms · usual 52` and value `—`. `recovery-inputs` has label `HRV, resting HR and sleep, Update ghoops on your Mac to see each part` and value `+75.5`. `recovery-total` is `73`. Capture `recovery-no-weights-sheet`.
- Fonts cannot be asserted in XCUITest. The lint, the Core tests and the screenshot review against the mockup cover them (plan F3).

## 8. Product calls for the lead, and follow-ups

Calls in this spec:
1. The older-Mac row: its label "HRV, resting HR and sleep" and the note "Update ghoops on your Mac to see each part" (§2.4).
2. Rewording the Sleep scale ranges to `0–69%`, `70–84%`, `85–100%` (T1). The issue suggested a font split; this spec rewrites them as numbers (D3).
3. The Sleep goal selector moves to Sofia `valueSmall` (R1), matching `sheets.html`.
4. `BPM` stays upper case in the zone rows and on the live screen, and only its font changes. The stat cells keep lower-case `bpm` and `rpm`.

Out of scope here:
- The app's other copies of engine numbers (zone edges, band edges, the calibration target and the penalty cap) are issue #11. It starts after this spec lands.

## 9. Lead decisions (2026-11-16)

- **Approved, with one change.** The older-Mac row's note reads "Update ghoops on your Mac to see each part" in place of "split this by input"; the label stays "HRV, resting HR and sleep".
- **Approved as written:**
  - the Sleep scale ranges as numbers (`0–69%`, `70–84%`, `85–100%`);
  - the selector in Sofia `valueSmall`;
  - `BPM` keeping its case;
  - numbers inside notes and labels staying Nunito;
  - the 71-versus-73 mismatch in the `recovery_weights` fixture set.
- **R2** is status text, not drift. §4's DESIGN.md text gains a "Status text is Nunito" case to say so.
- **Engine-number copies** are filed as #11.
- **Owner.** The owner approved the before-and-after mockup on 2026-11-16 ("Build it").
