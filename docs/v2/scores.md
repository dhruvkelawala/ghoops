# ghoops v2: scores

Status: design spec. `score_version` for everything in this file is **`2.4.1`**. Inputs come from the v2 store described in [data.md](data.md); output field names are defined in [contract.md](contract.md). Golden test vectors live in [`fixtures/v2/scores/`](../../fixtures/v2/scores/); whole-response goldens are listed in [`fixtures/v2/README.md`](../../fixtures/v2/README.md).

These are ghoops's own transparent estimates. They are not WHOOP's or Fitbit's algorithms, they are not medical measurements, and no output may describe them as a diagnosis. Every score carries its inputs, the baseline it used, a confidence or coverage value, and is `null` with a machine-readable reason when an input is missing.

The phone's estimates use the engine's numbers from `score_constants` (contract §5.1.1).

Scores are computed in Go (`internal/score`), from the current store, every time a response is built. The app and assistants read the numbers through the CLI or HTTP. The phone also computes Strain for its live activity estimate, projected Day Strain, edit preview and instant-save overlay, always with the Mac's formula and `score_constants` ([parity1-spec §5.2](../goop/parity1-spec.md#52-projected-day-strain-and-the-crossing-phone-ghealthcore)). Its persisted `SessionTarget` has `cycleDate`, `baseTrimp`, `low`, `high` and `crossing` (`unknown`, `armed`, `inactive`, `fired`); these are phone session fields, not additional API scores. Because Google can revise past data, a past day's score can change after a later `collect`; that is expected.

## 0. Constants

Every constant below is a named Go constant in `internal/score/constants.go` with exactly this name and value. Changing any of them changes `score_version` (minor bump, for example `2.1.0`).

| Name | Value | Used in |
| --- | --- | --- |
| `BaselineWindowDays` | 42 | §1.3 |
| `BaselineMaxValues` | 28 | §1.3 |
| `BaselineMinValues` | 7 | §1.3, §2 |
| `CalibratedValues` | 14 | §2.5 |
| `SDFloorLnRMSSD` | 0.10 | §1.3 |
| `SDFloorRestingHR` | 2.0 (bpm) | §1.3 |
| `SDFloorRespRate` | 0.4 (breaths/min) | §1.3 |
| `SDFloorSpO2` | 0.5 (%) | §1.3 |
| `SDFloorSkinTemp` | 0.10 (°C) | §2.3 |
| `ZClamp` | 3.0 | §1.4 |
| `WeightHRV`, `WeightRestingHR`, `WeightSleep` | 0.55, 0.20, 0.25 | §2.3; reported in `components.weights` |
| `PenaltySlope`, `PenaltyMax` | 5.0, 10.0 | §2.3 |
| `RecoveryHighMin`, `RecoveryMediumMin` | 67, 34 | §2.4 |
| `TrimpA`, `TrimpB` (profile `banister_b192`, default) | 0.64, 1.92 | §3.5 |
| `TrimpA`, `TrimpB` (profile `banister_b167`) | 0.86, 1.67 | §3.5 |
| `HRRFloor` | 0.30 | §3.5 |
| `StrainK`, `StrainTrimpCap` | 10.0, 700.0 | §3.6 |
| `CoverageHigh`, `CoverageMedium` | 0.80, 0.50 | §3.7 |
| `TypicalWakeDays`, `TypicalWakeMinNights`, `TypicalWakeDefaultMinutes` | 14, 3, 420 | §3.1 |
| `EffortHRR`, `EffortMinMinutes`, `EffortMaxGap`, `EffortOverlap` | 0.50, 10, 2, 0.5 | §3.9 |
| `SleepBaseNeedMinutes` (default, configurable 360 to 600) | 450 | §4.4 |
| `StrainExtraPerPoint`, `StrainExtraFrom`, `StrainExtraMax` | 4.0, 10.0, 45 | §4.4 |
| `DebtFactor`, `DebtNights`, `DebtMax` | 0.25, 3, 60 | §4.4 |
| `NapCreditMax` | 120 | §4.4 |
| `NeedMin`, `NeedMax` | 300, 720 | §4.4 |
| `ConsistencyNights`, `ConsistencyMinNights`, `ConsistencyZeroSD` | 7, 4, 120.0 | §4.6 |
| `CollectorStaleMinutes` | 90 | contract §4 |
| `DeviceStaleMinutes` | 360 | contract §4 |
| `StrainTargetBase` | 6.0 | §3.12 |
| `StrainTargetPerRecovery` | 0.12 | §3.12 |
| `StrainTargetHalfWidth` | 1.5 | §3.12 |
| `StrainTargetRestoreOffset` | −3.0 | §3.12 |
| `StrainTargetOverreachOffset` | 2.0 | §3.12 |
| `Zone2HRR` | 0.50 | §3.5; reported in `score_constants` |
| `Zone3HRR` | 0.60 | §3.5; reported in `score_constants` |
| `Zone4HRR` | 0.70 | §3.5; reported in `score_constants` |
| `Zone5HRR` | 0.85 | §3.5; reported in `score_constants` |
| `StrainModerateMin` | 10.0 | §3.6; reported in `score_constants` |
| `StrainStrenuousMin` | 14.0 | §3.6; reported in `score_constants` |
| `StrainAllOutMin` | 18.0 | §3.6; reported in `score_constants` |
| `SleepPerformanceHighMin` | 85 | §4.5; reported in `score_constants` |
| `SleepPerformanceMediumMin` | 70 | §4.5; reported in `score_constants` |
| `ConsistencyHighMin` | 80 | §4.6; reported in `score_constants` |
| `ConsistencyMediumMin` | 60 | §4.6; reported in `score_constants` |
| `EfficiencyHighMin` | 90 | §4.2; reported in `score_constants` |
| `EfficiencyMediumMin` | 85 | §4.2; reported in `score_constants` |
| `RecordedHiddenOverlap` | 0.5 | §3.8a; reported in `score_constants` |
| `VitalRangeSD` | 1.25 | §5; reported in `score_constants` |
| `VitalAttentionNights` | 2 | §5.1, §6; reported in `score_constants` |
| `VitalAttentionMinVitals` | 2 | §5.2, §6; reported in `score_constants` |
| `SpO2FlagSD` | 2.0 | §6 |
| `CompositeWeightSufficiency`, `CompositeWeightConsistency`, `CompositeWeightEfficiency` | 0.70, 0.15, 0.15 | §4.5a; composite mode only; reported in `score_constants.sleep.composite` |
| `CompositeEfficiencyZero`, `CompositeEfficiencyFull` | 70, 90 | §4.5a; composite mode only; reported in `score_constants.sleep.composite` |
| `CompositeRevision` | `"composite.1"` | §4.5a; changing a composite constant bumps it instead of `Version` |
| `HRVTrendDays` | 7 | §5.3; reported in `score_constants` |
| `HRVTrendMinNights` | 4 | §5.3; reported in `score_constants` |
| `HRVTrendBandSD` | 1.0 | §5.3; reported in `score_constants` |
| `HRVTrendMinBaseline` | 14 | §5.3; reported in `score_constants` |

### 0.1 Owner configuration

`~/.config/ghealth/config.json` (create the directory `0700`, the file `0600`; a missing file means all defaults). It holds no secrets. `ghoops config show --json` prints the effective values; `ghoops config set <key> <value>` validates and writes; `ghoops config unset <key>` restores the default.

| Key | Type | Default | Valid | Effect |
| --- | --- | --- | --- | --- |
| `max_hr_override_bpm` | integer or null | null | 120 to 230 | §3.3 source 1 |
| `sleep_base_need_minutes` | integer | 450 | 360 to 600 | §4.4 |
| `trimp_profile` | string | `"banister_b192"` | `"banister_b192"`, `"banister_b167"` | §3.5 |
| `sport_aliases` | object from band type to sport type | `{}` | source `^[A-Z][A-Z0-9_]{0,39}$`; target in activity-spec.md §2.1; source differs from target; at most 20 | recorded labels and categories (§3.8a) |
| `strain_intent` | string | `"maintain"` | `"restore"`, `"maintain"`, `"overreach"`; null invalid | §3.12 |
| `wake_target` | string or null | null | exact 24-hour `HH:MM`, `^([01][0-9]\|2[0-3]):[0-5][0-9]$` | §4.11 |
| `sleep_score_mode` | string | `"sufficiency"` | `"sufficiency"`, `"composite"`; null and `""` invalid | §4.5a; Recovery's sleep input (§2.3) |

Set or unset one alias with `ghoops config set sport_alias.KICKBOXING BOXING` or `ghoops config unset sport_alias.KICKBOXING`. Invalid keys or values exit 2; unsetting a missing alias succeeds without a change. Aliases apply to every past and future recorded entry at read time. A per-entry sport edit wins. They never apply to goop or detected entries, and do not change `score_version`. The server loads config on each request, so changes need no restart.

`config set sleep_score_mode composite` turns on the composite Sleep Performance (§4.5a): Recovery takes it as its sleep input (§2.3), and `score_version` becomes `<Version>+composite.1`. Every past day recomputes on its next read; nothing is stored ([composite-sleep-spec](../goop/composite-sleep-spec.md)). `config set sleep_score_mode sufficiency` and `config unset sleep_score_mode` restore the default, which is never written to the file or echoed: `sleep_score_mode` appears in config `values` and in `score_config` only when it is `composite`, so default bodies keep their bytes. A file that says `"sufficiency"` is read as the default.

`config unset strain_intent` restores `maintain`. `config set wake_target null` and `config unset wake_target` clear the fixed wake time. A config file with `strain_intent: null` is invalid, like `trimp_profile: null`. Invalid values exit 2. Both keys appear in config `values`, `defaults` and every `score_config`.

Every response echoes the effective configuration in `score_config` (contract §5.1), so two consumers can see when they used different settings.

## 1. Shared rules

### 1.1 Rounding

