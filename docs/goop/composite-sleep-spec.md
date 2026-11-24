# ghoops: Composite Sleep Performance (issue #5)

Status: approved by the lead on 2026-11-22, with D5, D9, D10 and D11 accepted. The Mac steps CS1 to CS3 are built first; the app steps CS4 and CS5 wait for the lead. Written 2026-11-22 against `main` at `b99a4e9` (`score_version` 2.3.0). The mockup is [mockups/composite-sleep.html](mockups/composite-sleep.html), rendered in `mockups/screens/composite-sleep-<key>.png`. The build plan is [composite-sleep-plan.md](composite-sleep-plan.md). This document changes no code, golden, fixture or `score_version`.

## 0. In plain words

Today ghoops's Sleep Performance compares hours slept with sleep need, and nothing else. This adds a second way to score a night, the **composite**: 70% hours vs. needed, 15% consistency and 15% efficiency. It is a Mac setting and is **off by default**:

```sh
ghoops config set sleep_score_mode composite    # turn on
ghoops config unset sleep_score_mode            # back to hours vs. needed
```

When it is on, the Sleep and Home dials show the composite, Recovery uses it as its sleep input, and the Sleep info sheet shows how it was made. When it is off, every response, golden and `score_version` stays byte for byte what it is today.

On the owner's store (§2, counts only), the composite would lower the sleep dial by 5 points or more on 27 of 39 nights and drop its band on 12. Irregular bed and wake times cause most of the drop. Recovery would change on 30 of 31 days, but its band would change on only 1.

## 1. Decisions

This spec extends [scores.md](../v2/scores.md) §0, §0.1, §4.5 and §9, and [contract.md](../v2/contract.md) §5.1, §5.1.1, §5.2.1, §5.3, §5.5, §5.10 and the `config` body. Where they disagree with this spec, this spec wins, and the build updates each one in the step that changes its behaviour.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | Config key `sleep_score_mode`: `"sufficiency"` (default) or `"composite"`. `config unset` and `config set sleep_score_mode sufficiency` both restore the default. | Owner default for tonight: opt-in, off. The issue names the key. |
| D2 | Three parts: hours vs. needed (sufficiency), consistency and efficiency. Weights 0.70, 0.15 and 0.15. A missing consistency or efficiency gives its weight to sufficiency. | WHOOP's 2025 score blends these three plus sleep stress, and weights some parts more than others without publishing them [W1]. Oura calls total sleep its most significant contributor [O1]. Sleep stress needs a motion stream ghoops doesn't have (whoop-parity.md §4). Weights are the issue's, and the owner can change them (§11). |
| D3 | Efficiency part = clamp(100 × (efficiency − 70) / (90 − 70), 0, 100). It is 0 at 70% and full at 90%. | 90% is WHOOP's optimal edge and ghoops's own `EfficiencyHighMin` [W1]. At 70%, three of every ten hours in bed are spent awake. Oura treats 85% as a sign of good sleep [O2], and that maps to 75 here. |
| D4 | The composite uses the reported, rounded `performance.value`, `consistency.value` and `efficiency_pct`. It is an integer, rounded half away from zero, with the performance bands (85, 70). | scores.md §1.1: a reader can recompute it from JSON. WHOOP uses the same 85 and 70 edges for its blended score [W1]. |
| D5 | `sleep.performance` keeps its meaning in every mode. The composite is a new object, `sleep.performance_composite`, and it is **present only in composite mode**. | The issue keeps `performance.value`'s meaning, so schema 2 holds (contract §1). The lead's brief needs byte-identical default output, so the object can't always be present, as the issue first proposed. Its presence tells clients which mode the Mac used. |
| D6 | In composite mode Recovery's sleep input is the composite: `recovery.inputs.sleep_performance` and `recovery.components.sleep_score` carry it. Recovery's weights don't change. | The issue: the mode picks what feeds Recovery's sleep component. The Recovery sheet's "Sleep performance" line then equals the Sleep dial. |
| D7 | In composite mode `score_version` is `<Version>+composite.1`, so `2.3.0+composite.1` today. In default mode it stays `Version`. | Switching modes must change `score_version`, and unsetting must restore it (issue). A suffix keeps the default identical and never collides with another bump of `Version` on `main`. If the composite's constants change, `composite.1` becomes `composite.2`. |
| D8 | `score_config.sleep_score_mode` and `score_constants.sleep.composite` appear only in composite mode. | Default bodies stay byte-identical. The app reads every composite number from the Mac (AGENTS.md hard rule). |
| D9 | In composite mode `days` rows gain `sleep_performance_composite`, and `day.comparison.metrics` gains `sleep_performance_composite`. | The Home tile and the Trends chart named "Sleep Performance" must show the same number as the dial, with a 30-day mean of the same thing. |
| D10 | `brief` is unchanged, except that its Recovery values and `score_version` follow the mode. | `brief` has no `score_config`, and agents read `sleep.performance` as hours vs. needed. The suffix tells them which mode produced Recovery. Adding the composite to `brief` is a follow-up (§10). |
| D11 | The app shows the composite behind a new flag `GoopFeature.compositeSleep`: on in Debug, off in Release. With the flag off, the app ignores the composite fields. | AGENTS.md: unfinished features ship dark. The flag comes out only after the owner decides to turn the mode on (§11). |

