# ghoops v2: JSON and HTTP contract

Status: design spec. `schema_version` **2**. Every example value here is synthetic. The concrete, complete examples are the files in [`fixtures/v2/`](../../fixtures/v2/); where a table and a fixture disagree, the table wins and the fixture is a bug.

Readers: the Go builder (who produces these bodies), the iOS builder (who decodes them) and assistants that read the CLI's JSON. Formulas are in [scores.md](scores.md); collection in [data.md](data.md).

## 1. Principles

1. One body, many readers. `ghoops <command> --json` on the Mac and `GET /v2/<command>` over HTTP return byte-identical JSON for the same arguments and the same `now` (only `generated_at` can differ between two calls).
2. Additive evolution. Consumers must ignore unknown keys. Adding a key keeps `schema_version: 2`. Removing or renaming a key, changing a type, or changing a meaning needs `schema_version: 3`.
3. Missing stays missing. A number that is not known is `null`, never `0`. Arrays are `[]`, never `null`. Objects listed in this file are always present (their fields may be null) unless the table says "object or null".
4. Every nullable score explains itself through `status` and `reason`.
5. Times are RFC 3339 UTC strings with a `Z` suffix (`"2026-03-10T06:29:00Z"`); provider times are copied unchanged, so they may carry fractional seconds (`"…:35.600Z"`). Dates are `"YYYY-MM-DD"` London dates. Durations are minutes. Units are fixed per field (no unit conversion based on account settings).
6. Read-only. No command or endpoint in v2 writes to Google.

## 2. Shared types

| Type | JSON | Rule |
| --- | --- | --- |
| `Date` | string `YYYY-MM-DD` | London date |
| `Time` | string RFC 3339 UTC | see §1.5 |
| `int` | JSON integer | never a string |
| `num` | JSON number | rounded as the field says |
| `?` suffix | the value or `null` | e.g. `int?` |
| `Band3` | `"high"`, `"medium"`, `"low"` | recovery, sleep performance, consistency, sleep efficiency |
| `StrainBand` | `"light"`, `"moderate"`, `"strenuous"`, `"all_out"` | strain |
| `ScoreStatus` | `"ok"`, `"calibrating"`, `"in_progress"`, `"pending"`, `"unavailable"` | scores.md §1.2 |
| `Reason` | string from scores.md §1.2 or `null` | |
| `Confidence` | `"high"`, `"medium"`, `"low"` or `null` | |
| `MetricStatus` | `"available"`, `"missing"`, `"not_synced"`, `"unavailable"`, `"permission_missing"`, `"conflict"` | for plain measurements; see §2.1 |
| `Zones` | object `{below, z1, z2, z3, z4, z5}`, each `int` minutes | scores.md §3.5 |

### 2.1 MetricStatus for plain measurements

For a measurement (vitals, activity) on date D, derived from the v2 store `coverage` row of its stream for D:

| Condition | `status` | `value` |
| --- | --- | --- |
| a value exists for D (one value, or identical duplicates) | `available` | the value |
| different values exist for D | `conflict` | null |
| no value; coverage row `ok` | `missing` | null |
| no value; coverage row `permission_missing` | `permission_missing` | null |
| no value; coverage row `unavailable`, `unsupported` or `stale` | `unavailable` | null |
| no value; no coverage row | `not_synced` | null |

`Metric` (activity) = `{ "value": num?, "unit": string, "status": MetricStatus, "reason": null }` (`reason` is reserved and always null in 2.0.0).

## 3. CLI commands

New v2 commands. All read commands print exactly one JSON object followed by `\n` to stdout and never contact Google. `--json` is accepted on every v2 command and changes nothing (v2 read commands always print JSON). Global flags `--state-dir PATH` and `--json` keep their v1 meaning.

| Command | Flags | Output `kind` | Network |
| --- | --- | --- | --- |
| `ghoops collect` | `[--days N \| --from D --to D] [--quiet]` | `collect` (§5.14) | Google, read-only |
| `ghoops day` | `[--date D]` (default: scores.md §3.1 default date) | `day` (§5.2) | none |
| `ghoops sleep edit` | `--date D [--start T] [--end T]`; omitted endpoints keep their effective values | `sleep_edit` (§7.2) | stores the local override |
| `ghoops sleep restore` | `--date D` | `sleep_edit` (§7.2) | removes the override |
| `ghoops sleep edits` | `[--days N]`, default 30 | `sleep_edits` (§7.2), each with `applies` | none |
| `ghoops sleep` | `[--date D]` (same default) | `sleep` (§5.5) | none |
| `ghoops days` | `[--days N \| --from D --to D]`, default `--days 30`, N 1 to 90, the range ends at the default date | `days` (§5.10) | none |
| `ghoops workouts` | `[--days N \| --from D --to D]`, default `--days 14`, N 1 to 90, the range ends at the default date | `workouts` (§5.8) | none |
| `ghoops week` | `[--date D]` (default: the default date); the Monday-to-Sunday week containing D | `week` (§5.16) | none |
| `ghoops status` | none | `status` (§5.11) | none (reads the store, local auth state and the LaunchAgent plist files) |
| `ghoops snapshot` | none | `snapshot` (§5.12) | none |
| `ghoops brief` | `[--date D] [--include-values] [--part morning\|evening\|week]` | `brief` (§5.13) | none |
| `ghoops serve` | `[--port P]` (default 8787; 1024 to 65535) | HTTP server (§7) | listens on 127.0.0.1 only |
| `ghoops pair` | `[--rotate] [--url URL] [--png PATH]` | `pair` (§8) | runs `tailscale status --json` and `tailscale serve status --json` locally |
| `ghoops pair revoke` | none | `pair` with `"paired": false` | none |
| `ghoops schedule install \| uninstall \| status` | none | `schedule` (§5.14) | `launchctl` |
| `ghoops config show \| set KEY VALUE \| unset KEY` | keys include `strain_intent` and `wake_target` (scores.md §0.1), and the weekly targets `week_sleep_minutes` (240 to 720, default 420), `week_sleep_nights` (1 to 7, default 5), `week_activity_minutes` (1 to 1000, default 150) and `week_strength_days` (1 to 7, default 2) (week-review-spec.md §3.3); `unset` restores the default | `config` (§5.14) | none |
| `ghoops workout export-tcx` | `--id ID --output PATH [--partial]` | `export` (§5.14) | Google, read-only (data.md §2.4) |

Activity editing commands use the same validation as HTTP. They never write to Google Health.

| Command | Effect | Output `kind` |
| --- | --- | --- |
| `ghoops activity edit --id ID [--type T \| --type band] [--start T --end T \| --band-window] [--notes S \| --clear-notes] [--merge-with ID[,ID]]` | Reads the current edit, applies only the flags given, then stores it as PUT would. `--type band` and `--band-window` set those fields to null. | `edit` |
| `ghoops activity merge --id ID --with ID` | Computes the union window as scores.md §3.8a and adds `--with` to `merge_with`, keeping sport and notes. | `edit` |
| `ghoops activity hide --id ID` / `unhide --id ID` | Sets `hidden` true or false, keeping everything else. | `edit` |
| `ghoops activity restore --id ID` | As `DELETE /v2/edits/<id>`. | `edit` (`edit: null`) |
| `ghoops activity edits [--days N]` | Lists stored edits, `updated_at` within N days (default 30), each with `applies: bool`. | `edits` |
| `ghoops activity rate --id ID --rpe N` / `--clear` | As `PUT` / `DELETE /v2/ratings/<id>` (§7.2). Exactly one of `--rpe` and `--clear`, else usage exit 2. | `rating` |
| `ghoops activity add … [--origin added] [--notes S]` | Existing command, new optional flags; the default origin is `live`. | `activity` |
| `ghoops heart-rate --date D \| --start T --end T` | The §5.15 body. | `heart_rate` |
| `ghoops config set sport_alias.<TYPE> <TYPE>` / `config unset sport_alias.<TYPE>` | scores.md §0.1 | `config` |

Journal commands ([journal-spec.md](../goop/journal-spec.md) §5). They read and write the encrypted `journal-v2.enc` and never contact Google.

| Command | Effect | Output `kind` |
| --- | --- | --- |
| `ghoops journal show [--days N]` | N 1 to 90, default 30, ending at the default date. N over 90 is `date_out_of_range`. | `journal` (§5.14) |
| `ghoops journal set [--date D] KEY=yes\|no\|clear …` | Merges the arguments into the stored answers for D, default `default_date − 1`. D outside journal-spec §3 is `not_found`. | `journal_entry` |
| `ghoops journal behaviours [set KEY[,KEY…] \| reset]` | Lists the catalogue with `enabled` and `default`, replaces the enabled set, or restores the defaults. | `journal_behaviours` |

`ghoops activity list [--days N]`, `activity add --type T --start RFC3339 --end RFC3339 [--name S] [--origin added] [--notes S]` and `activity delete --id ID` remain available. Permanent activity deletion also removes its edit and merge references (§7.2).

Date rules (same as v1): `--date`, `--from`, `--to` are London dates; `--to` is inclusive; no future dates; at most 90 days per range; `--days` and `--from/--to` are mutually exclusive.

Exit codes (same as v1): `0` success; `1` operationally unavailable or incomplete (for example the store cannot be opened, or `collect` was partial); `2` invalid usage. On failure, v2 commands always write one error object (§6) to stderr, with or without `--json`.

Every response is computed from the store at the moment of the call. A read command never syncs implicitly.

## 4. Freshness and staleness

Every body except `brief` has a `freshness` object (`brief` has a reduced copy):

