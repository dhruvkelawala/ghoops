# ghoops: Parity pack 1

Status: design spec, written 2026-11-13 from the owner decisions on [whoop-parity.md](whoop-parity.md) §3, gaps 1 to 5 (commit `af88241`). The build plan is [parity1-plan.md](parity1-plan.md). It builds after activity editing ([edit-spec.md](edit-spec.md)) has gone live at step E12.

This pack adds five things the owner meets every day:
- **Strain target.** A Strain range for the day, from the morning's Recovery and a Mac setting for intent. It shows in the Strain insight, on the live activity screen and in the Live Activity. When the live estimate enters the range, the phone plays a haptic and the Live Activity alerts.
- **Sleep planner.** Tonight's need, turned into a time in bed and a bedtime for three goals. It shows on Sleep detail, in the Sleep info sheet and as a `BED BY` line on the Lock Screen widget.
- **Brief outlook.** `ghoops brief` gains a morning or evening part, 7-day against 30-day trends, the target, the plan and an evening review, for assistants.
- **Sport suggestion.** A detected effort that matches the owner's usual sport for that weekday and time gets that sport preselected when the owner names it.
- **HRV widget.** HRV in the small widget, the circular Lock Screen widget and as a line on the rectangular one.

All scores stay on the Mac. The one new computation on the phone is the projected Day Strain, labelled as an estimate (§5.2).

## 0. Precedence and owner decisions

- This spec extends [contract.md](../v2/contract.md), [scores.md](../v2/scores.md), [spec.md](spec.md), [activity-spec.md](activity-spec.md), [edit-spec.md](edit-spec.md), [DESIGN.md](../../DESIGN.md) and [PRODUCT.md](../../PRODUCT.md). Where they disagree, this spec wins for the features described here. Step P2 updates those documents (§6.7).
- **Mockups:** [mockups/parity1.html](mockups/parity1.html), one screen per key with `?screen=<key>`, rendered in `mockups/screens/parity1-<key>.png`:

  | Key | Screen |
  | --- | --- |
  | `strain-target` | Strain detail. The insight card starts with the target sentence. |
  | `live-target` | Live activity screen with `EST. DAY STRAIN` and `TARGET` under the dial, projection below the target |
  | `lock-live` | Lock Screen Live Activity with the projection inside the target |
  | `sleep-plan` | Sleep detail scrolled to the end, with the `TONIGHT'S SLEEP` card under the need card |
  | `sleep-info` | Sleep info sheet, Need section with tonight's arithmetic |
  | `lock` | Lock Screen: rectangular widget with `BED BY`, circular HRV; second row: the rectangular widget's HRV line |
  | `hrv-widget` | Small HRV widget: within range, below range, building baseline, beside the Recovery widget |
  | `sport-suggest` | Edit sheet's Sport sub-step for a detected effort, with the usual sport preselected |

  The renders use fictional values: Boxing 18:05–19:02, Day Strain 12.8, Recovery 59 (medium), so the target is 11.6–14.6. Layout, sizes, colours, type and icons must match. Fixture values differ, and that is expected.
- **Owner decisions (2026-11-13), fixed:**
  1. **Strain target.** The formula and constants of whoop-parity.md gap 1 as written: centre `6.0 + 0.12 × recovery`, intent offsets restore −3, maintain 0, overreach +2, band ±1.5. Mac setting `strain_intent`, default `maintain`. First slice only: the insight sentence; `TARGET low–high` and the projected Day Strain on the live screen and the Live Activity; a success haptic and a Live Activity alert when the projection enters the range; `day.strain_target` in the API and in `brief`. No target band on the Strain ring, and nothing on Home. `score_version` becomes `2.1.0`. The projected Day Strain is the second allowed exception to "the app never computes a score".
  2. **Sleep planner.** Wake time defaults to the typical wake (median of 14 nights); the optional Mac setting `wake_target` overrides it. `day.sleep_plan` as sketched. A `TONIGHT'S SLEEP` card on Sleep detail with goal rows 100, 85 and 70 %. A `BED BY` option on the Lock Screen rectangular widget; widget kinds unchanged. No bedtime notification and no permission prompt.
  3. **Brief.** `part: morning|evening`. `trend` directions always; `mean_7` and `mean_30` only with `--include-values`; `review` in evening mode. `strain_target` and `sleep_plan` status fields, values only with `--include-values`. Assistant updates are an owner follow-up outside the repo (§12).
  4. **Sport suggestion.** Suggestion only, never automatic naming. The sketch's rule: 56 days, same weekday, ±90 minutes, 0.5× to 2× duration, at least 3 matches and at least 60 %. It shows in the edit Sport sub-step as the preselected row with a trailing note (§2.8), and as `suggested` on detected entries in the API and `brief`.
  5. **HRV widget.** A new `hrv` metric for the small widget and the circular Lock Screen widget, and an optional HRV line on the rectangular one. Widget kinds unchanged.
  6. **Rollout.** Each user-visible part ships dark behind its own `GoopFeature` flag; the plan's last step removes the flags. Go fields and CLI land early and additively.
- **Dependencies.** The design cleanup ([design-cleanup-spec.md](design-cleanup-spec.md)) and activity editing through E12 have landed. This spec uses their components and type cases by the names they define (§3). If the code as built differs, use its names and keep the behaviour described here.
- Everything else was decided while writing this spec and is listed in §13.

## 1. Facts this design relies on

- **The phone already has every input.** The cached snapshot's `day` carries `recovery`, `strain` (with `trimp`, `resting_hr_bpm`, `max_hr_bpm`, `coverage_until`), `cycle` and `vitals.metrics.hrv_rmssd` (`value`, `range_low`, `range_high`, `position`) and `vitals.monitor_state` and `vitals.persistent`. Widgets read the same snapshot (spec.md §11.1).
- **The live estimator** takes resting and maximum heart rate from `snapshot.day.strain` and shares its TRIMP and strain functions through `StrainMath` (edit-spec §8.1). `LiveEstimate.trimp` is the session's TRIMP at 1 dp.
- **Config is read per request** (`internal/serve`), and every response echoes `config.Values` as `score_config`. `config.File.Load` rejects unknown keys (`DisallowUnknownFields`), so an older binary refuses a config file that holds a newer key.
- **The coming night has no need value today.** `sleep --date` refuses future dates, and `day.sleep.need` is the need for the night ending on D (contract §5.5).
- **The cycle** (scores.md §3.1): cycle D runs from the wake that ends night D to the start of cycle D+1. While it is `open`, tonight's sleep is the night ending D+1.
- **Widgets.** `ScoresWidget` (`ScoresIntent.metric`: recovery, strain, sleep, all) and `LockScoresWidget` (`LockScoresIntent.metric`: recovery, strain, sleep). The Lock metric only drives the circular family; the rectangular family always shows SLEEP, RECOVERY and STRAIN; the inline family shows one sentence. Kinds `ScoresWidget` and `LockScoresWidget` must not change (spec.md §17 decision 22).
- **App Intents metadata is static.** The cases of an `AppEnum` and the parameters of a widget intent are extracted at build time into `Metadata.appintents`. A runtime flag cannot hide them, so the widget parts of this pack are gated at compile time (§9).
- **Live Activity height.** iOS may truncate a Lock Screen Live Activity taller than 160 pt. By the font metrics, today's view (spec D in activity-spec §7) already measures about 176 pt, so this pack adds no height to it (§2.3).
- **The Sport sub-step** (edit-spec §2.3, §2.7). A detected effort's pencil opens the Edit sheet with the Sport sub-step showing. `USE <SPORT>` returns to the Edit step, whose commit is `SAVE <SPORT>`. `chevron.left` without `USE` returns with `Choose` and a disabled commit.
- **Retention.** The store keeps 400 days (data.md §3), more than the 56-day suggestion window and the 30-day trend window.
- **`GoopFeature.swift` is gone.** Edit step E12 deleted `ios/GHealth/App/GoopFeature.swift`. Step P8 creates it again for this pack.

## 2. Flows, screen by screen

Times on screen are London `HH:mm` (`GoopFormat.time`), durations `h:mm`, strain 1 dp. Number formats follow spec.md §4.1.

### 2.1 Strain detail (`strain-target`)

The existing Strain screen (spec.md §8.3). Only the insight card's text changes; no new chrome.