Rejected:
- **Changing what `performance.value` means in composite mode.** It needs `schema_version` 3 (contract §1), and assistants read it as hours vs. needed.
- **Always emitting `performance_composite`**, as the issue first said. Every default golden would change, against the brief.
- **A fourth part for restorative sleep (deep plus REM)**, as in Oura's contributors [O2]. WHOOP leaves stages out of Sleep Performance [W1]. Stages are the band's estimates (DESIGN.md, The Honest Number Rule), and the Sleep screen already shows them against typical ranges. It can be added later as `composite.2`.
- **Oura's latency and timing parts** [O2]. Consistency already covers timing, and efficiency already counts time awake in bed.
- **Renormalising the weights over the parts present** (0.70/0.85 and 0.15/0.85). The issue's rule gives a missing part's weight to sufficiency, which is easier to explain on the sheet.
- **Weights as config keys.** That would be a second way to change scores, three keys that must sum to 1, and more validation. A weight change is a constants change with a `composite.N` bump, decided by the lead.
- **`score_version` 2.4.0 in composite mode.** Another agent's bump to 2.4.0 on `main` would collide with it.

## 2. What the owner's data says

Read-only, on 2026-11-22, through `~/.local/bin/ghealth days --json` (four 90-day windows) and `day --date D --json` for each day with a Recovery. A script printed counts only. No value or date was printed or written.

| Count | Result |
| --- | --- |
| Rows read | 360 |
| Nights with a sleep performance | 39 |
| … with a consistency value | 36 |
| … with an efficiency value | 39 |
| … where hours vs. needed is capped at 100 | 10 |
| Days with a Recovery | 31 |
| Consistency below its medium edge (60) | 33 of 36 |
| Efficiency at or above 90 | 27 of 39 |
| Efficiency at or below 70 (part scores 0) | 0 of 39 |
| Method check: Recovery rebuilt from its reported components equals the reported value | 30 of 31 (one off by 1 from 1-dp rounding) |

Composite against hours vs. needed, and the Recovery it would give, for three weight sets and two efficiency ranges:

