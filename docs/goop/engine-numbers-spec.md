# ghoops: the app reads every score-engine number from the Mac (issue #11)

Status: approved. The lead approved it on 2026-11-16 (§10), and the owner approved the mockup the same day ("Build it"). Build after issue #9 closes (plan gate). Written 2026-11-16 against `main` at `133212f`. The build plan is [engine-numbers-plan.md](engine-numbers-plan.md). The mockup is [mockups/engine-numbers.html](mockups/engine-numbers.html).

The app keeps its own copies of numbers that the Mac's score engine owns. When the engine changes one, the app's explanations and its phone-side estimates stop matching the scores. Issue #10 fixed the Recovery weights ([sheets-followup-spec.md](sheets-followup-spec.md) §2). This spec fixes every other copy and adds a rule and a check so new ones don't appear.

## 0. Precedence and decisions

This spec extends [contract.md](../v2/contract.md) §2, §5.1, §5.2.3, §5.5, §5.5.1 and §5.6, and [scores.md](../v2/scores.md) §0, §3.5, §3.6, §4.2, §4.5 and §4.6. Where they disagree, this spec wins. The plan updates each document in the step that changes the behaviour it describes.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | The engine's constants travel in one new envelope object, `score_constants`, on every body that carries `score_config`. | The live estimator, the edit preview and the overlay need the strain model on the `heart_rate` body, which has no score objects. One object means one decoder and one place to look. Scales are drawn even when there is no score. |
| D2 | A window or minimum count that gates one score travels with that score, next to the count it is compared with. The new fields are `vitals.values_needed`, `sleep_plan.nights_needed`, `sleep_plan.window_nights`, `stage_typical.nights_needed`, `stage_typical.low_percentile` and `stage_typical.high_percentile`. | This follows `recovery.calibration.values_needed` and `comparison.window_days`, which already work this way. |
| D3 | Where the Mac already classifies a value, the app reads the class and never works it out again. That covers `band` for Recovery, Strain, sleep performance and consistency, the new `efficiency_band`, and `confidence`. Edges are used only to draw scale ranges and for the estimates the phone computes itself. | The class then matches the Mac's even when the app has no edges, as with an older Mac. |
| D4 | The Sleep Efficiency cut-offs (85, 90) move into the engine. The engine sends `sleep.efficiency_band` and the edges. | They were the only band on a score scale that the app owned ([spec.md](spec.md) §9.4, decision 4). With them in the engine, every score scale gets its numbers from one place. |
| D5 | The app keeps no fallback copy. Against a Mac that does not send a number, a scale range shows `—`, a sentence drops the clause that held the number or is left out, and a phone estimate shows `—`. | The app never invents a number. This is #10's D2. |
| D6 | The live estimator reads the strain model from the cached snapshot's `day.score_constants`. That is where it already gets resting and maximum heart rate (§5). | The snapshot is already on disk, so this needs no new storage. |
| D7 | Numbers the contract fixes as part of a field's type are schema, not engine numbers, and the app may use them. These are field ranges (Strain 0 to 21; Recovery and percentages 0 to 100), precision (1 dp, 2 dp), sampling (5-minute overnight buckets), the plan goals (100, 85, 70) and the zone names (`z1`…`z5`, zones 1–3 and 4–5). | Changing any of them changes a field's meaning, which needs `schema_version: 3` (contract §1.2). |
| D8 | The request limits in `internal/activities` stay out of scope. These are the 30-day edit horizon, the 180-minute shift, the 15-minute merge gap, the 4 merge ids, 500-character notes, 1 minute to 12 hours of activity and the 90-day range. | They are not score-engine numbers, and the Mac rejects a violation with `invalid_request`. They are a follow-up (§9). |
| D9 | The check has two parts. A new goop-lint rule, `enginenumber`, fails `make check` when a string literal holds a number. A GHealthCore test, `EngineNumberTests`, drives every changed surface with an odd-constants fixture and fails if a default number appears. | The lint catches the next typed sentence. The test catches code literals on the paths it drives (§7). |
| D10 | `score_version` stays `2.1.0`. | No score changes; the engine only reports numbers it already uses. |

Rejected:
- **Band edges on each score object** (`recovery.band_edges`, `strain.zone_edges`). The `heart_rate` body has no `strain` object, and the edit preview and overlay would need a second copy there.
- **Default constants bundled in the app as a fallback**, even if generated from Go at build time. The phone and the Mac are built and installed separately, so a bundled copy drifts at run time. That drift is what this issue removes.
- **A value-matching lint** that flags any literal equal to an engine constant. 7, 10, 14 and 30 also appear throughout the layout code, so it would be mostly noise.

The visible changes are small. With an updated Mac, one footnote changes wording (§4.4). Against an older Mac, the fallbacks of §5 appear. The lead approves them as product calls (§8).

## 1. Facts this design relies on

- `v2report.Envelope` (`internal/v2report/types.go:13`) sets `score_config` in `Builder.envelope` (`internal/v2report/report.go:161`) for every kind except `brief`. A field set beside it reaches `day`, `sleep`, `days`, `workouts`, `status`, `snapshot`, `heart_rate`, and each nested body of `snapshot`.
- These engine numbers are literals today: the zone edges 0.5, 0.6, 0.7 and 0.85 (`internal/score/strain.go:38-49`), the Strain band edges (`internal/score/math.go:32-42`), the sleep performance and consistency bands (`internal/score/sleep.go:44`, `:75`) and the recorded-overlap 0.5 (`internal/score/workouts.go:241`). The rest are named constants in `internal/score/constants.go` or in `sleep_plan.go:8-11`.
- The app caches the raw snapshot body (`ios/GHealthCore/Sources/GHealthCore/Cache/SnapshotStore.swift:51`). The live estimator is built from `snapshot.day` (`ios/GHealth/App/AppModel.swift:124`, `:330` → `ActivityController.updateRates`).
- Consumers ignore unknown keys (contract §1.2). The app decodes with snake-case conversion.
- `TestFixtureBodiesPreserveEveryKey` compares preview bodies as a subset (`internal/testutil/json.go:38`), so the Go change can land before the preview files gain the new keys.
- In `preview/snapshot_fresh.json`:
  - Recovery is 73 `high`, Strain 12.8 `moderate` with confidence `high`, resting 56 and max 187 bpm, TRIMP 124.1, target 13.3 to 16.3;
  - sleep performance is 93 `high`, consistency 87 `high`, efficiency 95;
  - the plan has 12 nights, `stage_typical.nights_used` is 27 and `metrics_with_range` is 5.

## 2. The sweep

Scope: every Swift file under `ios/GHealth`, `ios/Shared`, `ios/GHealthWidgets` and `ios/GHealthCore/Sources` at `133212f`, except `ios/GHealth/Debug/` and `GHealthCore/Fixtures/`. Layout, opacity, size, timing and colour numbers are left out. Two sweeps were run independently and merged. `C/` is `ios/GHealthCore/Sources/GHealthCore/`, and `A/` is `ios/GHealth/`.

### 2.1 Copies to remove