1. **Insight text** = the target sentence (§4.1), then the existing strain sentences (spec.md §9.2), joined by a space. Function: `Insights.strain(_:workouts:isToday:target:recoveryBand:)` (§8.2).
2. The target passed in is `day.strain_target` when `GoopFeature.strainTarget` is on, else nil (no sentence, today's text).
3. The dial is unchanged. The mockup shows `SO FAR` because its day is in progress (spec.md §8.3).
4. Nothing changes on Home (spec.md §8.1).

Fixture (`fresh`): `Today's target is 13.3 to 16.3 for high recovery. You are below it. Strain between 10.0 and 13.9 is considered moderate. Your heart worked hardest during kickboxing this afternoon. Strain keeps building until you sleep.`

### 2.2 Live activity screen (`live-target`)

`LiveActivityScreen` (activity-spec §2 step 3). A **target row** sits between the dial and the heart-rate card.

1. **When it shows:** `activity.session?.target != nil` (§5.2, set at start only when `GoopFeature.strainTarget` is on and the snapshot has a target). Otherwise the screen is exactly today's.
2. **Layout** (`LiveTargetRow`, `ios/GHealth/Live/LiveTargetRow.swift`): 14 pt below the dial, 16 pt side margins, the heart-rate card 22 pt below it (unchanged spacing).
   - `HStack(spacing: 0)`: left cell, a 1×40 `cardDivider` rule, right cell. No card or fill behind it.
   - Each cell: `VStack(spacing: 2)`, centred, `frame(maxWidth: .infinity)`. Value in `.goop(.valueLiveStat)` `text1`; caption in `.goop(.labelStat)` `iconMuted`. These are the heart card's stat styles.
   - Left value: the projected Day Strain, 1 dp, or `—` (§5.2). Left caption `EST. DAY STRAIN`. Id `activity-target-estimate` on the value.
   - Right value: `<low>–<high>`, 1 dp each, en dash, no spaces, for example `13.3–16.3`. Id `activity-target-range`.
   - Right caption: `HStack(spacing: 5)`: when the projection is within the target, `GoopSymbol(name: "checkmark", size: 9, color: Goop.Color.positive, weight: .semibold)` (id `activity-target-within`); then `TARGET`.
   - **Within** means `low ≤ projected ≤ high` on the 1-dp values.
3. **Accessibility:** the row is one element, id `activity-target`, label `Estimated Day Strain, <p>. Target <low> to <high>` plus `, reached` when within. With no projection: `Estimated Day Strain, not available. Target <low> to <high>`.
4. Pause and resume do not change the row. While paused, the projection holds its last value, as the dial does.
5. The row updates whenever the estimate updates (every sample).

Fixture (`-GHealthLiveFixture boxing_23m` on `fresh`): target `13.3–16.3`; base TRIMP 124.1 plus the session's TRIMP (about 26.7) gives about `13.7`, so the checkmark shows. The mockup shows the state below the target (no checkmark); record that as the expected difference.

### 2.3 Live Activity (`lock-live`), haptic and alert

`GoopLiveActivityView` (widget extension) and the Dynamic Island expanded view.

1. **Content state** gains `dayStrain: Double?`, `targetLow: Double?`, `targetHigh: Double?` and `targetWithin: Bool?` (§8.4). They are nil when the session has no target.
2. **With a target** (`targetLow` and `targetHigh` non-nil), the bottom row is three equal cells, `HStack(spacing: 0)`, each `frame(maxWidth: .infinity)`, with a 1×23 `plotGrid` hairline between cells:

   | Cell | Value (`.goop(.valueLiveStat)`) | Caption (`.goop(.labelMicro)`, `iconMuted`) |
   | --- | --- | --- |
   | 1 | `strainEstimate`, 1 dp, `strainLight` | `STRAIN` |
   | 2 | `dayStrain`, 1 dp, `text1`, or `—` | `EST. DAY STRAIN` |
   | 3 | `<low>–<high>`, `text1`, `lineLimit(1)`, `minimumScaleFactor(0.8)` | `TARGET`, preceded by `Image(systemName: "checkmark")` at 8 pt semibold in `positive` with 4 pt spacing when `targetWithin == true` |

   The wordmark and `AVG HR` are not shown in this state. The row is no taller than today's (22 pt values instead of 24 pt), so the view gains no height (§1).
3. **Without a target** the view is exactly today's.
4. The Dynamic Island expanded view (`showZone: false`) follows the same rule. Compact and minimal views are unchanged.
5. **Entering the target** (§5.2 `TargetCrossing`): when `SessionTarget.update(projected:)` returns true, `ActivityController`:
   1. calls `activity.update(ActivityContent(state:staleDate: nil), alertConfiguration: AlertConfiguration(title: "Strain target reached", body: "Your Day Strain estimate is <p>, inside today's target of <low> to <high>.", sound: .default))` at once, outside the 2-second throttle (activity-spec §7);
   2. when the app is active, plays `UINotificationFeedbackGenerator().notificationOccurred(.success)`.

   It fires at most once per session. No notification permission is requested; if Live Activities are off, only the haptic remains (when the app is active).
6. The band cannot vibrate (whoop-parity.md §4); nothing is sent to it.

Debug preview: `-GHealthWidgetPreview live_target` renders `LiveActivityPreview` with the state in §10.2.

### 2.4 Sleep detail: `TONIGHT'S SLEEP` (`sleep-plan`)

A new detail card, `GoopTonightCard` (`ios/GHealth/Components/Goop/GoopTonightCard.swift`), on `SleepScreen`.

1. **When it shows:** `GoopFeature.sleepPlanner` is on and the selected date's `day.sleep_plan` is non-null (the cycle is open, §6.3). Past days have no card.
2. **Where:** 12 pt below the need card. When the day has no sleep yet (the placeholder branch of `SleepScreen`), 12 pt below the last placeholder card. The 30 pt bottom spacer follows it.
3. **Card:** `GoopCard` (padding 16), id `tonight-card`.
   1. **Title row**, as the need card's: `TONIGHT'S SLEEP` (`labelCard`) and an `info.circle` 19 pt `iconMuted` button in a 44×44 target (id `tonight-info`, label "How tonight's sleep is planned") that opens the Sleep info sheet.
   2. **Key row**, 16 pt below, inset 10 pt each side: left `NEED` (`labelSmall` `textSoft`) + 4 pt + `need_minutes` as `h:mm` (`valueSmall` `text1`, id `tonight-need`); right `WAKE` + `wake_target` as `HH:mm` (id `tonight-wake`). At accessibility sizes the two stack, leading, 8 apart, as the sleep card's footer does.
   3. **Goal strip**, 12 pt below: `legendFill`, radius `Goop.Metric.radiusLegend` (8), padding 6 vertical and 14 horizontal, built like the need legend (spec.md §5.19 item 7).
      - A header row and three goal rows, each 5 pt vertical padding, in a three-column grid of equal widths: column 1 leading, columns 2 and 3 trailing.
      - Header: `GOAL`, `IN BED`, `BED BY` in `labelSmall` `textSoft`.
      - Goal rows, in `goals` order (100, 85, 70): `<pct>%` in `valueSmall` `legendText`; `in_bed_minutes` as `h:mm` in `valueSmall` `text1`; `bedtime` as `HH:mm` in `valueSmall` `text1`.
      - Each goal row is one accessibility element, id `tonight-goal-<pct>`, label `<pct> percent of need: <h> hours <m> minutes in bed, bed by <HH:mm>`.
   4. **Unavailable** (`status` `unavailable`): the title row, then 12 pt below a left-aligned `GoopPlaceholder` with `Needs 3 nights of sleep to plan tonight.` (id `tonight-placeholder`). No key row and no strip.
4. **Dimming:** values (not labels) use `Goop.Opacity.stale` when the phone copy is stale, as every detail value does.
5. **Gallery:** `GoopTonightCard` joins `ComponentGallery` at the default size and at accessibility 5, with the `fresh` plan and the unavailable state.

Fixture (`fresh`, copied from `day_full.json`): `NEED 8:03`, `WAKE 07:07`; `100% 8:48 22:19`, `85% 7:30 23:37`, `70% 6:12 00:55`.

### 2.5 Sleep info sheet (`sleep-info`)

The existing `SleepInfo` `GoopSheet` (spec.md §8.11). Only the **Need** section changes, and only when `GoopFeature.sleepPlanner` is on and `day.sleep_plan` is non-null. Otherwise it keeps today's single line.

The section body becomes a `VStack(alignment: .leading, spacing: 8)` of `bodyMid` `legendText` texts, in this order (copy in §4.3):
1. last night's need line, now prefixed `Last night: `;
2. tonight's need line;
3. when `status` is `ok`: the efficiency sentence, the three goal lines and the wake sentence;
4. when `status` is `unavailable`: the unavailable sentence.

The sheet opens from the Sleep info button, `DIVE INTO MY SLEEP`, the need card's info button and the Tonight card's info button. The Night, Breathing, Overnight HRV, Naps and How this works sections are unchanged.

The sheet needs `day.sleep_plan`, so `SleepInfo` gains a `plan: SleepPlan?` input, read from the same bundle as `sleep`.

### 2.6 Lock Screen widgets (`lock`)

`LockScoresWidget` keeps its kind and families.

1. **Circular, metric `hrv`:** `AccessoryWidgetBackground()`, no ring (HRV has no fixed scale), and centred `VStack(spacing: 0)`: the HRV value as an integer in `.goop(.valueLock)` (or `—`) and `HRV` in `.goop(.labelLock)` at 80 % opacity. Stale: 55 % opacity and the clock glyph, as today. Accessibility label `HRV, <v> milliseconds`.
2. **Rectangular, extra line:** a new intent parameter `line` (§8.5): `None` (default), `HRV` or `Bed by`.
   - `None`: today's three lines, unchanged, so installed widgets look the same.
   - `HRV` or `Bed by`: four lines in a `VStack(spacing: 0)`, each line `frame(maxHeight: .infinity)`. Lines 1–3 are today's (SLEEP, RECOVERY, STRAIN); line 4 is `HRV` with the HRV integer, or `BED BY` with the 100 % bedtime as `HH:mm`. Label and value styles are today's (`labelLockRow`, `valueWidgetList`).
   - `BED BY` shows `—` when there is no plan, the plan is unavailable, or the entry's date is at or after the plan's `wake_target` (§8.6). `HRV` shows `—` when the metric is not available.
   - Stale: values at 55 % opacity, the clock after the SLEEP line, as today.
   - Accessibility: the line reads `Bed by <HH:mm>` or `HRV, <v> milliseconds`.
3. **Inline:** unchanged.
4. **Which parameter shows when editing the widget:** circular and inline show `Score`; rectangular shows `Extra line` (§8.5).

The mockup's second row shows the HRV-line option. A real Lock Screen holds one row; the mockup stacks the two configurations for review.

### 2.7 Small HRV widget (`hrv-widget`)

`ScoresWidget` with `metric = hrv`, small family only (medium ignores `metric`, as today). New view `HRVSmallView` (`ios/Shared/WidgetViews/HRVSmallView.swift`), the vital tile's value and chip (spec.md §5.23) in the small widget's frame:

1. Container `widgetFill`, as every ghoops widget.
2. `VStack(spacing: 9)`, centred:
   1. A 100 pt tall `VStack(spacing: 3)`, the height of the score ring in the other small widgets, so labels line up in a stack:
      - `GoopWordmark(size: 14, color: Goop.Color.wordmarkDial)`, frame 30 × 8;
      - `HStack(alignment: .firstTextBaseline, spacing: 3)`: the value as an integer in `.goop(.scoreWidgetSmall)`, then `ms` in `.goop(.unit)` `text2`; with no value, only `—` in `text2`;
      - the range chip, 3 pt further down (6 pt from the value).
   2. `HRV` in `.goop(.labelWidget)`.
3. **Chip:** radius `Goop.Metric.radiusChip` (6), padding 3 × 8, `HStack(spacing: 5)`, no wrapping (`fixedSize`):

   | State | Fill / text colour | Symbol (`Image(systemName:)`, semibold) | Text |
   | --- | --- | --- | --- |
   | `status` available, `position` `within` | `vitalChipFill` / `positive` | `checkmark`, 9 pt | `<low> – <high>` in `.goop(.valueChip)` |
   | `above` or `below`, `hrv_rmssd` in `vitals.persistent` and `vitals.monitor_state` is `attention` | `caution` 12 % / `caution` | `arrowtriangle.up.fill` or `.down.fill`, 7 pt | same |
   | `above` or `below`, not in the attention pattern | `neutral` 15 % / `textSoft` | same | same |
   | `no_baseline` | `neutral` 15 % / `textSoft` | none | `Building baseline` in `.goop(.chip)` |
   | `status` not available | `neutral` 15 % / `textSoft` | none | `ReasonText.metric(status)` in `.goop(.chip)` |

   Range numbers are integers (HRV display precision), joined by ` – `.
4. **Stale:** value and chip at 55 % opacity; the clock and age at the top right, inset 10, as the other small widgets.
5. **Accessibility:** one element, label `HRV, <v> milliseconds, <state>`, where state is `within typical range <low> to <high>`, `below typical range …`, `above typical range …`, `building baseline` or the status text.

Fixture (`fresh`): `56 ms`, chip `✓ 47 – 58`.

### 2.8 Sport sub-step with a suggestion (`sport-suggest`)

The Sport sub-step of edit-spec §2.3, opened from a detected effort's pencil (edit-spec §2.7). It changes only when `GoopFeature.sportSuggestion` is on and the effort's `suggested` is non-null:

1. The sub-step opens with the suggested sport **selected**, so its commit `USE <SPORT>` is enabled at once.
2. **`RECENT`:**
   - row 1: the suggested sport, selected, with the note `Usual on <Wkd>`, where `<Wkd>` is the effort's London start weekday, `EEE`, `en_GB` (`Tue`);
   - row 2: the most recent distinct sport from the last 30 days of kind `recorded` or `goop`, other than the suggestion, with its usual note `Last: <Wkd>`; no row 2 when there is none.
3. **`ALL ACTIVITIES`:** activity-spec §2.1 in order, without the `RECENT` rows (unchanged rule).
4. Rows are `GoopChoiceRow`s with the existing ids (`edit-sport-<TYPE>`). The note uses the row's `rowNote` style, in sentence case like `Last: Sat` (§13 item 1).
5. Accessibility: row 1 reads `<Sport>, usual on <Weekday>` (full weekday, for example `Boxing, usual on Tuesday`).
6. Search filters every row as today; the suggested row keeps its note when it matches.
7. `USE <SPORT>` returns to the Edit step with that sport; the commit then reads `SAVE <SPORT>`. Naming is therefore pencil, `USE BOXING`, `SAVE BOXING`. Nothing is named without the owner's tap.
8. `chevron.left` without `USE` behaves as edit-spec §2.7 says (back to `Choose`).
9. Recorded and ghoops entries, and efforts without a suggestion, are unchanged.

Fixture (`-GHealthFixture parity -GHealthParityFixture sport`): the effort of Monday 2026-03-09 19:40–20:25 with `BOXING` preselected and the note `Usual on Mon`.

### 2.9 Missing, stale and offline

- **No target** (Recovery null): the insight's first sentence says why (§4.1), the live screen shows no target row and the Live Activity keeps today's layout.
- **No projection** (base unknown or no live TRIMP): the live screen and Live Activity show `—` for `EST. DAY STRAIN`; the target still shows; no alert can fire.
- **No plan:** no Tonight card on past days; `Needs 3 nights of sleep to plan tonight.` when the plan is unavailable; `BED BY —` on the widget.
- **Stale snapshot:** values dim at 55 % as everywhere. The widget's `BED BY` hides a bedtime whose wake time has passed (§8.6).
- **Offline:** nothing new. All of this reads the cached snapshot; the edit flow's offline rule (edit-spec §2.9) still applies to naming.

## 3. Components

### 3.1 Existing (DESIGN.md, design cleanup, edit)

| Component | Used for |
| --- | --- |
| `GoopInsightCard` | Strain insight with the target sentence (§2.1) |
| `GoopCard`, `GoopPlaceholder` | Tonight card and its unavailable state (§2.4) |
| `GoopSheet`, `GoopSheetSection` | Sleep info sheet Need section (§2.5) |
| `GoopSymbol` | live row checkmark (§2.2) |
| `GoopTaskSheet`, `GoopChoiceRow`, `GoopSectionLabel`, `GoopSearchField` | Sport sub-step (§2.8), unchanged components |
| `GoopWordmark`, `AccessoryWidgetBackground`, `ScoreRing` | widgets (§2.6, §2.7) |
| Type cases from the cleanup (design-cleanup-spec §3.1) | `valueLiveStat`, `labelStat`, `labelMicro`, `valueChip`, `chip`, `rowNote`, `labelLockRow`, plus the existing `valueSmall`, `labelSmall`, `labelCard`, `valueLock`, `labelLock`, `scoreWidgetSmall`, `labelWidget`, `unit`, `bodyMid` |
| Tokens | `strainLight`, `positive`, `caution`, `neutral`, `textSoft`, `text2`, `iconMuted`, `legendText`, `legendFill`, `cardDivider`, `plotGrid`, `vitalChipFill`, `wordmarkDial`, `widgetFill`, `Goop.Metric.radiusLegend`, `radiusChip`, `Goop.Opacity.stale` |

### 3.2 New (each in `ComponentGallery` at default size and accessibility 5, where it lives in the app target)

- **`LiveTargetRow`** (app): the two-cell row of §2.2. Inputs: `projected: Double?`, `low: Double`, `high: Double`.
- **`GoopTonightCard`** (app): §2.4. Inputs: `plan: SleepPlan`, `dimmed: Bool`, `info: () -> Void`.
- **`HRVSmallView`** (shared, widget): §2.7. Not in the gallery (widget target); shown in the widget preview host (§10.2).

No other new chrome: no pills, steppers, toggles, toasts, text header buttons or new colours. The checkmark keeps its DESIGN.md meaning (within range, mint). No dashes are added.

## 4. Copy

### 4.1 Strain target sentence (`Insights`)

`<low>`, `<high>` are 1 dp; `<band>` is `high`, `medium` or `low` from `day.recovery.band`. `<intent>` adds ` on a restore day` (restore), nothing (maintain) or ` on an overreach day` (overreach).

| Target | `isToday` true | `isToday` false |
| --- | --- | --- |
| `status` `ok` | `Today's target is <low> to <high> for <band> recovery<intent>.` | `The target was <low> to <high> for <band> recovery<intent>.` |
| then `position` `below` / `within` / `above` | `You are below it.` / `You are within it.` / `You are above it.` | `You finished below it.` / `You finished within it.` / `You finished above it.` |
| `position` null | no second sentence | no second sentence |
| `status` `pending` | `Today's target appears when Recovery is ready.` | (cannot occur) |
| `status` `unavailable` | `There is no target without a Recovery score.` | same |

`isToday` is the existing parameter (`selectedDate == default_date`). When `day.strain.value` is null, the target sentence comes first and the existing reason sentence follows.

### 4.2 Screens

| Where | Text |
| --- | --- |
| Live row captions | `EST. DAY STRAIN`, `TARGET` |
| Live Activity captions (target layout) | `STRAIN`, `EST. DAY STRAIN`, `TARGET` |
| Live Activity alert | title `Strain target reached`; body `Your Day Strain estimate is <p>, inside today's target of <low> to <high>.` |
| Tonight card | title `TONIGHT'S SLEEP`; keys `NEED`, `WAKE`; headers `GOAL`, `IN BED`, `BED BY`; rows `100%`, `85%`, `70%` |
| Tonight card unavailable | `Needs 3 nights of sleep to plan tonight.` |
| Lock rectangular extra line labels | `HRV`, `BED BY` |
| Lock circular HRV caption | `HRV` |
| Small HRV widget | `ms`, `HRV`, `Building baseline` |
| Widget intent options | Score: `HRV`; parameter `Extra line`: `None`, `HRV`, `Bed by` |
| Sport row note | `Usual on <Wkd>` |

Uppercase strings are passed already uppercased, with sentence-case accessibility labels (§2).

### 4.3 Sleep info sheet, Need section

`<b>`, `<s>`, `<d>`, `<n>`, `<t>` are `h:mm`; `<eff>` is `efficiency_pct_used` with no decimals when whole, else 1 dp (`90%`, `92.5%`); `<lat>` is `latency_minutes_used`; `<N>` is `nights_used`; `<wake>` is `wake_target` as `HH:mm`.

| Line | Text |
| --- | --- |
| Last night | `Last night: baseline <b> + strain <s> + debt <d> − naps <n> = <t> needed.` (from `sleep.need`) |
| Tonight | `Tonight so far: baseline <b> + strain <s> + debt <d> − naps <n> = <t> needed.` (from `sleep_plan.need_parts` and `need_minutes`) |
| Efficiency, `<lat>` > 0 | `Time in bed is need × goal ÷ your usual efficiency (<eff>), plus your usual <lat> min to fall asleep. Both come from your last <N> nights.` |
| Efficiency, `<lat>` = 0 | `Time in bed is need × goal ÷ your usual efficiency (<eff>), from your last <N> nights.` |
| Goal 100 | `100%: <g> ÷ <eff> + <L> = <in bed> in bed. Bed by <bedtime> to wake at <wake>.` |
| Goal 85, 70 | `<pct>%: <g> ÷ <eff> + <L> = <in bed> in bed. Bed by <bedtime>.` |
| Wake, `typical` | `<wake> is your typical wake time over the last <N> nights. To plan for a fixed wake time, set it on your Mac with ghoops config.` |
| Wake, `config` | `<wake> is the wake time set on your Mac with ghoops config.` |
| Unavailable | `Tonight's plan needs at least 3 nights of sleep from the last 14.` |

In goal lines, `<g>` is `round(need_minutes × pct / 100)` as `h:mm` and `<L>` is `<lat>` as `h:mm`; with `<lat>` 0 the ` + <L>` part is dropped. The goal lines explain the Mac's numbers and can differ from a hand calculation on the rounded `<g>` by one minute; `<in bed>` and `<bedtime>` are always the Mac's values. With no plan, the section is today's single line, unchanged (no `Last night:` prefix).

Fixture (`fresh`):
- `Last night: baseline 7:30 + strain 0:06 + debt 0:16 − naps 0:28 = 7:24 needed.`
- `Tonight so far: baseline 7:30 + strain 0:11 + debt 0:22 − naps 0:00 = 8:03 needed.`
- `Time in bed is need × goal ÷ your usual efficiency (92.5%), plus your usual 6 min to fall asleep. Both come from your last 12 nights.`
- `100%: 8:03 ÷ 92.5% + 0:06 = 8:48 in bed. Bed by 22:19 to wake at 07:07.`
- `85%: 6:51 ÷ 92.5% + 0:06 = 7:30 in bed. Bed by 23:37.`
- `70%: 5:38 ÷ 92.5% + 0:06 = 6:12 in bed. Bed by 00:55.`
- `07:07 is your typical wake time over the last 12 nights. To plan for a fixed wake time, set it on your Mac with ghoops config.`

The first line comes from the preview snapshot's own `sleep.need` (444 minutes); the others come from `day_full.json`'s plan, which the preview script copies (§10.1).

## 5. Logic

All rounding is half away from zero (scores.md §1.1). "Reported" values are the rounded output values.

### 5.1 Strain target (Mac, scores.md new §3.12)

Constants in `internal/score/constants.go` (they change scores, so `Version` becomes `"2.1.0"`):

| Name | Value |
| --- | --- |
| `StrainTargetBase` | 6.0 |
| `StrainTargetPerRecovery` | 0.12 |
| `StrainTargetHalfWidth` | 1.5 |
| `StrainTargetRestoreOffset` | −3.0 |
| `StrainTargetOverreachOffset` | 2.0 |

For day D with reported `recovery.value` R (integer), `strain_intent` I and reported Day Strain S:

```
if R is null:
    low = high = position = null
    status = recovery.status            # "pending" or "unavailable"
    reason = recovery.reason
else:
    centre = 6.0 + 0.12 × R + {restore: −3.0, maintain: 0.0, overreach: +2.0}[I]
    low  = round1(clamp(centre − 1.5, 0, 21))
    high = round1(clamp(centre + 1.5, 0, 21))
    position = null when S is null; else below if S < low, above if S > high, otherwise within
    status = "ok", reason = null
```

`position` compares the reported 1-dp values, so a reader can recompute it from JSON. With these constants `0.12 × R` never ends in 5 at the second decimal, so no half-way rounding occurs. The target uses the current `strain_intent` for every date, past ones included, because config is not stored per day (scores are views).

**Worked examples** (golden `fixtures/v2/scores/strain_target.json`):

| Case | R | I | S | low | high | position |
| --- | --- | --- | --- | --- | --- | --- |
| `medium_maintain` (mockup) | 59 | maintain | 12.8 | 11.6 | 14.6 | within |
| `medium_restore` | 59 | restore | 12.8 | 8.6 | 11.6 | above |
| `medium_overreach` | 59 | overreach | 12.8 | 13.6 | 16.6 | below |
| `low_edge_inclusive` | 34 | maintain | 8.6 | 8.6 | 11.6 | within |
| `high_edge_inclusive` | 67 | maintain | 15.5 | 12.5 | 15.5 | within |
| `just_above` | 67 | maintain | 15.6 | 12.5 | 15.5 | above |
| `clamped_at_21` | 100 | overreach | 21.0 | 18.5 | 21.0 | within |
| `zero_restore_no_strain` | 0 | restore | null | 1.5 | 4.5 | null |
| `day_full` | 73 | maintain | 12.8 | 13.3 | 16.3 | below |
| `no_recovery` | null (`pending`, `no_sleep`) | maintain | 5.0 | null | null | null, status `pending`, reason `no_sleep` |

`day_full.json`: `{"low": 13.3, "high": 16.3, "intent": "maintain", "position": "below", "status": "ok", "reason": null}`. With config `strain_intent: restore` (`day_full_config.json`): `low 10.3`, `high 13.3`, `position within`.

### 5.2 Projected Day Strain and the crossing (phone, GHealthCore)

The second allowed phone computation (PRODUCT.md). It uses only the Mac's reported `day.strain.trimp`, the live session's TRIMP and `StrainMath`.

**`SessionTarget`** (`GHealthCore/Live/SessionTarget.swift`, Codable, stored in `ActivitySession.target`, so `live-session.json` keeps it across relaunch):

| Field | Rule |
| --- | --- |
| `cycleDate` | `day.date` |
| `baseTrimp` | `day.strain.trimp`; `0` when `trimp` is null and `strain.reason == "no_heart_rate"`; otherwise null |
| `low`, `high` | `day.strain_target.low`, `.high` |
| `crossing` | `TargetCrossing`: `unknown` at creation |

`SessionTarget.make(day:sessionStart:)` returns nil unless all of these hold: `day.isCurrentCycle`; `day.cycle.start ≤ sessionStart`; `day.strainTarget?.status == "ok"` with non-null `low` and `high`. `ActivityController` calls it once, at start, with the cached snapshot's `day`, only when `GoopFeature.strainTarget` is on. The base is frozen at start, so a snapshot refreshed during the session cannot count the session's minutes twice.

**Projection:** `projected(liveTrimp:)` = `StrainMath.strain(trimp: baseTrimp + liveTrimp)` (1 dp), where `liveTrimp` is `LiveEstimate.trimp` (1 dp). Nil when either is nil. Minutes between the band's last sync before the start and the start itself are missing from the base, so the projection can only be low, never double counted; it is labelled an estimate.

**Crossing** (`mutating func update(projected: Double?) -> Bool`, true means "alert now"):

```
p == nil                     → no change, false
crossing == unknown          → crossing = (p < low) ? armed : inactive; false
crossing == armed, p ≥ low   → if p ≤ high { crossing = fired; true } else { crossing = inactive; false }
otherwise                    → false
```

A session that starts inside or above the target never alerts. A session alerts at most once.

**Worked examples** (GHealthCore tests):

| Base | Live TRIMP | Projected | Note |
| --- | --- | --- | --- |
| 25.0 | 26.7 | 9.0 | mockup `live-target` (activity strain 6.4) |
| 25.0 | 79.3 | 12.0 | mockup `lock-live` (activity strain 10.8) |
| 124.1 | 26.7 | 13.7 | `fresh` + `boxing_23m` |
| 124.1 | 13.1 | 13.2 | 137.2 total, just below 13.3 |

Crossing sequences with target 11.6–14.6: `[9.0, 11.5, 11.6, 12.0]` → true once, at 11.6. `[12.0, 13.0]` → never. `[9.0, 15.0]` → never, ends `inactive`. `[nil, 9.0, 11.6]` → true at 11.6. A restored session with `crossing == fired` → never.

### 5.3 Sleep plan (Mac, scores.md new §4.11, display only)

Display constants, so `score_version` is not affected by them: `PlanNights = 14`, `PlanMinNights = 3`, `PlanGoals = [100, 85, 70]`.

Present only while cycle D is `open`; otherwise `day.sleep_plan` is null. For the night ending D+1 ("tonight"), at `now`:

```
base         = sleep_base_need_minutes
cycle_strain = reported day.strain.value of cycle D (0 when null)
strain_extra = min(45, round(4 × max(0, cycle_strain − 10)))
debt_extra   = min(60, round(0.25 × Σ max(0, base − asleep(n)) over the main sleeps ending D, D−1, D−2))
               nights without a main sleep or with unknown asleep minutes are skipped (debt_nights_used counts the rest)
nap_credit   = min(120, Σ asleep minutes of sleep sessions that are not the main sleep of their London end date,
               with end time in [cycle_start(D), now))
need         = clamp(base + strain_extra + debt_extra − nap_credit, 300, 720)
```

This is scores.md §4.4 applied to the night ending D+1 with the data seen so far: `S` is the current cycle's strain so far, and naps count up to `now` because the main sleep has not started.

```
nights   = main sleeps ending on D−13 … D (14 London dates) whose efficiency_pct is non-null
N        = len(nights)                               # nights_used
if N < 3: status "unavailable", reason "insufficient_nights"
          efficiency_pct_used = latency_minutes_used = null, goals = []
          wake_target as below when wake_source is "config", else null
efficiency_pct_used = median of the nights' efficiency_pct            (1 dp; .5 when the count is even)
latency_minutes_used = round(median of the nights' non-null minutes_to_fall_asleep), 0 when none has one
wake_source = "config" when wake_target is set in config, else "typical"
wake_minutes = config HH:MM, or floor(median of the nights' local wake time-of-day in minutes, seconds as fractions)
wake_target  = London wall clock on D+1 at wake_minutes (spring-forward gap → 02:00, as scores.md §3.1)
for pct in (100, 85, 70):
    in_bed_minutes = round(need × pct / efficiency_pct_used) + latency_minutes_used
    bedtime        = wake_target − in_bed_minutes
```

`efficiency_pct_used` is used at full precision (a median of integers is exact at 1 dp). The planner's typical wake uses the same nights as its efficiency, so it equals scores.md §3.1's typical wake whenever every main sleep has asleep minutes (§13 item 8).

**Worked example: `day_full.json`** (store_full, D = 2026-03-10, now 14:30Z, GMT):
- `cycle_strain` 12.8 → `strain_extra` round(11.2) = **11**.
- Nights D, D−1, D−2 asleep 415, 427, 419 → shortfalls 35 + 23 + 31 = 89 → `debt_extra` round(22.25) = **22**, `debt_nights_used` 3.
- No nap ends in [06:29Z, 14:30Z) → `nap_credit` **0**.
- `need` = 450 + 11 + 22 − 0 = **483** (8:03).
- Nights 2026-02-25 … 03-10 with efficiency: 12 (02-26 and 03-05 missing). Efficiencies sorted 90, 90, 91, 91, 91, 92, 93, 93, 93, 94, 94, 95 → median **92.5**. Latencies: eleven 6 and one 4 → median **6**. Wake times sorted 06:29, 06:56, 06:58, 06:59, 07:02, 07:06, 07:08, 07:10, 07:12, 07:16, 07:23, 07:23 → median 427 min → **07:07**.
- Goals: 100 % → round(483 × 100 / 92.5) = 522 + 6 = **528** (8:48), bed by **22:19**; 85 % → round(443.84) = 444 + 6 = **450** (7:30), **23:37**; 70 % → round(365.51) = 366 + 6 = **372** (6:12), **00:55** (2026-03-11).

```json
"sleep_plan": {
  "status": "ok", "reason": null,
  "need_minutes": 483,
  "need_parts": { "baseline_minutes": 450, "strain_extra_minutes": 11, "debt_extra_minutes": 22,
                  "nap_credit_minutes": 0, "cycle_strain": 12.8, "debt_nights_used": 3 },
  "wake_target": "2026-03-11T07:07:00Z", "wake_source": "typical",
  "efficiency_pct_used": 92.5, "latency_minutes_used": 6, "nights_used": 12,
  "goals": [
    { "pct": 100, "in_bed_minutes": 528, "bedtime": "2026-03-10T22:19:00Z" },
    { "pct": 85,  "in_bed_minutes": 450, "bedtime": "2026-03-10T23:37:00Z" },
    { "pct": 70,  "in_bed_minutes": 372, "bedtime": "2026-03-11T00:55:00Z" } ] }
```

With config `wake_target: "06:45"` (`day_full_config.json`): `wake_source "config"`, `wake_target 2026-03-11T06:45:00Z`, bedtimes 21:57, 23:15, 00:33; everything else equal.

**Goal vectors** (`fixtures/v2/scores/sleep_plan.json`, key `goals`; input `need_minutes`, `efficiency_pct_used`, `latency_minutes_used`, `wake_target`):

| Case | need | eff | lat | wake | 100 % | 85 % | 70 % |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mockup` | 470 | 90 | 10 | 2026-03-11T06:45Z | 532, 21:53 | 454, 23:11 | 376, 00:29 |
| `day_full` | 483 | 92.5 | 6 | 2026-03-11T07:07Z | 528, 22:19 | 450, 23:37 | 372, 00:55 |
| `need_floor` | 300 | 100 | 0 | 2026-03-11T05:00Z | 300, 00:00 | 255, 00:45 | 210, 01:30 |
| `half_rounds_up` | 455 | 100 | 0 | 2026-03-11T07:00Z | 455, 23:25 | 387, 00:33 | 319, 01:41 |
| `spring_forward` | 480 | 96 | 0 | 2026-03-29 07:00 BST = 06:00Z | 500, 2026-03-28T21:40Z | 425, 22:55Z | 350, 2026-03-29T00:10Z |

Key `need` holds the day_full need-parts case above and one with a nap: same inputs plus a 40-minute nap ending 13:10Z → `nap_credit 40`, need 443. Key `nights` holds `two_nights` (status `unavailable`, `insufficient_nights`) and `config_wake_with_two_nights` (unavailable, `wake_target` present, `goals []`).

### 5.4 Sport suggestion (Mac, scores.md new §3.9a, display only)

Display constants: `SuggestWindowDays = 56`, `SuggestStartToleranceMinutes = 90`, `SuggestMinRatio = 0.5`, `SuggestMaxRatio = 2.0`, `SuggestMinMatches = 3`, `SuggestMinShare = 0.6`. Day Strain and every score are untouched.

For each visible detected effort E (after edit-spec §5.5):

```
candidates = visible entries of kind "recorded" or "goop", built by edit-spec §5.5 steps 1–5 (effective sport and window,
             no scoring), whose effective exercise_type is in activity-spec §2.1 and is not OTHER,
             and whose cycle_date is in [E.cycle_date − 56, E.cycle_date − 1]
match(c)   = London weekday of c.start == London weekday of E.start
             and |tod(c.start) − tod(E.start)| ≤ 90        # tod = London minutes after local midnight, no wrap
             and 0.5 × E.elapsed_minutes ≤ c.elapsed_minutes ≤ 2.0 × E.elapsed_minutes
count[s]   = number of matching candidates with exercise_type s
s*         = the s with the largest count
suggested  = s* when count[s*] ≥ 3 and count[s*] ≥ 0.6 × Σ count; otherwise null
```

A tie for the largest count fails the 60 % rule, so no tie-break is needed. `display_name` is the activity-spec §2.1 label of `s*`.

**Worked example** (`fixtures/v2/parity/workouts.json`): store_parity adds band `BOXING` 19:30–20:30Z on Mondays 2026-02-16, 02-23 and 03-02 to store_full. The detected effort of Monday 2026-03-09 19:40–20:25 (45 min) matches all three: same weekday, 10 minutes apart, 60 minutes within 22.5–90. `suggested = {"exercise_type": "BOXING", "display_name": "Boxing", "matches": 3, "window_days": 56}`. In `workouts_full.json` (store_full, no history) the same effort has `suggested: null`.

### 5.5 Brief trend (Mac, contract §5.13, display only)

Display constants: `TrendShortDays = 7`, `TrendLongDays = 30`, `TrendShortMinDays = 4`, `TrendLongMinDays = 7`, `TrendBandSD = 0.5`.

For brief date D and each metric key in this order: `recovery`, `hrv_rmssd_ms`, `resting_hr_bpm`, `sleep_performance`, `asleep_minutes`, `strain`:

```
rows_30 = days rows D−29 … D; rows_7 = days rows D−6 … D
values  = the key's non-null row values; for "strain" only, rows whose cycle_status is not "closed" are skipped
days_7, days_30 = counts
if days_7 ≥ 4 and days_30 ≥ 7:
    mean_7, mean_30 = arithmetic means; sd_30 = sample SD of the 30-day values (n − 1)
    delta = mean_7 − mean_30
    direction = above if delta > 0.5 × sd_30, below if delta < −0.5 × sd_30, else near
else: direction = null, mean_7 = mean_30 = null
```

Means are reported at 1 dp. Vectors (`fixtures/v2/scores/trend.json`, input `values[30]` oldest first and `last_open`):

| Case | Values | days_7, days_30 | mean_7, mean_30 | direction |
| --- | --- | --- | --- | --- |
| `above` | 23 × 60 then 7 × 70 | 7, 30 | 70.0, 62.3 | above (sd 4.30) |
| `below` | 23 × 60 then 7 × 50 | 7, 30 | 50.0, 57.7 | below |
| `near` | 23 × 60 then 61, 59, 60, 61, 59, 60, 60 | 7, 30 | 60.0, 60.0 | near |
| `flat` | 30 × 60 | 7, 30 | 60.0, 60.0 | near (sd 0) |
| `three_recent` | 23 × 60, then 60, null, 60, null, 60, null, null | 3, 26 | null, null | null |
| `open_strain` | strain: 29 closed rows of 10.0, then an open row of 15.0 | 6, 29 | 10.0, 10.0 | near (the open row is skipped) |

`brief_full.json` (D = 2026-03-10): `hrv_rmssd_ms` near, 6 and 28 days (53.1, 52.3); `resting_hr_bpm` near, 7 and 30 (56.0, 56.1); `asleep_minutes` near, 6 and 28 (431.7, 432.2); `strain` null, 2 and 2 (store_full has heart rate only from 2026-03-09, and the open cycle is skipped). `recovery` and `sleep_performance` are whatever the engine's day rows give; the golden records them.

### 5.6 Brief evening review

With `--part evening`, `review` is:

| Field | Always | Only with `--include-values` |
| --- | --- | --- |
| `workouts` | int: entries of kind `recorded` or `goop` with `cycle_date` D | |
| `detected_efforts` | int: entries of kind `detected` with `cycle_date` D | |
| `new_flags` | string[]: codes in D's `health_flags` that are not in D−1's, in table order | |
| `zones_1_3_minutes`, `zones_4_5_minutes` | | `int?`, from D's `strain.zones_minutes` |

Day Strain against the target is `strain_target.position`, tonight's bedtime is `sleep_plan.bedtime`, and workouts with their strain are `workouts[]`, so `review` does not repeat them. `brief_full_evening_values.json`: `workouts 1`, `detected_efforts 0`, `new_flags []`, `zones_1_3_minutes 27`, `zones_4_5_minutes 33`.

## 6. Contract changes (schema 2, additive)

### 6.1 `score_config` and `config`

`config.Values` gains, after the existing keys (and edit's `sport_aliases`):

| Key | Type | Default | Valid |
| --- | --- | --- | --- |
| `strain_intent` | string | `"maintain"` | `"restore"`, `"maintain"`, `"overreach"` |
| `wake_target` | string or null | null | `HH:MM`, 24-hour, `^([01][0-9]\|2[0-3]):[0-5][0-9]$` |

Both are echoed in every `score_config` and in the `config` body's `values` and `defaults`. A file with `"strain_intent": null` is invalid, like `trimp_profile`.

### 6.2 `day.strain_target` (after `strain`)

| Field | Type | Rule |
| --- | --- | --- |
| `low`, `high` | `num?` | §5.1, 1 dp; null when `status` is not `ok` |
| `intent` | string | the effective `strain_intent` |
| `position` | string? | `below`, `within`, `above`; null when `low` or `strain.value` is null |
| `status` | ScoreStatus | `ok`, `pending` or `unavailable` |
| `reason` | Reason | Recovery's reason when Recovery is null; else null |

Always present (contract §1.3). Not added to `days` rows (§12).

### 6.3 `day.sleep_plan` (after `sleep`), object or null

Null unless `cycle.status == "open"`. Fields as in the §5.3 example:

| Field | Type | Rule |
| --- | --- | --- |
| `status` | string | `ok` or `unavailable` |
| `reason` | Reason | `insufficient_nights` or null |
| `need_minutes` | int | §5.3, always computed |
| `need_parts` | object | `{baseline_minutes, strain_extra_minutes, debt_extra_minutes, nap_credit_minutes}` ints, `cycle_strain: num?`, `debt_nights_used: int` |
| `wake_target` | `Time?` | null only when unavailable with `wake_source` `typical` |
| `wake_source` | string | `typical` or `config` |
| `efficiency_pct_used` | `num?` | 1 dp |
| `latency_minutes_used` | `int?` | |
| `nights_used` | int | |
| `goals` | array | `[{pct: int, in_bed_minutes: int, bedtime: Time}]`, 100, 85, 70; `[]` when unavailable |

`snapshot.day` carries it, so the phone and widgets need no new request.

### 6.4 Workouts: `suggested`

Every workout object gains `suggested`, after edit's fields: `{exercise_type: string, display_name: string, matches: int, window_days: int}` or null. Non-null only on `kind: "detected"` entries that pass §5.4. It appears wherever workouts appear (`workouts`, `day.workouts`, `snapshot`).

### 6.5 `brief`

Field order: `disclosure`, `part`, `date`, `freshness`, `recovery`, `strain`, `strain_target`, `sleep`, `sleep_plan`, `trend`, `vitals_adverse`, `workouts`, `health_flags`, `review` (evening only), `note`.

| Field | Always | Only with `--include-values` |
| --- | --- | --- |
| `part` | `"morning"` or `"evening"` | |
| `strain_target` | `{status, reason, intent, position}` | `low`, `high` |
| `sleep_plan` | object or null: `{status, reason, wake_source}` | `need_minutes`, `bedtime` (the 100 % goal's, or null) |
| `trend` | `{<key>: {direction, days_7, days_30}}` for the six keys of §5.5, in that order | `mean_7`, `mean_30` per key |
| `workouts[]` | gains `suggested_exercise_type` (string?) | |
| `review` | evening only: `{workouts, detected_efforts, new_flags}` | `zones_1_3_minutes`, `zones_4_5_minutes` |

As today, value keys are absent in status-only mode, not null, and `review` is absent in the morning part. The status-only brief still carries no workout or sleep timestamps: `bedtime` is a value key.

Example, `brief_full.json` additions (status only, morning):

```json
"part": "morning",
"strain_target": { "status": "ok", "reason": null, "intent": "maintain", "position": "below" },
"sleep_plan": { "status": "ok", "reason": null, "wake_source": "typical" },
"trend": {
  "recovery":          { "direction": "<golden>", "days_7": "<golden>", "days_30": "<golden>" },
  "hrv_rmssd_ms":      { "direction": "near", "days_7": 6, "days_30": 28 },
  "resting_hr_bpm":    { "direction": "near", "days_7": 7, "days_30": 30 },
  "sleep_performance": { "direction": "<golden>", "days_7": "<golden>", "days_30": "<golden>" },
  "asleep_minutes":    { "direction": "near", "days_7": 6, "days_30": 28 },
  "strain":            { "direction": null, "days_7": 2, "days_30": 2 } },
"workouts": [ { "kind": "recorded", "category": "combat", "exercise_type": "KICKBOXING", "suggested_exercise_type": null } ]
```

### 6.6 CLI and HTTP

| Command / route | Change |
| --- | --- |
| `ghoops brief [--date D] [--include-values] [--part morning\|evening]` | `--part` defaults to `morning`; any other value is usage error 2, `invalid_request` naming `part` |
| `GET /v2/brief` | new query `part` (`morning`, `evening`; default `morning`); other values `invalid_request` naming `part` |
| `ghoops config set strain_intent restore\|maintain\|overreach` / `unset strain_intent` | `unset` restores `maintain`; invalid value exits 2 |
| `ghoops config set wake_target HH:MM\|null` / `unset wake_target` | `unset` and `null` clear it; invalid value exits 2 |

CLI and HTTP bodies stay byte-identical (contract §1.1). No new route, no new `kind`.

### 6.7 Documents to edit (step P2)

| Document | Sections |
| --- | --- |
| `docs/v2/contract.md` | §3: `brief` flags (`--part`); `config` keys in the `config` row's note. §5.1: `score_version` `"2.1.0"`; `score_config` gains `strain_intent`, `wake_target`. §5.2: `strain_target` after `strain`, `sleep_plan` after `sleep`. New §5.2.2 `strain_target` and §5.2.3 `sleep_plan` field tables (§6.2, §6.3). §5.8: `suggested`. §5.13: the §6.5 table, order and example; the `--part` note. §5.14: `config` `values`/`defaults` keys. §7.2: `/v2/brief` query `part`. §9.2: one sentence that an assistant may use `--part evening` (owner follow-up §12). |
| `docs/v2/scores.md` | Status line and §9 envelope: `2.1.0`. §0: the five strain-target constants. §0.1: `strain_intent` and `wake_target` rows. New §3.12 Strain target (§5.1). New §3.9a Sport suggestion (§5.4, display only). New §4.11 Sleep planner (§5.3, display only). New §11b Brief trends (§5.5, display only). §9: rows for `strain_target.json`, `sleep_plan.json`, `trend.json`. |
| `docs/v2/data.md` | No change. No new stream, store or key; §3 retention (400 days) already covers the 56-day and 30-day windows. |
| `PRODUCT.md` | Capabilities and Constraints: "The app never computes a score… The live activity estimate and the projected Day Strain (parity1-spec §5.2) are the two exceptions, and the app labels both as estimates." Capabilities today: add the strain target, sleep planner, HRV widget and sport suggestion once P14 ships them (written in P2 as "after parity pack 1"). |
| `DESIGN.md` | Components inventory: `LiveTargetRow`, `GoopTonightCard`, `HRVSmallView`. A short "Live Activity with a target" note under Signature or Feedback: the three-cell bottom row (§2.3), and why (160 pt). Checkmark meaning unchanged. |
| `docs/goop/spec.md` | §8.4 item 6 (Tonight card), §8.11 Sleep sheet Need, §9.2 (target sentence first, pointer to this spec), §11.2–§11.6 (HRV metric, extra line, preview host additions), §14 copy pointer. |
| `docs/goop/activity-spec.md` | §2 step 3 (target row), §7 (content state fields, target layout, alert). Pointers to this spec. |
| `docs/goop/edit-spec.md` | §2.3: one paragraph pointing to this spec §2.8 for a suggested sport. |
| `fixtures/v2/README.md` | `store_parity`, `parity/` goldens, the new score vectors and the new `day_full_config` / brief evening goldens (§10.1). |

## 7. Config keys (owner)

```sh
ghoops config set strain_intent restore      # restore | maintain | overreach; default maintain
ghoops config unset strain_intent
ghoops config set wake_target 06:45          # plan bedtimes for a fixed wake time
ghoops config unset wake_target              # back to the typical wake time
ghoops config show                           # values.strain_intent, values.wake_target
```

The server reads config per request, so the next app refresh shows the change. The installed Mac binary must be this pack's before these keys are set, because an older binary refuses a config file with keys it does not know (§1).

## 8. App changes

### 8.1 Models (GHealthCore)

- `ScoreConfig` gains `strainIntent: String?` and `wakeTarget: String?`.
- New `StrainTarget {low: Double?, high: Double?, intent: String, position: String?, status: ScoreStatus, reason: Reason?}` and `Day.strainTarget: StrainTarget?`.
- New `SleepPlan {status, reason, needMinutes, needParts: SleepPlanNeed, wakeTarget: Date?, wakeSource, efficiencyPctUsed: Double?, latencyMinutesUsed: Int?, nightsUsed, goals: [SleepGoal]}`, `SleepPlanNeed`, `SleepGoal {pct, inBedMinutes, bedtime}`, and `Day.sleepPlan: SleepPlan?`.
- New `WorkoutSuggestion {exerciseType, displayName, matches, windowDays}` and `Workout.suggested: WorkoutSuggestion?`.
- `Brief` gains the §6.5 fields, all optional.
- Everything new is optional, so bodies from an older Mac still decode.

### 8.2 Presentation (GHealthCore, pure)

- `Insights.strain(_:workouts:isToday:target:recoveryBand:)` with `target: StrainTarget? = nil` and `recoveryBand: Band3? = nil`; §4.1 then the existing sentences. Callers that pass nil get today's text.
- `SleepPlanText.needLines(need: SleepNeed, plan: SleepPlan?) -> [String]`: the §4.3 lines; with a nil plan, today's single line.
- `SleepPlanText.goalAccessibility(_ goal: SleepGoal) -> String`.
- `GoopFormat.weekdayShort(_:)` and `weekdayLong(_:)` (London, `en_GB`), if not already present.
- `SuggestionText.note(effortStart: Date) -> String` (`Usual on Tue`) and `.accessibility(sport:effortStart:)`.

### 8.3 Live session (GHealthCore and app)

- `ActivitySession.target: SessionTarget?` (§5.2), encoded in `live-session.json`; older files decode with nil.
- `ActivityController.start`: `session.target = GoopFeature.strainTarget ? SessionTarget.make(day: cached day, sessionStart: start) : nil`.
- On every estimate update: compute `projected`; call `session.target?.update(projected:)`; on true, run §2.3 step 5; persist the session as today.
- `LiveTargetRow` reads `session.target` and the current estimate.

### 8.4 Live Activity content state

`GoopActivityAttributes.ContentState` gains `dayStrain: Double?`, `targetLow: Double?`, `targetHigh: Double?`, `targetWithin: Bool?`, all optional, so a Live Activity started by an older build still decodes. `init(session:estimate:now:)` fills them from `session.target` and the projection. They take part in the "only when a field changes" rule (activity-spec §7).

### 8.5 Widget configuration (`ios/Shared/WidgetViews/Configuration.swift`)

- `ScoreMetric` gains `hrv` ("HRV"); `score` returns nil for it. A non-gated helper `var isHRV: Bool { rawValue == "hrv" }` lets views branch without naming the case.
- `LockScoreMetric` gains `hrv` ("HRV"); `selectedMetric` maps it to `ScoreMetric.hrv`.
- New `enum LockExtraLine: String, AppEnum { case none, hrv, bedtime }`, type "Extra line", cases "None", "HRV", "Bed by".
- `ScoresConfiguration` gains `var extraLine: LockExtraLine { get }`, default `.none` in a protocol extension.
- `LockScoresIntent` gains `@Parameter(title: "Extra line", default: .none) var line: LockExtraLine`, `extraLine` returns it, and:

  ```swift
  static var parameterSummary: some ParameterSummary {
      When(widgetFamily: .equalTo, .accessoryRectangular) {
          Summary("Lock Screen scores") { \.$line }
      } otherwise: {
          Summary("Lock Screen scores") { \.$metric }
      }
  }
  ```

- `ScoresEntry` gains `line: LockExtraLine`; `LockWidgetEntry` passes `metric: entry.metric` (now a `ScoreMetric`) and `line: entry.line` to `LockScoresView`.
- The dark-launch gating of these cases and the parameter is compile-time (§9).

### 8.6 Widget data (`WidgetData`)

- `hrv: VitalMetric?` = `snapshot.day.vitals.metrics.hrv_rmssd` when paired; `hrvAttention: Bool` = `vitals.monitor_state` is `attention` and `vitals.persistent` contains `hrv_rmssd`; `hrvText` = the integer value when `status` is available, else `—`.
- `bedtime: Date?` = the 100 % goal's `bedtime` when `sleep_plan.status == ok` and `date < wake_target`; else nil. `bedtimeText` = `GoopFormat.time(bedtime)` or `—`.
- Views: `HomeScoresView` branches `metric.isHRV` → `HRVSmallView`; `LockScoresView(data:family:metric:line:)` per §2.6.

## 9. Dark launch

Every commit lands on `main`, which must stay safe to install (AGENTS.md, Trunk-based development).

- **The flags.** Step P8 creates `ios/GHealth/App/GoopFeature.swift`:

  ```swift
  enum GoopFeature {
      #if DEBUG
      static let strainTarget = true
      static let sleepPlanner = true
      static let sportSuggestion = true
      static let hrvWidget = true
      #else
      static let strainTarget = false
      static let sleepPlanner = false
      static let sportSuggestion = false
      static let hrvWidget = false
      #endif
  }
  ```

- **Runtime gates (app target), the only places that read a flag:**

  | Flag | Gate |
  | --- | --- |
  | `strainTarget` | (1) `StrainScreen` passes `day.strainTarget` to `Insights.strain`, else nil. (2) `ActivityController.start` creates `session.target`, else nil. The live row, the Live Activity layout, the haptic and the alert all key off `session.target`, so they need no flag of their own. |
  | `sleepPlanner` | `SleepScreen` reads `plan = flag ? day.sleepPlan : nil` once and passes it to the card and to `SleepInfo`. |
  | `sportSuggestion` | `EditSheet` reads `suggestion = flag ? workout.suggested : nil` once when it opens on a detected effort. |
  | `hrvWidget` | `WidgetPreviewHost`'s parity section (§10.2). |

- **Compile-time gates (widget configuration, §1):** the `hrv` cases of `ScoreMetric` and `LockScoreMetric`, their display entries, `LockScoresIntent.line` and its `parameterSummary` are inside `#if DEBUG` blocks, each marked `// GoopFeature.hrvWidget` or `// GoopFeature.hrvWidget, GoopFeature.sleepPlanner` on the `#if` line. Release builds then offer exactly today's options. `LockExtraLine`, `isHRV`, `HRVSmallView` and the views compile in both configurations.
- **Mac:** the Go fields, CLI flags and config keys land as normal in P3–P6. The installed app ignores the new keys until the flags go.
- **P14** removes the flags and the `#if DEBUG` gates (keeping their Debug branches) and deletes `GoopFeature.swift`.

## 10. Fixtures and Debug launch arguments

### 10.1 Go fixtures (`fixtures/v2/`)

- **`inputs/store_parity.json`**, generated by `scripts/parity_fixture_store.py` (stdlib, deterministic, run with `python3 -I`) from `inputs/store_full.json`: store_full plus three band exercise records, `BOXING`, display name `Boxing`, 19:30:00Z–20:30:00Z on 2026-02-16, 2026-02-23 and 2026-03-02, ids `7400000000000000001` to `…003` (the last segment of `name`), copying the structure of store_full's kickboxing record and marked `synthetic_fixture: true`. Nothing else changes. Test `scripts/parity_fixture_store_test.py`: deterministic output; exactly three added records; every other record equal to store_full.
- **Goldens regenerated** with the existing `-update-goldens` flag (review the diff; existing bodies may only change `score_version` to `2.1.0` and gain the new keys):
  - every existing golden: `score_version` `2.1.0`, and, where the body has `score_config`, `strain_intent: "maintain"` and `wake_target: null`;
  - `day_full.json`: `strain_target` (§5.1) and `sleep_plan` (§5.3);
  - `day_no_sleep.json`: target `pending`, reason `no_sleep`, position null; a `sleep_plan` with `status ok` from 11 nights (the night ending 2026-03-10 is missing);
  - `day_calibrating.json`: target 13.6–16.6 from Recovery 76, position `below` (strain 12.8); plan `ok` from its 9 nights;
  - `day_new_user.json`: target `unavailable`, reason `insufficient_baseline`; plan `ok` from 4 nights;
  - `workouts_full.json`: `suggested: null` everywhere;
  - `brief_full.json`, `brief_full_values.json`: §6.5 morning fields;
  - `commands/config_show.json`: both keys in `values` and `defaults`.
- **New goldens:**

  | File | Input | Command | Notes |
  | --- | --- | --- | --- |
  | `day_full_config.json` | store_full, config `strain_intent: restore`, `wake_target: "06:45"` | `day --date 2026-03-10` | §5.1, §5.3 config cases |
  | `brief_full_evening.json` | store_full | `brief --date 2026-03-10 --part evening` | `review` status keys |
  | `brief_full_evening_values.json` | store_full | `brief --date 2026-03-10 --part evening --include-values` | §5.6 values |
  | `parity/workouts.json` | store_parity | `workouts --from 2026-03-09 --to 2026-03-10` | effort `suggested` BOXING, 3 |
  | `parity/brief_0309.json` | store_parity | `brief --date 2026-03-09` | detected workout with `suggested_exercise_type: "BOXING"` |
  | `parity/snapshot.json` | store_parity | `snapshot` | the iOS `parity` fixture set |
  | `parity/heart_rate_effort.json` | store_parity | `heart-rate --start 2026-03-09T16:40:00Z --end 2026-03-09T23:25:00Z` | the Edit sheet's request for the effort (edit-spec §6.4: ±180 min) |
  | `scores/strain_target.json`, `scores/sleep_plan.json`, `scores/trend.json` | none | pure functions | §5.1, §5.3, §5.5 |

  All at now `2026-03-10T14:30:00Z`. The three existing score vector files change only their `score_version`.
- **Preview fixtures:** `scripts/goop_preview_fixtures.py` copies `strain_target` and `sleep_plan` from `fixtures/v2/day_full.json` into `day` of `preview/snapshot_fresh.json` and `preview/snapshot_stale.json`, and adds `strain_intent: "maintain"` and `wake_target: null` to every `score_config` in the three preview files. It stays idempotent and keeps every existing key and value (their `score_version` stays `2.0.0`). Update its test.
- **Live fixture:** none new. `boxing_23m` on `fresh` gives the within-target state (§2.2).
- The app bundle copies `fixtures/v2/parity/*.json` to `Fixtures/parity/` in Debug only, in the `project.yml` build phase that removes `Fixtures` in Release.

### 10.2 Debug launch arguments

| Argument | Opens | Mockup |
| --- | --- | --- |
| `-GHealthFixture fresh`, Strain detail | target sentence (§2.1) | `strain-target` |
| `-GHealthLiveFixture boxing_23m` | live screen with the target row (§2.2) | `live-target` |
| `-GHealthWidgetPreview live_target` | `LiveActivityPreview` with zone 4, bpm 161, `strainEstimate 10.8`, `avgHR 152`, `dayStrain 12.0`, `targetLow 11.6`, `targetHigh 14.6`, `targetWithin true`, elapsed 48:10 | `lock-live` |
| `-GHealthFixture fresh`, Sleep detail scrolled to the end | Tonight card (§2.4) | `sleep-plan` |
| same, then `tonight-info` | Sleep info sheet (§2.5) | `sleep-info` |
| `-GHealthWidgetPreview fresh`, scrolled to `widget-parity` | widget preview parity section (below) | `lock`, `hrv-widget` |
| `-GHealthFixture parity -GHealthParityFixture sport` | the 2026-03-09 effort's Edit sheet on the Sport sub-step | `sport-suggest` |

- **`FixtureSet.parity`** loads `Fixtures/parity/snapshot.json`, now `2026-03-10T14:30:00Z`. It installs `FixtureEditAPI` (edit-spec §10.2) with the parity bodies: it serves `Fixtures/parity/heart_rate_effort.json` for the effort's heart-rate request and answers every mutation with 400, so a test that saves fails loudly.
- **`-GHealthParityFixture sport`** (with `-GHealthFixture parity`): pushes the workout screen for `effort-2026-03-09T19:40:00Z` on 2026-03-09 and opens its Edit sheet, which shows the Sport sub-step (edit-spec §2.7).
- **Widget preview parity section** (`WidgetPreviewHost`, appended after the inline widget and before `font-check`, id `widget-parity`, shown when `GoopFeature.hrvWidget`): a `HStack(spacing: 18)` with the small HRV widget (170×170, id `widget-hrv-small`); a `HStack(spacing: 14)` with the circular HRV (76×76, id `widget-lock-hrv`); the rectangular with `line: .bedtime` (172×76, id `widget-lock-rect-bedtime`); the rectangular with `line: .hrv` (172×76, id `widget-lock-rect-hrv`).
- **Release builds** contain no `Fixtures/parity`, no `-GHealthParityFixture`, no `parity` fixture set name in a launch-argument context and no `live_target` preview (plan P12).

## 11. Tests

### 11.1 Go

- **Config:** set and unset of both keys; each invalid value (`strain_intent push`, `wake_target 25:00`, `7:5`, `"null"` intent in the file); `config show`; `score_config` echo; the server picking up a change without a restart; an old config file without the keys reads with defaults.
- **Strain target:** every `strain_target.json` case; `day_full` and `day_full_config`; status and reason copied from Recovery (pending, unavailable); position null when strain is null; the target present on a closed past day; `score.Version == "2.1.0"` and in every body.
- **Sleep plan:** every `sleep_plan.json` case; null for closed and not-started cycles; a nap after waking lowers `need_minutes`; a nap before `cycle_start` does not; the main sleep that starts the cycle is never a nap; 2 nights → unavailable; config wake with 2 nights; DST spring-forward; `cycle_strain` null → `strain_extra 0`.
- **Suggestion:** the parity case; each failing rule on its own (different weekday, 91 minutes apart, 0.49× and 2.01× duration, two matches, 3 of 6 matches = 50 %, a hidden entry, an `OTHER` entry, a candidate on the effort's own date, one 57 days back); a named effort (goop, `origin: added`) counts as history; `suggested` null on recorded and goop entries; Day Strain unchanged.
- **Brief:** every `trend.json` case; `--part` morning, evening and an invalid value (CLI exit 2, HTTP 400 naming `part`); status-only has no `low`, `high`, `need_minutes`, `bedtime`, `mean_7`, `mean_30`, `zones_*`; `review` absent in the morning; `new_flags` against D−1; CLI and HTTP bodies `same`.
- **Goldens:** all of §10.1.

### 11.2 GHealthCore (`make ios-core-test`)

- Decoding `day_full.json` (target and plan), `parity/workouts.json` (suggestion), `brief_full_evening_values.json`, `commands/config_show.json`, and a body without any new key.
- `Insights.strain`: every row of §4.1 (ok × below/within/above × today/past, each intent, pending, unavailable, null strain), and the `fresh` fixture sentence.
- `SleepPlanText.needLines`: the `fresh` lines of §4.3; latency 0; config wake; unavailable; nil plan (today's single line).
- `SessionTarget`: `make` (not current cycle, cycle started after the session, target not ok, `no_heart_rate` base 0, other null base); projections and crossing sequences of §5.2; Codable round trip; an old `live-session.json` without `target`.
- `ContentState` with and without target fields, and decoding an older state.
- `SuggestionText` for each weekday.

### 11.3 UI (XCUITest, fixture mode)

- **`testStrainTarget`.** Launch `fresh`; open Strain; assert the insight text starts with `Today's target is 13.3 to 16.3 for high recovery. You are below it.` Relaunch with `-GHealthLiveFixture boxing_23m`; assert `activity-target` exists, `activity-target-range` reads `13.3–16.3`, `activity-target-within` exists, and `activity-target-estimate` matches `^1[3-6]\.[0-9]$`.
- **`testTonightsSleep`.** Launch `fresh`; open Sleep; reveal `tonight-card`; assert `tonight-need` `8:03`, `tonight-wake` `07:07` and `tonight-goal-100` label `100 percent of need: 8 hours 48 minutes in bed, bed by 22:19`; tap `tonight-info`; assert the sheet contains `Tonight so far: baseline 7:30 + strain 0:11 + debt 0:22 − naps 0:00 = 8:03 needed.`
- **`testSportSuggestion`.** Launch `parity` + `sport`; assert `edit-sport-BOXING` is selected and contains `Usual on Mon`, and `edit-sport-use` reads `USE BOXING` and is enabled; tap it; assert `edit-sport-row` shows `Boxing` and `edit-save` reads `SAVE BOXING`; close with `edit-close`. `FixtureEditAPI` received no mutation.
- **`testWidgetsTour`** (extended): for `fresh`, reveal `widget-parity`, assert `widget-hrv-small` contains `56`, `widget-lock-rect-bedtime` contains `22:19`, `widget-lock-rect-hrv` contains `56`; capture `widgets-fresh-3`.
- **`testParityScreensTour`.** Captures `parity1-strain-target` (+ `-2` scrolled to the insight), `parity1-live-target`, `parity1-lock-live`, `parity1-sleep-plan`, `parity1-sleep-info`, `parity1-widgets` (the parity section) and `parity1-sport-suggest`, using §10.2.
- **`testAccessibilityTour`** adds Sleep scrolled to the Tonight card at accessibility 5 (`parity1-sleep-plan-ax5`).
- **`testGalleryTour`** shows `LiveTargetRow` and `GoopTonightCard` at the default size and accessibility 5.
- **Full suite:** only `testBackgroundRefreshProbe` is skipped.

## 12. Out of scope

- A target band on the Strain ring, any strain target on Home, and `days` row fields for the target (whoop-parity.md gap 1's second step).
- A bedtime notification or any notification permission.
- Automatic naming of detected efforts at read time.
- HRV in the medium widget or the inline Lock Screen widget; resting HR in widgets; a new widget kind.
- More-tab rows for `strain_intent` or `wake_target` (settings stay on the Mac).
- A weekly or monthly brief part (gap 7).
- **Owner follow-ups outside the repo (not built by this plan):**
  - A morning assistant run: read `trend`, `strain_target` and `sleep_plan` from `brief --include-values`.
  - An evening assistant run with `brief --part evening --include-values`.
  - A coaching assistant: the same new fields, and that `workouts[].suggested_exercise_type` can be confirmed with `ghoops activity edit` (edit-spec §7) or by naming in the app.
  - Which new fields may go to cloud models in status-only mode is already decided (decision 3); the agents keep sending only `brief` output (contract §9.3).

## 13. Decisions made in this spec

1. **The suggestion note is `Usual on Tue`, in sentence case.** The owner wrote `USUAL ON TUE`, and also asked for the existing picker row style. That style's note is sentence-case `rowNote` (`Last: Sat`); an uppercase note would break DESIGN.md's Uppercase Label Rule. **Owner may overrule** with an uppercase note, which would need a label-style note in `GoopChoiceRow`.
2. **Live Activity target layout.** A fourth row does not fit the 160 pt limit. With a target, the bottom row is `STRAIN | EST. DAY STRAIN | TARGET` and the wordmark and `AVG HR` leave the Lock Screen view; without one it is unchanged. The in-app live screen keeps `AVG HR`. **Owner may overrule:** keep the wordmark and drop `EST. DAY STRAIN` (target only), or keep `AVG HR` and drop the wordmark.
3. **Checkmark beside `TARGET`**, not beside the range, so the Lock Screen cell fits; the live screen does the same for consistency.
4. **The projection's caption is `EST. DAY STRAIN`** on both surfaces, to label it an estimate in the width a Lock Screen cell allows.
5. **One extra rectangular line, HRV or BED BY**, chosen by a new `Extra line` parameter that only the rectangular family shows. Both together would need five lines.
6. **Widget options are gated at compile time** (§9), because App Intents metadata cannot be hidden at runtime.
7. **`need_parts` field names** follow `sleep.need` (`*_minutes`, `debt_nights_used`) rather than the sketch's short names, plus `cycle_strain` for the current cycle's strain.
8. **The planner's typical wake uses the planner's own nights** (main sleeps with an efficiency), so one count `nights_used` describes wake, efficiency and latency.
9. **Fewer than 3 nights → no plan**, rather than a default efficiency or a 07:00 wake (missing stays missing). Latency is 0 when no night records it, as sketched.
10. **The projection base is frozen at the start**, so a mid-session snapshot refresh cannot count minutes twice; it can undercount the time before the band's last sync, which the estimate label covers.
11. **Naming takes `USE BOXING`, then `SAVE BOXING`.** The sketch hoped for one tap, but edit-spec opens an effort on the Sport sub-step, and that flow stays.
12. **`review` carries only evening-only fields**; the target position, bedtime and workout strain stay in their own brief fields.
13. **Past days' targets use today's `strain_intent`**, because config is not stored per day.
14. **Bedtimes and times in the Tonight card are Sofia `valueSmall`**, as the sketch says and as chart start and end times are. Activity-row clock times stay Nunito `time`.
15. **The trend's strain values skip the open cycle**, so a morning brief does not compare a partial day with full ones.