| Weights (S/C/E) | Efficiency 0 → full | Sleep same | Sleep higher | Sleep lower by ≥ 5 | Sleep band moves (down/up) | Recovery changes | Recovery band moves |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **70/15/15 (chosen)** | **70 → 90** | **1** | **6** | **27** | **12 (12/0)** | **30 of 31** | **1 of 31 (down)** |
| 70/15/15 | 75 → 95 | 2 | 3 | 29 | 15 (15/0) | 30 of 31 | 1 of 31 (down) |
| 60/20/20 | 70 → 90 | 1 | 6 | 29 | 18 (18/0) | 30 of 31 | 1 of 31 (down) |
| 60/20/20 | 75 → 95 | 2 | 3 | 31 | 22 (22/0) | 30 of 31 | 1 of 31 (down) |
| 80/10/10 | 70 → 90 | 2 | 5 | 22 | 6 (6/0) | 27 of 31 | 1 of 31 (down) |
| 80/10/10 | 75 → 95 | 2 | 3 | 24 | 8 (8/0) | 27 of 31 | 1 of 31 (down) |

What this means for the owner:
- The composite is mostly a consistency signal on this store, because consistency is low on 33 of 36 nights and efficiency is usually high.
- It moves the sleep dial a lot and Recovery a little: Recovery's sleep weight is 0.25, so a 10-point sleep drop costs Recovery 2.5 points.
- The Recovery band count is at most 1 either way, because of the one-point method error above.

## 3. References

Retrieved 2026-11-22.

- [W1] WHOOP, "WHOOP Sleep", support.whoop.com/s/article/WHOOP-Sleep. The score "combines sleep consistency, sufficiency, stress, and efficiency"; it was "previously … based solely on 'Hours vs Needed'". "Each factor is weighted based on its impact … Some factors have a greater influence on your score than others." Bands: performance 85%+ optimal, 70–85% sufficient, under 70% poor; consistency 80/70; efficiency 90/80; "a Sleep Efficiency above 90% is considered optimal".
- [O1] Oura, "Sleep Score", support.ouraring.com/hc/articles/360025445574. "Total sleep time is the most significant contributor in achieving optimal rest." Bands 85–100 optimal, 70–84 good, 60–69 fair, below 60 pay attention.
- [O2] Oura, "Sleep Contributors", support.ouraring.com/hc/en-us/articles/360057792293. Seven contributors: total sleep, efficiency, restfulness, REM, deep, latency and timing. "For most adults, sleep efficiency of 85% is a sign of peaceful and uninterrupted sleep."
- Already cited in scores.md §11: Watson et al. 2015 (duration), Reed and Sacco 2016 (efficiency denominator), Phillips et al. 2017 and Fischer, Klerman and Phillips 2021 (regularity).

## 4. The formula (scores.md new §4.5a)

Constants in `internal/score/constants.go`, reported in `score_constants.sleep.composite` (§6.2):

| Name | Value |
| --- | --- |
| `CompositeWeightSufficiency` | 0.70 |
| `CompositeWeightConsistency` | 0.15 |
| `CompositeWeightEfficiency` | 0.15 |
| `CompositeEfficiencyZero` | 70 |
| `CompositeEfficiencyFull` | 90 |
| `CompositeRevision` | `"composite.1"` |

For the night ending on D, in composite mode:

```
S = sleep.performance.value            # int?, §4.5
C = sleep.consistency.value            # int?, §4.6
E = sleep.efficiency_pct               # int?, §4.2
if S is null:
    value = band = weights = parts = null
    status, reason = performance.status, performance.reason    # "pending" or "unavailable", "no_sleep"
else:
    e_part = E is null ? null : clamp(100 × (E − 70) / (90 − 70), 0, 100)       # full precision
    w_s, w_c, w_e = 0.70, 0.15, 0.15
    if C is null:      w_s += w_c; w_c = 0
    if e_part is null: w_s += w_e; w_e = 0
    value  = round(w_s × S + w_c × (C or 0) + w_e × (e_part or 0))            # int, half away from zero
    band   = high ≥ SleepPerformanceHighMin (85); medium ≥ SleepPerformanceMediumMin (70); else low
    status = "ok", reason = null
```

Floating point must not move a half-way case: compute `w × part` in integer hundredths when the parts are integers (they always are with these constants, because e_part is 5 × (E − 70) clamped), then round once.