| # | Where | Copies (Go) | Sent today? | After |
| --- | --- | --- | --- | --- |
| S1 | `C/Edit/StrainMath.swift:4` | `StrainK` 10, `StrainTrimpCap` 700 (`constants.go:33-34`, `strain.go:27`) | no | `score_constants.strain.scale` |
| S2 | `C/Edit/StrainMath.swift:7` | zone edges 0.3/0.5/0.6/0.7/0.85 (`HRRFloor`, `strain.go:38-49`) | no | `strain.zones_hrr` |
| S3 | `C/Edit/StrainMath.swift:11` | TRIMP floor 0.3 (`HRRFloor`) | no | `strain.zones_hrr.z1` |
| S4 | `C/Edit/StrainMath.swift:12-13` | `TrimpA/B` 0.64/1.92, `TrimpA167/B167` 0.86/1.67 | profile name only | `strain.trimp` (the effective profile's pair) |
| S5 | `C/Live/LiveEstimator.swift:17`, `C/Edit/WindowEstimator.swift:41`, `A/Live/ActivityController.swift:71` | default profile `"banister_b192"` (`config.go`) | yes (`score_config`) | removed; S4 makes it unused |
| S6 | `C/Live/LiveEstimator.swift:25` | zone edges, for the live bpm range | no | `strain.zones_hrr` through `ZoneScale` |
| S7 | `A/Components/Goop/GoopSleepComponents.swift:178` | zone edges, for the zone rows' bpm ranges | no | `strain.zones_hrr` through `ZoneScale` |
| S8 | `C/Changes/WorkoutProjection.swift:23` | `CoverageHigh/Medium` 0.8/0.5 | no | `strain.coverage` |
| S9 | `C/Live/ActivityModels.swift:97` | `CoverageHigh` 0.8 | yes (`workout.confidence`) | `confidence == .high` |
| S10 | `C/Presentation/Insights.swift:49` | `CoverageHigh` 0.8 | yes (`strain.confidence`) | `confidence != .high` |
| S11 | `A/Screens/WorkoutScreen.swift:129` | `CoverageHigh` 0.8 | yes (`workout.confidence`) | `confidence != .high` |
| S12 | `C/Changes/Overlay.swift:37` | goop hides recorded at ½ of the shorter window (`workouts.go:241`) | no | `workouts.recorded_hidden_overlap` |
| S13 | `C/Changes/Overlay.swift:45` | `EffortOverlap` 0.5 (`constants.go:43`) | no | `workouts.effort_hidden_overlap` |
| B1 | `C/Presentation/Levels.swift:43-45`; marker `A/Screens/RecoveryScreen.swift:84` | `RecoveryMediumMin/HighMin` 34/67 | band yes, edges no | ranges from `recovery.bands`; marker from `recovery.band` |
| B2 | `Levels.swift:48-51`; marker `A/Screens/StrainScreen.swift:74` | Strain bands 10/14/18 (`math.go:32-42`) | band yes, edges no | `strain.bands`; marker from `strain.band` |
| B3 | `Levels.swift:10`, used at `A/Screens/SleepScreen.swift:14`, `:17`, `:170` and `Insights.swift:56` | sleep performance 70/85 (`sleep.go:44`) | band yes, edges no | `sleep.performance_bands`; level from `performance.band` |
| B4 | `Levels.swift:11`, used at `SleepScreen.swift:19`, `:171` | consistency 60/80 (`sleep.go:75`) | band yes, edges no | `sleep.consistency_bands`; level from `consistency.band` |
| B5 | `Levels.swift:12`, used at `SleepScreen.swift:21`, `:172` | none: the app owns 85/90 | no | engine owns them (D4): `sleep.efficiency_bands`, `sleep.efficiency_band` |
| B6 | `Insights.swift:37-40` | Strain band edges, as sentences | no | `strain.bands` |
| B7 | `Insights.swift:43` | ≥ 10, the moderate edge | no | `strain.bands.moderate` |
| R1 | `A/Screens/RecoveryScreen.swift:53` | `CalibratedValues` 14 (bar fill) | yes | `calibration.values_for_full_confidence` |
| R2 | `RecoveryScreen.swift:54` | tick at half width, which is 7 of 14 | yes | `values_needed / values_for_full_confidence` |
| R3 | `RecoveryScreen.swift:57` | "7 nights to start · 14 for full confidence" | yes | both calibration fields |
| R4 | `Insights.swift:7` | "of 7 nights", "has 7 nights" (`BaselineMinValues`) | yes | `calibration.values_needed` |
| R5 | `C/Presentation/ReasonText.swift:13` | "of 7 nights" | yes | `calibration.values_needed` |
| R6 | `RecoveryScreen.swift:77` | "up to 10 points" (`PenaltyMax`) | no | `recovery.penalty_max` |
| C1 | `Levels.swift:77` | "needs 7 nights" (`BaselineMinValues`, `vitals.go:28`) | no | `vitals.values_needed` |
| C2 | `ReasonText.swift:18` | "Needs 4 nights this week" (`ConsistencyMinNights`, `ConsistencyNights`) | no | no number: no caller reaches it today |
| C3 | `C/Presentation/SleepPlanText.swift:5` | "3 nights … last 14" (`PlanMinNights`, `PlanNights`) | no | `sleep_plan.nights_needed`, `window_nights` |
| C4 | `A/Components/Goop/GoopTonightCard.swift:46` | "Needs 3 nights" | no | `sleep_plan.nights_needed` |
| C5 | `A/Screens/GoopDetailSupport.swift:111` | "the 30 days before it" (`ComparisonDays`) | yes | `comparison.window_days` |
| C6 | `A/Components/Goop/GoopCards.swift:193` | "versus prior 30 days average" | yes | `comparison.window_days` |
| C7 | `GoopCards.swift:256` | "vs. prior 30 days" | yes | `comparison.window_days` |
| C8 | `GoopDetailSupport.swift:112` | "middle half", "30 nights", "7 such nights" (`StageTypical*`) | window yes; rest no | `stage_typical.window_nights`, `nights_needed`, `low_percentile`, `high_percentile` |
| C9 | `A/Live/ActivityController.swift:139` | "within 30 minutes" (collector interval, `report.go:264`) | yes (`status.collector.interval_minutes`) | that field |

### 2.2 Kept, and why

| Class | Where | Why it stays |
| --- | --- | --- |
| Schema (D7) | Strain 21: `ios/Shared/Goop/ScoreRing.swift:6`, `:16`; `A/Live/LiveActivityScreen.swift:14`; `A/Components/Goop/GoopTrendComponents.swift:124`; the cap in `StrainMath.strain`; the top of the Strain scale. 100: `SleepScreen.swift:168`; the top of the integer scales. Precision: `WindowEstimator.swift:34-35`, `:44`; `LiveEstimator.swift:45`. 5-minute buckets: `A/Components/Goop/GoopCharts.swift:134`, `:138`. Goals: `SleepScreen.swift:83`, `:116`; `ios/Shared/WidgetViews/WidgetData.swift:21`. Zone names: `LiveActivityScreen.swift:71`; `C/Presentation/TrendMetricKey.swift:20-21`; `LiveEstimator.swift:10`. Range limit: `C/Presentation/TrendStore.swift:29`. | contract §3, §5.2.3, §5.4, §5.5, §5.10 fix them |
| Request limits (D8) | `WorkoutScreen.swift:115`; `C/Edit/EditDraft.swift:49-50`, `:58`, `:60`; `C/Edit/ActivityWindow.swift:9-14`; the 12-hour and 60-second limits in `ActivitySession`, `ActivityStore`, `ActivityController`, `GoopLiveActivityView`, `EditSheet` and `ActivityPicker` | contract §7.2; follow-up |
| App-owned | z ±0.5 wording, `Insights.swift:13-14`; the unused 5% arrow, `C/Presentation/Format.swift:38`; cache age 6 h and 2 h (`AppModel.swift:355`, `WidgetData.swift:9`, `HomeScreen.swift:131`, `:151`, `ActivityModels.swift:97`); trend windows (`C/Presentation/TrendWindow.swift:5`); refresh timing (`A/App/BackgroundRefresh.swift:29`, `ios/GHealthWidgets/ScoresProvider.swift:29`, `C/API/SnapshotRefresher.swift:24`); sensor range (`C/Live/HeartRateSource.swift:35`); Add-past days (`C/Edit/AddDraft.swift:16`) | the engine has no such number |
| Arithmetic on sent values | awake % (`GoopSleepComponents.swift:58`), restorative (`SleepScreen.swift:73-75`), asleep target (`SleepPlanText.swift:9`) | uses no engine constant |

Not found anywhere in the app: the max-HR formula, the sleep need constants, the strain target constants, effort detection, typical wake, the consistency SD, the SD floors, the z clamp, penalty slope, the Recovery weights (#10) and the staleness minutes.

## 3. Contract

### 3.1 `score_constants` (contract §5.1, new §5.1.1)

The envelope gains `score_constants` directly after `score_config`, on exactly the bodies that carry `score_config`. Example: `fixtures/v2/day_full.json` after step E1.

```json
"score_constants": {
  "recovery": { "bands": { "medium": 34, "high": 67 }, "penalty_max": 10 },
  "strain": {
    "bands": { "moderate": 10, "strenuous": 14, "all_out": 18 },
    "zones_hrr": { "z1": 0.3, "z2": 0.5, "z3": 0.6, "z4": 0.7, "z5": 0.85 },
    "trimp": { "a": 0.64, "b": 1.92 },
    "scale": { "k": 10, "trimp_cap": 700 },
    "coverage": { "medium": 0.5, "high": 0.8 }
  },
  "sleep": {
    "performance_bands": { "medium": 70, "high": 85 },
    "consistency_bands": { "medium": 60, "high": 80 },
    "efficiency_bands": { "medium": 85, "high": 90 }
  },
  "workouts": { "recorded_hidden_overlap": 0.5, "effort_hidden_overlap": 0.5 }
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `recovery.bands` | `{medium: int, high: int}` | lowest value of each band; below `medium` is `low` (scores.md §2.4) |
| `recovery.penalty_max` | num | the most each optional-input penalty subtracts (§2.3) |
| `strain.bands` | `{moderate, strenuous, all_out}` num | lowest rounded Strain of each band; below `moderate` is `light` (§3.6) |
| `strain.zones_hrr` | `{z1…z5}` num | lowest heart-rate reserve of each zone. Below `z1` counts as `below` and adds no TRIMP (§3.5) |
| `strain.trimp` | `{a, b}` num | the coefficients of the effective `trimp_profile` (§3.5) |
| `strain.scale` | `{k, trimp_cap}` num | `strain = min(21, 21 × ln(1 + trimp / k) / ln(1 + trimp_cap / k))`, 1 dp (§3.6) |
| `strain.coverage` | `{medium, high}` num | `confidence` cut-offs on unrounded covered ÷ expected minutes (§3.7) |
| `sleep.*_bands` | `{medium: int, high: int}` | lowest value of each band for performance (§4.5), consistency (§4.6) and efficiency (§4.2) |
| `workouts.recorded_hidden_overlap` | num | a goop entry hides a recorded entry it overlaps by at least this share of the shorter window (§3.8a) |
| `workouts.effort_hidden_overlap` | num | recorded and goop windows hide a detected effort they cover by at least this share (§3.9) |

Add under the table: "`score_constants` was added on <date of step E1>. A Mac built before then omits it. A client must treat a missing `score_constants` as unknown and must not substitute its own values. The Recovery weights are reported per score in `recovery.components.weights` (§5.3) and are not repeated here."

### 3.2 Fields that travel with a score (D2)

| Where | New field, directly after | Type and value |
| --- | --- | --- |
| §5.5 sleep summary (in `day.sleep` and the `sleep` body) | `efficiency_band`, after `efficiency_pct` | `Band3?`; null when `efficiency_pct` is null (scores.md §4.2) |
| §5.5.1 `stage_typical` | `nights_needed`, `low_percentile`, `high_percentile`, after `nights_used` | ints: `StageTypicalMinNights` (7), `round(100 × StageTypicalLowQuantile)` (25), `round(100 × StageTypicalHighQuantile)` (75) |
| §5.2.3 `sleep_plan` | `nights_needed`, `window_nights`, after `nights_used` | ints: `PlanMinNights` (3), `PlanNights` (14); present for `ok` and `unavailable` |
| §5.6 `vitals` | `values_needed`, after `metrics_with_range` | int: `BaselineMinValues` (7), the baseline count a metric needs before it has a range |

Also in contract.md:
- §2 `Band3` row: add "sleep efficiency".
- §5.5 `performance`: write `value: int? (0 to 100)`.

Each new field gets the same "added on <date>" note as §3.1.

### 3.3 Against an older Mac

The phone can be updated before the Mac. Every new field decodes as optional, so an older body still decodes. §5 lists what each surface shows without them. A snapshot cached before the update behaves the same until the next refresh. Installing the Mac first means the phone never shows these fallbacks.

## 4. Engine (Go)

### 4.1 Named constants

Add to `internal/score/constants.go`, and use each one in place of its literal:

| Constant | Value | Replaces |
| --- | --- | --- |
| `Zone2HRR`, `Zone3HRR`, `Zone4HRR`, `Zone5HRR` | 0.50, 0.60, 0.70, 0.85 | `strain.go` `.5`, `.6`, `.7`, `.85`. `HRRFloor` stays the `z1` edge |
| `StrainModerateMin`, `StrainStrenuousMin`, `StrainAllOutMin` | 10.0, 14.0, 18.0 | `math.go` `strainBand` |
| `SleepPerformanceHighMin`, `SleepPerformanceMediumMin` | 85, 70 | `sleep.go:44` |
| `ConsistencyHighMin`, `ConsistencyMediumMin` | 80, 60 | `sleep.go:75` |
| `EfficiencyHighMin`, `EfficiencyMediumMin` | 90, 85 | new (D4) |
| `RecordedHiddenOverlap` | 0.5 | `workouts.go:241` |

Rename `overlapsHalf` to `goopHidesRecorded`. Values do not change, and neither does `score_version`.

### 4.2 The report

New file `internal/score/report_constants.go`:

```go
// Constants is contract §5.1.1 `score_constants`: the engine numbers the app shows or computes with.
type Constants struct {
	Recovery RecoveryConstants `json:"recovery"`
	Strain   StrainModel       `json:"strain"`
	Sleep    SleepConstants    `json:"sleep"`
	Workouts WorkoutOverlap    `json:"workouts"`
}
type Band3Edges struct {
	Medium int `json:"medium"`
	High   int `json:"high"`
}
type RecoveryConstants struct {
	Bands      Band3Edges `json:"bands"`
	PenaltyMax float64    `json:"penalty_max"`
}
type StrainModel struct {
	Bands    StrainBandEdges   `json:"bands"`
	Zones    ZoneFloors        `json:"zones_hrr"`
	Trimp    TrimpCoefficients `json:"trimp"`
	Scale    StrainScale       `json:"scale"`
	Coverage CoverageCuts      `json:"coverage"`
}
type StrainBandEdges struct {
	Moderate  float64 `json:"moderate"`
	Strenuous float64 `json:"strenuous"`
	AllOut    float64 `json:"all_out"`
}
type ZoneFloors struct {
	Z1 float64 `json:"z1"`
	Z2 float64 `json:"z2"`
	Z3 float64 `json:"z3"`
	Z4 float64 `json:"z4"`
	Z5 float64 `json:"z5"`
}
type TrimpCoefficients struct {
	A float64 `json:"a"`
	B float64 `json:"b"`
}
type StrainScale struct {
	K        float64 `json:"k"`
	TrimpCap float64 `json:"trimp_cap"`
}
type CoverageCuts struct {
	Medium float64 `json:"medium"`
	High   float64 `json:"high"`
}
type SleepConstants struct {
	Performance Band3Edges `json:"performance_bands"`
	Consistency Band3Edges `json:"consistency_bands"`
	Efficiency  Band3Edges `json:"efficiency_bands"`
}
type WorkoutOverlap struct {
	Recorded float64 `json:"recorded_hidden_overlap"`
	Effort   float64 `json:"effort_hidden_overlap"`
}

func ConstantsFor(profile string) Constants
func trimpCoefficients(profile string) (a, b float64)
```

- `trimpCoefficients` returns `TrimpA167, TrimpB167` for `"banister_b167"` and `TrimpA, TrimpB` otherwise. `ComputeMinutes` calls it in place of its inline switch (`strain.go:31-34`). `ConstantsFor` uses it for `Strain.Trimp`.
- `ConstantsFor` fills every other field from the named constants of §4.1 and `constants.go`. That makes the reported values and the values used the same constants.
- `v2report.Envelope` gains `Constants *score.Constants `json:"score_constants,omitempty"`` directly after `Config`. In `Builder.envelope`, inside `if kind != "brief"`, set `c := score.ConstantsFor(b.engine.Config.TrimpProfile); e.Constants = &c`.

### 4.3 Fields that travel with a score

- `SleepSummary` gains `EfficiencyBand *string `json:"efficiency_band"`` directly after `Efficiency`. Add `func EfficiencyBand(pct *int) *string` to `sleep.go`. It returns nil for nil, else `band(float64(*pct), EfficiencyHighMin, EfficiencyMediumMin)`. `Engine.Sleep` sets it right after `out.Efficiency`.
- `StageTypical` gains `Needed int `json:"nights_needed"``, `LowPct int `json:"low_percentile"`` and `HighPct int `json:"high_percentile"`` after `Nights`. They are set wherever the struct is built, from `StageTypicalMinNights` and `int(math.Round(100 * q))` of the two quantiles.
- `SleepPlan` gains `Needed int `json:"nights_needed"`` and `Window int `json:"window_nights"`` after `Nights`. Both are set in the first struct literal of `Engine.SleepPlan`, so `unavailable` carries them too.
- `Vitals` gains `Needed int `json:"values_needed"`` after `WithRange`, set to `BaselineMinValues` where `Vitals` is built.
- `scripts/v2_shape.py`: add `"efficiency_band"` to `ENUM_FIELDS`.

## 5. App

### 5.1 Models (GHealthCore)

New file `Models/ScoreConstants.swift` holds the types of §4.2, with every field `public var`, `Codable, Sendable, Equatable`:
- `ScoreConstants{recovery, strain, sleep, workouts}`;
- `Band3Edges{medium: Int, high: Int}`;
- `RecoveryConstants{bands, penaltyMax: Double}`;
- `StrainModel{bands, zonesHrr, trimp, scale, coverage}`;
- `StrainBandEdges{moderate, strenuous, allOut: Double}`;
- `ZoneFloors{z1…z5: Double}`, with `public var all: [Double] { [z1, z2, z3, z4, z5] }`;
- `TrimpCoefficients{a, b}`;
- `StrainScale{k, trimpCap}`;
- `CoverageCuts{medium, high}`;
- `SleepConstants{performanceBands, consistencyBands, efficiencyBands}`;
- `WorkoutOverlap{recordedHiddenOverlap, effortHiddenOverlap}`.

The doc comment on `ScoreConstants` is: "The engine's numbers (contract §5.1.1). Nil when the Mac predates them; never substitute values."

New optional properties, each nil against an older Mac:
- `scoreConstants: ScoreConstants?`, after `scoreConfig` in `Day`, `Sleep` and `HeartRateBody`;
- `efficiencyBand: Band3?`, after `efficiencyPct` in `SleepSummary` and `Sleep`;
- `StageTypical`: `nightsNeeded`, `lowPercentile`, `highPercentile: Int?` after `nightsUsed`;
- `SleepPlan`: `nightsNeeded`, `windowNights: Int?` after `nightsUsed`;
- `Vitals`: `valuesNeeded: Int?` after `metricsWithRange`.

### 5.2 Estimates the phone computes (step E2)

| Unit | Change | Without `score_constants` |
| --- | --- | --- |
| `StrainMath` | `strain(trimp:scale: StrainScale)`, `zone(bpm:rest:maximum:zones: ZoneFloors)`, `trimp(bpm:rest:maximum:model: StrainModel)`, and new `confidence(covered: Int, expected: Int, cuts: CoverageCuts) -> Confidence?`. Formulas are those of §3.1. `confidence` is nil when `expected == 0`; otherwise the ratio `≥ high` is `.high`, `≥ medium` is `.medium`, else `.low`. The old profile and literal versions are deleted. The `21` in `strain` stays, with the comment `// contract §5.4: Strain is 0 to 21`. | n/a |
| `ZoneScale` (new, `Presentation/ZoneScale.swift`) | `public init?(rest: Double?, maximum: Double?, zones: ZoneFloors?)` is nil when any input is nil or `maximum <= rest`. `public func range(_ zone: Int) -> String`: with `e = zones.all.map { Int(ceil(rest + $0 * (maximum - rest))) }`, zone 0 is `"<e[0]"`, zones 1–4 are `"e[z-1]–(e[z] − 1)"` and zone 5 is `"e[4]+"`. | type is nil |
| `LiveEstimator` | `init(restingHR:maximumHR:model: StrainModel?)` replaces the profile init, and `profile` and `static strain(trimp:)` are removed. `zone`, `estimate` and `range` need the model as well as the rates. `range(zone:)` returns `ZoneScale(...)?.range(zone)` for zones 0–5, and `"—"` otherwise or without a scale. `LiveEstimate` gains `scale: StrainScale?`, set to `model.scale` whenever the model and rates exist. | strain, TRIMP and zone nil; range `—`; average and max still shown |
| `SessionTarget.projected` | `projected(liveTrimp: Double?, scale: StrainScale?)`, nil when either is nil. The callers are `ActivityContentState.swift:27`, `LiveActivityScreen.swift:22` and `ActivityController.swift:173`; each passes `estimate?.scale`. | no projected Day Strain and no target crossing |
| `WindowEstimator` | uses `heartRate.scoreConstants?.strain`; the guard at `:36` also requires it | strain, TRIMP and zones nil; average, peak, coverage and elapsed still computed. The edit preview shows STRAIN `—` |
| `WorkoutProjection` `:23` | `confidence = estimate.strain == nil ? nil : heartRate.scoreConstants.flatMap { StrainMath.confidence(covered: estimate.covered, expected: estimate.expected, cuts: $0.strain.coverage) }` | nil |
| `OverlapRules.apply` | gains `rules: WorkoutOverlap?`. A recorded row is hidden when `overlap > 0 && overlap >= rules.recordedHiddenOverlap × min(both durations)`. A detected row is hidden when `covered >= rules.effortHiddenOverlap × duration`. `Overlay.apply(_:to:)` passes `snapshot.day.scoreConstants?.workouts`, and `apply(_:date:day:workouts:)` passes `day.scoreConstants?.workouts`. | nothing is hidden until the Mac answers |
| `LocalActivity.isFinal` | `workout.confidence == .high \|\| now.timeIntervalSince(upload.end) > 6 * 3600` | unchanged; `confidence` is sent by every Mac |
| `ActivityController.updateRates` | `LiveEstimator(restingHR:…, maximumHR:…, model: day?.scoreConstants?.strain)` | see `LiveEstimator` |
| `GoopZoneRows` | gains `var floors: ZoneFloors?` after `maximum`; `range(_:)` returns `ZoneScale(rest:maximum:zones: floors)?.range(zone)`. `StrainScreen.swift:62`, `WorkoutScreen.swift:33` and `ComponentGallery.swift:227` pass the bundle's `day.scoreConstants?.strain.zonesHrr`. | no bpm range under the zone names, as today without rates |
| `WorkoutScreen.swift:129` | `if let coverage = workout.hrCoverage, let confidence = workout.confidence, confidence != .high` | unchanged |

**Live estimator, first run and offline (D6).** The estimator is built from the cached snapshot, so it works offline as long as one snapshot from an updated Mac has been cached. With no snapshot it has no rates and no model, so the live screen shows heart rate, average and max with Strain and zone `—`, as it does today. The trade-off: a phone whose cached snapshot came from an older Mac also shows no live Strain until the Mac is updated and one refresh succeeds. We accept that rather than keep a fallback copy.

### 5.3 Text and scales (step E3)

**Levels** (`Presentation/Levels.swift`):
- Delete `enum Levels`, `LevelScale.Band.lower`, `LevelScale.index(_ value:)` and the five static scales.
- Add:
  - `SleepLevel.init?(_ band: Band3?)`: `.high` is `.optimal`, `.medium` is `.sufficient`, `.low` is `.poor`, anything else is nil;
  - `static func recovery(_:)`, `strain(_:)`, `hours(_:)`, `consistency(_:)` and `efficiency(_:)`, each taking `ScoreConstants?` and returning a `LevelScale`;
  - `static func index(_ band: Band3?) -> Int?` (low 0, medium 1, high 2);
  - `static func index(_ band: StrainBand?) -> Int?` (light 0 … all out 3).
- Band names and tones do not change.
- Ranges, from edges `m < h` (integer scales) or `d < s < a` (Strain):

| Scale | Ranges | Default | Odd fixture (§6) |
| --- | --- | --- | --- |
| Recovery | `0–(m−1)`, `m–(h−1)`, `h–100` | `0–33`, `34–66`, `67–100` | `0–39`, `40–69`, `70–100` |
| Hours, Consistency, Efficiency | the same with `%` | Hours `0–69%`, `70–84%`, `85–100%`; Consistency `0–59%`, `60–79%`, `80–100%`; Efficiency `0–84%`, `85–89%`, `90–100%` | Hours `0–74%`, `75–89%`, `90–100%`; Consistency `0–64%`, `65–84%`, `85–100%`; Efficiency `0–87%`, `88–92%`, `93–100%` |
| Strain | `0–t(d−0.1)`, `t(d)–t(s−0.1)`, `t(s)–t(a−0.1)`, `t(a)–21`; `t(x)` is `x` to 1 dp, with no decimal when whole | `0–9.9`, `10–13.9`, `14–17.9`, `18–21` | `0–10.9`, `11–15.4`, `15.5–18.9`, `19–21` |

With no constants, every range is `—`.

**Call sites.**
- Recovery sheet: `GoopLevelHeader(scale: .recovery(day.scoreConstants))`, and `GoopLevelScale(scale: .recovery(day.scoreConstants), current: LevelScale.index(recovery.band), …)`.
- Strain sheet: likewise with `.strain`, `strain.band` and `day.scoreConstants`.
- Sleep sheet (`SleepScreen.swift:169-172`): the scales take `sleep.scoreConstants`, where `sleep` is the sleep body. `current` is `LevelScale.index` of `sleep.performance.band`, `sleep.consistency.band` and `sleep.efficiencyBand`.
- Sleep dial and rows (`SleepScreen.swift:14`, `:17`, `:19`, `:21`) use `SleepLevel(…band)` with the same three bands, from `day.sleep`.
- `Insights.sleep` uses `SleepLevel(sleep.performance.band)`.

**Sentences.** New Core file `Presentation/EngineText.swift`, `public enum EngineText`. `n(x)` below is `GoopFormat.number(x, decimals: x is whole ? 0 : 1)`.

| Function | With the number | Without it |
| --- | --- | --- |
| `penaltyNote(_ c: ScoreConstants?)` | `Breathing rate and skin temperature only subtract, up to n(penaltyMax) points each, when they run above usual.` | `Breathing rate and skin temperature only subtract when they run above usual.` |
| `calibrationNote(_ c: Calibration)` | `<values_needed> nights to start · <values_for_full_confidence> for full confidence` | always sent |
| `calibrationFill(_ c: Calibration) -> Double` | `min(nightsUsed, full) / full`; 0 when `full <= 0` | |
| `calibrationTick(_ c: Calibration) -> Double?` | `needed / full`; nil when `full <= 0` or `needed >= full` | |
| `comparisonNote(_ c: Comparison?)` | `Arrows compare today with your average over the <window_days> days before it. Green and orange show the usual direction for that measure; they are not medical advice.` | `Arrows compare today with your recent average. Green and orange show the usual direction for that measure; they are not medical advice.` |
| `comparisonLegend(_ c: Comparison?)` | `vs. prior <window_days> days` | `vs. your average` |
| `comparisonSpoken(_ windowDays: Int?)` | `versus prior <n> days average` | `versus prior average` |
| `typicalNote(_ t: StageTypical?)` | `Typical ranges are the middle <high − low>% of your last <window_nights> nights with sleep stages (shown after <nights_needed> such nights).` | new fields nil: `Typical ranges come from your last <window_nights> nights with sleep stages.` `t` nil: `Typical ranges come from your recent nights with sleep stages.` |
| `uploadedNote(collectorMinutes: Int?)` | `Live estimate. Final Strain arrives when your band syncs with your Mac, usually within <n> minutes.` | `Live estimate. Final Strain arrives when your band syncs with your Mac.` |

Existing functions that change:

| Function | With the number | Without it |
| --- | --- | --- |
| `Insights.recovery`, line 7 | `Recovery is calibrating: <nightsUsed> of <values_needed> nights so far. It starts once ghoops has <values_needed> nights of your HRV and resting heart rate.` | always sent |
| `ReasonText.score(_:status:calibration: Calibration? = nil)` (replaces `nights:`) | `insufficientBaseline`: `Calibrating: <nightsUsed> of <values_needed> nights`. `insufficientNights`: `Not enough nights yet` | `Calibrating` |
| `Insights.strain(…, constants: ScoreConstants?)`, a new last parameter with no default | band sentences: `Strain under g(d) is considered light.`, `Strain between g(d) and g(s−0.1) is considered moderate.`, `Strain between g(s) and g(a−0.1) is considered strenuous.`, `Strain of g(a) or more is considered all out.`, where `g` is 1 dp. The hardest-workout sentence uses `strain ≥ d`. The coverage sentence needs `confidence != .high`. | the band sentence and the hardest-workout sentence are left out |
| `HealthState.sentence` (stores `vitals.valuesNeeded`) | `ghoops needs <n> nights to learn your ranges.` | `ghoops is still learning your ranges.` |
| `SleepPlanText.unavailable(_ plan: SleepPlan) -> String` (was a constant) | `Tonight's plan needs at least <nights_needed> nights of sleep from the last <window_nights>.` | `Tonight's plan needs more nights of sleep.` |
| `SleepPlanText.placeholder(_ plan: SleepPlan) -> String` (new) | `Needs <nights_needed> nights of sleep to plan tonight.` | `Needs more nights of sleep to plan tonight.` |

With default numbers every sentence reads exactly as today, except `typicalNote`: "the middle half" becomes "the middle 50%".

**Call sites.**
- Delete `GoopNotes` (`GoopDetailSupport.swift:110-113`).
  - `RecoveryScreen.swift:85` and `StrainScreen.swift:75` use `EngineText.comparisonNote(day.comparison)`.
  - `SleepScreen.swift:173` uses `EngineText.typicalNote(sleep.stageTypical)`.
- `RecoveryCalibration` (`RecoveryScreen.swift:45-60`): the bar fill uses `calibrationFill`. The white tick sits at `geometry.size.width * tick − 1` and is left out when `calibrationTick` is nil. The footnote is `calibrationNote`.
- `RecoveryScreen.swift:77` uses `EngineText.penaltyNote(day.scoreConstants)`.
- `GoopCards.swift:20` and `Insights.swift:9` pass `calibration: recovery.calibration`.
- `StrainScreen.swift:25` passes `constants: day.scoreConstants`.
- `GoopLegend` gains `let windowDays: Int?`. A `let` with no default makes every caller pass it. `RecoveryScreen.swift:20` and `StrainScreen.swift:21` pass `bundle?.day.comparison?.windowDays`, `SleepScreen.swift:22` passes nil, and `ComponentGallery` passes 30. The legend text is `comparisonLegend`.
- `GoopMetricRow` gains `let windowDays: Int?` directly after `mean`. Every caller passes the day's `comparison?.windowDays`, and `ComponentGallery` passes 30. The spoken direction uses `comparisonSpoken`.
- `SleepScreen.swift:138` uses `SleepPlanText.unavailable(plan)`, and `GoopTonightCard.swift:46` uses `SleepPlanText.placeholder(plan)`.
- `ActivityController`: `configure(day:collectorMinutes:api:fixture:now:)` and `updateRates(_:collectorMinutes:)` store `collectorMinutes`, and line 139 uses `EngineText.uploadedNote`. `AppModel.swift:124` and `:330` pass `snapshot.status.collector.intervalMinutes`.

## 6. Fixtures

- **Go goldens.** `$GO test ./internal/v2report -update-goldens` regenerates every golden that carries `score_config`: 29 files, the 32 of `grep -rl '"score_config"' fixtures/v2` minus the 3 preview files. They may only gain keys: `score_constants` after `score_config`, and the §3.2 fields. Plan E1 gives a script that checks this. Brief goldens do not change. Any other diff: stop and tell the lead.
- **Preview fixtures.** `scripts/goop_preview_fixtures.py` gains `add_engine_fields(body, full)`. `update()` runs it last on each body, and every value comes from `fixtures/v2/day_full.json`, so Python holds no copy:
  1. Any dict with `score_config` and no `score_constants` gets `full['score_constants']` inserted after `score_config`.
  2. Any dict with `metrics_with_range` and no `values_needed` gets `full['vitals']['values_needed']` after it.
  3. Any dict with `efficiency_pct` and `consistency` and no `efficiency_band` gets one after `efficiency_pct`: `high` at or above `full['score_constants']['sleep']['efficiency_bands']['high']`, `medium` at or above `medium`, else `low`, and null for a null value.
  4. Any `sleep_plan` dict without `nights_needed` gets `nights_needed` and `window_nights` from `full['sleep_plan']` after `nights_used`.
  5. Any `stage_typical` dict without `nights_needed` gets `nights_needed`, `low_percentile` and `high_percentile` from `full['sleep']['stage_typical']` after `nights_used`.
- **`fixtures/v2/engine/odd_constants.json`** (new, synthetic, hand-made, `"synthetic_fixture": true`). Every number differs from the default. The bands are chosen so the fresh fixture's bands stay the same, so the fixture is a consistent Mac whose constants changed:

  ```json
  {
    "synthetic_fixture": true,
    "score_constants": {
      "recovery": { "bands": { "medium": 40, "high": 70 }, "penalty_max": 8 },
      "strain": {
        "bands": { "moderate": 11, "strenuous": 15.5, "all_out": 19 },
        "zones_hrr": { "z1": 0.35, "z2": 0.55, "z3": 0.65, "z4": 0.75, "z5": 0.9 },
        "trimp": { "a": 0.7, "b": 2.0 },
        "scale": { "k": 12, "trimp_cap": 800 },
        "coverage": { "medium": 0.6, "high": 0.9 }
      },
      "sleep": {
        "performance_bands": { "medium": 75, "high": 90 },
        "consistency_bands": { "medium": 65, "high": 85 },
        "efficiency_bands": { "medium": 88, "high": 93 }
      },
      "workouts": { "recorded_hidden_overlap": 0.6, "effort_hidden_overlap": 0.4 }
    },
    "calibration": { "values_needed": 4, "values_for_full_confidence": 12 },
    "vitals_values_needed": 9,
    "sleep_plan": { "nights_needed": 4, "window_nights": 21 },
    "stage_typical": { "window_nights": 28, "nights_needed": 6, "low_percentile": 20, "high_percentile": 80 },
    "comparison_window_days": 28,
    "collector_interval_minutes": 20
  }
  ```

  The window and percentile changes do not recompute the fixture's means and ranges. They exist only to prove the app prints what the Mac sends. Record this in the fixture README.
- **App bundle.** `ios/project.yml` "Copy debug fixtures" adds `Fixtures/engine`, in the same form as the `recovery` lines.
- **Fixture sets** (`Fixtures/FixtureLoader.swift`) gain `engineOdd = "engine_odd"` and `engineNone = "engine_none"`. Both start from `snapshot_fresh`.
  - `engine_odd` decodes `engine/odd_constants.json` into an internal `EngineFixture` and sets:
    - `day.scoreConstants` and `sleep.scoreConstants`;
    - both `day.recovery.calibration` counts;
    - `day.vitals.valuesNeeded`;
    - `day.sleepPlan`'s two fields;
    - the four `stageTypical` fields in `day.sleep` and in `sleep`;
    - `day.comparison.windowDays`;
    - `status.collector.intervalMinutes`.
  - `engine_none` sets every §5.1 property to nil: both `scoreConstants`, both `efficiencyBand`, `valuesNeeded`, the plan's and both stage-typical new fields. It stands in for an older Mac.
- `fixtures/v2/README.md` gains an "Engine numbers" section describing the above.

## 7. Tests and the check

**Go** (`make check`):
- `TestReportedConstantsReproduceTheEngine` (new, `internal/score`). Using only `ConstantsFor("banister_b192")`, a test-local reference does the following:
  - It classifies and sums each `fixtures/v2/scores/strain.json` case with `zones_hrr`, `trimp` and `scale`, and bands it with `bands`. The result must equal the case's `zones_minutes`, `trimp`, `strain` and `band`.
  - `recovery.json` bands equal the reference band from `recovery.bands`, and every penalty is ≤ `penalty_max`.
  - `sleep.json` performance and consistency bands equal the reference bands.
  - `confidence` equals the reference at 0.49, 0.50, 0.79 and 0.80.
  - `goopHidesRecorded` is true at exactly `recorded_hidden_overlap` of the shorter window and false one second below.

  For `"banister_b167"`, `ConstantsFor` reports `{0.86, 1.67}`, and `ComputeMinutes` of the `boxing_hour` case equals the reference with those coefficients. The test fails if a formula and the report ever use different numbers.
- `TestEfficiencyBand` (new): `EfficiencyBand` of nil, 84, 85, 89 and 90 gives nil, low, medium, medium and high.
- `TestScoreConstantsTravelWithScoreConfig` (new, `internal/v2report`). For every body that `TestGoldenResponses` builds, `score_constants` is present exactly when `score_config` is, and equals `score.ConstantsFor(cfg.TrimpProfile)`. A builder with `trimp_profile: banister_b167` reports `strain.trimp` `{0.86, 1.67}`.

**Python** (`make check`). In `scripts/goop_preview_fixtures_test.py`, `remove_parity` also pops `score_constants`, `values_needed`, `efficiency_band`, `nights_needed`, `low_percentile` and `high_percentile`. After `update`, each snapshot's `score_constants` equals `day_full.json`'s, and `day.sleep.efficiency_band` is `high`.

**GHealthCore** (`make ios-core-test`). New file `EngineNumberTests.swift`. "Default" means `day_full.json`'s `score_constants`; "odd" means `engine/odd_constants.json`.

| Test | Asserts |
| --- | --- |
| `liveEstimatorUsesTheMacsStrainModel` | Rest 56 and max 187. Samples at `start + i×60 s` with bpm `[100, 100, 130, 130, 150, 150, 175, 175, 90, 160]`, `now = start + 600 s`. **Default:** zones `[1, 2, 2, 0, 3, 2]` (below…z5), TRIMP 15.6, Strain 4.6, zone 4, ranges `<96`, `96–121`, `122–134`, `135–147`, `148–167`, `168+`. **Odd:** zones `[3, 0, 2, 2, 1, 2]`, TRIMP 17.2, Strain 4.4, zone 4, ranges `<102`, `102–128`, `129–141`, `142–154`, `155–173`, `174+`. **No model:** Strain, TRIMP and zone nil, range `—`, average 136, max 175. |
| `projectedDayStrainUsesTheMacsScale` | `SessionTarget(cycleDate: "2026-03-10", baseTrimp: 124.1, low: 13.3, high: 16.3)`. `projected(liveTrimp: 15.6, scale: default)` is 13.3; `(17.2, odd)` is 12.7; `scale: nil` is nil. |
| `windowEstimateUsesTheMacsModel` | Decode `edits/heart_rate_tue.json` and set `restingHrBpm` 56, `maxHrBpm` 187 and `minutes` to five minutes at `start + 0…4 min` with `avgBpm` `[100, 130, 150, 175, 160]` and `maxBpm` equal to them. The window is `start … start + 6 min`. **Default:** zones `[0, 1, 1, 0, 2, 1]`, TRIMP 9.0, Strain 3.2, coverage 0.83. **Odd:** zones `[1, 0, 1, 1, 1, 1]`, TRIMP 10.0, Strain 3.0, coverage 0.83. **No `scoreConstants`:** Strain, TRIMP and zones nil; average 143, peak 175 and coverage 0.83 still set. `StrainMath.confidence(covered: 5, expected: 6, cuts:)` is `high` with default cuts and `medium` with odd. `WorkoutProjection.project(editWorkout("unedited"), body: EditBody(), window: ActivityWindow(start: start, end: start + 6 min), heartRate: body, now: start + 6 min)` gives `confidence` `high`, `medium` and nil for the three bodies (`editWorkout` is the EditTests.swift helper). |
| `overlapRulesUseTheMacsShares` | One cycle date, all windows 60 minutes, recorded 18:00–19:00. Goop 18:33–19:33 (27 min overlap): recorded kept at default 0.5 and at odd 0.6. Goop 18:27–19:27 (33 min): hidden at 0.5, kept at 0.6. Goop 18:24–19:24 (36 min): hidden at both. A 40-minute detected effort that the visible windows cover for 18 minutes: kept at 0.5, hidden at odd 0.4. `rules: nil` hides nothing in any of these. |
| `scalesUseTheMacsEdges` | The five scales' ranges for default, odd (§5.3 table) and nil (all `—`). `LevelScale.index` and `SleepLevel` of every `Band3` and `StrainBand` case. |
| `sentencesUseTheMacsNumbers` | Every `EngineText` function; `Insights.recovery` and `ReasonText.score` with `day_new_user.json`'s recovery (`insufficient_baseline`, 3 values); `Insights.strain` with the fresh day; `HealthState.sentence` with `day_new_user.json`'s vitals and `metricsWithRange` set to 0; and `SleepPlanText.unavailable` and `.placeholder` with the fresh plan. For the odd case, the test copies the fixture's counts onto those bodies as `engine_odd` does (§6). Each gives the exact strings of §5.3 for default, odd and missing. With odd: `up to 8 points each`, `4 nights to start · 12 for full confidence`, `Strain between 11.0 and 15.4 is considered moderate.`, `vs. prior 28 days`, `the middle 60% of your last 28 nights … (shown after 6 such nights)`, `ghoops needs 9 nights to learn your ranges.`, `needs at least 4 nights of sleep from the last 21.`, `usually within 20 minutes`. `calibrationFill` is 1.0 and `calibrationTick` is 1/3. |
| `defaultsNeverLeakIntoOddOutput` | Join every string the two tests above produce with the odd fixture. It contains none of: `0–33`, `34–66`, `67–100`, `9.9`, `13.9`, `17.9`, `10.0`, `14.0`, `18.0`, `7 nights`, `14 for full`, `10 points`, `30 days`, `30 nights`, `middle half`, `<96`, `168+`, `3 nights`, `last 14`, `within 30`. |
| `olderMacBodiesDecode` | `preview/snapshot_fresh.json` and `edits/heart_rate_tue.json` decode with every §3 key removed. All new properties are nil and every other value is unchanged. |

Existing tests:
- `ActivityTests.liveEstimatorMatchesAllGoVectorsAndScale`, `liveZonesPartialBucketPauseAndMissingRates` and `EditTests`' `WindowEstimator` and `trimp_to_strain` checks build the model from `day_full.json`'s `score_constants`. Their expected values do not change.
- `ChangeTests`' `OverlapRules` calls pass the default rules.
- `ParityTests.levelScalesPlaceValuesInTheirBand` becomes band-index checks.
- `GoopPresentationTests` drops the `Levels.*` value checks in favour of `SleepLevel(band)`.

**UI** (`ios/GHealthUITests/GHealthUITests.swift`). `testEngineNumbersFromMac` (new) runs two launches.
- **`engine_odd`**:
  - Recovery page: the static text `vs. prior 28 days` exists (the legend).
  - Recovery sheet: `scale-recovery` is `Low 0–39, Medium 40–69, High 70–100. Today: High`. Static texts `Breathing rate and skin temperature only subtract, up to 8 points each, when they run above usual.` and `4 nights to start · 12 for full confidence` exist.
  - Strain sheet: `scale-strain` is `Light 0–10.9, Moderate 11–15.4, Strenuous 15.5–18.9, All Out 19–21. Today: Moderate`. A zone row shows `155–173`.
  - Sleep sheet: `scale-hours` is `Hours vs. needed, 93%. Poor 0–74%, Sufficient 75–89%, Optimal 90–100%. Today: Optimal`, and `scale-efficiency` is `Efficiency, 95%. Poor 0–87%, Sufficient 88–92%, Optimal 93–100%. Today: Optimal`.
  - Capture `engine-odd-recovery`, `engine-odd-strain` and `engine-odd-sleep`.
- **`engine_none`**:
  - `scale-recovery` is `Low —, Medium —, High —. Today: High`.
  - The footnote `Breathing rate and skin temperature only subtract when they run above usual.` exists.
  - `scale-efficiency` is `Efficiency, 95%. Poor —, Sufficient —, Optimal —`.
  - Capture `engine-none-recovery` and `engine-none-sleep`.
- `testExplanationSheets` (fresh) keeps every assertion and adds one: on the Sleep sheet, a static text exists whose label ends `the middle 50% of your last 30 nights with sleep stages (shown after 7 such nights).`

**Lint rule `enginenumber`** (`scripts/goop_lint.py`):
- **Files.** The loop adds `ios/GHealthCore/Sources/GHealthCore`. Files under `ios/GHealthCore/` run only `enginenumber`; the existing rules keep their current files. `enginenumber` skips `ios/GHealth/Debug/` and `ios/GHealthCore/Sources/GHealthCore/Fixtures/`.
- **What counts.** On a line that does not start with `//`, take each string literal found by the existing `STRING` pattern. Remove each `\(` … `)` interpolation by counting parentheses to any depth, then remove every other backslash escape. The literal is one finding when what remains does either of these:
  - it contains whitespace and a number, matching `(?<![\w.%$])\d+(?:\.\d+)?(?!\w)`;
  - it contains a digit, an en dash and a digit, matching `\d\s*–\s*\d`.
- **Running it.** The output line is `<path>:<line>: enginenumber: <text>`, the existing `// goop-lint: allow enginenumber: <reason>` marker exempts a line, and there is no baseline entry.
- **Probe result.** Run against `133212f` (a probe in this design run), the rule reports 35 findings:
  - 24 are §2.1 copies, which E3 removes: C5, C6, C7, C4, C9, C8, R3, R6, R4, B6 (4), B1 (3), B2 (4), C1, R5, C2 and C3.
  - 11 get an allow marker in E4, with the reason in brackets:
    - `AppModel.swift:223` and `:229` (HTTP status and round-trip time);
    - `GoopTrendComponents.swift:101` (trend window);
    - `LiveActivityScreen.swift:71` (zone names, contract §5.10);
    - `GoopMoreScreen.swift:54` (licence version);
    - `SleepScreen.swift:168` (schema: performance is 0 to 100, contract §5.5);
    - `ScoreRing.swift:16` (schema: Strain is 0 to 21, contract §5.4);
    - `ChangeTiming.swift:15` (a count of one);
    - `Coding.swift:14` (standard name);
    - `TrendMetricKey.swift:20` and `:21` (zone names).
- **Lint tests** (`scripts/goop_lint_test.py`). `test_each_rule_fires_once` gains `"enginenumber": 'Text("7 nights to start")'`. A table test checks these lines in `ios/GHealth/Sample.swift`, plus one Core and two skipped paths:

  | Line or path | Findings |
  | --- | --- |
  | `GoopFootnote(text: "7 nights to start · 14 for full confidence")` | 1 |
  | `Text("Strain under 10.0 is considered light.")` | 1 |
  | `Band(name: "LOW", range: "0–33", tone: .recoveryLow)` | 1 |
  | `Text("\(GoopFormat.number(v, decimals: 1)) of 21")` | 1 |
  | `Text("\(needed) nights to start · \(full) for full confidence")` | 0 |
  | `Text("Last: \($0.formatted(.dateTime.weekday(.abbreviated)))")` | 0 |
  | `Text("ZONE \(zone)")`, `Text("Zones \(a)–\(b)")` | 0 |
  | `Image(systemName: "gauge.with.dots.needle.33percent")`, `let day = "2026-03-10"`, `String(format: "%d:%02d", h, m)` | 0 |
  | `// Strain under 10.0 is light` | 0 |
  | the first line, in `ios/GHealthCore/Sources/GHealthCore/Sample.swift` | 1 |
  | the first line, in `ios/GHealthCore/Sources/GHealthCore/Fixtures/Sample.swift` and in `ios/GHealth/Debug/Sample.swift` | 0 |
  | `Image(systemName: "x")` in the Core sample (other rules skip Core) | 0 |

**What the check can't catch.** The lint sees only string literals. It misses:
- a number in code (`>= 10`, `0.85`, `min(n, 14)`);
- a number inside an interpolation;
- a number spelled as a word ("half", "a week");
- a constant held in a variable and then interpolated.

`EngineNumberTests` catches those only on the paths it drives. A new screen or function that copies an engine number through code is caught by neither; review against the AGENTS.md rule is the remaining guard.

## 8. Rule text

**AGENTS.md**, in "Hard rules", after the bullet about specs winning over code:

> - The app never hard-codes a score-engine number. Every band edge, zone edge, formula constant, window and minimum count that `internal/score` uses reaches the app from the Mac, in `score_constants` or in the field beside the score. When the Mac sends none, the app shows `—` or leaves the sentence out, and never falls back to a copy. Field ranges, precision and names that contract.md fixes (Strain 0 to 21, percentages 0 to 100, 1 dp) are schema, not engine numbers. The goop lint's `enginenumber` rule and `EngineNumberTests` enforce this ([engine-numbers-spec.md](docs/goop/engine-numbers-spec.md)).

**DESIGN.md**, in Do's and Don'ts → Don't, after the line added by #10:

> **Don't** type a score-engine number, such as a band edge, a zone edge, a window or a minimum count, into a label, footnote or sentence. Build it from the Mac's value, and leave it out when the Mac sends none (AGENTS.md).

## 9. Product calls for the lead, and follow-ups

Calls in this spec:
1. **D4.** The Sleep Efficiency cut-offs (85, 90) become engine numbers, and the Mac sends `efficiency_band`. The alternative is to keep them app-owned and allow-listed.
2. **The one wording change with an updated Mac.** The typical-range footnote says "the middle 50%" instead of "the middle half" (§5.3).
3. **The older-Mac fallbacks** (§5.2 and §5.3):
   - ranges `—`;
   - sentences without their number clause;
   - no live Strain, zone or projected Day Strain;
   - edit preview Strain `—`;
   - no overlay hiding until the Mac answers.

   Installing the Mac first avoids all of them.
4. **The fallback wordings:**
   - "vs. your average";
   - "Arrows compare today with your recent average.";
   - "ghoops is still learning your ranges.";
   - "Tonight's plan needs more nights of sleep.";
   - "Needs more nights of sleep to plan tonight.";
   - "Not enough nights yet".
5. **`isFinal` reads `confidence`.** A Mac workout with coverage but no Strain (resting or max heart rate unknown) no longer replaces the phone's live entry before 6 hours. Both entries show Strain `—` in that case.

Follow-ups, not in this issue:
- The request limits of D8 could travel in `status` so the edit sheet never offers what the Mac will reject. Filed as #13.
- Existing bug: the Live Activity reads "NO HR" when heart rate is live but the zone is unknown (`GoopLiveActivityView.swift:65`). That happens today without resting or max heart rate, and after this spec also against an older Mac. Filed as #12.

## 10. Lead decisions (2026-11-16)

- **Decisions D1 to D10** are approved as written.
- **Calls 1 to 5 in §9** are approved as written:
  - the efficiency cut-offs move into the engine;
  - "the middle 50%";
  - the older-Mac fallbacks and their wordings;
  - `isFinal` reads `confidence`.
- **Install order.** The lead installs the Mac before the phone for this change, so the owner never sees the older-Mac fallbacks.
- **Strain review.** This matters for #6, the owner's Strain constants review. Once this lands, a change to `StrainK` or `StrainTrimpCap` on the Mac reaches the live estimator and the edit preview, with no app release.
- **Follow-ups** are filed as #12 (NO HR) and #13 (request limits).