| Field | Type | Rule |
| --- | --- | --- |
| `collected_at` | `Time?` | `finished_at` of the most recent run in the store with `core_complete: true`; null if none |
| `collect_age_minutes` | `int?` | `floor((now − collected_at) / 60 s)`; null if `collected_at` is null |
| `last_collect_status` | `"ok"`, `"partial"`, `"failed"`, `"never"` | status of the most recent run of any kind |
| `collector_stale` | bool | `collected_at` is null or `collect_age_minutes > 90` |
| `device_last_sync_at` | `Time?` | max `lastSyncTime` over `user.paired_devices` entries with `deviceType: "TRACKER"` |
| `device_sync_age_minutes` | `int?` | as `collect_age_minutes` |
| `device_stale` | `bool?` | `device_sync_age_minutes > 360`; null when `device_last_sync_at` is null |
| `device_sync_source` | `"paired_devices"`, `"scope_missing"`, `"error"`, `"no_tracker"` | `scope_missing` when `user.paired_devices.status` is `permission_missing`; `error` for `unavailable` or `never`; `no_tracker` when the list has no tracker with a sync time |

Two separate questions, two separate fields: "Has the Mac collected recently?" is `collector_stale`. "Has the band synced to the Fitbit app recently?" is `device_stale`. The app shows both (app.md §5).

## 5. Bodies

### 5.1 Envelope

Every body starts with these keys, in this order:

| Field | Type | Value |
| --- | --- | --- |
| `schema_version` | int | `2` |
| `kind` | string | `day`, `sleep`, `days`, `workouts`, `status`, `snapshot`, `brief`, `collect`, `pair`, `schedule`, `config`, `export`, `activity`, `activity_deleted`, `edit`, `edits`, `heart_rate`, `sleep_edit`, `sleep_edits`, `journal`, `journal_entry`, `journal_behaviours`, `rating`, `week`, `error` |
| `source` | string | `"google_health_v4"` |
| `score_version` | string | `"2.4.1"`; `"2.4.1+composite.1"` (`<Version>+composite.1`) when `sleep_score_mode` is `composite` (scores.md §4.5a), on every body that carries it, `brief` included (omitted from `collect`, `pair`, `schedule`, `config`, `export`, `error`) |
| `generated_at` | Time | when the body was built |
| `timezone` | string | `"Europe/London"` |
| `score_config` | object | `{max_hr_override_bpm: int?, sleep_base_need_minutes: int, trimp_profile: string, sport_aliases: {string: string}, strain_intent: string, wake_target: string?, sleep_score_mode: "composite" (present only when composite)}` (scores.md §0.1). Present on `day`, `sleep`, `days`, `workouts`, `status`, `snapshot` and `heart_rate`. |
| `score_constants` | object | The engine numbers the app shows or computes with (§5.1.1), on exactly the bodies carrying `score_config`. Added on 2026-11-16. |
| `synthetic_fixture` | bool | present and `true` only when the store contains any record with `synthetic_fixture: true`; omitted otherwise. Production consumers (assistants, the app's live mode) must reject bodies that carry it. |

### 5.1.1 `score_constants`

| Field | Type | Rule |
| --- | --- | --- |
| `recovery.bands` | `{medium: int, high: int}` | lowest value of each band; below `medium` is `low` (scores.md §2.4) |
| `recovery.penalty_max` | num | the most each optional-input penalty subtracts (§2.3) |
| `strain.bands` | `{moderate, strenuous, all_out}` num | lowest rounded Strain of each band; below `moderate` is `light` (§3.6) |
| `strain.zones_hrr` | `{z1…z5}` num | lowest heart-rate reserve of each zone. Below `z1` counts as `below` and adds no TRIMP (§3.5) |
| `strain.trimp` | `{a, b}` num | the coefficients of the effective `trimp_profile` (§3.5) |
| `strain.scale` | `{k, trimp_cap}` num | `strain = min(21, 21 × ln(1 + trimp / k) / ln(1 + trimp_cap / k))`, 1 dp (§3.6) |
| `strain.coverage` | `{medium, high}` num | `confidence` cut-offs on unrounded covered ÷ expected minutes (§3.7) |
| `sleep.unstaged_counts_as` | string | `"asleep"`: how minutes inside a sleep window with no stage count (scores.md §4.2a). Added on 2026-11-19. An older Mac omits it; a client treats it as unknown and omits the sentence naming the rule. |
| `sleep.*_bands` | `{medium: int, high: int}` | lowest value of each band for performance (§4.5), consistency (§4.6) and efficiency (§4.2) |
| `sleep.composite` | `{weights: {sufficiency, consistency, efficiency} (num), efficiency_zero_pct: int, efficiency_full_pct: int}` | present only in composite mode (scores.md §4.5a), last key of `sleep`. Added on 2026-11-22. A client that finds it missing treats the composite's rules as unknown and leaves out the sentences that name them. |
| `workouts.recorded_hidden_overlap` | num | a goop entry hides a recorded entry it overlaps by at least this share of the shorter window (§3.8a) |
| `workouts.effort_hidden_overlap` | num | recorded and goop windows hide a detected effort they cover by at least this share (§3.9) |
| `vitals` | `{range_sd: num, attention_nights: int, attention_min_vitals: int}` | scores.md §5 and §6. Added on 2026-11-18. |
| `hrv_trend` | `{days: int, min_nights: int, band_sd: num, min_baseline: int}` | scores.md §5.3. Added on 2026-11-22. |
| `journal` | `{window_days: int, min_answers: int}` | the journal impact window and the fewest "yes" and "no" mornings before a difference is reported (scores.md §11c). Added on 2026-11-23; an older Mac omits it. |

`score_constants.vitals` was added on 2026-11-18. A Mac built before that date omits `vitals`, and a client treats it as unknown.

`score_constants.hrv_trend` was added on 2026-11-22. A Mac built before that date omits it, and a client treats it as unknown.

`score_constants` was added on 2026-11-16. A Mac built before then omits it. A client must treat a missing `score_constants` as unknown and must not substitute its own values. The Recovery weights are reported per score in `recovery.components.weights` (§5.3) and are not repeated here.

### 5.2 `day`

Fixture: `day_full.json`, `day_no_sleep.json`, `day_calibrating.json`, `day_new_user.json`.

| Field | Type | Rule |
| --- | --- | --- |
| envelope | | §5.1 |
| `freshness` | object | §4 |
| `date` | Date | the cycle date |
| `is_current_cycle` | bool | `cycle.status == "open"` |
| `cycle` | object | `{start: Time, end: Time?, status: "open"\|"closed"\|"not_started", start_source: "main_sleep_wake"\|"typical_wake_fallback", end_source: "now"\|"next_cycle_start"\|null}` (scores.md §3.1). For `not_started`, `start` is the future start and `end`, `end_source` are null. |
| `recovery` | object | §5.3 |
| `strain` | object | §5.4 |
| `strain_target` | object | §5.2.2 |
| `sleep` | object | sleep summary, §5.5 |
| `sleep_plan` | object or null | §5.2.3 |
| `vitals` | object | §5.6 |
| `activity` | object | §5.7 |
| `workouts` | array | §5.8 without `hr_series`, ordered by `start` |
| `strength_minutes` | `int?` | recorded and ghoops strength-workout duration, §5.4.1 |
| `vo2_max` | object | §5.7 |
| `health_flags` | array | §5.9 |
| `comparison` | object | prior 30-day means, §5.2.1 |

### 5.2.1 Prior-day comparison

New key in the `day` body (and therefore `snapshot.day`), after `health_flags`. Always present.

```json
"comparison": {
  "window_days": 30,
  "from": "2026-02-08",
  "to": "2026-03-09",
  "min_days": 7,
  "metrics": {
    "recovery": { "mean": 61.4, "available_days": 27 },
    "...": {}
  }
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `window_days` | int | `ComparisonDays` (30) |
| `from`, `to` | Date | `D − 30`, `D − 1` |
| `min_days` | int | `ComparisonMinDays` (7) |
| `metrics.<key>` | object | `{mean: num?, available_days: int}` for each key below, in this order: `recovery`, `strain`, `sleep_performance`, `asleep_minutes`, `efficiency_pct`, `restorative_minutes`, `hrv_rmssd_ms`, `resting_hr_bpm`, `respiratory_rate_bpm`, `spo2_pct`, `skin_temp_deviation_c`, `steps`, `zones_1_3_minutes`, `zones_4_5_minutes`, `strength_minutes`, and `sleep_performance_composite` last, present only in composite mode (added on 2026-11-22) |
| `mean` | `num?` | arithmetic mean of the non-null `days`-row values of that key for `from … to` (§5.10 defines the new row keys), 1 decimal (`steps`: 0 decimals; `skin_temp_deviation_c`: 2 decimals); null when `available_days < min_days` |
| `available_days` | int | count of non-null row values in the window |

Use a Go struct (not a map) so key order is stable.

### 5.2.2 `strain_target`

| Field | Type | Rule |
| --- | --- | --- |
| `low`, `high` | `num?` | scores.md §3.12, 1 dp; null when `status` is not `ok` |
| `intent` | string | the effective `strain_intent` |
| `position` | string? | `below`, `within`, or `above`. Null when `strain.confidence` is `low` or when `low` or `strain.value` is null. |
| `status` | ScoreStatus | `ok`, `pending` or `unavailable` |
| `reason` | Reason | `low_coverage` when `strain.confidence` is `low`. Otherwise, Recovery's reason when Recovery is null, or null. |

`low_coverage` applies to the position. The target range still uses Recovery, and the day still carries its observed Strain and coverage.

Always present (§1.3). Not added to `days` rows.

### 5.2.3 `sleep_plan`

Null unless `cycle.status == "open"`. The planner is defined in scores.md §4.11:

| Field | Type | Rule |
| --- | --- | --- |
| `status` | string | `ok` or `unavailable` |
| `reason` | Reason | `insufficient_nights` or null |
| `need_minutes` | int | scores.md §4.11, always computed |
| `need_parts` | object | `{baseline_minutes, strain_extra_minutes, debt_extra_minutes, nap_credit_minutes}` ints, `cycle_strain: num?`, `debt_nights_used: int` |
| `wake_target` | `Time?` | null only when unavailable with `wake_source` `typical` |
| `wake_source` | string | `typical` or `config` |
| `efficiency_pct_used` | `num?` | 1 dp |
| `latency_minutes_used` | `int?` | null since score 2.3.3: `efficiency_pct_used` already holds the time to fall asleep (scores.md §4.11). Kept so older clients decode. |
| `nights_used` | int | |
| `nights_needed` | int | `PlanMinNights` (3); present for `ok` and `unavailable`. Added on 2026-11-16. |
| `window_nights` | int | `PlanNights` (14); present for `ok` and `unavailable`. Added on 2026-11-16. |
| `goals` | array | `[{pct: int, in_bed_minutes: int, bedtime: Time}]`, 100, 85, 70; `[]` when unavailable |

`snapshot.day` carries it, so the phone and widgets need no new request.

### 5.3 `recovery`

| Field | Type | Rule |
| --- | --- | --- |
| `value` | `int?` | 0 to 100 |
| `band` | `Band3?` | scores.md §2.4 |
| `status` | ScoreStatus | `ok`, `calibrating`, `pending`, `unavailable` |
| `reason` | Reason | first of `missing_inputs`; null when `value` is present |
| `missing_inputs` | string[] | scores.md §2.2 order; `[]` when present |
| `confidence` | `Confidence` | null when `value` is null |
| `calibrating` | bool | `min(hrv_values, resting_hr_values) < 14` |
| `calibration` | object | `{values_needed: 7, values_for_full_confidence: 14, hrv_values: int, resting_hr_values: int}` |
| `inputs` | object | `{hrv_rmssd_ms: num? (1 dp), resting_hr_bpm: int?, respiratory_rate_bpm: num? (1 dp), skin_temp_deviation_c: num? (2 dp), sleep_performance: int?}` |
| `baseline` | object | `{window_days: 42, hrv: {values_used: int, ln_mean: num? (4 dp), ln_sd: num? (4 dp, after floor), sd_floor_applied: bool?, mean_ms: num? (1 dp, = exp(ln_mean))}, resting_hr: {values_used, mean (2 dp), sd (2 dp, after floor), sd_floor_applied}, respiratory_rate: {same as resting_hr}}`. `sd`/`ln_sd`/`sd_floor_applied` are null when `values_used < 2`; `mean`/`ln_mean` null when 0. |
| `components` | object or null | null when `value` is null; else `{hrv_z (2 dp), hrv_score (1 dp), resting_hr_z, resting_hr_score, sleep_score (int), weighted_base (1 dp), weights: {hrv, resting_hr, sleep} (num, 2 dp, sum 1.00), respiratory_rate_z (num?), respiratory_rate_penalty (1 dp), skin_temp_z (num?), skin_temp_penalty (1 dp), optional_missing: string[]}` |

In composite mode (scores.md §4.5a), `inputs.sleep_performance` and `components.sleep_score` hold `sleep.performance_composite.value`, the sleep input Recovery used; `score_config.sleep_score_mode` and `score_version` say so.

`weights` was added on 2026-11-16. A Mac built before then omits it. A client must treat a missing `weights` as unknown and must not substitute its own values.

### 5.4 `strain`

| Field | Type | Rule |
| --- | --- | --- |
| `value` | `num?` | 0.0 to 21.0, 1 dp |
| `band` | `StrainBand?` | from the rounded value |
| `status` | ScoreStatus | `ok`, `in_progress`, `pending`, `unavailable` |
| `reason` | Reason | `cycle_not_started`, `resting_hr_unknown`, `max_hr_unknown`, `no_heart_rate`, or null |
| `confidence` | `Confidence` | from `hr_coverage`; null when `value` is null |
| `trimp` | `num?` | 1 dp; null when `value` is null |
| `hr_coverage` | `num?` | 0.00 to 1.00, 2 dp; null when not computed |
| `covered_minutes`, `expected_minutes` | `int?` | scores.md §3.4 |
| `coverage_until` | `Time?` | end used for coverage (open cycles: `min(now, device_last_sync_at)`; closed: cycle end) |
| `avg_hr_bpm`, `peak_hr_bpm` | `int?` | |
| `resting_hr_bpm` | `int?` | |
| `resting_hr_source` | string? | `"daily_resting_heart_rate"`, `"baseline_mean"` |
| `max_hr_bpm` | `int?` | |
| `max_hr_source` | string? | `"override"`, `"age_predicted_profile"`, `"fitbit_zone_peak"`, `"observed"` |
| `zones_minutes` | `Zones?` | |

### 5.4.1 Strength duration in `day`

New key in `day` after `workouts`: `int?`, and the same value in the `days` row.

- Sum of `elapsed_minutes` of visible recorded strength workouts and strength sessions started or added in ghoops in cycle D, with `category == "strength"`, rounded half away from zero to an integer.
- When there are none: `0` if `MissingStatus(D, "exercise", "list") == "missing"` (the exercise stream was collected successfully for D and had nothing), otherwise null (not collected, permission missing or unavailable).
- Detected efforts never count (they have no category). This is a duration; it is not a measure of muscular load.

### 5.5 Sleep summary (in `day.sleep`) and `sleep` detail

Sleep summary fields:

| Field | Type | Rule |
| --- | --- | --- |
| `performance` | object | `{value: int? (0 to 100), band: Band3?, status: "ok"\|"pending"\|"unavailable", reason: "no_sleep"\|null}` |
| `performance_composite` | object, composite mode only | `{value: int? (0 to 100), band: Band3?, status, reason` (as `performance`)`, weights: {sufficiency, consistency, efficiency} (num, sum 1.00) or null, parts: {sufficiency: int, consistency: int?, efficiency: num? (1 dp)} or null}`; scores.md §4.5a. `weights` and `parts` are null when `value` is null. Absent in default mode. Added on 2026-11-22. |
| `asleep_minutes` | `int?` | main sleep; includes unstaged minutes (scores.md §4.2a); null when Google's totals don't reconcile with the window |
| `time_in_bed_minutes` | `int?` | |
| `need` | object | `{total_minutes: int, baseline_minutes: int, strain_extra_minutes: int, debt_extra_minutes: int, nap_credit_minutes: int, previous_cycle_strain: num?, debt_nights_used: int}`; always computed |
| `efficiency_pct` | `int?` | |
| `efficiency_band` | `Band3?` | null when `efficiency_pct` is null; scores.md §4.2. Added on 2026-11-16. |
| `consistency` | object | `{value: int?, band: Band3?, status: "ok"\|"unavailable", reason: "insufficient_nights"\|null, nights_used: int, bedtime_sd_minutes: num? (1 dp), wake_sd_minutes: num? (1 dp)}` |
| `stage_typical` | object | prior stage ranges, §5.5.1 |
| `stages` | object or null | null without a main sleep; else `{light, deep, rem, awake, unstaged}`, each `{minutes: int?, segments: int?, pct_of_asleep: num? (1 dp; always null for awake)}`. Unstaged fields are null when the main sleep has no stage segments (scores.md §4.2a). |
| `disturbances` | object or null | `{total: int, awake_segments: int, short_awakenings: int}` |
| `minutes_to_fall_asleep` | `int?` | |
| `bedtime`, `wake_time` | `Time?` | effective main sleep window start and end |
| `naps` | array | `[{start: Time, end: Time, asleep_minutes: int?}]` for naps ending on D |

`ghoops sleep` / `GET /v2/sleep` body (fixtures `sleep_full.json`, `sleep_no_sleep.json`) = envelope + `freshness` + `date` + every sleep-summary field above at the top level, plus:

| Field | Type | Rule |
| --- | --- | --- |
| `session` | object or null | `{start: Time, end: Time, type: "STAGES"\|"CLASSIC"\|null, main_sleep: bool, processed: bool?, stages_status: string?, minutes_awake: int?, minutes_after_wake_up: int?, minutes_in_sleep_period: int?}` |
| `respiratory_rate` | object or null | `{full_bpm: num?, deep_bpm: num?, light_bpm: num?, rem_bpm: num?}` (scores.md §4.9) |
| `hypnogram` | object or null | `{outside: [{start, end, stage}], start: Time, end: Time, segments: [{start: Time, end: Time, stage}], short_awakenings: [{start, end, stage}], unstaged: [{start: Time, end: Time}]}`; `stage` ∈ `awake`, `light`, `deep`, `rem`, `asleep`, `restless`; segments sorted, non-overlapping and clipped to the window. Unstaged spans are the uncovered time at the window's start or end (scores.md §4.2a), sorted; `[]` with none or no segments. Gaps between segments are not listed. |
| `overnight_hr` | array | `[{t: Time, bpm: int}]`, 5-minute buckets (scores.md §4.8) |
| `overnight_hrv` | array | `[{t: Time, rmssd_ms: num}]` |

With no main sleep: `session`, `respiratory_rate`, `hypnogram` are null and both series are `[]`.

`session.start` and `session.end` are the effective window. `session.type`, `processed`, `stages_status`, `minutes_awake`, `minutes_after_wake_up` and `minutes_in_sleep_period` stay Google's raw values, untouched by either the unstaged rule or a ghoops edit.

The session also carries these additive keys:

| Field | Type | Rule |
| --- | --- | --- |
| `google` | object | `{start: Time, end: Time, asleep_minutes: int?, minutes_to_fall_asleep: int?, stage_minutes: {light, deep, rem, awake: int?}, stage_segments: {light, deep, rem, awake: int?}}`, Google's night before the rule or edit |
| `edit` | object or null | `{start: Time, end: Time, updated_at: Time}` when a stored edit applies |
| `edit_range` | object or null | `{earliest_start: Time, latest_end: Time}`, available only inside the horizon with stage segments. It intersects the shift bound with neighbouring effective sleeps, naps and visible workouts, the London wake day and now. A workout inside Google's night caps `latest_end` at its start. |

`hypnogram.outside` contains the parts of Google's stage segments outside the effective window, sorted by start. It is `[]` without an edit. New fields are optional to older clients.

### 5.5.1 Typical stage ranges

Added to the sleep summary object, so it appears in `day.sleep` and at the top level of the `sleep` body (contract §5.5). Always present.

```json
"stage_typical": {
  "window_nights": 30,
  "nights_used": 27,
  "nights_needed": 7,
  "low_percentile": 25,
  "high_percentile": 75,
  "light":       { "low_minutes": 196, "high_minutes": 232, "nights_used": 27 },
  "deep":        { "low_minutes": 74,  "high_minutes": 96,  "nights_used": 27 },
  "rem":         { "low_minutes": 92,  "high_minutes": 121, "nights_used": 27 },
  "awake":       { "low_minutes": 18,  "high_minutes": 34,  "nights_used": 27 },
  "restorative": { "low_minutes": 170, "high_minutes": 214, "nights_used": 27 }
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `window_nights` | int | `StageTypicalNights` (30) |
| `nights_used` | int | number of London dates `D−30 … D−1` (D excluded) whose main sleep (scores.md §4.1) exists and has session `type == "STAGES"` |
| `nights_needed` | int | `StageTypicalMinNights` (7). Added on 2026-11-16. |
| `low_percentile` | int | `round(100 × StageTypicalLowQuantile)` (25). Added on 2026-11-16. |
| `high_percentile` | int | `round(100 × StageTypicalHighQuantile)` (75). Added on 2026-11-16. |
| `<stage>.nights_used` | int | of those nights, how many have a non-null `stages.<stage>.minutes` (restorative: both `deep` and `rem` non-null; value = their sum) |
| `<stage>.low_minutes`, `.high_minutes` | `int?` | the 25th and 75th percentiles of those values, rounded half away from zero; null when `<stage>.nights_used < StageTypicalMinNights` (7) |

Percentile (same as numpy `linear`, R type 7): sort ascending `v[0…n−1]`; `pos = q·(n−1)`; `i = floor(pos)`; `f = pos − i`; result `v[i] + f·(v[i+1] − v[i])` (when `i + 1 = n`, `v[i]`). Compute at full precision, round once.

Classic sessions and nights without a main sleep are excluded. Values are computed from the store at request time, like every score.

### 5.6 `vitals`

| Field | Type | Rule |
| --- | --- | --- |
| `metrics` | object | keys `hrv_rmssd`, `resting_hr`, `respiratory_rate`, `spo2`, `skin_temp_deviation`, each a VitalMetric |
| `outside_range` | string[] | keys with `position` `above` or `below` |
| `adverse` | string[] | keys outside in their less favourable direction (scores.md §5; skin temperature: above only) |
| `persistent` | string[] | scores.md §5.1. Added on 2026-11-18. |
| `metrics_with_range` | int | keys with `position` `above`, `below` or `within` |
| `values_needed` | int | `BaselineMinValues` (7), the baseline count a metric needs for a range. Added on 2026-11-16. |
| `monitor_state` | string | `building`, `within`, `outside` or `attention` (scores.md §5.2). Added on 2026-11-18. |
| `hrv_trend` | object | a VitalMetric plus `nights: int` (scores.md §5.3). `baseline_values` counts the baseline before the week. Display only. Added on 2026-11-22. |

VitalMetric: `{value: num?, unit, status: MetricStatus, range_low: num?, range_high: num?, baseline_values: int? (null for skin temperature), position: "above"|"below"|"within"|"no_baseline"|null}`. Units: `ms`, `bpm`, `breaths_per_minute`, `percent`, `celsius_deviation`. `resting_hr.value` is an integer; the others use the decimals in scores.md §5.

`range_low` and `range_high` are mean ± `VitalRangeSD` × `sd_eff` (scores.md §5).

### 5.7 `activity` and `vo2_max`

`activity` = `{steps: Metric (unit "steps", int), active_zone_minutes: Metric (unit "minutes", int; sum of the three zone sums), calories_kcal: Metric (unit "kcal", int; Google's total-calories estimate), distance_km: Metric (unit "km", 2 dp)}` for London date D (the cycle date). These are Google's values, not ghoops computations.

`vo2_max` = `{value: num?, unit: "ml_per_kg_min", date: Date?, cardio_fitness_level: string?, estimated: bool?, status: "available"|"missing", reason: "no_data"|null}` (scores.md §8).

### 5.8 Workouts

Workout object:

| Field | Type | Rule |
| --- | --- | --- |
| `kind` | `"recorded"`, `"detected"` or `"goop"` | scores.md §3.8, §3.9 |
| `id` | string | recorded: last segment of the exercise `name` (use with `workout export-tcx --id`); goop: `"goop-<uuid>"`; detected: `"effort-<start>"` |
| `exercise_type` | string? | effective sport after alias and edit; null for detected |
| `display_name` | string? | effective name after alias and edit; `"Detected effort"` for detected |
| `category` | string | `combat`, `strength`, `walking`, `cardio`, `other`, `detected` |
| `cycle_date` | Date | cycle that contains `start` |
| `start`, `end` | Time | effective window after edit and merge; detected: minute boundaries |
| `elapsed_minutes` | num | 1 dp |
| `paused_minutes` | int | 0 for recorded and detected entries; excluded slots for ghoops |
| `active_minutes` | `num?` | recorded: provider `activeDuration`, 1 dp, or null when the window was edited or merged; goop: effective window minus paused slots |
| `strain`, `trimp` | `num?` | 1 dp |
| `hr_coverage` | `num?` | 2 dp |
| `confidence` | Confidence | |
| `avg_hr_bpm`, `peak_hr_bpm` | `int?` | from roll-ups |
| `zones_minutes` | `Zones?` | |
| `provider` | object or null | recorded: `{avg_hr_bpm: int?, calories_kcal: num?, active_zone_minutes: int?}` from `metricsSummary`; detected: null |
| `source` | object or null | recorded: `{recording_method: string?, platform: string?, form_factor: string?}`; detected: null |
| `has_gps` | bool | `exerciseMetadata.hasGps`, default false |
| `hr_series` | array | **only** in the `workouts` body: `[{t: Time, bpm: int}]`, one point per covered minute |
| `original` | object or null | `{exercise_type, display_name, start, end}`: the band's values before alias and edit (recorded), or the uploaded values (goop). Null for detected. |
| `edit` | object or null | The stored edit for this id, without `hidden` (a visible entry is never hidden): `{exercise_type, start, end, notes, merge_with, updated_at}`. Null when none. |
| `edited` | bool | `edit` is non-null and has a non-null `exercise_type`, a non-null window or a non-empty `merge_with`. Notes alone do not count. |
| `merged` | array | `[{id, kind, exercise_type, display_name, start, end}]`, the originals of absorbed entries ordered by start. `[]` when none. |
| `notes` | string? | The edit's notes, else the ghoops activity's notes, else null. |
| `rpe` | int? | The owner's rating of the session, 0 to 10 on Foster's CR-10 scale (§7.2, Ratings), else null. Always null for detected entries. No score reads it. Added 2026-11-22. |
| `origin` | string? | `"live"` or `"added"` for goop; null otherwise. |
| `pauses` | array | `[{start, end}]`: goop pauses that intersect the effective window, clipped to it. `[]` for others. The phone needs them for preview parity. |
| `suggested` | object or null | `{exercise_type: string, display_name: string, matches: int, window_days: int}`. Non-null only for detected efforts passing scores.md §3.9a. Present wherever workouts appear, including `day.workouts` and `snapshot`. |

The `start`, `end`, `exercise_type`, `display_name`, `category`, `cycle_date`, `elapsed_minutes` and score fields are effective values after alias, edit and merge. `cycle_date` follows the effective start. `provider`, `source`, `id` and `kind` remain unchanged. Hidden and absorbed entries are absent from every body, including `day.workouts`, `snapshot`, `brief`, `days` counts and `strength_minutes`. See scores.md §3.8a.

`workouts` body (fixture `workouts_full.json`): envelope + `freshness` + `from: Date` + `to: Date` (inclusive) + `workouts: Workout[]`, every workout whose `cycle_date` is in the range, sorted by `start`.

### 5.9 Health flags

`health_flags: [{code, severity: "info"|"attention", message}]`, codes, conditions, fixed messages and order from scores.md §6.

### 5.10 `days`

Fixtures: `days_full.json` (golden), `preview/days_30.json`. Envelope + `freshness` + `from` + `to` + `days[]` (one row per date, ascending, every date in the range even when empty) + `summary`.

Row fields (all values are the same numbers `day` would return for that date; null for every non-available reason; use `day` for reasons):

`date`, `cycle_status`, `recovery` (int?), `recovery_band`, `recovery_status`, `recovery_reason`, `strain` (num?), `strain_band`, `strain_status`, `hr_coverage`, `sleep_performance` (int?), `sleep_performance_band`, `asleep_minutes`, `sleep_need_minutes` (int), `time_in_bed_minutes`, `efficiency_pct`, `hrv_rmssd_ms`, `resting_hr_bpm`, `respiratory_rate_bpm`, `spo2_pct`, `skin_temp_deviation_c`, `steps`, `active_zone_minutes`, `calories_kcal`, `workouts` (int, recorded only), `detected_efforts` (int), `vitals_adverse` (int, `len(adverse)`).

Additional row fields:

| Field | Type | Rule |
| --- | --- | --- |
| `zones_1_3_minutes` | `int?` | `z1 + z2 + z3` of that date's `strain.zones_minutes`; null when `zones_minutes` is null |
| `zones_4_5_minutes` | `int?` | `z4 + z5`; null likewise |
| `strength_minutes` | `int?` | §5.4.1 |
| `restorative_minutes` | `int?` | `stages.deep.minutes + stages.rem.minutes` of that date's sleep summary; null when `stages` is null or either is null |
| `sleep_consistency` | `int?` | that date's `sleep.consistency.value` |
| `sleep_performance_composite` | `int?` | composite mode only: that date's `sleep.performance_composite.value`. Absent in default mode. Added on 2026-11-22. |

`summary`: for each of `recovery`, `strain`, `sleep_performance`, `asleep_minutes`, `hrv_rmssd_ms`, `resting_hr_bpm`, `steps`: `{mean: num? (1 dp; steps 0 dp), min, max, available_days: int}` over non-null row values.

### 5.11 `status`

Fixtures: `status_full.json`, `status_new_user.json`.

| Field | Type | Rule |
| --- | --- | --- |
| envelope, `freshness` | | |
| `default_date` | Date | scores.md §3.1 |
| `auth` | object | `{authorized: bool, state: string, refreshable: bool, missing_scopes: string[], partial_permissions: bool}` copied from v1 `auth.Status` (no network) |
| `collector` | object | `{schedule_installed: bool (both LaunchAgent plists exist), interval_minutes: 30, last_run: {started_at, finished_at, status, pass, core_complete, requests, failed_streams: string[]} or null, last_core_success_at: Time?, streams: [{stream, last_date: Date?, status: coverage status or "never", last_success_at: Time?, error: string?}]}`; `streams` lists the 17 streams of data.md §2 in table order, using each stream's most recent coverage row |
| `device` | object | `{status: "ok"\|"scope_missing"\|"error"\|"no_tracker", name: string? (deviceVersion), battery_level: int?, battery_status: string?, last_sync_at: Time?}` for the tracker with the latest `lastSyncTime` |
| `store` | object | `{oldest_date: Date?, newest_date: Date?, heart_rate_days: int}` |
| `calibration` | object | `{status: "insufficient"\|"calibrating"\|"ready", hrv_values, resting_hr_values, values_needed: 7, values_for_full_confidence: 14}` for `default_date` |
| `user_resources` | object | `profile`, `settings`, `paired_devices`, `irn_profile`, each `{status, fetched_at}`; `irn_profile` adds `onboarded: bool?`, `enrolled: bool?` |
| `provider_timezone` | string? | `settings.timeZone` when available |
| `server` | object | `{version, revision}` of the binary |
| `edit_limits` | object | The Mac's request limits, below. |

| Field | Type | Rule |
| --- | --- | --- |
| `horizon_days` | int ≥ 1 | An edit's target needs its original `cycle_date` ≥ `default_date − (horizon_days − 1)`. A new activity needs `start ≥ now − horizon_days × 24 h`. |
| `shift_minutes` | int | An edited window lies in `[min original start − shift_minutes, max original end + shift_minutes]` over the target and every absorbed entry. For sleep, the original window is Google's window for the night. |
| `sleep_min_minutes` | int | The shortest edited sleep window, inclusive. Added 2026-11-19; absent on older Macs. |
| `merge_gap_minutes` | int | A merge candidate starts at most this long after the saved window ends, or ends at most this long before it starts. Overlap counts as 0. |
| `merge_max_ids` | int | The most ids `merge_with` may hold. |
| `notes_max_chars` | int | The most Unicode code points a note may hold after trimming. |
| `active_min_minutes`, `active_max_minutes` | int | The shortest and longest window, minus pauses, inclusive. |
| `heart_rate_span_max_minutes` | int | The longest `start`/`end` heart-rate read. |
| `rpe_scale` | string | `"cr10"`: a rating's `rpe` is a whole number from 0 to 10 on Foster's modified CR-10 scale. The range is schema. Added 2026-11-22; absent on older Macs, and then a client offers no rating. |

`horizon_days` also bounds journal dates: a journal date E needs `default_date − horizon_days ≤ E ≤ default_date` ([journal-spec.md](../goop/journal-spec.md) §3).

`edit_limits` was added on 2026-11-17. A Mac built before then omits it. A client must treat a missing `edit_limits` as unknown and must not substitute its own values. The overlap, cover and merge-graph rules of §7.2 have no number and apply always.

### 5.12 `snapshot`

The app's single request. Fixtures: `preview/snapshot_fresh.json`, `preview/snapshot_stale.json`.

Envelope + `freshness` + `default_date` + six complete nested bodies, each with its own envelope:

| Key | Equals |
| --- | --- |
| `status` | `ghoops status` |
| `day` | `ghoops day --date <default_date>` |
| `sleep` | `ghoops sleep --date <default_date>` |
| `days` | `ghoops days --from <default_date − 29> --to <default_date>` |
| `workouts` | `ghoops workouts --from <default_date − 13> --to <default_date>` |
| `journal` | `ghoops journal show` (30 days). The owner's private answers ([journal-spec.md](../goop/journal-spec.md) §6.4); added on 2026-11-22, so an older Mac omits it. |

All six use the same `now`, so their `generated_at` values are equal. Expected size: under 200 KB.

### 5.13 `brief` (for agents)

Fixtures: `brief_full.json` (default), `brief_full_values.json` (`--include-values`), `brief_full_evening.json`, `brief_full_evening_values.json`, `brief_week.json` and `brief_week_values.json`. `--part` defaults to `morning`; `evening` includes a review; `week` includes the week (added 2026-11-22). Other values return usage exit 2 / HTTP 400 `invalid_request` naming `part`. Envelope without `score_config`, then these fields in table order:

| Field | Always | Only with `--include-values` |
| --- | --- | --- |
| `disclosure` | `"status_only"` or `"values"` | |
| `part` | `"morning"`, `"evening"` or `"week"` | |
| `date` | Date | |
| `freshness` | `{collected_at, collector_stale, device_stale}` | |
| `recovery` | `{status, reason, band, calibrating}` | `value` |
| `strain` | `{status, reason, band, confidence}` | `value`, `hr_coverage` |
| `strain_target` | `{status, reason, intent, position}` | `low`, `high` |
| `sleep` | `{status, reason, band}` (performance) | `performance`, `asleep_minutes`, `need_minutes` |
| `sleep_plan` | object or null: `{status, reason, wake_source}` | `need_minutes`, `bedtime` (100% goal, or null) |
| `trend` | six ordered keys, each `{direction, days_7, days_30}` (scores.md §11b) | `mean_7`, `mean_30` per key |
| `vitals_adverse` | string[] | |
| `hrv_trend` | `{position, nights, baseline_values}` (scores.md §5.3). Added on 2026-11-22. | `value`, `range_low`, `range_high` |
| `workouts` | `[{kind, category, exercise_type, suggested_exercise_type: string?}]` | `elapsed_minutes`, `strain` per workout |
| `health_flags` | string[] (codes only) | |
| `week` | week only: `{from, to, days_counted, complete, targets: {sleep, activity, strength: {status}}, workouts: {total, detected_efforts, by_sport: [{exercise_type, count}]}}` for the week containing `date` (§5.16) | `metrics` as §5.16; each target's settings, counts and missing counts as §5.16 |
| `review` | evening only: `{workouts: int, detected_efforts: int, new_flags: string[]}` | `zones_1_3_minutes: int?`, `zones_4_5_minutes: int?` |
| `note` | `"ghealth estimates from documented formulas; not medical advice."` | |

Hidden and absorbed entries are excluded from `workouts` in both disclosure modes.

In `status_only` mode the value keys are absent, not null. No timestamps of workouts or sleep, no device names, no raw records.

`review.workouts` counts recorded and goop entries on D; `detected_efforts` counts detected entries. `new_flags` lists D’s health-flag codes absent on D−1, in health-flag table order. Zone sums come from D’s strain. Morning and week omit `review` entirely; morning and evening omit `week`. `bedtime` is a value key and is absent in status-only mode.

The six trend keys are `recovery`, `hrv_rmssd_ms`, `resting_hr_bpm`, `sleep_performance`, `asleep_minutes`, `strain`, in that order.

`hrv_trend` and `trend.hrv_rmssd_ms` differ. The first compares a 7-day ln mean with a range built before the week (scores.md §5.3). The second compares two arithmetic means (scores.md §11b).

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

### 5.14 Command outputs

| `kind` | Shape |
| --- | --- |
| `collect` | data.md §4.4 |
| `schedule` | `{schema_version, kind, source, generated_at, timezone, agents: [{label: "io.ghealth.collect"\|"io.ghealth.serve", installed: bool, loaded: bool, path: string}]}` |
| `config` | `{…envelope without score_version, values: {max_hr_override_bpm, sleep_base_need_minutes, trimp_profile, sport_aliases, strain_intent, wake_target, sleep_score_mode (only when "composite"), week_targets: {sleep_minutes, sleep_nights, activity_minutes, strength_days}}, defaults: {the first six keys and week_targets}, path: string}`. `week_targets` was added on 2026-11-22. It changes no score, so `score_config` (§5.1) does not carry it. |
| `export` | `{…envelope without score_version, exported: "tcx", id, path, bytes: int, plaintext_export: true}` |
| `pair` | §8.3 |
| `edit` | `{…envelope, id, edit: {id, exercise_type, start, end, notes, hidden, merge_with, updated_at} or null}`; PUT and restore (§7.2) |
| `edits` | envelope plus stored edits updated within `--days N`, default 30; each edit has `applies: bool`, false for an orphan whose entry is missing |
| `journal` | envelope with `score_version` and without `score_config`, then `default_date`, `from`, `to`, `behaviours: [{key, name, question}]` (the enabled set in catalogue order) `entries: [{date, answers: {key: bool}, updated_at}]` (stored dates in the range, ascending) and `impact: {from, to, behaviours: [{key, status, yes_mornings, no_mornings, yes_mean, no_mean, difference, direction}]}` (scores.md §11c; added on 2026-11-23). [journal-spec.md](../goop/journal-spec.md) §6.1 and §6.3. Fixtures `journal/journal_basic.json`, `journal/journal_empty.json`. |
| `journal_entry` | envelope, `date`, `entry: {date, answers, updated_at}` or null when no answer is left |
| `journal_behaviours` | envelope, `behaviours: [{key, name, question, enabled, default}]` for the whole catalogue |

### 5.15 `heart_rate`

The per-minute heart rate around a window, for the live preview.

**Query.** Exactly one form; anything else is `invalid_request`:
- `date=D`: the whole cycle D, `[cycle_start, cycle_end)`. For an open cycle the end is `min(now, device_last_sync_at)`, as in scores.md §3.4. A `not_started` cycle returns no minutes.
- `start=T&end=T`: RFC 3339 times, each truncated to the minute.
  - `start < end`, else `invalid_request` naming `start`.
  - A span over 18 h is `date_out_of_range`.
  - `end > now + 5 min` is `date_out_of_range`.
  - A `start` before the store's oldest date is allowed and returns fewer minutes.

For an edit, the phone asks for `[earliest start − shift_minutes, min(latest end + shift_minutes, now))` over the target, its originals and its candidates, at most `heart_rate_span_max_minutes` long (§5.11). It asks for `date=D` for Add past, and for an edit when the Mac sends no `edit_limits`.

**Response.** The envelope (with `score_config`), `freshness`, then:

| Field | Type | Rule |
| --- | --- | --- |
| `cycle_date` | Date | the cycle containing `start` (or `date`) |
| `start`, `end` | Time | the span served |
| `resting_hr_bpm`, `max_hr_bpm` | `int?` | that cycle's scores.md §3.2 and §3.3 values; null with the reason in `rates_reason` |
| `max_hr_source` | string? | as in `strain` |
| `rates_reason` | Reason | `resting_hr_unknown`, `max_hr_unknown` or null |
| `minutes` | array | `[{t: Time, avg_bpm: num (2 dp), max_bpm: int}]`, covered minutes only, ascending |

- The body is about 45 bytes per minute, so under 60 KB for a 24-hour cycle.
- `ghoops heart-rate` prints the byte-identical body (contract §1.1).
- The body has `kind: "heart_rate"`.

### 5.16 `week`

Fixtures: `week_full.json`, `week_current.json`, `week_config.json`. Added on 2026-11-22 ([week-review-spec.md](../goop/week-review-spec.md)). Envelope without `score_config` and `score_constants`, then:

| Field | Type | Rule |
| --- | --- | --- |
| `freshness` | object | §4 |
| `date` | Date | the requested date |
| `from` | Date | the Monday on or before `date` |
| `to` | Date | `min(week_end, default_date)`, the last day counted |
| `week_end` | Date | `from + 6`, a Sunday |
| `days_counted` | int | `to − from + 1`, 1 to 7 |
| `complete` | bool | `week_end < default_date`: Sunday's cycle has closed |
| `last_week` | `{from, to}` | `from − 7` and `to − 7`: the same days one week earlier |
| `usual` | `{from, to, min_days}` | `from − 28`, `from − 1` and `ComparisonMinDays` (7) |
| `metrics` | object | below |
| `workouts` | object | `{total: int, last_week_total: int, detected_efforts: int, by_sport: [{exercise_type, display_name, category, count: int}]}` |
| `targets` | object | below |

Every value comes from the `days` rows (§5.10) of the dates named, so edits, hidden workouts and the unstaged-sleep rule apply as on the day bodies. The current day counts as it is.

`metrics` keys, in order: means `recovery`, `strain`, `sleep_performance`, `asleep_minutes`, `sleep_consistency`, `hrv_rmssd_ms`, `resting_hr_bpm`; totals `zones_1_3_minutes`, `zones_4_5_minutes`, `strength_minutes`, `steps`. Each is `{value: num?, available_days: int, last_week: num?, change: num?, usual: num?}`:

- A mean is the mean of the non-null row values from `from` to `to`, 1 dp. A total is their sum, an integer. Either is null when no row has a value.
- `last_week` is the same over `last_week`. `change` is `value − last_week`, null when either is null.
- `usual` is the mean over `usual` for a mean, and that daily mean × `days_counted` (rounded) for a total. It is null with fewer than `min_days` values.

`workouts` counts visible recorded and ghoops entries with `cycle_date` in the week, by their effective sport (§5.8). `by_sport` is sorted by `count` descending, then `display_name`. Detected efforts are counted only in `detected_efforts`. `last_week_total` is the `workouts` row count over `last_week`.

`targets` (settings from `config`, §5.14):

| Key | Fields | Counts |
| --- | --- | --- |
| `sleep` | `{status, min_minutes, nights, met_nights, missing_nights}` | a night meets it when `asleep_minutes ≥ min_minutes`; missing when `asleep_minutes` is null |
| `activity` | `{status, minutes, vigorous_weight, credit_minutes: int?, missing_days}` | `credit_minutes` = Σ `zones_1_3_minutes` + `vigorous_weight` × Σ `zones_4_5_minutes` over days with zones, null when none has; missing when zones are null. `vigorous_weight` is 2 (`WeekVigorousWeight`). |
| `strength` | `{status, days, met_days, missing_days}` | a day meets it when `strength_minutes > 0`; missing when null |

`status`, in this order: `met` when the count reaches the setting; `open` when not met and `complete` is false; `not_met` when not met and the missing nights or days could not have changed it (`sleep`, `strength`: count + missing < setting; `activity`: none missing); otherwise `no_data`.

## 6. Errors

One object, on stderr for the CLI, as the HTTP body for the API (fixtures in `fixtures/v2/errors/`):

```json
{ "schema_version": 2, "kind": "error", "source": "google_health_v4", "generated_at": "…", "timezone": "Europe/London",
  "error": { "code": "invalid_request", "message": "date must be a valid YYYY-MM-DD", "http_status": 400 } }
```

| `code` | HTTP | CLI exit | When |
| --- | --- | --- | --- |
| `invalid_request` | 400 | 2 | bad flag, query parameter or date |
| `date_out_of_range` | 400 | 2 | future date, range over 90 days, `from > to` |
| `unauthorized` | 401 | n/a | missing, malformed or wrong bearer token |
| `not_found` | 404 | 2 | unknown path or command |
| `method_not_allowed` | 405 | n/a | unsupported method/path combination |
| `conflict` | 409 | 2 | activity ID already exists with a different POST body, a merge-graph conflict, or an edit PUT whose `if_updated_at` no longer matches (§7.2) |
| `payload_too_large` | 413 | 2 | activity POST or edit PUT exceeds 64 KiB; message `Request body exceeds 64 KiB.` |
| `rate_limited` | 429 | n/a | more than 10 failed authentications from all clients within 60 s; lasts until the window clears; response has `Retry-After: 60` |
| `store_unavailable` | 503 | 1 | the store cannot be opened (Keychain locked, key missing, corrupt file) |
| `collect_in_progress` | n/a | 1 | `collect` while another holds `collect.lock` |
| `permission_missing` | n/a | 1 | TCX export without the location scope |
| `collect_failed` | n/a | 1 | `collect` run status `failed` (the `collect` body is still printed to stdout) |
| `internal` | 500 | 1 | unexpected error; message is generic |

`message` is a fixed English sentence per code plus, for `invalid_request`, which parameter was wrong. It never contains provider response bodies, tokens, health values or file contents. A missing store file is **not** an error: read commands return bodies whose metrics are `not_synced` and whose freshness says `"last_collect_status": "never"`.

Edit validation returns `invalid_request` with `Invalid edit field: <field>.`, for `id`, `body`, `exercise_type`, `start`, `end`, `active_duration`, `duration`, `notes`, `hidden`, `merge_with` or `if_updated_at`. Merge conflicts say `This activity is merged into another.` when the target is absorbed, or `A merged activity is already part of another.` when a candidate is absorbed elsewhere or absorbs others. An edit PUT whose `if_updated_at` no longer matches says `This activity changed on your Mac.` Sleep edit precondition conflicts say `This night changed on your Mac.` Sleep validation uses `body`, `start`, `end`, `duration` and `if_updated_at`. Unknown targets, targets outside the edit horizon, and missing edits on DELETE are `not_found`. Heart-rate query failures are `invalid_request`; spans over 18 hours or ends over `now + 5 min` are `date_out_of_range`. Journal PUT validation returns `invalid_request` with `Invalid journal field: <field>.` for `body`, `answers` or `if_updated_at`; a stale `if_updated_at` is 409 `conflict` with `This day's journal changed on your Mac.`; a malformed date or one outside journal-spec §3 is `not_found`.

## 7. HTTP API

### 7.1 Transport

| Item | Value |
| --- | --- |
| Listener | `ghoops serve` on `127.0.0.1:8787` (IPv4 loopback only; refuse any other address) |
| Public URL | `https://<mac>.<tailnet>.ts.net:8787`, provided by `tailscale serve --bg --https=8787 http://127.0.0.1:8787` (tailnet only, never Funnel). Ports 443 and 8443 are already used by other services on this Mac. |
| TLS | terminated by Tailscale with its tailnet certificate |
| Methods | GET on reads; POST `/v2/activities`; DELETE `/v2/activities/<id>`; PUT and DELETE `/v2/edits/<id>` and `/v2/sleep-edits/<date>`; PUT `/v2/journal/<date>` |
| Request limits | header 8 KiB; body only on activity POST, edit PUT and journal PUT, `application/json`, at most 64 KiB; `ReadHeaderTimeout` 5 s; `WriteTimeout` 30 s; `IdleTimeout` 60 s |
| Response headers | `Content-Type: application/json; charset=utf-8`, `Cache-Control: no-store`, `X-Ghealth-Schema: 2` |
| Compression | gzip when the request's `Accept-Encoding` lists `gzip` with a non-zero q value and the body is at least 1,024 bytes. Such responses carry `Content-Encoding: gzip` and `Vary: Accept-Encoding`. Otherwise the body is identity. Applies to every route and to error bodies. |
| Logging | one line per request to stderr: time, method, path without query, status, duration ms. Never the query string, headers or body. |

A 405 sets `Allow` to `GET` on reads, `POST` on `/v2/activities`, `DELETE` on `/v2/activities/<id>`, `PUT, DELETE` on `/v2/edits/<id>` and `/v2/sleep-edits/<date>`, or `PUT` on `/v2/journal/<date>`. Mutation routes accept no query string. A DELETE body is `invalid_request`. `/v2/edits` and `/v2/edits/`, `/v2/sleep-edits` and `/v2/sleep-edits/` are `not_found`, and so is `/v2/journal/`.

### 7.2 Endpoints

| Path | Query | Body |
| --- | --- | --- |
| `/v2/status` | none | `status` |
| `/v2/day` | `date` (optional) | `day` |
| `/v2/sleep` | `date` (optional) | `sleep` |
| `/v2/days` | `days` or `from`+`to` (optional, CLI defaults) | `days` |
| `/v2/workouts` | `days` or `from`+`to` | `workouts` |
| `/v2/snapshot` | none | `snapshot` |
| `/v2/brief` | `date`, `include_values` (`true`/`false`, default false), `part` (`morning`/`evening`/`week`, default `morning`; invalid values name `part`) | `brief` |
| `/v2/heart-rate` | exactly `date=D` or `start=T&end=T` (§5.15) | `heart_rate` |
| `/v2/journal` | `days` (optional, 1 to 90, default 30; over 90 is `date_out_of_range`) | `journal` (§5.14) |
| `/v2/week` | `date` (optional) | `week` |

Activity routes accept no query parameters. POST `/v2/activities` accepts `{id, exercise_type, display_name, start, end, pauses?, live?, origin?, notes?}`. The ID is a lowercase UUID; sport is one of activity-spec.md §2.1; name is 1–40 characters. Start precedes end, active duration is 60 seconds through 12 hours, start is within the last 30 days, and end is at most 5 minutes ahead. Pauses have ends, lie inside the interval, and are ordered without overlap. Optional `live` holds the phone estimate only and never feeds scores. `origin` is `"live"` by default or `"added"`; `added` requires `live` to be absent, otherwise field `live` is invalid. Optional `notes` is 1–500 characters after trimming. Existing records without origin read as `live`. Past windows without live samples are valid, and pauses may be absent or `[]`. Invalid fields return `invalid_request` naming the field.

Idempotency compares the whole body, including origin and notes. `origin` is always present and `notes` nullable in stored records and responses. A new ID returns 201; the same ID and body returns 200; a changed body returns 409 `conflict`. Success is the envelope with `kind: "activity"` and `activity: {id, exercise_type, display_name, start, end, pauses, origin, notes, created_at}`. DELETE `/v2/activities/<id>` returns 200 with `kind: "activity_deleted"` and `id`, or 404 `not_found`. Both require the usual bearer authentication. Logs never include bodies.

**Edits.** `PUT /v2/edits/<id>` replaces one override; `DELETE /v2/edits/<id>` restores the original by removing it. They use the same encrypted activities file and `activities.lock`. The stored shape is `{id, exercise_type: string?, start: Time?, end: Time?, notes: string?, hidden: bool, merge_with: string[], updated_at: Time}`. All-null fields with `hidden: false` and `merge_with: []` remove the override. Orphans remain stored and ignored. Edits older than 400 days are dropped on the next write. Permanent `DELETE /v2/activities/<uuid>` also removes `goop-<uuid>`'s edit and removes that id from every `merge_with`. Restoring an absorber makes its absorbed entries visible again. Google Health is never changed.

**Request**, with the six edit keys required and optional `if_updated_at`; unknown keys are ignored:

```json
{ "exercise_type": "BOXING", "start": "2026-03-10T17:56:00Z", "end": "2026-03-10T19:12:00Z",
  "notes": "Sparring, 6 rounds of 3 minutes.", "hidden": false, "merge_with": [] }
```

| Key | Type | Meaning |
| --- | --- | --- |
| `if_updated_at` | Time, null, or absent | Absent: no check, for the CLI and older phones. Null: the phone expects no stored edit. A time: the phone expects the stored edit's `updated_at`. |

**Order of checks**, under `activities.lock`:
1. Validate and normalise the body as today.
2. If the normalised edit equals the stored one, ignoring `updated_at`, answer 200 with the stored edit. A replay after a lost answer never trips the check.
3. Otherwise, if `if_updated_at` is present and does not match, answer 409 `conflict` with `This activity changed on your Mac.` Both must be null, or times equal after truncating to the second in UTC. The phone encodes whole seconds.
4. Otherwise store as today.

`if_updated_at` is request metadata and is never stored. DELETE edits and POST activities take no precondition. The CLI sends no precondition.

**Validation.** Any failure is `invalid_request` with the message `Invalid edit field: <field>.`:

| Field | Fails when |
| --- | --- |
| `id` | the path id is empty, has a `/`, or starts with `effort-` (detected efforts are named through POST) |
| `body` | the body is not a JSON object |
| `exercise_type` | not null and not in activity-spec §2.1 |
| `start` / `end` | only one is null; not RFC 3339; `start ≥ end`; `end > now + 5 min`; outside the edit-spec.md §5.7 shift bound |
| `active_duration` | the effective window minus pauses is under 60 s or over 12 h |
| `notes` | not null and, after trimming, empty or over 500 characters |
| `hidden` | missing or not a bool |
| `merge_with` | not an array of strings; over 4; contains the target; fails an edit-spec.md §5.6 merge check |
| `if_updated_at` | present, non-null and not RFC 3339 |

**Lookup.** The target is found among the entries built by scores.md §3.8a steps 1–2 (no edits applied) whose original `cycle_date` is in the edit horizon:
- `goop-<uuid>` must exist in the activities store;
- any other id must be a recorded entry.

If not found: 404 `not_found`.

**Conflicts.** 409 `conflict`:
- the target is absorbed by another edit: message `This activity is merged into another.`;
- an id in `merge_with` is absorbed elsewhere or absorbs others: message `A merged activity is already part of another.`;
- `if_updated_at` no longer matches: message `This activity changed on your Mac.`

**Response 200.** The envelope plus:
- `kind: "edit"`;
- `id`;
- `edit`: the stored object (as described above), or null when normalisation removed it.

**Idempotency.** PUT replaces the edit. The same body again gives 200 with the same `edit` and an unchanged `updated_at`. There is no 201 and no body conflict.

The phone refreshes the snapshot after any 200. The response does not carry recomputed scores.

**DELETE `/v2/edits/<id>`.**

- 200: `kind: "edit"`, `id`, `edit: null`.
- 404 `not_found` when no edit is stored for that id.

This is permanent for the edit only. The band's record is untouched.

The target's original cycle date must be within the 30 days ending on the default date. Both edited times must lie within the original windows of the target and absorbed entries plus 180 minutes on either side, and overlap at least one original window. Merge candidates are adjacent visible recorded or goop entries in the same cycle with a gap at most 15 minutes, computed from the saved effective window. The new window must cover every absorbed window. Detected neighbours are merged by extending the window without storing their unstable ids. At most four ids can be absorbed. See scores.md §3.8a and [edit-spec.md §5.6](../goop/edit-spec.md#56-merge).

These numbers are reported in `status.edit_limits` (§5.11).

ghoops workouts have `id: "goop-<uuid>"`, `source: "goop"`, null provider, and sport/name from the activity. Their scoring window excludes paused slots. Their effective windows hide recorded entries overlapping at least 50% of the shorter window; hidden goop entries keep suppressing those replacements, and absorber pairs are exempt. Visible and hidden windows suppress detected efforts under scores.md §3.9. Day Strain is unchanged.

CLI equivalents are `ghoops activity list [--days N]`, `activity add --type T --start RFC3339 --end RFC3339 [--name S] [--origin added] [--notes S]` and `activity delete --id ID`. They emit schema-2 JSON, use the same validation, and add generates a UUID.

Unknown query parameters are `invalid_request`. A trailing slash is `not_found`.

**Ratings.** `PUT /v2/ratings/<id>` stores how hard a session felt; `DELETE` removes it. Bearer authentication, no query string. PUT requires `application/json`, at most 64 KiB, with `rpe`, a whole number from 0 to 10 (`7.0` counts); unknown keys are ignored. The id follows the edit rules (field `id`: empty, `/`, or an `effort-` id) and the edit lookup above, so a target outside the edit horizon is 404 `not_found`. Validation failures are 400 `invalid_request`, `Invalid edit field: <field>.` with field `body` or `rpe`. A PUT with the stored value returns it unchanged and writes nothing. There is no precondition: the last write wins. Success is 200, envelope, `kind: "rating"`, `id`, `rating: {id, rpe, updated_at}`. DELETE returns `rating: null`, or 404 when none is stored, with no lookup or horizon; a DELETE body is `invalid_request`. A 405 sets `Allow: PUT, DELETE`; `/v2/ratings` and `/v2/ratings/` are `not_found`. A rating feeds no score, so the response carries none. See [effort-rating-spec.md](../goop/effort-rating-spec.md) §4.

**Edits to sleep.** `PUT /v2/sleep-edits/<date>` stores a local sleep window; `DELETE` restores Google's window. Both require bearer authentication and accept no query string. PUT requires `application/json`, at most 64 KiB, with required `start`, `end` and optional `if_updated_at`; unknown keys are ignored. Preconditions and replay ordering match activity edits above, with conflict message `This night changed on your Mac.` No Google route is called.

Lookup returns 404 `not_found` for a malformed date, a date outside the horizon ending on `default_date`, no main sleep, or no stage segments. Validation returns 400 `invalid_request`, `Invalid edit field: <field>.`:

| Field | Fails when |
| --- | --- |
| `body` | not a JSON object |
| `start` / `end` | missing, null, not RFC 3339, not a whole minute, or start at or after end |
| `end` | later than now + 5 min or its London date differs from the path date |
| `start` / `end` | outside Google's start minus `shift_minutes` through Google's end plus `shift_minutes` |
| `start` | the new window does not overlap Google's window |
| `duration` | shorter than `sleep_min_minutes` |
| `start` / `end` | overlaps another effective main sleep, a nap, or a visible recorded or ghoops workout; `start` for an earlier neighbour, `end` for a later one |
| `if_updated_at` | present, non-null and not RFC 3339 |

A successful PUT returns 200, envelope, `kind: "sleep_edit"`, `date`, and `sleep_edit: {date, start, end, updated_at}`. A window equal to Google's current window removes the edit and returns `sleep_edit: null`. DELETE returns the same null response, or 404 if nothing was stored; it has no horizon check. Orphans remain stored and ignored. Every write uses `activities.lock` and retention in data.md. The response carries no recomputed scores.

`ghoops sleep edit --date D [--start T] [--end T]` uses the same validation and keeps the effective value of each omitted endpoint. `sleep restore --date D` is DELETE. `sleep edits [--days N]` lists stored edits updated within N days, default 30, with `kind: "sleep_edits"`, `sleep_edits: [{date, start, end, updated_at, applies}]`. `sleep [--date D] [--json]` keeps reading; only the first argument can select a subcommand.

**Journal.** `PUT /v2/journal/<date>` replaces the answers stored for one journal date ([journal-spec.md](../goop/journal-spec.md) §6.2). Bearer authentication, `application/json`, at most 64 KiB, no query string. The body is `{answers: {key: bool}, if_updated_at?}`; unknown top-level keys are ignored, and `{"answers": {}}` removes the entry. Order under `journal.lock`: validate; answers equal to the stored ones return 200 with the stored entry; otherwise a present `if_updated_at` that does not match (null expects no entry, a time must equal `updated_at` to the second) is 409; otherwise store with `updated_at = now`. The response is the envelope with `kind: "journal_entry"`, `date` and `entry` (or null). There is no DELETE. The phone refreshes the snapshot after a 200.

### 7.3 Authentication

- Every endpoint requires `Authorization: Bearer <token>`.
- Compare the SHA-256 of the presented token with the SHA-256 of the stored token using `crypto/subtle.ConstantTimeCompare`.
- The server reads the token from Keychain at start and caches it. On a mismatch, it re-reads Keychain at most once per 5 s before answering 401, so `ghoops pair --rotate` takes effect without restarting.
- No token stored: every request gets 401 and the server logs `no pairing token; run ghoops pair` once at start.

### 7.4 Reading the store

The server opens the store read-only per request when the file's modification time or size changed since the last load, otherwise uses the decrypted copy in memory. It never takes `collect.lock` (saves are atomic renames). Responses are computed with `now` = request time. Concurrent requests are allowed.

## 8. Pairing

### 8.1 Token

- 32 bytes from `crypto/rand`, encoded base64url without padding, prefixed `ghv2_` (48 characters).
- Mac: Keychain item `<secure.Service(stateDir)>.serve-token`, created through the existing `secure.Vault` (trusted only to the installed binary, no approval UI).
- iPhone: Keychain (app.md §6).
- One active token. `ghoops pair` reuses the existing token; `--rotate` replaces it; `pair revoke` deletes it.

### 8.2 Pairing link

```
ghealth://pair?v=1&url=<percent-encoded https base URL>&token=<token>&name=<percent-encoded Mac name>
```

- `url` default: `https://` + `Self.DNSName` from `tailscale status --json` with the trailing dot removed + `:8787`. `--url` overrides it (must start with `https://`).
- `name` = `Self.HostName` from the same output.
- `tailscale` binary: `tailscale` on `PATH`, else `/Applications/Tailscale.app/Contents/MacOS/Tailscale`. Pass no secrets in its arguments.

### 8.3 `ghoops pair` output

Text mode (default): prints a QR code of the link in the terminal (Unicode half-block characters, quiet zone of 2 modules, error correction M), the link itself, and one line: `Scan with the iPhone camera, or AirDrop/paste this link into the app.` If `tailscale serve status --json` shows no HTTPS handler on port 8787 that proxies to `http://127.0.0.1:8787`, it prints the exact command from §7.1 and exits 1 after printing the QR. `--png PATH` also writes a PNG (new `0600` file, refuses overwrite).

QR generation: CoreImage `CIQRCodeGenerator` through cgo (the binary already uses cgo for Keychain), no third-party Go modules.

`--json` mode: `{schema_version: 2, kind: "pair", source, generated_at, timezone, paired: true, url, name, link, token_created_at: Time, tailscale_serve_configured: bool, png_path: string?}`. The link contains the token: it is a secret. `pair revoke --json` prints `{…, paired: false}`.

### 8.4 Pairing flow

1. Owner runs `ghoops pair` on the Mac.
2. iPhone camera reads the QR and offers to open ghoops; or the owner pastes the link in Settings → Pair.
3. The app parses `url`, `token`, `name`, calls `GET <url>/v2/status` with the token, and on 200 stores url and name in the App Group defaults and the token in Keychain. On 401 it shows "This phone is no longer paired with your Mac. Run ghoops pair on your Mac, then scan its code." On a network error it shows "Can't reach your Mac over Tailscale. Is Tailscale on?".

## 9. v1 compatibility and agents

### 9.1 v1 stays unchanged

- `sync`, `today`, `summary`, `trends`, `data export`, `doctor`, `auth *`, `probe` keep their flags, output and `schema_version: 1`.
- `records.enc` is not read or written by any v2 command; `records-v2.enc` is not read by any v1 command.
- `scripts/morning_summary.py` is not modified and still requires `schema_version: 1`.
- v2 commands use new names only, so no v1 command line changes meaning.

### 9.2 Assistants

An assistant that runs `ghealth sync --days 7` then `summary --days 2 | morning_summary.py --include-values` keeps working. With v2 installed, it can instead run `~/.local/bin/ghealth brief --json` (status only) or `brief --json --include-values`, which needs no network (the LaunchAgent keeps the store fresh) and takes well under a second. Values mode includes recovery, strain and sleep performance.

An assistant may also use `brief --part evening` for an evening review (parity1-spec.md §12). Assistant setups live outside this repo.

Agent rules (put these in any skill that reads v2):

1. Check `schema_version == 2` and that `synthetic_fixture` is absent.
2. If `freshness.collector_stale` is true, say the data is stale and give `collected_at`; do not present scores as today's.
3. Report `status`/`reason` when a value is null. Never substitute another day's value.
4. Never call the numbers diagnoses; repeat `note` when giving advice.
5. Never read `journal`, `journal_entry` or `snapshot.journal`, or pass them to a model. They hold the owner's private answers, and the owner has not agreed to share them ([journal-spec.md](../goop/journal-spec.md) §6.4).

### 9.3 Assistant workspaces

Assistants that run shell commands in their own workspace use the same commands (`ghealth brief --json`, `ghealth day --json`, `ghealth days --json --days 14`). Bodies are private health data: keep them inside the agent workspace, never in shared directories, and send only `brief` output to cloud models unless the owner has agreed to more.

## 10. Consumer rules (app and agents)

| Situation | Show |
| --- | --- |
| `value` present, `status` `ok` | the value in its band colour |
| `status` `calibrating` | value plus "Calibrating" |
| `status` `in_progress` | strain value plus "so far" |
| `status` `pending` | "Waiting for …" text by `reason` (app.md §7) |
| `status` `unavailable` | dash plus the reason text |
| `confidence` `low` | value with a "low data" badge |
| `freshness.collector_stale` | banner: "Mac last collected <relative time>" |
| `freshness.device_stale` | banner: "Band last synced <relative time>" |
| `device_stale` null | "Band sync time unavailable" (scope missing) |
| any MetricStatus other than `available` | dash; tap shows the status in words |

## 11. Fixtures

Index, golden/preview split and the inputs that reproduce the goldens: [`fixtures/v2/README.md`](../../fixtures/v2/README.md).