Recovery (§2.3) in composite mode uses `sleep_score = performance_composite.value`. Every other Recovery rule is unchanged; the gate is the same, because the composite is null exactly when the sufficiency is.

### 4.1 Golden vectors (`fixtures/v2/scores/sleep_composite.json`)

Input `{performance: {value, status, reason}, consistency, efficiency_pct}`. Expected `{value, band, status, reason, weights, parts}`.

| Case | S | C | E | e_part | Weights used | Value, band |
| --- | --- | --- | --- | --- | --- | --- |
| `full_night` (half-way rounds up) | 100 | 90 | 94 | 100 | .70/.15/.15 | 98.5 → **99**, high |
| `short_night_usual_time` | 72 | 92 | 93 | 100 | .70/.15/.15 | 79.2 → **79**, medium |
| `full_night_odd_time` | 100 | 35 | 92 | 100 | .70/.15/.15 | 90.25 → **90**, high |
| `odd_time_poor_efficiency` (mockup) | 94 | 52 | 84 | 70 | .70/.15/.15 | 84.1 → **84**, medium |
| `no_consistency` | 94 | null | 88 | 90 | .85/.00/.15 | 93.4 → **93**, high |
| `efficiency_at_zero_edge` | 90 | 80 | 70 | 0 | .70/.15/.15 | **75**, medium |
| `efficiency_below_zero_edge` | 90 | 80 | 62 | 0 (clamped) | .70/.15/.15 | **75**, medium |
| `efficiency_at_full_edge` | 90 | 80 | 90 | 100 | .70/.15/.15 | **90**, high |
| `efficiency_above_full_edge` | 90 | 80 | 97 | 100 (clamped) | .70/.15/.15 | **90**, high |
| `no_efficiency` | 90 | 80 | null | null | .85/.15/.00 | 88.5 → **89**, high |
| `no_sleep` | null (`unavailable`, `no_sleep`) | 80 | null | — | null | null, `unavailable`, `no_sleep` |
| `no_sleep_today` | null (`pending`, `no_sleep`) | 80 | null | — | null | null, `pending`, `no_sleep` |

The issue's two nights now differ: a short night at the usual time scores 79, and a full night at an odd time scores 90. Hours vs. needed alone gives 72 and 100.

## 5. Config (scores.md §0.1)

| Key | Type | Default | Valid | Effect |
| --- | --- | --- | --- | --- |
| `sleep_score_mode` | string | `"sufficiency"` | `"sufficiency"`, `"composite"`; null and `""` invalid | §4.5a, §2.3 |

- `ghoops config set sleep_score_mode composite` writes the key. `set … sufficiency` and `config unset sleep_score_mode` remove it from the file. Any other value exits 2.
- The default is never written or echoed. `config show --json` lists `sleep_score_mode` in `values` only when it is `composite`, and `defaults` doesn't change. A file that says `"sufficiency"` is valid and is treated as absent.
- The server loads config on each request, so a change needs no restart (scores.md §0.1).

## 6. API (contract.md)

All additions appear only in composite mode. In default mode no body changes.

### 6.1 Envelope

- `score_version`: `"2.3.0+composite.1"` on every body that carries `score_version`, `brief` included.
- `score_config.sleep_score_mode`: `"composite"`, after `wake_target`.

### 6.2 `score_constants.sleep.composite`

```json
"composite": {
  "weights": { "sufficiency": 0.70, "consistency": 0.15, "efficiency": 0.15 },
  "efficiency_zero_pct": 70,
  "efficiency_full_pct": 90
}
```

Last key of `score_constants.sleep`. A client that finds it missing treats the composite's rules as unknown and leaves out the sentences that name them.

### 6.3 `sleep.performance_composite` (sleep summary, contract §5.5)

After `performance` in the sleep summary, so it appears in `day.sleep`, the `sleep` body, `snapshot.day.sleep` and `snapshot.sleep`.