- Compute in float64 at full precision. Round only when writing output.
- Rounding is half away from zero (Go `math.Round(x*10^n)/10^n`).
- Output precision is set per field in contract.md. Defaults: scores that are integers in this file (recovery, sleep performance, consistency, efficiency) are integers; strain and TRIMP have 1 decimal; z values 2 decimals; component scores 1 decimal; baseline means and SDs 2 decimals (ln values 4 decimals).
- When a later formula uses an earlier score (sleep need uses the previous cycle's strain), it uses the **reported, rounded** value, so a reader can recompute it from JSON.

### 1.2 Status and reason vocabulary

| `status` | Meaning |
| --- | --- |
| `ok` | Value present, inputs complete. |
| `calibrating` | Recovery only: value present, baseline has 7 to 13 values. |
| `in_progress` | Strain only: the cycle is still open; the value will grow. |
| `pending` | Value null; the day is the current London date (or the current open cycle) and the missing input may still arrive. |
| `unavailable` | Value null; it will not appear without new data. |

For scores, `reason` is null when the value is present. `missing_inputs` (Recovery only) lists every applicable code in this order.

| `reason` | Meaning |
| --- | --- |
| `no_sleep` | No main sleep session for the date, or its asleep minutes are unknown. |
| `sleep_processing` | Main sleep present but `metadata.processed` is `false`. |
| `no_hrv` | No `averageHeartRateVariabilityMilliseconds` for the date. |
| `hrv_conflict` | Two daily HRV records for the date with different values. |
| `no_resting_hr` | No daily resting HR for the date. |
| `rhr_conflict` | Two daily resting HR records with different values. |
| `insufficient_baseline` | Fewer than 7 baseline values for HRV or resting HR. |
| `cycle_not_started` | Strain: the cycle starts in the future. |
| `resting_hr_unknown` | Strain: no resting HR for the date and no baseline mean. |
| `max_hr_unknown` | Strain: no maximum heart rate source (§3.3). |
| `no_heart_rate` | Strain: zero covered minutes in the window. |
| `low_coverage` | Strain target: low-confidence Strain has no target position. |
| `insufficient_nights` | Consistency: fewer than 4 main sleeps in the 7-night window. |
| `no_data` | VO2 max: no record in the last 31 days. |

### 1.3 Personal baselines

For metric `m` (HRV, resting HR, respiratory rate, SpO2) and London date `D`:

1. Walk dates `D-1`, `D-2`, … `D-42` (never `D` itself).
2. Keep a date's value only when that metric is `available` for that date: exactly one value, or several identical values. Conflicting dates are skipped.
3. Stop after collecting 28 values. `n` is the number collected (0 to 28).
4. For HRV, transform each value with the natural log first: `x = ln(rmssd_ms)`.
5. `mean` = arithmetic mean. `sd` = sample standard deviation (divide by `n-1`); undefined when `n < 2`.
6. `sd_eff = max(sd, floor)` with the floors from §0. The floor stops one unusually stable fortnight from turning tiny changes into large z-scores.

Sources: ln-transformed RMSSD compared with a rolling individual baseline follows Plews et al. 2013 and Buchheit 2014; using day-to-day deviations of resting HR and HRV from a personal norm follows Altini and Plews 2021. Window length, value cap and floors are ghoops choices.

### 1.4 z-score

`z = clamp((today - mean) / sd_eff, -3, 3)` (for HRV, `today = ln(rmssd_ms)`). Normal CDF: `Φ(z) = 0.5 × (1 + erf(z / √2))` using Go `math.Erf`.

## 2. Recovery (0 to 100)

### 2.1 Inputs for date D

| Input | Source | Required |
| --- | --- | --- |
| Sleep performance | §4.5, main sleep ending on D | yes |
| Daily HRV `rmssd` (ms) | `daily-heart-rate-variability` date D, `averageHeartRateVariabilityMilliseconds` | yes |
| Resting HR (bpm) | `daily-resting-heart-rate` date D, `beatsPerMinute` | yes |
| Baselines for HRV and resting HR | §1.3, each `n ≥ 7` | yes |
| Respiratory rate (breaths/min) and its baseline | `daily-respiratory-rate` date D, `breathsPerMinute`; baseline `n ≥ 7` | no |
| Skin temperature | `daily-sleep-temperature-derivations` date D: `nightlyTemperatureCelsius`, `baselineTemperatureCelsius`, `relativeNightlyStddev30dCelsius` (all three needed; exactly one record for the date) | no |
| SpO2 | `daily-oxygen-saturation` | never: flag only (§5) |

### 2.2 Gate

Collect the reasons in this order: `no_sleep` or `sleep_processing`, then `hrv_conflict` or `no_hrv`, then `rhr_conflict` or `no_resting_hr`, then `insufficient_baseline`. If the list is not empty: `value = null`, `band = null`, `confidence = null`, `components = null`, `reason` = first code, `missing_inputs` = the list. `status` is `pending` when D is the current London date and the list contains any of `no_sleep`, `sleep_processing`, `no_hrv`, `no_resting_hr`; otherwise `unavailable`. `inputs` and `baseline` are still filled with whatever exists.

### 2.3 Formula

```
z_hrv   = clamp((ln(rmssd) − mean_ln) / sd_eff_ln, −3, 3)
z_rhr   = clamp((rhr − mean_rhr) / sd_eff_rhr, −3, 3)
hrv_score = 100 × Φ(z_hrv)
rhr_score = 100 × Φ(−z_rhr)              # lower resting HR is better
sleep_score = sleep_performance          # 0..100 integer from §4.5
base = w_hrv × hrv_score + w_rhr × rhr_score + w_sleep × sleep_score

if respiratory rate present and its baseline n ≥ 7:
    z_rr = clamp((rr − mean_rr) / sd_eff_rr, −3, 3)
    rr_penalty = z_rr > 1 ? min(10, 5 × (z_rr − 1)) : 0
else: z_rr = null, rr_penalty = 0, add "respiratory_rate" to optional_missing

if skin temperature inputs present:
    z_temp = clamp((nightly − baseline) / max(stddev_30d, 0.10), −3, 3)
    temp_penalty = z_temp > 1 ? min(10, 5 × (z_temp − 1)) : 0
else: z_temp = null, temp_penalty = 0, add "skin_temperature" to optional_missing

recovery = round(clamp(base − rr_penalty − temp_penalty, 0, 100))   # integer
```

In composite mode (`sleep_score_mode: composite`, §0.1), `sleep_score` is the composite sleep performance of §4.5a instead of §4.5. The gate (§2.2) does not change, because the composite is null exactly when §4.5 is.

`(w_hrv, w_rhr, w_sleep)` are `WeightHRV`, `WeightRestingHR` and `WeightSleep` (0.55, 0.20, 0.25). The engine reports them in `components.weights` (contract §5.3), and the app reads them from there.

Only elevations are penalised: a raised breathing rate or skin temperature overnight is the pattern that wearable studies associate with illness or strain (Natarajan et al. 2020; Miller et al. 2020; Mason et al. 2022). A drop is shown in the vitals panel (§5) but does not lower recovery. Both penalties start at one standard deviation and reach the 10-point cap at three.

At baseline (all z = 0) with full sleep, recovery is 63: the scale leaves room above for good nights and below for poor ones.

### 2.4 Bands

| `band` | Range | App colour token |
| --- | --- | --- |
| `high` | 67 to 100 | `recoveryHigh` |
| `medium` | 34 to 66 | `recoveryMedium` |
| `low` | 0 to 33 | `recoveryLow` |

### 2.5 Calibration and confidence

| HRV and RHR baseline values (`min(n_hrv, n_rhr)`) | `status` | `value` | App text |
| --- | --- | --- | --- |
| 0 to 6 | `unavailable`, reason `insufficient_baseline` | null | "Calibrating: N of 7 nights" |
| 7 to 13 | `calibrating` | present | value plus "Calibrating" badge |
| 14 or more | `ok` | present | value |

`calibrating` is also `true` in the response whenever `min(n_hrv, n_rhr) < 14`. `calibration` reports `values_needed: 7`, `values_for_full_confidence: 14`, `hrv_values` and `resting_hr_values`.

`confidence`: `high` when not calibrating and `optional_missing` is empty; `low` when calibrating and `optional_missing` is not empty; otherwise `medium`.

A new user needs 7 nights with HRV and 7 days with resting HR in the 42 days before D. If about one night in three is missing (band not worn or not synced), expect 10 to 11 calendar days. Running `ghoops collect --days 60` once fills the baseline from Google's history immediately.

### 2.6 Worked example (golden: `fixtures/v2/scores/recovery.json`, case `worked_example_full_day`)

Inputs: rmssd 56.0 ms; resting HR 56 bpm; respiratory rate 15.2; skin temperature nightly 33.95 °C, baseline 33.80 °C, 30-day SD 0.20 °C; sleep performance 94. Baselines from the 28 values in the case file.

| Step | Value |
| --- | --- |
| HRV baseline `mean_ln`, `sd_eff_ln` (raw SD below floor) | 3.9531, 0.1000 |
| `ln(56.0)` | 4.0254 |
| `z_hrv`, `hrv_score` | 0.72, 76.5 |
| RHR baseline `mean`, `sd_eff` (floor) | 56.04, 2.00 |
| `z_rhr`, `rhr_score` | −0.02, 50.7 |
| `base` = 0.55×76.5 + 0.20×50.7 + 0.25×94 | 75.7 |
| `z_rr`, `rr_penalty` = 5 × (1.46 − 1) | 1.46, 2.3 |
| `z_temp` = 0.15 / 0.20, `temp_penalty` | 0.75, 0.0 |
| **recovery** = round(75.7 − 2.3 − 0.0) | **73**, band `high`, status `ok`, confidence `high` |

Other golden cases in the same file: `poor_night_and_illness_signs` (9, low), `at_baseline_full_sleep` (63, medium), `z_clamped_at_plus_three` (100), `optional_inputs_missing` (45, medium confidence), `calibrating_eight_values` (47, `calibrating`, confidence `low`), `insufficient_baseline_six_values` (null), `temp_baseline_missing` (45), `no_sleep` (null).

### 2.7 Edge cases

| Case | Behaviour |
| --- | --- |
| Band not worn overnight (no sleep, no HRV; resting HR still present) | null, `reason: no_sleep`, `missing_inputs: ["no_sleep","no_hrv"]`; `pending` today, `unavailable` for past days. |
| Main sleep exists but `processed: false` | null, `sleep_processing`, `pending`. |
| HRV present, sleep missing (manual sleep deleted) | null, `no_sleep`. HRV still shows in vitals. |
| Today's resting HR not yet published | null, `no_resting_hr`, `pending`, until a later `collect` brings it. |
| Two different HRV values for D | null, `hrv_conflict`. |
| Baseline window contains conflict days | those days are skipped, not averaged. |
| Skin temperature present but baseline or SD missing, or sent as `"NaN"` (data.md §3.1) | penalty 0, `skin_temperature` in `optional_missing`. |
| Respiratory rate present but its own baseline has fewer than 7 values | penalty 0, `respiratory_rate` in `optional_missing`. |
| DST change night | No special case: provider dates and sleep end dates are used. |

## 3. Strain (0 to 21)

### 3.1 The cycle

Strain is measured over a physiological cycle rather than a calendar day, because sleep can start well after midnight and a workout can cross midnight. Cycle `D` (named by its London date) runs from the wake time of the main sleep that ends on `D` to the start of cycle `D+1`.

```
cycle_start(D) =
    effective_wake(D)                                  if main_sleep(D) exists   (start_source "main_sleep_wake")
    local wall clock D at typical_wake_minutes(D)       otherwise                 (start_source "typical_wake_fallback")

typical_wake_minutes(D) = floor(median of the local wake time-of-day, in minutes after local 00:00
                          including seconds as fractions, of main sleeps ending on D-1 … D-14),
                          when at least 3 such nights exist; else 420 (07:00)

cycle_end(D) = cycle_start(D+1)
status:  now < cycle_start(D)          → "not_started"  (end null, strain null, reason cycle_not_started, status pending)
         now < cycle_end(D)            → "open"         (end null, effective end = now, end_source "now")
         otherwise                     → "closed"       (end = cycle_end(D), end_source "next_cycle_start")
```

`effective_wake(D)` is the main sleep's effective wake after a ghoops edit (sleep-edit-spec §3.3). Typical wake samples use effective wakes too.

"Local wall clock D at m minutes" means `time.Date(D.year, D.month, D.day, m/60, m%60, 0, 0, Europe/London)`; if that local time does not exist (the spring-forward gap, 01:00–02:00 on the last Sunday of March), use 02:00 local. Because `wake(D)` and the fallback always fall inside London day `D`, cycles never overlap and always advance. When a late sleep sync moves `cycle_start(D+1)`, the previous cycle's end moves with it on the next read; values are recomputed, never stored.

**Default date.** `ghoops day` with no `--date`, and the app's "today", use the latest of {current London date, previous London date} whose cycle `status` is `open`; if neither is open, the current London date. At 01:30, before going to bed, the open cycle is still yesterday's, so the app keeps showing it.

### 3.2 Resting heart rate for strain

1. `daily-resting-heart-rate` for date D (`resting_hr_source: "daily_resting_heart_rate"`).
2. Else the §1.3 baseline mean of resting HR for D (any `n ≥ 1`), rounded to an integer for output (`"baseline_mean"`).
3. Else strain is null, `resting_hr_unknown`.

### 3.3 Maximum heart rate

Sources, in order:

1. `max_hr_override_bpm` from config → `max_hr_source: "override"`. Used as is.
2. Age-predicted: `round(208 − 0.7 × age)` (Tanaka et al. 2001) with `age` from `user/profile` → `"age_predicted_profile"`.
3. If source 2 is not available (profile status not `ok`, or `age` absent): the most recent `daily-heart-rate-zones` record dated D−30 … D, `PEAK` zone `maxBeatsPerMinute`, accepted only in 150 to 220 → `"fitbit_zone_peak"`. Fitbit derives its zones from heart-rate reserve (Karvonen), so the top of the peak zone is Fitbit's own maximum estimate.
4. Observed maximum: for each recorded workout (§3.8) that starts in London dates D−365 to D, `workout_peak` = the second-highest `beatsPerMinuteMax` among its covered minutes (needs at least 2 covered minutes; the second-highest rejects a single-minute optical spike). `observed_max` = the highest `workout_peak` in 120 to 220. If `observed_max` is greater than the value from source 2 or 3, use it → `"observed"`.
5. No source from 1 to 3 → strain null, `max_hr_unknown`. The observed maximum alone is never used, because a short history of easy workouts would underestimate it and inflate strain. If the chosen maximum is not greater than the resting HR, strain is also null with `max_hr_unknown`.

### 3.4 Minutes in a window

Heart-rate windows are 60 s, aligned to whole UTC minutes. For a window `[a, b)`:

- `slots` = every UTC minute start `t` (a multiple of 60 s) with `a ≤ t < b`. `expected_minutes = len(slots)`.
- A slot is covered when the store has a window starting at `t` (data.md §2.2 coverage rule). `covered_minutes` = covered slots.
- For an **open** cycle, the window is `[cycle_start, coverage_until)` with `coverage_until = min(now, device_last_sync_at)` when the device's last sync time is known, else `now`. Data cannot exist after the band last synced, so this keeps coverage honest while the phone has not synced. TRIMP, zones and averages use the same window. For a closed cycle the window is `[cycle_start, cycle_end)` and `coverage_until = cycle_end`.
- `hr_coverage = covered_minutes / expected_minutes`, 2 decimals; null if `expected_minutes` is 0.

Missing minutes contribute nothing. They are never filled, interpolated or counted as rest.

### 3.5 TRIMP (Banister, heart-rate reserve)

For each covered minute with average heart rate `avg`:

```
hrr = (avg − rest) / (max − rest)
if hrr < HRRFloor: contributes 0 (minute counts in zones_minutes.below)
else:
    h = min(hrr, 1.0)
    trimp += 1 minute × h × TrimpA × e^(TrimpB × h)
```

`TrimpA`/`TrimpB` come from `trimp_profile` (§0.1): Banister's coefficients 0.64/1.92 (derived from male data) and 0.86/1.67 (female data) (Banister 1991; Morton, Fitz-Clarke and Banister 1990). The profile has no sex field, so the owner chooses; the default is `banister_b192`.

The 0.30 floor drops ordinary daily movement. Without it, sixteen waking hours at a slightly raised heart rate would add as much TRIMP as a hard hour of boxing. 0.30 of reserve corresponds to about 50 % of maximum heart rate for typical resting and maximum values, the bottom of Edwards' lowest training zone (Edwards 1993).

Zones by `hrr` (Karvonen 1957), counted on covered minutes:

| Key | `hrr` range |
| --- | --- |
| `below` | < `HRRFloor` |
| `z1` | `HRRFloor` to < `Zone2HRR` |
| `z2` | `Zone2HRR` to < `Zone3HRR` |
| `z3` | `Zone3HRR` to < `Zone4HRR` |
| `z4` | `Zone4HRR` to < `Zone5HRR` |
| `z5` | ≥ `Zone5HRR` (including above 1.0) |

### 3.6 Strain scale

```
strain = min(21, 21 × ln(1 + TRIMP / StrainK) / ln(1 + StrainTrimpCap / StrainK))      # 1 decimal
```

The logarithm makes each extra point harder to earn. Reference points (golden table in `strain.json`, key `trimp_to_strain`):

| TRIMP | 0 | 5 | 10 | 25 | 50 | 75 | 100 | 150 | 200 | 300 | 450 | 700 | 1000 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Strain | 0.0 | 2.0 | 3.4 | 6.2 | 8.8 | 10.5 | 11.8 | 13.7 | 15.0 | 16.9 | 18.9 | 21.0 | 21.0 |

Bands: `light` < `StrainModerateMin`; `moderate` from `StrainModerateMin` to < `StrainStrenuousMin`; `strenuous` from `StrainStrenuousMin` to < `StrainAllOutMin`; `all_out` ≥ `StrainAllOutMin`. Compare against the rounded 1-decimal value.

### 3.7 Day strain output and confidence

| Field | Rule |
| --- | --- |
| `value` | §3.6 over the cycle window, null when `covered_minutes` is 0 (`no_heart_rate`) |
| `status` | `in_progress` (open cycle), `ok` (closed), `pending` (not started), `unavailable` (null for another reason) |
| `confidence` | by `hr_coverage`: ≥ 0.80 `high`; ≥ 0.50 `medium`; otherwise `low`. Null when `value` is null. |
| `avg_hr_bpm` | mean of covered minute averages, integer |
| `peak_hr_bpm` | max of covered minute `beatsPerMinuteMax`, integer |
| `zones_minutes` | §3.5 |

Low coverage still reports the strain of the minutes that were seen (decision 7) and says so; the app shows "Based on N % of the day".

### 3.8 Workout strain

A **recorded workout** is an `exercise/list` record. Its `original` holds the band's type, name, start and end before alias or edit. It belongs to the cycle containing its effective start. Its scoring window is `[effective start truncated to the minute, effective end)`; apply §3.4 to §3.7 with the cycle's resting and maximum heart rate. Report `strain`, `trimp`, `hr_coverage`, `confidence`, `avg_hr_bpm`, `peak_hr_bpm`, `zones_minutes`. Workout strain is a view: day strain already contains those minutes; never add workout strain to day strain.

Workout duplicates: merge exactly as v1 (`report.exercises`): identical start and end and compatible type. A merged workout takes `id`, `exercise_type`, `display_name`, `active_minutes`, `provider` and `source` from one representative record: the first record, ordered by `name`, whose `exerciseType` is not `WORKOUT` or `OTHER`; if all are generic, the first by `name`. Categories (`category` field):

| `category` | `exerciseType` values |
| --- | --- |
| `combat` | `BOXING`, `KICKBOXING`, `MARTIAL_ARTS`, `MUAY_THAI`, `KARATE`, `TAEKWONDO`, `WRESTLING`, `JIU_JITSU`, `FENCING` |
| `strength` | `FREE_WEIGHTS`, `FUNCTIONAL_STRENGTH_TRAINING`, `POWERLIFTING`, `STRENGTH_TRAINING`, `WEIGHTLIFTING`, `WEIGHT_MACHINES`, `WEIGHTS` (same list as v1 lifting) |
| `walking` | `WALKING`, `POWER_WALKING`, `TREADMILL_WALK`, `HIKING`, `NORDIC_WALKING` |
| `cardio` | `RUNNING`, `TREADMILL`, `TRAIL_RUN`, `BIKING`, `OUTDOOR_BIKE`, `STATIONARY_BIKE`, `SPINNING`, `ROWING_MACHINE`, `ELLIPTICAL`, `HIIT`, `SWIMMING`, `SWIMMING_POOL`, `JUMPING_ROPE`, `INTERVAL_WORKOUT`, `CIRCUIT_TRAINING`, `CARDIO_WORKOUT` |
| `other` | every other value |
| `detected` | detected efforts (§3.9) |

ghoops entries are locally started or added activities, with uploaded values in `original`, scored over `[start truncated to the minute, end)` with slots overlapping pauses removed. They report `paused_minutes`; recorded and detected entries report 0. The same category table and scoring rules apply. Alias, edit, absorption and overlap suppression follow §3.8a before scoring. A visible goop entry counts in day-row workouts and brief like a recorded workout, without changing Day Strain.

### 3.8a Aliases, edits, hidden entries and merges

For a range of cycles, with the edits and config:
1. **Build entries.** Build recorded entries (duplicate merge as now) and goop entries. Set `original` on each.
2. **Alias.** Apply `sport_aliases` to recorded entries.
3. **Edits.** Apply each edit whose id matches an entry:
   - the sport, with `display_name` from activity-spec.md §2.1;
   - the window;
   - the notes.

   Then mark the entry `hidden` when `edit.hidden`. Mark every id in its `merge_with` as *absorbed by* it.
4. **Absorbed entries** are hidden. They take the absorber's hidden state into account: a hidden absorber hides all it absorbed.
5. **Hide by overlap** (activity-spec §8.6, unchanged rule).
   - A goop entry hides a recorded entry when their effective windows overlap by at least 50 % of the shorter.
   - Hidden goop entries take part, so deleting a ghoops session does not bring back the band record it had replaced.
   - Exception: a pair where one absorbs the other never hides each other.
6. **Detected efforts** (§3.9). Step 4 sums the overlaps of every recorded and goop entry's effective window, **visible or hidden**. So a deleted activity does not reappear as a detected effort, and a window extended over an effort removes that effort.
7. **Score and output.** Score every visible entry over its effective window (§3.8, goop pauses as now) and output it.
   - Hidden entries are absent from `workouts`, `day.workouts`, `snapshot`, `brief`, the `days` row counts and `strength_minutes`.
8. **Day Strain** is unchanged by all of this.

The **effective window** of a recorded entry is the edit's window, else the provider window. For goop it is the edit's window, else the uploaded window. `cycle_date` follows the effective start.

#### Merge

**Candidates** (phone, edit-spec.md §2.2 step 7, and server validation), for entry T with effective window `[a, b)`:
- **next:** the visible entry with the smallest start ≥ `a`, other than T, of kind `recorded`, `goop` or `detected`, with the same `cycle_date` and `start − b ≤ 15 min` (`MergeMaxGapMinutes`). Overlap counts as a gap ≤ 0.
- **previous:** the visible entry with the largest start < `a` under the same conditions, with `a − its end ≤ 15 min`.
- These are computed from the entry's saved window, not the sheet's unsaved window, so the rows do not jump while dragging.

**Two band records.** T keeps its id. Its edit gets:
- `start` = min of the starts and `end` = max of the ends (union);
- `merge_with += [X.id]`;
- its sport and notes as set in the Edit step.

X becomes absorbed (hidden). The combined entry is scored over the union, including the minutes between.

**A ghoops entry and a band record.** The same rule in either direction: T absorbs X.
- If T is goop, T's own pauses inside the union still count, and X's are ignored.
- If T is recorded and X is goop, X's pauses are ignored.
- The overlap-hide rule skips the pair (§3.8a step 5).

**A detected neighbour.** The window is extended to the union and `merge_with` stays `[]`. The effort disappears through §3.8a step 6.

**Server checks for `merge_with`**, all `invalid_request` with field `merge_with` unless noted:
- each id is a visible recorded or goop entry, other than T, that is a candidate of T by the rule above using T's currently stored effective window;
- the new window covers each absorbed window entirely;
- no id is absorbed by another edit (409 `conflict`);
- no id has its own non-empty `merge_with` (409 `conflict`);
- T is not absorbed by anyone (409 `conflict`).

**Undoing a merge** is Restore, which removes the edit. There is no separate unmerge.

`active_minutes` is null for a recorded entry whose window was edited or merged. Goop pauses are clipped to the effective window; goop active minutes exclude those slots. `original`, `edit`, `edited`, `merged`, `notes`, `origin` and `pauses` follow contract.md §5.8. A notes-only override does not set `edited`.

### 3.9 Detected efforts

Boxing sessions are not always auto-detected, and lifting is logged in Hevy, not Fitbit. ghoops shows unrecorded hard stretches as **detected efforts** so their strain is visible. Hevy data is never read.

Detected efforts are computed only when the cycle has both a resting and a maximum heart rate. The scan covers the slots of `[cycle_start, now)` for an open cycle and `[cycle_start, cycle_end)` for a closed one.

1. Walk the cycle's slots in time order. A slot is *hot* when covered and `hrr(avg) ≥ 0.50`.
2. A segment starts at a hot slot and extends while the gap of consecutive non-hot slots (uncovered or cool) stays ≤ 2. It ends after its last hot slot.
3. Keep segments with at least 10 hot slots. `start` = first hot slot; `end` = last hot slot + 60 s.
4. Drop a segment when the effective windows of recorded workouts and ghoops activities, visible or hidden, overlap at least 50 % of its length (sum of overlaps in seconds ≥ 0.5 × (end − start)).
5. Each kept segment becomes a workout entry with `kind: "detected"`, `category: "detected"`, `exercise_type: null`, `display_name: "Detected effort"`, `id: "effort-<start RFC 3339>"`, provider fields null, and its own strain (§3.8).

### 3.9a Sport suggestion (display only)

Display constants: `SuggestWindowDays = 56`, `SuggestStartToleranceMinutes = 90`, `SuggestMinRatio = 0.5`, `SuggestMaxRatio = 2.0`, `SuggestMinMatches = 3`, `SuggestMinShare = 0.6`. Day Strain and every score are untouched.

For each visible detected effort E (after [edit-spec §5.5](../goop/edit-spec.md#55-building-the-visible-list)):

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

A tie for the largest count fails the 60 % rule, so no tie-break is needed. `display_name` is the [activity-spec §2.1](../goop/activity-spec.md#21-sports) label of `s*`.

**Worked example** (`fixtures/v2/parity/workouts.json`): store_parity adds band `BOXING` 19:30–20:30Z on Mondays 2026-02-16, 02-23 and 03-02 to store_full. The detected effort of Monday 2026-03-09 19:40–20:25 (45 min) matches all three: same weekday, 10 minutes apart, 60 minutes within 22.5–90. `suggested = {"exercise_type": "BOXING", "display_name": "Boxing", "matches": 3, "window_days": 56}`. In `workouts_full.json` (store_full, no history) the same effort has `suggested: null`.

### 3.10 Worked example (golden: `strain.json`, case `boxing_hour`)

Resting HR 56, max HR 187 (so reserve = 131). Sixty covered minutes: 10 warm-up minutes rising from 108 to 136.8 bpm, 42 minutes of rounds (3 minutes at 168, 1 minute at 141), 8 cool-down minutes falling from 150 to 122.

| Quantity | Value |
| --- | --- |
| Minute at 168 bpm: `hrr` = 112/131 = 0.855 → 0.855 × 0.64 × e^(1.92×0.855) | 2.83 TRIMP per minute |
| Minute at 141 bpm: `hrr` = 0.649 → 0.649 × 0.64 × e^(1.246) | 1.44 TRIMP per minute |
| Total TRIMP | 124.0 |
| Strain = 21 × ln(1 + 12.40) / ln(71) | **12.8**, band `moderate` |
| Zones (below, z1..z5) | 0, 5, 8, 14, 1, 32 |

Same hour with a 20-minute sensor gap in the middle (`boxing_hour_with_20_minute_gap`): TRIMP 74.4, strain 10.5, `hr_coverage` 0.67, confidence `medium`. The gap lowers strain; it is not filled.

### 3.11 Edge cases

| Case | Behaviour |
| --- | --- |
| Band off for hours (charging) | Those minutes are uncovered; coverage drops; strain counts only seen minutes. |
| No sleep recorded for D | `cycle_start(D)` uses the typical wake time; `start_source: "typical_wake_fallback"`. |
| Workout crosses midnight | Belongs to the cycle containing its start; minutes after midnight still count in that cycle while it is open. |
| HR above max | `hrr` capped at 1.0 for TRIMP; minute counts in `z5`. |
| Resting HR ≥ max HR (bad data) | strain null, `max_hr_unknown`. |
| DST days | Slots are UTC minutes; the fallback start uses local wall-clock time on D. A 23- or 25-hour day needs no special case. |
| Phone not synced since morning | Open-cycle coverage ends at `device_last_sync_at`, so a stale phone does not look like low wear. |

### 3.12 Strain target

Constants in `internal/score/constants.go` (they change scores, so `Version` is `"2.1.0"`):

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
    position = null when S is null or strain.confidence is low
    otherwise position = below if S < low, above if S > high, or within
    status = "ok", reason = null
if strain.confidence is low:
    reason = "low_coverage"
```

When a position is available, it compares the reported 1-dp values. A low-confidence day still reports observed Strain, coverage and any target range from Recovery. With these constants `0.12 × R` never ends in 5 at the second decimal, so no half-way rounding occurs. The target uses the current `strain_intent` for every date, past ones included, because config is not stored per day (scores are views).

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
| `one_covered_minute` | 74 | maintain | 0.2 (`low` confidence) | 13.4 | 16.4 | null, reason `low_coverage` |
| `no_recovery` | null (`pending`, `no_sleep`) | maintain | 5.0 | null | null | null, status `pending`, reason `no_sleep` |

`day_full.json`: `{"low": 13.3, "high": 16.3, "intent": "maintain", "position": "below", "status": "ok", "reason": null}`. With config `strain_intent: restore` (`day_full_config.json`): `low 10.3`, `high 13.3`, `position within`.

## 4. Sleep

### 4.1 Main sleep and naps

Candidates: `sleep/reconcile` records whose London end date is D.

1. Records with `metadata.mainSleep: true`. With more than one, take the largest asleep minutes, then the earliest start.
2. If none is flagged: the longest session whose interval is at least 180 minutes, ties broken by earliest start.
3. Otherwise there is no main sleep for D.

All other candidates are **naps** for D. Selection uses Google's records; ghoops sleep edits and §4.2a apply after it.

### 4.2 Asleep minutes, time in bed, efficiency

- `asleep_minutes` = `summary.minutesAsleep`. If absent: the sum of `LIGHT`, `DEEP`, `REM` and `ASLEEP` minutes in `summary.stagesSummary` when every listed stage has `minutes`. Otherwise unknown (null). A session interval alone never supplies asleep minutes (v1 rule). This is Google's base value; §4.2a reconciles it with the stage segments and the window.
- `time_in_bed_minutes` = `round((we − ws) in minutes)` for the window in §4.2a.
- `efficiency_pct` = `round(100 × asleep_minutes / (we − ws in minutes, unrounded))`, integer (time-in-bed denominator, Reed and Sacco 2016).

`efficiency_band` is null when efficiency is null; otherwise `high` ≥ `EfficiencyHighMin` (90), `medium` from `EfficiencyMediumMin` (85) to 89, and `low` < `EfficiencyMediumMin`.

### 4.2a Unstaged time

For a main sleep or nap, the window is `W = [ws, we)`, Google's interval unless a ghoops sleep edit applies ([sleep-edit-spec §3.3](../goop/sleep-edit-spec.md#33-computing-a-night)). Main-sleep selection always uses Google's records before this rule. Covered time is the union of stage segments intersected with W. An uncovered stretch is one of two kinds:

- **Unstaged span**: uncovered time at the start of W (before the first segment) or at its end (after the last). A time edit makes these, in Google's app or in ghoops, so they are the person's own statement that they were asleep.
- **Gap**: uncovered time between two segments. No edit makes one, so Google's asleep total has already decided it, whether as sleep or not. A gap adds nothing, is not unstaged and is drawn as empty.

Both exist only when the session has at least one segment; a session with no segments keeps §4.2's values and is never all unstaged. Durations are summed in seconds and turned into minutes rounded half away from zero, separately for unstaged spans and for gaps.

Google's total can count uncovered time already: a segment can be missing from the detail while the summary keeps its minutes (oss-data-audit row 1). With `A` Google's §4.2 value and `S` the sleep minutes of all of Google's segments (LIGHT, DEEP, REM and ASLEEP, unclipped):

```
unexplained = max(0, A − S)                     # 0 when A is null; minutes of A no sleep segment explains
in_gaps     = min(gap minutes, unexplained)      # gap minutes A counts
added       = max(0, unstaged minutes − (unexplained − in_gaps))   # unstaged minutes A does not count yet
```

The rest of A's unexplained minutes are taken to lie in the unstaged spans inside Google's window, so they are not added again. Unstaged minutes count as asleep, separately from every stage; `score_constants.sleep.unstaged_counts_as` reports `"asleep"`. No engine number is added.

| Value | Rule |
| --- | --- |
| Asleep, segments not clipped | A + `added`; null if A is null |
| Asleep, some segment outside W | Round the seconds of LIGHT, DEEP, REM and ASLEEP inside W divided by 60, then add `in_gaps` and the unstaged minutes |
| Asleep that does not reconcile | Below 0, or above W's length in minutes: null, with efficiency and every percentage. Google's totals contradict the window, so ghoops does not guess. |
| Stage minutes and counts, not clipped or no segments | Google's stage summary unchanged |
| Stage minutes and counts, clipped | Round seconds of that type inside W divided by 60; count intersecting segments. A type absent from the summary stays null. |
| `stages.unstaged` | `{minutes, segments: number of unstaged spans, pct_of_asleep}`; `minutes` is `added` when not clipped and the unstaged minutes when clipped; all three null with no stage segments |
| Light, deep, REM and unstaged percent | `round(100 × minutes / asleep_minutes, 1)` when asleep is positive; awake percent stays null |
| In bed and efficiency | §4.2 using W |
| Latency | Google's when ws equals Google's start; otherwise null |
| Awake disturbances | AWAKE segments after clipping that start after ws and end before we |
| Short awakenings | Count those intersecting W |
| Bedtime and wake | ws and we |

The rule reaches performance, Recovery's sleep component, prior-night debt, nap credit, planner efficiency, comparison means and days rows. Restorative time remains deep plus REM. Typical stage ranges use computed stage minutes and never unstaged minutes. Heart rate and HRV show samples across W but decide no stage; breathing-rate summaries still match Google's window.

Worked fixture (`sleep_unstaged.json`): Google extends 23:12–06:29 to 07:41 without adding stages. The 72-minute span 06:29–07:41 gives 487 asleep minutes rather than 415, 509 in bed, efficiency 96% rather than 82%, and performance 100 rather than 94 against need 443. Light/deep/REM/unstaged percentages are 43.9/17.5/23.8/14.8. The previous cycle's Strain remains 11.2 because the added resting minutes add no TRIMP.

With no edit and no uncovered time, every existing value stays the same. The shared vectors in `fixtures/v2/sleep_edit/rule_cases.json` also cover trims, earlier starts, gaps, classic sleep and naps.

Gaps (2.3.1, oss-data-audit row 1). Before 2.3.1 a gap counted as unstaged sleep on top of Google's total, so a missing segment that the total already counted was counted twice. On `store_full`'s night with the 23:16–23:44 LIGHT segment removed and the summary kept, 2.3.0 gave 443 asleep and efficiency 101%; 2.3.1 gives Google's 415 and 95%, and Sleep Performance, Recovery, the next night's debt and the planner equal the untouched night's. Vectors: `internal_gap_counted`, the same night extended to 07:41 (487, unstaged 72) and trimmed to 05:59 (391), `middle_gap` (a gap Google's total does not count: asleep stays 100 of 120, efficiency 83), `edge_gap_partly_counted` (the last LIGHT and AWAKE missing: Google's total already counts 24 of the 30 unstaged minutes, so 6 are added, asleep 421) and `summary_exceeds_window` (asleep 130 in a 120-minute window: null). Go and Swift (`SleepWindowRule`) run the same file.

### 4.3 Stages, latency, disturbances

| Field | Rule |
| --- | --- |
| `stages.light/deep/rem/awake.minutes` | `stagesSummary[type].minutes` as integer; null when that type is absent |
| `stages.*.segments` | `stagesSummary[type].count` |
| `stages.light/deep/rem.pct_of_asleep` | `round(100 × minutes / asleep_minutes, 1)`; `awake.pct_of_asleep` is always null |
| `minutes_to_fall_asleep` | `summary.minutesToFallAsleep` as integer, else null |
| `disturbances.awake_segments` | count of `stages[]` entries with `type: "AWAKE"` that start after the session start and end before the session end (the first and last awake periods are not disturbances) |
| `disturbances.short_awakenings` | count intersecting the window (§4.2a) |
| `disturbances.total` | sum of the two |

Stage values and disturbances follow §4.2a when a window has uncovered time or clips segments. `CLASSIC` sessions (`ASLEEP`/`RESTLESS`/`AWAKE`) leave light, deep and REM null and still report asleep minutes and disturbances.

### 4.4 Sleep need for the night ending on D

```
base         = sleep_base_need_minutes                               (default 450; AASM/SRS ≥ 7 h, Watson et al. 2015)
strain_extra = min(45, round(4 × max(0, S − 10)))   S = reported strain of cycle D−1; 0 when null
debt_extra   = min(60, round(0.25 × Σ max(0, base − asleep(D−k)) for k = 1..3))
               nights without a main sleep or with unknown asleep minutes are skipped (debt_nights_used counts the rest)
nap_credit   = min(120, Σ asleep minutes of naps whose end time is in [cycle_start(D−1), main_sleep(D).startTime))
               (0 when there is no main sleep for D)
need         = clamp(base + strain_extra + debt_extra − nap_credit, 300, 720)
```

Debt uses the base need, not each night's full need, so the formula never recurses. Its 0.25 factor and 3-night horizon are conservative choices: sleep loss accumulates over consecutive nights (Van Dongen et al. 2003) but is not repaid minute for minute.

### 4.5 Sleep performance

`performance = min(100, round(100 × asleep_minutes(main sleep D) / need))`, integer; null with `no_sleep` when there is no main sleep or its asleep minutes are unknown (`pending` for the current date). Bands: `high` ≥ `SleepPerformanceHighMin`; `medium` from `SleepPerformanceMediumMin` to < `SleepPerformanceHighMin`; `low` < `SleepPerformanceMediumMin`.

Worked example (`sleep.json`, case `worked_example_full_day`, the same night as §2.6): base 450; previous cycle strain 11.2 → `strain_extra` = round(4.8) = 5; prior nights 427, 419, 441 → shortfalls 23 + 31 + 9 = 63 → `debt_extra` = round(15.75) = 16; one 28-minute nap → `nap_credit` 28; need = 450 + 5 + 16 − 28 = **443**; asleep 415 → performance round(93.7) = **94**, `high`.

### 4.5a Composite sleep performance (composite mode only)

Computed only when `sleep_score_mode` is `composite` (§0.1); spec: [composite-sleep-spec.md](../goop/composite-sleep-spec.md). It blends the reported, rounded values of the night ending on D, so a reader can recompute it from JSON:

```
S = performance.value (§4.5)   C = consistency.value (§4.6)   E = efficiency_pct (§4.2)
if S is null: value, band, weights, parts = null; status and reason copied from performance
e_part = E is null ? null : clamp(100 × (E − CompositeEfficiencyZero) / (CompositeEfficiencyFull − CompositeEfficiencyZero), 0, 100)
w_s, w_c, w_e = 0.70, 0.15, 0.15
if C is null:      w_s += w_c; w_c = 0
if e_part is null: w_s += w_e; w_e = 0
value = round(w_s × S + w_c × C + w_e × e_part)        # integer, half away from zero
band  = performance bands (SleepPerformanceHighMin, SleepPerformanceMediumMin)
```

The weights are applied as whole percents, so with integer parts every product is an integer and a half-way total such as 98.5 rounds to 99 exactly. `weights` reports the weights used for that night and `parts` reports S, C and e_part (1 dp). Vectors: `fixtures/v2/scores/sleep_composite.json` (spec §4.1), for example `odd_time_poor_efficiency` (S 94, C 52, E 84 → e_part 70 → 84.1 → **84**, medium) and `no_consistency` (S 94, E 88 → weights 0.85/0.00/0.15 → **93**).

### 4.6 Consistency

Over the main sleeps ending on D−6 … D (7 nights), with at least 4 present:

```
bed(n)  = local start time of day, in minutes after midnight
wake(n) = local end time of day, in minutes after midnight
sd_bed, sd_wake = clock spread of the bed times and of the wake times (below)
consistency = round(clamp(100 × (1 − ((sd_bed + sd_wake) / 2) / 120), 0, 100))
```

**Clock spread** is the sample standard deviation of times of day around their circular centre. Sort the n times. There are n ways to cut the 24-hour clock between two neighbouring times; for each cut, add 1440 to the times before it so the list runs forward from the cut, and take the sample standard deviation. The spread is the smallest of the n. It needs no cut point and no threshold, so a schedule is judged the same at any time of day. When the times are spread evenly around the clock, every cut gives the same value, so there is no ambiguous centre.

Before 2.3.2 the rule cut the clock at fixed points: bedtimes at noon, wakes at 18:00 (oss-data-audit row 5). A wake list that straddled 18:00 then looked a day wide: six wakes at 17:30 and one at 18:05 under a fixed 10:00 bedtime gave a wake spread of 531 minutes and Consistency 0. The clock spread gives 13.2 minutes and 94. Lists that the old cuts did not split, which covers ordinary nights, keep their values.

Bands: `high` ≥ `ConsistencyHighMin`; `medium` from `ConsistencyMediumMin` to < `ConsistencyHighMin`; `low` < `ConsistencyMediumMin`. Fewer than 4 nights: null, `insufficient_nights`. Local times use `Europe/London` wall clock, so a DST change does not look like a one-hour shift. Regular timing matters for sleep and circadian health (Phillips et al. 2017; Fischer, Klerman and Phillips 2021); the standard-deviation form is used instead of the Sleep Regularity Index because SRI needs continuous 24-hour sleep/wake data and breaks on missing nights.

Golden cases (`sleep.json`, key `consistency`): `regular_week` 90; `crosses_midnight` 68; `late_sleeper_irregular` 15; `evening_wake_wraps` 80; `shift_evening_wake` 94 (bed spread 0.0, wake 13.2); `shift_noon_bedtime` 92 (bedtimes 11:40 to 12:20: bed 13.2, wake 6.5); `irregular_shift_schedule` 0 (both 376.3); `ambiguous_centre` 0 (four times six hours apart: both 464.8); `three_nights_only` null.

### 4.7 Hypnogram

From the main sleep: `segments` = `stages[]` sorted by `startTime`, each `{start, end, stage}` with `stage` the lower-case type (`awake`, `light`, `deep`, `rem`, `asleep`, `restless`). `short_awakenings` = `shortAwakenings[]` in the same shape. Segments are clipped to the window (§4.2a), with RFC 3339 UTC times. Unstaged spans (§4.2a: uncovered time at the window's start or end) are reported in `unstaged: [{start, end}]` and drawn as the unstaged block, never as a guessed stage. Gaps between segments are drawn as empty. With no segments or no unstaged span, `unstaged` is `[]`. Shape: contract §5.5.

### 4.8 Overnight series

- `overnight_hr`: covered heart-rate minutes in `[startTime truncated to the minute, endTime)`, grouped into 5-minute buckets counted from the truncated start; each bucket `{t: bucket start, bpm: round(mean of minute averages)}`; empty buckets omitted.
- `overnight_hrv`: `heart-rate-variability` samples with `startTime ≤ physicalTime < endTime` and an RMSSD value, `{t, rmssd_ms}` (1 decimal), sorted. Display only; no score uses them.

### 4.9 Respiratory rate by stage

Choose the `respiratory-rate-sleep-summary` record whose `sampleTime.physicalTime` lies in `[startTime − 1 h, endTime + 1 h]` of the main sleep and is closest to `endTime`. Output `full_bpm`, `deep_bpm`, `light_bpm`, `rem_bpm` from the matching `*Stats.breathsPerMinute`; any missing stage, or a stage whose value is `0` (not measured, data.md §3.1), is null; no match makes the whole object null.

### 4.10 Typical stage ranges (display only)

For D, use main sleeps with `type == "STAGES"` on London dates D−30 through D−1, excluding D. For light, deep, REM and awake, collect each non-null stage duration. Restorative duration requires both deep and REM and is their sum. Each range reports its own count; the overall count includes every eligible night. After 7 values, report the 25th and 75th percentiles using linear interpolation (R type 7), rounded half away from zero once. Otherwise both limits are null. Contract §5.5.1 defines the object.

Display constants: `StageTypicalNights = 30`, `StageTypicalMinNights = 7`, `StageTypicalLowQuantile = 0.25`, `StageTypicalHighQuantile = 0.75`. No score uses them, so `score_version` is unaffected by these display constants.

### 4.11 Sleep planner (display only)

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

This is §4.4 applied to the night ending D+1 with the data seen so far: `S` is the current cycle's strain so far, and naps count up to `now` because the main sleep has not started.

```
nights   = main sleeps ending on D−13 … D (14 London dates) whose efficiency_pct is above 0
N        = len(nights)                               # nights_used
if N < 3: status "unavailable", reason "insufficient_nights"
          efficiency_pct_used = null, goals = []
          wake_target as below when wake_source is "config", else null
efficiency_pct_used = median of the nights' efficiency_pct            (1 dp; .5 when the count is even)
latency_minutes_used = null                                           (kept in the body; see below)
wake_source = "config" when wake_target is set in config, else "typical"
wake_minutes = config HH:MM, or floor(median of the nights' local wake time-of-day in minutes, seconds as fractions)
wake_target  = London wall clock on D+1 at wake_minutes (spring-forward gap → 02:00, as §3.1)
for pct in (100, 85, 70):
    in_bed_minutes = round(need × pct / efficiency_pct_used)
    bedtime        = wake_target − in_bed_minutes
```

`efficiency_pct_used` is used at full precision (a median of integers is exact at 1 dp). Efficiency is asleep over the whole time in bed (§4.2), so it already holds the time to fall asleep and the usual time awake; dividing by it once gives the whole time in bed. A night with 0% efficiency says nothing about how long sleep takes, so it is not a planner night, and a zero efficiency never divides a goal (`SleepPlanGoals` returns no goals).

Before 2.3.3 the planner added the median `minutes_to_fall_asleep` on top, counting it twice (oss-data-audit, accuracy item 1). `latency_minutes_used` stays in the body as null so an older client still decodes it; a client shows no separate time to fall asleep. The planner's typical wake uses the same nights as its efficiency, so it equals §3.1's typical wake whenever every main sleep has asleep minutes (parity1-spec §13 item 8).

**Worked example: `day_full.json`** (store_full, D = 2026-03-10, now 14:30Z, GMT):
- `cycle_strain` 12.8 → `strain_extra` round(11.2) = **11**.
- Nights D, D−1, D−2 asleep 415, 427, 419 → shortfalls 35 + 23 + 31 = 89 → `debt_extra` round(22.25) = **22**, `debt_nights_used` 3.
- No nap ends in [06:29Z, 14:30Z) → `nap_credit` **0**.
- `need` = 450 + 11 + 22 − 0 = **483** (8:03).
- Nights 2026-02-25 … 03-10 with efficiency: 12 (02-26 and 03-05 missing). Efficiencies sorted 90, 90, 91, 91, 91, 92, 93, 93, 93, 94, 94, 95 → median **92.5**. Wake times sorted 06:29, 06:56, 06:58, 06:59, 07:02, 07:06, 07:08, 07:10, 07:12, 07:16, 07:23, 07:23 → median 427 min → **07:07**.
- Goals: 100 % → round(483 × 100 / 92.5) = **522** (8:42), bed by **22:25**; 85 % → round(443.84) = **444** (7:24), **23:43**; 70 % → round(365.51) = **366** (6:06), **01:01** (2026-03-11).

```json
"sleep_plan": {
  "status": "ok", "reason": null,
  "need_minutes": 483,
  "need_parts": { "baseline_minutes": 450, "strain_extra_minutes": 11, "debt_extra_minutes": 22,
                  "nap_credit_minutes": 0, "cycle_strain": 12.8, "debt_nights_used": 3 },
  "wake_target": "2026-03-11T07:07:00Z", "wake_source": "typical",
  "efficiency_pct_used": 92.5, "latency_minutes_used": null, "nights_used": 12,
  "goals": [
    { "pct": 100, "in_bed_minutes": 522, "bedtime": "2026-03-10T22:25:00Z" },
    { "pct": 85,  "in_bed_minutes": 444, "bedtime": "2026-03-10T23:43:00Z" },
    { "pct": 70,  "in_bed_minutes": 366, "bedtime": "2026-03-11T01:01:00Z" } ] }
```

With config `wake_target: "06:45"` (`day_full_config.json`): `wake_source "config"`, `wake_target 2026-03-11T06:45:00Z`, bedtimes 22:03, 23:21, 00:39; everything else equal.

**Goal vectors** (`fixtures/v2/scores/sleep_plan.json`, key `goals`; input `need_minutes`, `efficiency_pct_used`, `wake_target`):

| Case | need | eff | wake | 100 % | 85 % | 70 % |
| --- | --- | --- | --- | --- | --- | --- |
| `mockup` | 470 | 90 | 2026-03-11T06:45Z | 522, 22:03 | 444, 23:21 | 366, 00:39 |
| `day_full` | 483 | 92.5 | 2026-03-11T07:07Z | 522, 22:25 | 444, 23:43 | 366, 01:01 |
| `need_floor` | 300 | 100 | 2026-03-11T05:00Z | 300, 00:00 | 255, 00:45 | 210, 01:30 |
| `half_rounds_up` | 455 | 100 | 2026-03-11T07:00Z | 455, 23:25 | 387, 00:33 | 319, 01:41 |
| `spring_forward` | 480 | 96 | 2026-03-29 07:00 BST = 06:00Z | 500, 2026-03-28T21:40Z | 425, 22:55Z | 350, 2026-03-29T00:10Z |
| `zero_efficiency` | 470 | 0 | 2026-03-11T06:45Z | no goals | | |

Before 2.3.3, `mockup` and `day_full` added 10 and 6 minutes of latency (532 and 528 at 100 %). Engine tests cover a night with no latency (`TestSleepPlanWakeAcrossSpringGapAndMissingLatency`: goals equal need at 100 % efficiency) and nights with 0 % efficiency (`TestSleepPlanSkipsZeroEfficiencyNights`: skipped; one positive night of four is `insufficient_nights` with no goals).

Key `need` holds the day_full need-parts case above and one with a nap: same inputs plus a 40-minute nap ending 13:10Z → `nap_credit 40`, need 443. Key `nights` holds `two_nights` (status `unavailable`, `insufficient_nights`) and `config_wake_with_two_nights` (unavailable, `wake_target` present, `goals []`).

## 5. Overnight vitals panel

For date D, five metrics, each against a personal range:

| Key | Value | Range | Adverse direction |
| --- | --- | --- | --- |
| `hrv_rmssd` | daily HRV (ms, 1 dp) | `[exp(mean_ln − VitalRangeSD × sd_eff_ln), exp(mean_ln + VitalRangeSD × sd_eff_ln)]` | below |
| `resting_hr` | daily resting HR (bpm, integer) | `mean ± VitalRangeSD × sd_eff` | above |
| `respiratory_rate` | daily respiratory rate (1 dp) | `mean ± VitalRangeSD × sd_eff` | above |
| `spo2` | daily `averagePercentage` (1 dp) | `mean ± VitalRangeSD × sd_eff` | below |
| `skin_temp_deviation` | `nightly − baseline` (°C, 2 dp) | `[−VitalRangeSD × max(stddev_30d, 0.10), +VitalRangeSD × max(stddev_30d, 0.10)]` from Google's own fields | above |

Ranges use §1.3 baselines and need `n ≥ 7`; output `range_low`/`range_high` rounded to 1 decimal (2 for skin temperature). `position`: `below` (value < low), `above` (value > high), `within`, `no_baseline` (value present, fewer than 7 baseline values, or skin temperature without baseline/SD), or null (no value). Compare unrounded numbers.

`outside_range` lists keys positioned `above` or `below`; `adverse` lists keys outside the range in their adverse direction.

Below its range, skin temperature is outside but not less favourable.

### 5.1 Persistent vitals

`persistent` lists, in the order `hrv_rmssd`, `resting_hr`, `respiratory_rate`, `spo2`, `skin_temp_deviation`, each key that is in `adverse` on night D and in `adverse` on each of the `VitalAttentionNights − 1` London dates before D, each night judged against its own baseline. A night with no value, no range or a conflict for that key breaks the run. Nothing is carried over a missing night.

### 5.2 Monitor state

`monitor_state` is `building` when `metrics_with_range` is 0. Otherwise it is `attention` when `persistent` has at least `VitalAttentionMinVitals` keys; `outside` when `outside_range` is not empty; else `within`.

### 5.3 Weekly HRV trend

`hrv_trend` is a VitalMetric plus `nights`. For date D:

1. `nights` is the number of London dates D−6 … D on which daily HRV is `available` (§1.3, step 2).
2. When `nights ≥ HRVTrendMinNights`, `mean_w` is the mean of `ln(rmssd_ms)` over those nights, `value = exp(mean_w)` rounded to 1 dp, and `status` is `available`. Otherwise `value`, `range_low`, `range_high` and `position` are null and `status` is `missing`.
3. The baseline is the §1.3 HRV baseline for date D−(`HRVTrendDays` − 1): dates D−7 … D−48, at most 28 values, ln-transformed. `baseline_values` is its `n`. `sd_eff = max(sd, SDFloorLnRMSSD)`.
4. When `n ≥ HRVTrendMinBaseline`, `range_low = exp(mean_b − HRVTrendBandSD × sd_eff)` and `range_high = exp(mean_b + HRVTrendBandSD × sd_eff)`, each rounded to 1 dp. Otherwise both are null.
5. `position` is null when `value` is null; `no_baseline` when `n < HRVTrendMinBaseline`; otherwise `below` when `mean_w < mean_b − HRVTrendBandSD × sd_eff`, `above` when `mean_w > mean_b + HRVTrendBandSD × sd_eff`, else `within`. Compare unrounded numbers.
6. `unit` is `ms`.

`hrv_trend` is display only. It never enters `metrics`, `outside_range`, `adverse`, `persistent`, `metrics_with_range`, `monitor_state`, any health flag or any score.

Sources: 7-day rolling ln RMSSD after Plews et al. 2012 and 2013; the 1 × CV band after Plews as reported by Buchheit 2014; at least 3 nights a week after Plews et al. 2014. The 4-night minimum, the lag and the 14-value minimum are ghoops choices. Rule, replay and model: [hrv-trend-spec.md](../goop/hrv-trend-spec.md).

## 6. Health flags

`health_flags` is an array of `{code, severity, message}`. Messages are fixed strings (copy exactly); they describe and never diagnose.

| `code` | `severity` | Condition | `message` |
| --- | --- | --- | --- |
| `vitals_outside_range` | `attention` | `len(persistent) ≥ VitalAttentionMinVitals` | `"<N> overnight vitals have been outside your usual range for <VitalAttentionNights> nights in a row, in the less favourable direction."` |
| `spo2_below_usual` | `attention` | SpO2 value < `mean − SpO2FlagSD × sd_eff` (n ≥ 7) | `"Overnight SpO2 is well below your usual range."` |
| `irn_alert_recorded` | `attention` | any `irregular-rhythm-notification` record with start in D−29 … D | `"Your Fitbit recorded an irregular rhythm notification. Check the Fitbit app and speak to a clinician if you are concerned."` |
| `device_battery_low` | `info` | tracker `batteryLevel < 20` or `batteryStatus` `Low` or `Empty` | `"Tracker battery is low."` |
| `collector_stale` | `attention` | `freshness.collector_stale` | `"The Mac has not collected new data recently."` |
| `device_sync_stale` | `info` | `freshness.device_stale == true` | `"The tracker has not synced to the Fitbit app recently."` |
| `provider_timezone_mismatch` | `attention` | settings `timeZone` present and not `Europe/London` | `"Your Google Health timezone is not Europe/London, so daily dates may not align."` |

Order: as in this table.

SpO2 is a flag only. It never changes recovery: night-to-night wrist SpO2 varies and a fixed clinical threshold would make a medical claim.

## 7. Daytime stress: not shipped in v2

A stress-style score needs either daytime HRV or heart rate with reliable activity context. v2 has neither: Google gives HRV samples only during sleep, the heart-rate samples on this account carry no `motionContext`, and minute steps are not collected. Heart rate raised without movement is confounded by caffeine, heat, posture, digestion and illness, and stress measures based on HRV need controlled conditions to mean much (Kim et al. 2018). A number built on that would look precise and mislead, so v2 ships no stress score. Detected efforts (§3.9) already surface unexplained high-heart-rate periods without labelling them stress.

## 8. VO2 max

The latest `daily-vo2-max` record dated D−30 … D: `value` = `vo2Max` (ml/kg/min, 1 dp), `date`, `cardio_fitness_level` (provider enum as is), `estimated` (bool or null), `status: "available"`. None: all null, `status: "missing"`, `reason: "no_data"`. ghoops never estimates VO2 max itself. The probe shows no VO2 data for this account yet.

## 9. Golden vectors

Files in `fixtures/v2/scores/` share this envelope:

```json
{ "kind": "score_vectors", "score_version": "2.4.1", "synthetic_fixture": true, "cases": [ { "name": "...", "input": { }, "expected": { } } ] }
```

| File | Function under test | `input` fields | `expected` fields |
| --- | --- | --- | --- |
| `recovery.json` | recovery from explicit inputs (§2.2 to §2.5) | `hrv_ms`, `hrv_baseline_ms[]`, `rhr_bpm`, `rhr_baseline_bpm[]`, `rr_bpm`, `rr_baseline_bpm[]`, `skin_temp {nightly_c, baseline_c, stddev_30d_c}` or null, `sleep_performance` (any can be null) | `value`, `band`, `status`, `reason`, `confidence`, `components` |
| `strain.json` | TRIMP and strain from minute averages (§3.4 to §3.7); key `cases` plus key `trimp_to_strain` | `resting_hr`, `max_hr`, `minute_avg_bpm[]` (covered minutes only), `expected_minutes` | `trimp`, `strain`, `band`, `hr_coverage`, `zones_minutes` |
| `sleep.json` | sleep need and performance (§4.4, §4.5) under key `sleep_need`; consistency (§4.6) under key `consistency` | need: `baseline_need_minutes`, `previous_cycle_strain`, `prior_nights_asleep_minutes[3]` (D−1 first; null = no night), `nap_asleep_minutes[]`, `main_asleep_minutes`; consistency: `nights[] {bed_local "HH:MM", wake_local "HH:MM"}` | need: `strain_extra_minutes`, `debt_extra_minutes`, `debt_nights_used`, `nap_credit_minutes`, `total_minutes`, `performance`, `band`; consistency: `value`, `status`, `reason`, `nights_used`, `bedtime_sd_minutes`, `wake_sd_minutes`, `band` |
| `strain_target.json` | target (§3.12) | reported Recovery, Strain value and confidence, intent | low, high, intent, position, status, reason |
| `sleep_plan.json` | planner (§4.11), keys `goals`, `need`, `nights` | need, efficiency, latency, wake; need parts and eligible nights | goal times; need parts; unavailable cases |
| `hrv_trend.json` | weekly HRV trend (§5.3) | `week_hrv_ms[7]` (D first; null for no value), `baseline_hrv_ms[]` (already selected, most recent first, at most 28) | `value`, `status`, `nights`, `range_low`, `range_high`, `baseline_values`, `position` |
| `trend.json` | trend (§11b) | `values[30]` oldest first, `last_open` | days_7, days_30, mean_7, mean_30, direction |
| `sleep_composite.json` | composite sleep performance (§4.5a); `score_version` `<Version>+composite.1` (2.3.3+composite.1 today) | `performance {value, status, reason}`, `consistency`, `efficiency_pct` | `value`, `band`, `status`, `reason`, `weights`, `parts` |
| `vitals.json` | ranges, positions, `adverse`, `persistent`, `monitor_state` and the two vitals flags (§5, §6) | `tonight` and `last_night` (null for none), each `{hrv_ms, hrv_baseline_ms[], rhr_bpm, rhr_baseline_bpm[], rr_bpm, rr_baseline_bpm[], spo2_pct, spo2_baseline_pct[], skin_temp {nightly_c, baseline_c, stddev_30d_c} or null}`; any value can be null; baselines already selected, most recent first | `ranges {key: [low, high] or null}`, `positions {key: position or null}`, `outside_range`, `adverse`, `persistent`, `metrics_with_range`, `monitor_state`, `flags [{code, message}]` |

Baseline arrays in `recovery.json` are already selected (most recent first, at most 28); the selection rule of §1.3 is tested by the whole-day goldens. Compare integers exactly and decimals within one unit of the last decimal place.

## 10. README philosophy change

Replace the second paragraph of `README.md` ("It does not generate readiness or sleep scores…") with:

> Version 2 adds transparent estimates: Recovery (0–100), Strain (0–21) and Sleep performance, computed on this Mac by formulas documented in [docs/v2/scores.md](docs/v2/scores.md). They are ghoops's own estimates, not WHOOP's or Fitbit's algorithms, and not medical measurements. Every score shows its inputs, the personal baseline it used and its coverage or confidence, and is empty with a reason when data is missing. ghoops still never invents measurements: missing data stays missing, time you add to a night counts as sleep without a stage and is shown that way, gaps in heart rate are never filled, and the v1 commands keep their original meaning. It does not diagnose, infer calories, or read lifting volume.

Also replace "No scheduled background process is installed." in "Collect and read" with "`ghoops schedule install` installs two LaunchAgents (collection every 30 minutes and the local API server); v1 `sync` installs nothing." Update `docs/privacy-security.md` "Data semantics and lifecycle" first sentence to: "v1 reports generate no scores. v2 generates the documented estimates in docs/v2/scores.md and never diagnoses."

## 11. Sources

- Altini M, Plews D. What is behind changes in resting heart rate and heart rate variability? A large-scale analysis of longitudinal measurements acquired in free-living. *Sensors* 2021;21(23):7932.
- Banister EW. Modeling elite athletic performance. In: MacDougall JD, Wenger HA, Green HJ, eds. *Physiological Testing of the High-Performance Athlete*. Human Kinetics; 1991:403–424.
- Buchheit M. Monitoring training status with HR measures: do all roads lead to Rome? *Frontiers in Physiology* 2014;5:73.
- Edwards S. *The Heart Rate Monitor Book*. Polar Electro; 1993.
- Fischer D, Klerman EB, Phillips AJK. Measuring sleep regularity: theoretical properties and practical usage of existing metrics. *Sleep* 2021;44(10):zsab103.
- Karvonen MJ, Kentala E, Mustala O. The effects of training on heart rate; a longitudinal study. *Annales Medicinae Experimentalis et Biologiae Fenniae* 1957;35(3):307–315.
- Kim HG, Cheon EJ, Bai DS, Lee YH, Koo BH. Stress and heart rate variability: a meta-analysis and review of the literature. *Psychiatry Investigation* 2018;15(3):235–245.
- Morton RH, Fitz-Clarke JR, Banister EW. Modeling human performance in running. *Journal of Applied Physiology* 1990;69(3):1171–1177.
- Phillips AJK, et al. Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing. *Scientific Reports* 2017;7:3216.
- Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring. *Sports Medicine* 2013;43(9):773–781.
- Reed DL, Sacco WP. Measuring sleep efficiency: what should the denominator be? *Journal of Clinical Sleep Medicine* 2016;12(2):263–266.
- Tanaka H, Monahan KD, Seals DR. Age-predicted maximal heart rate revisited. *Journal of the American College of Cardiology* 2001;37(1):153–156.
- Van Dongen HPA, Maislin G, Mullington JM, Dinges DF. The cumulative cost of additional wakefulness. *Sleep* 2003;26(2):117–126.
- Watson NF, et al. Recommended amount of sleep for a healthy adult: a joint consensus statement of the American Academy of Sleep Medicine and Sleep Research Society. *Sleep* 2015;38(6):843–844.
- Google Health API v4 reference and data-type guides (field meanings, roll-up wear filtering, sleep summary definitions): https://developers.google.com/health.

- [S1] Alavi A, et al. Real-time alerting system for COVID-19 using wearable data (title as retrieved from PMC). *Nature Medicine*. doi:10.1038/s41591-021-01593-2 (full text, PMC8799466).
- [S2] Mishra T, et al. Early detection of COVID-19 using a smartwatch (title as retrieved from PMC). *Nature Biomedical Engineering* 2020;4:1208–1220. doi:10.1038/s41551-020-00640-6 (full text, PMC9020268).
- [S3] Natarajan A, Su H-W, Heneghan C. Assessment of physiological signs associated with COVID-19 measured using wearable devices. *npj Digital Medicine* 2020;3:156. doi:10.1038/s41746-020-00363-7 (full text, PMC7705652).
- [S4] Esmaeilpour Z, et al. Detection of common respiratory infections, including COVID-19, using consumer wearable devices in health care workers: prospective model validation study. *JMIR* 2024. JMIR Publications, 2024. doi:10.2196/53716 (full text, PMC11292157).
- [S5] Miller DJ, et al. Analyzing changes in respiratory rate to predict the risk of COVID-19 infection. *PLoS ONE* 2020;15(12):e0243693 (full text, PMC7728254).
- [S6] Mason AE, et al. Detection of COVID-19 using multimodal data from a wearable device: results from the first TemPredict Study. *Scientific Reports* 2022;12:3463 (full text, PMC8891385).
- [S7] Plews DJ, Laursen PB, Kilding AE, Buchheit M. Heart rate variability in elite triathletes, is variation in variability the key to effective training? A case comparison. *European Journal of Applied Physiology* 2012;112(11). doi:10.1007/s00421-012-2354-4. Abstract only.
- Bellenger CR, et al. Monitoring athletic training status through autonomic heart rate regulation: a systematic review and meta-analysis. *Sports Medicine* 2016. PubMed 26888648.
- Javaloyes A, Sarabia JM, Lamberts RP, Moya-Ramón M. Training prescription guided by heart-rate variability in cycling. *International Journal of Sports Physiology and Performance* 2019;14(1):23–32. doi:10.1123/ijspp.2018-0122.
- Le Meur Y, et al. Evidence of parasympathetic hyperactivity in functionally overreached athletes. *Medicine and Science in Sports and Exercise* 2013;45(11):2061–2071. PubMed 24136138.
- Plews DJ, et al. Monitoring training with heart-rate variability: how much compliance is needed for valid assessment? *International Journal of Sports Physiology and Performance* 2014;9(5):783. PubMed 24334285.
- Vesterinen V, et al. Individual endurance training prescription with heart rate variability. *Medicine and Science in Sports and Exercise* 2016;48(7):1347–1354. doi:10.1249/MSS.0000000000000910.
- [S8] Schneider C, et al. Heart rate variability monitoring during strength and high-intensity interval training overload microcycles. *Frontiers in Physiology* 2019;10:582. doi:10.3389/fphys.2019.00582 (full text, PMC6538885).

## 11a. Comparison windows (display only)

`ComparisonDays = 30`, `ComparisonMinDays = 7`. For D, average each non-null day-row measurement on D−30 through D−1, excluding D. Report available counts; means need at least 7 values. Round means to 1 decimal, except steps (0) and skin temperature (2). Contract §5.2.1 defines metric order and fields. These constants affect display only; no score uses them and `score_version` is unaffected by these display constants.

## 11b. Brief trends (display only)

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

## 11c. Journal impact (display only)

For each enabled journal behaviour, as of the default date D ([journal-spec.md](../goop/journal-spec.md) §4): over the Recovery dates R from D − (`JournalWindowDays` − 1) to D, pair the answer for journal date R − 1 with the reported, rounded Recovery of R (§1.1). A null Recovery drops its answer. When both the "yes" and the "no" list hold at least `JournalMinAnswers` values, report both means (1 dp), `difference = round(mean(yes) − mean(no), 1)` from the unrounded means, and `direction` `higher`, `lower` or `same` (0.0). Otherwise report only the counts, with status `insufficient`. Display constants, so `score_version` is unaffected: `JournalWindowDays = 90`, `JournalMinAnswers = 5`, reported in `score_constants.journal`. Vectors: `fixtures/v2/scores/journal.json`. The result is an association in the owner's own data, never a cause.