```json
"performance_composite": {
  "value": 84, "band": "medium", "status": "ok", "reason": null,
  "weights": { "sufficiency": 0.70, "consistency": 0.15, "efficiency": 0.15 },
  "parts": { "sufficiency": 94, "consistency": 52, "efficiency": 70.0 }
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `value` | `int?` | §4.5a, 0 to 100 |
| `band` | `Band3?` | performance bands |
| `status` | `"ok"`, `"pending"`, `"unavailable"` | as `performance` |
| `reason` | `"no_sleep"` or null | as `performance` |
| `weights` | object or null | the weights used for this night (2 dp, sum 1.00); null when `value` is null |
| `parts` | object or null | `{sufficiency: int, consistency: int?, efficiency: num? (1 dp)}`: the inputs S and C and the efficiency part `e_part`; null when `value` is null |

### 6.4 Recovery (contract §5.3)

`inputs.sleep_performance` and `components.sleep_score` hold `performance_composite.value`. Nothing else changes.

### 6.5 `days` rows and comparison (contract §5.10, §5.2.1)

- Each row gains `sleep_performance_composite` (`int?`), after `sleep_consistency`.
- `day.comparison.metrics` gains `sleep_performance_composite`, last, by the §5.2.1 rule.
- The `days` summary doesn't change.

### 6.6 What follows Recovery

Everything computed from Recovery follows the mode: `strain_target` (its centre moves 0.12 per Recovery point), the `days` rows' `recovery`, `comparison.metrics.recovery` and `brief` Recovery and its trend.

## 7. Past days and switching

Scores are views: the Mac computes every score from the store and the current config on each read, and stores none (scores.md §0.1, §3.12).
- Turning the mode on recomputes Recovery, and everything in §6.6, for every past day on the next read. Nothing is migrated or written apart from the config file.
- Turning it off restores every body exactly, except `generated_at`. Plan step C3 checks this byte for byte.
- The phone shows whatever its last body says. A cached snapshot keeps the old mode until the next refresh, and widgets keep it until their next timeline. Each body is consistent with itself, because its values, `score_config` and `score_version` come from one build.
- The phone never computes sleep performance or Recovery. After a sleep edit it shows UPDATING until the Mac answers (sleep-edit-spec), so the instant-save overlay needs no change.

## 8. App

Everything below is behind `GoopFeature.compositeSleep` (D11). With the flag off, or with no `performance_composite` in the body, the app behaves exactly as today. The mockup shows each screen.

| Where | Composite mode |
| --- | --- |
| Home Sleep dial; Sleep detail dial; widget sleep ring | `performance_composite.value`, band colour from its band. |
| Home tile and Trends "Sleep Performance" | the composite row value and `comparison.metrics.sleep_performance_composite.mean`. |
| Sleep contributor card | unchanged: HOURS VS. NEEDED, CONSISTENCY, EFFICIENCY (issue). |
| Recovery info sheet | unchanged code. Its "Sleep performance" line now carries the composite (D6). |
| Sleep insight sentence | first sentence from the composite band; the hours sentence from the sufficiency band (today's logic); one sentence naming the low part (below). |
| Sleep info sheet, HOW THIS WORKS | the composite breakdown, then a Sleep performance scale above the three existing scales (below). |
| Fine print | "Score version 2.3.0+composite.1", from the body. |

**Approved copy.** Numbers in angle brackets come from the body. Nothing else is a number.

Insight card:
- `Your Sleep Performance is <composite level>.` then today's hours sentence: `You got <asleep> of the <need> you needed.` (sufficiency optimal), or `You were <short> short of the <need> you needed.`
- Then the low part, when its band is `low`: `Irregular bed and wake times lowered it.` (consistency), `Time awake in bed lowered it.` (efficiency), or `Irregular bed and wake times and time awake in bed lowered it.` (both).
- The debt and strain sentences stay as today.

Sleep info sheet, HOW THIS WORKS:
- Sentence: `Sleep Performance blends hours vs. needed, consistency and efficiency.`
- A `GoopBreakdown` (The Numbers-In-Rows Rule):

  | Label | Note | Value |
  | --- | --- | --- |
  | Hours vs. needed | `<S>% · <w_s>% weight` | `+<w_s × S>` (1 dp) |
  | Consistency | `<C>% · <w_c>% weight`, or `Not available · share moved to hours` | `+<w_c × C>` or `—` |
  | Efficiency | `<E>% · scores <e_part> · <w_e>% weight`, or `Not available · share moved to hours` | `+<w_e × e_part>` or `—` |
  | **SLEEP PERFORMANCE** (total) | | `<value>%` |

- Footnotes:
  - `Efficiency scores nothing at <efficiency_zero_pct>% and full marks from <efficiency_full_pct>%. The total is rounded to a whole percent.` (Rule sentences, built from `score_constants.sleep.composite`. Left out when it is missing.)
  - `Set on your Mac with ghoops config. Without it, Sleep Performance is hours vs. needed.`
- Then `GoopLevelHeader` and four `GoopLevelScale`s: `Sleep performance` (composite value and band, performance bands), then today's `Hours vs. needed`, `Consistency` and `Efficiency`.
- With no sleep, the breakdown shows `—` values and the total `—`, as the Recovery sheet does.

`Hours vs. needed` replaces today's sentence `Sleep Performance = time asleep ÷ sleep need, capped at 100%.` in composite mode only.

## 9. Fixtures and tests

- `fixtures/v2/scores/sleep_composite.json`: §4.1 vectors, `score_version` `"2.3.0+composite.1"`.
- `fixtures/v2/composite/`: whole-body goldens built from `store_full` with `sleep_score_mode: composite`: `day_full.json`, `sleep_full.json`, `days_full.json` and `snapshot.json`.
- Every existing golden is unchanged. The test that writes goldens fails if any existing file differs, without `-update-goldens`.
- An engine test moves two of the seven nights before D by four hours in an in-memory copy of `store_full`. It checks that consistency drops, that the composite is below the sufficiency, that Recovery's `sleep_score` equals the composite, and that Recovery's value changes. It also checks that default mode on the same copy gives the sufficiency.
- iOS: fixture set `composite` (Debug), from `preview/snapshot_fresh.json` with the composite fields of the mockup night. Core tests cover the helper, the copy and `EngineNumberTests`; UI tests cover the dial, the tile and the sheet.

## 10. Out of scope, follow-ups

- `brief` carries no composite (D10). If assistants should report it, add `sleep.performance_composite` to `brief` (values mode) and say which mode in status mode.
- A restorative part (`composite.2`), if the owner wants stages in the score.
- Removing `GoopFeature.compositeSleep` once the owner turns the mode on.

## 11. What the owner decides

1. **Turn it on or not.** On this store it lowers the sleep dial on most nights, mostly through consistency, and moves the Recovery band on about 1 day in 31 (§2). Recommended: try it for a week with `ghoops config set sleep_score_mode composite`, after the app flag comes out.
2. **The weights.** 70/15/15 with efficiency counted from 70% to 90% (recommended), or another set from §2.

What the lead decides before the build: D5 (present only in composite mode), D9 (rows and comparison), D10 (`brief` unchanged) and D11 (flag scope includes widgets).

**Owner decision (2026-11-24): turn it on, with weights 70/15/15.** This follows [sleep-model-research.md](../v2/sleep-model-research.md): stages and sleeping heart rate stay out, and a wake-ups part (`composite.2`) is a later lead call. Sol builds CS4, CS5 and the flag-removal step (CS6 in the plan). After the owner's next install, the lead runs `config set sleep_score_mode composite` on the owner's Mac with the owner present, and the owner checks the phone.
