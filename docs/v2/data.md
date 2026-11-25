# ghoops v2: data collection

Status: design spec for implementers. Score formulas are in [scores.md](scores.md), and the JSON and HTTP contract is in [contract.md](contract.md).

v2 adds a second collector, `ghoops collect`, that writes a second encrypted store, `records-v2.enc`. The v1 collector (`ghoops sync`), the v1 store (`records.enc`) and every v1 command stay byte-for-byte unchanged. Assistants that read v1 output keep working (see [contract.md §9](contract.md#9-v1-compatibility-and-agents)).

All public API facts below come from the v4 discovery document, revision `20261110` (`https://health.googleapis.com/$discovery/rest?version=v4`), the [data-type table](https://developers.google.com/health/data-types) and the [filter guide](https://developers.google.com/health/filters), as read on 2026-11-12.

## 1. Conventions

| Term | Meaning |
| --- | --- |
| London day `D` | The civil date in `Europe/London` (embedded tzdata, as v1). A London day runs from local 00:00 to the next local 00:00, so it lasts 23 or 25 hours on DST change days. |
| `[from, until)` | Every range is closed-open. CLI `--to` is inclusive and becomes `until = to + 1 day`. |
| UTC bounds of a London day | `local_midnight(D).UTC()` to `local_midnight(D+1).UTC()`. |
| Provider civil date | The `date` object (`{year, month, day}`) on daily types. Google computes it in the account's timezone. v2 treats it as the London day and checks the account timezone through `settings.timeZone` (§6). |
| Stream | One (data type, route) pair, named `<data-type>/<route>`, for example `heart-rate/rollUp`. Coverage is tracked per stream and per London day. |
| Core streams | `sleep/reconcile`, `daily-heart-rate-variability/list`, `daily-resting-heart-rate/list`, `heart-rate/rollUp`. A run is `core_complete` only when all four succeed for every requested day. |
| Scope suffix | Appended to `https://www.googleapis.com/auth/googlehealth.` |

Every health request stays read-only: GET for list, reconcile and user resources; POST only for the read-only `:rollUp` and `:dailyRollUp` routes (as v1's `probe` already does). No create, patch, batchDelete, subscription or settings mutation route is ever called.

## 2. What v2 collects

Base URL `https://health.googleapis.com`. In the tables, `.../<type>/dataPoints` abbreviates `/v4/users/me/dataTypes/<type>/dataPoints`. All paths use the user alias `me`.

List and reconcile requests build their query exactly like v1 `health.Client.Fetch`: `filter=<field> >= "<lower>" AND <field> < "<upper>"` (URL-encoded) plus `pageSize`, following `nextPageToken` with the v1 repeated-token and changed-record guards. For time fields (`…_time`) the bounds are the UTC instants of the London range, formatted RFC 3339 with `Z`. For `.date` fields and `civil_start_time` they are `YYYY-MM-DD`. After decoding, each record gets its London-day key (last column) and records outside the requested London dates are dropped, as v1 does.

### 2.1 Data-point streams

| # | Stream | Route | Filter field (list/reconcile) | Page size | Scope | Fields v2 relies on | London-day key |
| - | --- | --- | --- | --- | --- | --- | --- |
| 1 | `sleep/reconcile` | `GET /v4/users/me/dataTypes/sleep/dataPoints:reconcile` | `sleep.interval.end_time` (RFC 3339 UTC) | 25 | `sleep.readonly` | `dataPointName`; `sleep.interval.startTime`, `.endTime`; `sleep.type`; `sleep.stages[]` (`type`, `startTime`, `endTime`); `sleep.shortAwakenings[]` (same fields); `sleep.summary.minutesAsleep`, `.minutesAwake`, `.minutesInSleepPeriod`, `.minutesToFallAsleep`, `.minutesAfterWakeUp`, `.stagesSummary[]` (`type`, `minutes`, `count`); `sleep.metadata.mainSleep`, `.nap`, `.processed`, `.stagesStatus` | London date of `interval.endTime` (date of waking, as v1) |
| 2 | `daily-heart-rate-variability/list` | `GET .../daily-heart-rate-variability/dataPoints` | `daily_heart_rate_variability.date` (`YYYY-MM-DD`) | 1440 | `health_metrics_and_measurements.readonly` | `date`; `averageHeartRateVariabilityMilliseconds` (score input); `deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds`, `nonRemHeartRateBeatsPerMinute`, `entropy` (display only); `dataSource` | provider civil date |
| 3 | `daily-resting-heart-rate/list` | `GET .../daily-resting-heart-rate/dataPoints` | `daily_resting_heart_rate.date` | 1440 | `health_metrics_and_measurements.readonly` | `date`; `beatsPerMinute` (int64 string); `dailyRestingHeartRateMetadata.calculationMethod` | provider civil date |
| 4 | `daily-respiratory-rate/list` | `GET .../daily-respiratory-rate/dataPoints` | `daily_respiratory_rate.date` | 1440 | `health_metrics_and_measurements.readonly` | `date`; `breathsPerMinute` | provider civil date |
| 5 | `daily-oxygen-saturation/list` | `GET .../daily-oxygen-saturation/dataPoints` | `daily_oxygen_saturation.date` | 1440 | `health_metrics_and_measurements.readonly` | `date`; `averagePercentage`; `lowerBoundPercentage`; `upperBoundPercentage`; `standardDeviationPercentage` (optional; absent on early days) | provider civil date |
| 6 | `daily-sleep-temperature-derivations/list` | `GET .../daily-sleep-temperature-derivations/dataPoints` | `daily_sleep_temperature_derivations.date` | 1440 | `health_metrics_and_measurements.readonly` | `date`; `nightlyTemperatureCelsius`; `baselineTemperatureCelsius` (optional); `relativeNightlyStddev30dCelsius` (optional) | provider civil date |
| 7 | `daily-heart-rate-zones/list` | `GET .../daily-heart-rate-zones/dataPoints` | `daily_heart_rate_zones.date` | 1440 | `health_metrics_and_measurements.readonly` | `date`; `heartRateZones[]` (`heartRateZoneType`, `minBeatsPerMinute`, `maxBeatsPerMinute`) | provider civil date |
| 8 | `daily-vo2-max/list` | `GET .../daily-vo2-max/dataPoints` | `daily_vo2_max.date` | 1440 | `activity_and_fitness.readonly` | `date`; `vo2Max`; `estimated`; `cardioFitnessLevel` | provider civil date |
| 9 | `respiratory-rate-sleep-summary/list` | `GET .../respiratory-rate-sleep-summary/dataPoints` | `respiratory_rate_sleep_summary.sample_time.physical_time` (RFC 3339 UTC) | 1440 | `health_metrics_and_measurements.readonly` | `sampleTime.physicalTime`; `fullSleepStats.breathsPerMinute` (required); `deepSleepStats.breathsPerMinute`, `lightSleepStats.breathsPerMinute`, `remSleepStats.breathsPerMinute` (optional; `0` means not measured) | London date of `sampleTime.physicalTime`; matched to a sleep session by time ([scores.md §4.9](scores.md#49-respiratory-rate-by-stage)) |
| 10 | `heart-rate-variability/list` | `GET .../heart-rate-variability/dataPoints` | `heart_rate_variability.sample_time.physical_time` | 1440 | `health_metrics_and_measurements.readonly` | `sampleTime.physicalTime`; `rootMeanSquareOfSuccessiveDifferencesMilliseconds` (display only: overnight HRV chart) | London date of `sampleTime.physicalTime` |
| 11 | `exercise/list` | `GET .../exercise/dataPoints` | `exercise.interval.civil_start_time` (`YYYY-MM-DD`), widened by one day on both sides as v1 | 25 | `activity_and_fitness.readonly` | `name` (ID for TCX export); `exercise.exerciseType`; `.displayName`; `.interval.startTime`, `.endTime`; `.activeDuration`; `.metricsSummary.caloriesKcal`, `.averageHeartRateBeatsPerMinute`, `.activeZoneMinutes`; `.exerciseMetadata.hasGps`; `dataSource.recordingMethod`, `.platform`, `.device.formFactor` | London date of `interval.startTime` (v1 rule) |
| 12 | `irregular-rhythm-notification/list` | `GET .../irregular-rhythm-notification/dataPoints` | `irregular_rhythm_notification.interval.start_time` (RFC 3339 UTC); see note | 25 | `irn.readonly` | `interval.startTime`, `.endTime` only. `alertWindows[].heartBeats` is never stored. | London date of `interval.startTime` |

Note on row 12: the filter guide names session filters for exercise, sleep and ECG only. `interval.start_time` follows the ECG pattern and is what `ghoops probe` already sends. Plan step G1 confirms it once the IRN scope is granted. If Google rejects it with HTTP 400, use `irregular_rhythm_notification.interval.civil_start_time` with `YYYY-MM-DD` bounds widened by one day, as for exercise.

### 2.2 Roll-up streams

| # | Stream | Route | Request body | Max range per request | Scope | Response fields used | London-day key |
| - | --- | --- | --- | --- | --- | --- | --- |
| 13 | `heart-rate/rollUp` | `POST /v4/users/me/dataTypes/heart-rate/dataPoints:rollUp` | `{"range":{"startTime":"<D 00:00 London as UTC RFC 3339>","endTime":"<D+1 00:00 London as UTC>"},"windowSize":"60s","pageSize":1500}` | one London day per request (Google allows 14 days) | `health_metrics_and_measurements.readonly` | `rollupDataPoints[].startTime`, `.endTime`, `.heartRate.beatsPerMinuteMin`, `.beatsPerMinuteAvg`, `.beatsPerMinuteMax` | the London day requested |
| 14 | `steps/dailyRollUp` | `POST .../steps/dataPoints:dailyRollUp` | `{"range":{"start":{"date":{"year":Y,"month":M,"day":D}},"end":{"date":{...}}},"windowSizeDays":1,"pageSize":90}` | 90 days | `activity_and_fitness.readonly` | `rollupDataPoints[].civilStartTime.date`; `.steps.countSum` | `civilStartTime.date` |
| 15 | `active-zone-minutes/dailyRollUp` | `POST .../active-zone-minutes/dataPoints:dailyRollUp` | as row 14 | 90 days | `activity_and_fitness.readonly` | `.activeZoneMinutes.sumInFatBurnHeartZone`, `.sumInCardioHeartZone`, `.sumInPeakHeartZone` | `civilStartTime.date` |
| 16 | `total-calories/dailyRollUp` | `POST .../total-calories/dataPoints:dailyRollUp` | as row 14 with `"pageSize":14` | 14 days | `activity_and_fitness.readonly` | `.totalCalories.kcalSum` | `civilStartTime.date` |
| 17 | `distance/dailyRollUp` | `POST .../distance/dataPoints:dailyRollUp` | as row 14 | 90 days | `activity_and_fitness.readonly` | `.distance.millimetersSum` (int64 string) | `civilStartTime.date` |

Roll-up rules:

- Google computes roll-ups from reconciled data and excludes wearable intervals when the device was not worn (`RollupDataPoint` description). That is the behaviour v2 wants: a minute without a heart-rate value is a minute without coverage.
- A 60 s window counts as covered only when `heartRate.beatsPerMinuteAvg` is present and is a finite number in `[1, 300]`. Windows that are absent, have no `heartRate` object, or carry an out-of-range average are uncovered. Never insert zeros.
- Sort windows by `startTime`. Reject a page whose windows are not 60 s long, overlap, or fall outside the requested range, with error code `invalid_rollup_window`.
- A London day has 1440 windows, or 1380 / 1500 on DST change days. `pageSize` 1500 fits every day in one page. Still follow `nextPageToken` if present, with the v1 repeated-token guard.
- Daily roll-ups: the `range.end` date is exclusive. A returned window with no value object (for example no `steps` key) means no data for that day, not zero. A present `countSum` of `"0"` is an observed zero.
- `dailyRollUp` on `daily-heart-rate-variability` and `daily-resting-heart-rate` returned HTTP 400 for this account even though the discovery document advertises personal-range roll-ups. v2 does not call them and computes its own baselines.

### 2.3 User resources

| # | Stream | Route | Scope | Fields used | Stored | Output |
| - | --- | --- | --- | --- | --- | --- |
| 18 | `user/profile` | `GET /v4/users/me/profile` | `profile.readonly` | `age` (int32) | whole body, encrypted | `age` feeds the age-predicted maximum heart rate. Never printed. |
| 19 | `user/settings` | `GET /v4/users/me/settings` | `settings.readonly` | `timeZone`, `utcOffset`, `distanceUnit`, `temperatureUnit` | whole body | `timeZone` drives the `provider_timezone_mismatch` flag. Units are not used: v2 always outputs metric units. |
| 20 | `user/paired-devices` | `GET /v4/users/me/pairedDevices?pageSize=10` | `settings.readonly` | `pairedDevices[].name`, `.deviceType`, `.deviceVersion`, `.batteryLevel`, `.batteryStatus`, `.lastSyncTime`, `.features` | body without `macAddress` (drop it before storing) | device battery and "Fitbit last synced" freshness |
| 21 | `user/irn-profile` | `GET /v4/users/me/irnProfile` | `irn.readonly` | `onboardingStatus`, `enrollmentStatus`, `updateTime` | whole body | Health monitor shows enrolment state only |

### 2.4 On-demand route: TCX export

| Route | Scopes (both required) | Trigger | Output |
| --- | --- | --- | --- |
| `GET /v4/users/me/dataTypes/exercise/dataPoints/{id}:exportExerciseTcx?alt=media` (add `&partialData=true` only when the user passes `--partial`) | `activity_and_fitness.readonly` and `location.readonly` | `ghoops workout export-tcx --id <id> --output PATH [--partial]` only. Never during `collect`, never over HTTP. | Raw TCX bytes written to a new `0600` file; refuses to overwrite, like `data export`. `{id}` is the last path segment of the exercise `name`. |

TCX contains GPS tracks, so it stays a deliberate, local, file-only action. Response limit: the existing 32 MiB `netx.MaxBody`. HTTP 403 maps to `permission_missing` with the message "TCX export needs the location.readonly scope; run ghoops auth login".

### 2.5 Not collected in v2, and why

| Data type | Probe result | Reason |
| --- | --- | --- |
| `heart-rate` raw list and reconcile (1 s samples) | many pages | Replaced by 60 s roll-ups (§4). v1 `sync` still collects them for v1 reports. |
| `oxygen-saturation` (per minute) | records | `daily-oxygen-saturation` already gives the nightly mean and bounds that the vitals panel needs. |
| `active-energy-burned`, `active-minutes`, `activity-level`, `sedentary-period`, `time-in-heart-rate-zone`, `calories-in-heart-rate-zone`, `floors` | records | No v2 score or screen uses them. Heart-rate zones are computed from roll-ups with ghoops's own zone edges. |
| `swim-lengths-data` | 466 records | Likely artefacts on a band worn while boxing; would mislead. |
| `weight`, `body-fat` | 1 record each | Too sparse to show; can be added later as a separate stream. |
| `altitude`, `blood-glucose`, `core-body-temperature`, `vo2-max`, `run-vo2-max`, `height` | empty | Nothing to show. `daily-vo2-max` (row 8) is collected because the app shows VO2 max when present. |
| `skin-temperature-sensors` | HTTP 400 (v4beta) | Unsupported for this device; `daily-sleep-temperature-derivations` covers skin temperature. |
| `electrocardiogram`, nutrition, hydration, reproductive and mindfulness types | not granted | Out of scope; scopes not requested. |

## 3. The v2 store

Path: `<state dir>/records-v2.enc` (default state dir `~/.local/share/ghealth`, `0700`). Same AES-256-GCM envelope as v1 with three changes:

| Item | v1 | v2 |
| --- | --- | --- |
| File | `records.enc` | `records-v2.enc` |
| Header and AAD prefix | `ghealth-cache-v1\n` | `ghealth-cache-v2\n` |
| Key | Keychain item `<secure.Service(dir)>.cache-key` | the same item; the different header in the AAD keeps the two files cryptographically separate |
| Size limit | 256 MiB | 256 MiB (expected size at 400 days is about 25 MiB) |
| Lock | `sync.lock` | `collect.lock` (v1 `sync` and v2 `collect` can run at the same time; both take `auth.lock` for token refresh as today) |

Plaintext JSON inside the envelope (field names are exact):

```json
{
  "schema_version": 2,
  "source": "google_health_v4",
  "account": "<health user id from identity>",
  "timezone": "Europe/London",
  "records": [ { "data_type": "sleep", "stream": "reconciled", "date": "2026-03-10", "data_point": { } } ],
  "hr_minutes": [ { "date": "2026-03-10", "windows": [[1773100800, 62, 66.4, 70]] } ],
  "daily_rollups": [ { "data_type": "steps", "date": "2026-03-10", "value": { } } ],
  "user": {
    "profile":        { "status": "ok", "fetched_at": "2026-03-10T14:15:40Z", "error": null, "body": { } },
    "settings":       { "status": "permission_missing", "fetched_at": null, "error": "permission_denied", "body": null },
    "paired_devices": { },
    "irn_profile":    { }
  },
  "coverage": [ { "data_type": "heart-rate", "stream": "rollUp", "date": "2026-03-10", "status": "ok", "attempt_at": "...", "last_success_at": "...", "record_count": 862, "error": "" } ],
  "runs": [ { "started_at": "...", "finished_at": "...", "pass": "hot", "status": "ok", "core_complete": true, "requests": 21, "failed_streams": [] } ]
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `records[]` | v1 `health.Record` (`data_type`, `stream`, `date`, `data_point`, optional `synthetic_fixture`) | Holds rows 1 to 12. `stream` is `"reconciled"` for `sleep` and `"raw"` for the rest. `data_point` is the provider JSON unchanged except that IRN `alertWindows` are removed. Replacement per (data_type, stream, date) follows v1 `cache.Sync` exactly (replace successful dates, keep failed dates, `record_timestamp_changed` handling). |
| `hr_minutes[]` | one object per London day | `windows` is an array of `[start_unix_seconds (int), min (number), avg (number), max (number)]` sorted by start, covered windows only. A successful fetch replaces the whole day. A failed fetch keeps the previous day. |
| `daily_rollups[]` | one object per (data_type, date) | `value` is the provider `DailyRollupDataPoint` unchanged. A successful chunk replaces every date in the chunk; a date with no returned window, or a window without the value object, is removed (no data). A failed chunk keeps its previous rows. |
| `user.*` | resource snapshot | `status` is `ok`, `permission_missing` (HTTP 403), `unavailable` (other failure; keep the previous `body` and `fetched_at`) or `never`. `paired_devices.body` has `macAddress` removed. |
| `coverage[]` | v1 `cache.Coverage` | One row per (stream, London date). Here `stream` holds the **route** (`list`, `reconcile`, `rollUp`, `dailyRollUp`), so `data_type + "/" + stream` is the stream name of §2 (unlike `records[].stream`, which keeps v1's `raw`/`reconciled`). `record_count` = records, covered minute windows, or 0/1 roll-up days for that date. New status value `permission_missing` for HTTP 403. User resources are not in `coverage`. |
| `runs[]` | collect history | Keep the most recent 50. `status` is `ok`, `partial` or `failed` (§4.4). |

Retention: on every successful save, drop `records`, `hr_minutes`, `daily_rollups` and `coverage` older than 400 London days before today. 400 days covers the 365-day observed-maximum-HR window in [scores.md §3.3](scores.md#33-maximum-heart-rate).

Validation: reuse v1 `health.Decode` rules for sleep, HRV, RHR and exercise. As in v1, one invalid record fails its whole job with the error code, and the job's dates keep their previous data with coverage `unavailable`. New types fail closed with error code `invalid_data_point` when a required field is missing or out of the documented range: SpO2 percentages outside `[0,100]`, respiratory rate outside `[4,60]`, skin temperature outside `[20,45]` °C, VO2 max outside `[0,100]`, zone bounds outside `[30,250]`, roll-up heart rate outside `[1,300]`.

#### 3.1 Provider quirks (verified on the real account, 2026-11-12)

Found by `ghoops probe --v2 --diagnose-fields --days 60` (counts only; evidence in `acceptance.md`, G3 resolution). These rules override the validation paragraph above where they differ.

| Stream | Observed | Rule |
| --- | --- | --- |
| `daily-oxygen-saturation` | `standardDeviationPercentage` absent on 7 of 25 days. Google marks it Optional. | Required: `date`, `averagePercentage`, `lowerBoundPercentage`, `upperBoundPercentage`, each in `[0,100]`. `standardDeviationPercentage` is optional: absent → null; present → must be in `[0,100]`. No score uses it. |
| `daily-sleep-temperature-derivations` | `baselineTemperatureCelsius` and `relativeNightlyStddev30dCelsius` were the JSON string `"NaN"` on 2 of 27 days (proto3 JSON encoding of NaN; the baseline is not established yet). `nightlyTemperatureCelsius` was a number in `[20,45]` on all 27. | Any optional numeric field whose JSON value is the string `"NaN"`, `"Infinity"` or `"-Infinity"` is stored and treated as null (absent), never as a number and never as an error. `nightlyTemperatureCelsius` stays required in `[20,45]`; a non-finite required field is still `invalid_data_point`. With a null baseline or SD, scores.md §2.3 adds `skin_temperature` to `optional_missing` and §5 reports `position: "no_baseline"`. |
| `respiratory-rate-sleep-summary` | All 63 records carry the same `name`, the collection path ending in `/dataPoints/` with no point ID. 5 per-stage `breathsPerMinute` values were `0` (deep 1, light 1, REM 3); full-sleep values were all in `[4,60]`. | (a) A `name` that ends with `/dataPoints/` (no point ID) is not an identity: treat the record as unnamed. The "identified data point changed during pagination" guard applies only to names with a point ID; unnamed records are deduplicated by canonical content hash as v1 already does. This rule applies to every data type. (b) `fullSleepStats.breathsPerMinute` is required in `[4,60]`. A per-stage `breathsPerMinute` of exactly `0` means not measured: store it, and output that stage as null in scores.md §4.9. Other per-stage values must be in `[4,60]`; anything else is `invalid_data_point`. |

Tests for G3 must cover each row with a synthetic record: SpO2 without SD accepted; temperature with `"NaN"` baseline and SD accepted and read as null; a `"NaN"` nightly temperature rejected; respiratory summaries sharing a `/dataPoints/` name across two pages with different content accepted (no pagination error); a REM `0` accepted and output null; a REM `2.0` rejected.

## 4. Sync design (chosen)

**Decision: 60 s heart-rate roll-ups for every minute of every day, no raw 1 s heart-rate samples in v2, every other stream fetched per incremental window, with up to four requests in flight.**

### 4.1 Why

v1 spends almost all of its time paging 1 s heart-rate samples: tens of thousands per day per stream, 1440 per page, for both the raw and the reconciled stream. A 7-day sync makes several hundred heart-rate requests and ran past 240 s. With roll-ups, one request returns a whole London day (≤1500 windows), so 7 days take 7 heart-rate requests.

| Option | Requests per 3-day window | Strain accuracy | Workout chart | Chosen |
| --- | --- | --- | --- | --- |
| A. Raw 1 s samples all day (v1) | ~180 | exact | 1 s | no: too slow, storage heavy |
| B. 60 s roll-ups all day + raw 1 s only inside workouts and sleep | 3 + ~2 per workout/sleep (several pages each) | exact inside workouts | 1 s | no: adds a second heart-rate path and pagination for little gain |
| C. 60 s roll-ups all day | 3 | TRIMP computed on minute means; within-minute variation is lost (see below) | 1 min | **yes** |

Trade-offs of option C, accepted:

- TRIMP weights grow exponentially with heart rate, so a minute mean slightly underestimates the TRIMP of a minute whose heart rate swings. For boxing rounds (3 min on, 1 min off) the change inside one minute is small; the error is a few percent of TRIMP. Strain is a log of TRIMP, so this moves day strain by about 0.1 to 0.2.
- Peak heart rate stays exact because each window carries `beatsPerMinuteMax`.
- Workout and sleep heart-rate charts are 1-minute and 5-minute resolution, which is enough on a phone.
- If 1 s detail is wanted later, option B can be added as a new stream without changing the store shape of the rest.

### 4.2 Windows per run

`ghoops collect` with no range flags runs the **incremental** plan. `today` is the current London date at run start.

| Pass | When | London dates | Streams |
| --- | --- | --- | --- |
| Hot | every run | `today-2` to `today` (3 days) | rows 1 to 13 and 14 to 17. Exercise uses the v1 widened civil filter. |
| Settle | the first run whose start time is at or after 12:00 London on a given day, if no run with `pass: "settle"` and `core_complete: true` has started on that London day | `today-9` to `today` (10 days: the 3 hot days plus 7 older ones, in one run) | rows 1 to 13 and 14 to 17. Catches late syncs and Google reprocessing. The run is recorded with `pass: "settle"`. |
| User | every run | n/a | row 20 (`pairedDevices`, for battery and last sync) |
| User daily | when the last `ok` fetch is older than 24 h, or the resource has never been fetched | n/a | rows 18, 19, 21 |

`ghoops collect --days N` (1 to 90) or `--from YYYY-MM-DD --to YYYY-MM-DD` runs the **explicit** plan instead: the given London dates for rows 1 to 17, plus all user resources. Use `ghoops collect --days 60` once after install to build baselines; it should finish in about two minutes (60 heart-rate requests plus about 30 others).

Every `runs[]` entry has `pass`: `"hot"`, `"settle"` or `"explicit"`.

### 4.3 Request plan and concurrency

1. Acquire `collect.lock` (non-blocking; if held, exit 1 with error code `collect_in_progress`).
2. Read the stored session's account and check it against the encrypted store. The collection gets or refreshes tokens only for this account. An account or timezone mismatch with the store stops the run.
3. Build the job list. One job per (stream, request range):
   - `heart-rate/rollUp`: one job per London date.
   - list and reconcile streams: one job covering the whole window, paginated inside the job.
   - `dailyRollUp` streams: one job per chunk of at most 90 days (14 for `total-calories`).
   - user resources: one job each.
4. Run jobs on a worker pool of **4**. Each job uses the existing `Client.do` retry rules (429 and 5xx with `Retry-After` within the 60 s budget, 401 refresh once). Do not add parallelism inside a job.
5. The whole command keeps the v1 ten-minute context. A cancelled run saves nothing.
6. Merge the job results in memory and check the session's account again before saving. If it changed, collection exits with `account changed during collection; cache unchanged`. A completed write prunes by retention, appends a `runs[]` entry and saves once, atomically.

`ghoops auth login` checks the owners of both encrypted stores. It accepts the account that owns the profile. If the two stores have different owners, login refuses the profile. Login and logout wait for collection to finish. Logout keeps both encrypted stores available for offline reads.

Expected incremental run: 3 heart-rate + 9 list/reconcile + 4 roll-up + 1 to 4 user requests, about 20 requests, typically under 15 s.

### 4.4 Run status and exit codes

| Run `status` | Condition | Exit code |
| --- | --- | --- |
| `ok` | every job succeeded, or failed only with `permission_missing` on a non-core stream | 0 |
| `partial` | at least one core job succeeded for every requested date and at least one other job failed | 1 |
| `failed` | authentication failed, or any core stream failed for any requested date | 1 |

`core_complete` is true when all four core streams succeeded for every requested date. `freshness.collected_at` in the contract is `finished_at` of the latest run with `core_complete: true`.

Output: `ghoops collect --json` prints one object to stdout (full examples: `fixtures/v2/commands/collect_ok.json`, `collect_partial.json`):

```json
{"schema_version":2,"kind":"collect","source":"google_health_v4","generated_at":"2026-03-10T14:16:02Z","timezone":"Europe/London","status":"ok","pass":"hot","from":"2026-03-08","until_exclusive":"2026-03-11","requests":21,"duration_ms":14210,"core_complete":true,"streams":[{"stream":"heart-rate/rollUp","dates":3,"status":"ok","records":2581,"error":null}]}
```

| Field | Type | Rule |
| --- | --- | --- |
| envelope | | `schema_version`, `kind: "collect"`, `source`, `generated_at` (run finish time), `timezone` (contract §5.1, no `score_version`) |
| `status` | `"ok"`, `"partial"`, `"failed"` | §4.4 table |
| `pass` | `"hot"`, `"settle"`, `"explicit"` | §4.2 |
| `from`, `until_exclusive` | Date | London dates covered by the run's data-point and roll-up jobs |
| `requests` | int | HTTP requests sent, including retries and pages |
| `duration_ms` | int | wall time of the run |
| `core_complete` | bool | §4.4 |
| `streams[]` | array | one entry per stream of §2.1 and §2.2 in table order: `{stream, dates: int (London dates attempted), status, records: int (sum of coverage record_count), error: string? (first error code)}` |

`streams[].status` is the worst status over its dates (`ok` < `permission_missing` < `unavailable` < `unsupported`). Counts only; never values. A recorded run prints its object to stdout. If the account changes during collection, the command sends the error object to stderr. Without `--quiet`, one progress line per finished job also goes to stderr, for example `heart-rate/rollUp 2026-03-10 ok 1312 windows`; `--quiet` suppresses those lines.

### 4.5 Schedule (LaunchAgents)

`ghoops schedule install` writes two user LaunchAgents and loads them with `launchctl bootstrap gui/<uid> <plist>`. `ghoops schedule uninstall` boots them out and deletes the files. `ghoops schedule status --json` reports whether each is loaded. Program paths are always the installed binary `~/.local/bin/ghealth` (absolute path written into the plist).

| Label | File | ProgramArguments | Timing | Logs |
| --- | --- | --- | --- | --- |
| `io.ghealth.collect` | `~/Library/LaunchAgents/io.ghealth.collect.plist` | `[<home>/.local/bin/ghealth, collect, --json, --quiet]` | `StartInterval` 1800, `RunAtLoad` true | `StandardOutPath` and `StandardErrorPath` = `<home>/.local/share/ghealth/logs/collect.log` |
| `io.ghealth.serve` | `~/Library/LaunchAgents/io.ghealth.serve.plist` | `[<home>/.local/bin/ghealth, serve]` | `RunAtLoad` true, `KeepAlive` true, `ThrottleInterval` 30 | `<home>/.local/share/ghealth/logs/serve.log` |

Rules:

- Create `logs/` with `0700` and log files with `0600`. `--quiet` suppresses the stderr progress lines, so the log gets one JSON line per run (counts, statuses). Neither command ever logs health values, tokens or request URLs with query strings.
- At the start of each `collect` run, any of `collect.log` and `serve.log` larger than 1 MiB is truncated to zero length (`os.Truncate`; launchd opens them in append mode, so writers continue safely).
- Keychain access needs the user's login session. After a reboot without login, `collect` fails with the existing Keychain error. That run is recorded as `failed` only if the store can be opened; otherwise nothing is written and `status` shows the old `collected_at`, so the app shows staleness.
- A daily v1 `sync` run by an assistant and the 30-minute v2 `collect` can overlap; they use different locks and stores.

## 5. Mapping to London days and cycles

| Data | London-day rule | Notes |
| --- | --- | --- |
| Sleep session | date of `interval.endTime` | A night that ends 07:10 on 10 March belongs to 10 March. Naps belong to the date they end. |
| Daily types (rows 2 to 8) | provider `date` | Fitbit dates nightly HRV, respiratory rate, SpO2 and skin temperature with the wake-up date. Plan step G1 verifies this against sleep end dates (count of matching dates only). |
| Daily resting HR | provider `date` | Computed by Google from the whole day; it can appear later than the nightly metrics. |
| Heart-rate roll-up windows | the London day requested; each window keeps its UTC `startTime` | Strain uses windows by timestamp, not by date, because a physiological cycle crosses midnight ([scores.md §3.1](scores.md#31-the-cycle)). |
| Exercise | London date of `interval.startTime` for storage; for display, a workout belongs to the cycle that contains its start time | |
| Daily roll-ups | `civilStartTime.date` | |
| HRV samples, respiratory-rate summaries, IRN | London date of their timestamp | |

## 6. Timezone check

When `user/settings` is `ok` and `body.timeZone` is not `"Europe/London"`, every v2 response carries the health flag `provider_timezone_mismatch` (contract §5.9) and `ghoops status` reports `provider_timezone` with the value. Nothing is shifted: provider dates stay provider dates, as in v1. When settings are not available, the check is skipped and `status` reports `provider_timezone: null`.

## 7. Missing scopes (until the owner logs in again)

`profile`, `settings`, `pairedDevices`, `irnProfile` and the IRN list returned HTTP 403 before the owner's re-login. The re-login was completed on 2026-11-12 and all four now return 200, but the behaviour below still applies if a scope is later withdrawn or missing:

| Missing | Effect |
| --- | --- |
| `profile.readonly` | No age. Maximum HR falls back to the Fitbit zone peak, then to null ([scores.md §3.3](scores.md#33-maximum-heart-rate)). |
| `settings.readonly` | No battery, no device last-sync time: `freshness.device_*` fields are null with `device_sync_source: "scope_missing"`. Timezone check skipped. |
| `irn.readonly` | Health monitor shows "Irregular rhythm notifications: not available (permission not granted)". |
| `location.readonly` | `workout export-tcx` fails with `permission_missing`. Nothing else changes. |

These streams record `permission_missing`, never `unavailable`, so a run stays `ok` (§4.4). `ghoops status` lists them in `auth.missing_scopes` (already computed by `auth.Status`). The login must not be automated; the owner runs it.

## ghoops activities

`<state dir>/activities-v2.enc` uses the same AES-256-GCM envelope and Keychain key as `records-v2.enc`, with `{version: 1, activities: [...], edits: [...], sleep_edits: [...], ratings: [...]}`. Activity writes use atomic rename under their own advisory lock, `activities.lock`. The collector never touches it. Missing file means no activities. The server reloads on modification time or size changes. Retention is 400 days. Optional phone estimates are stored but never used as score inputs. See [activity-spec.md §8](../goop/activity-spec.md#8-mac-side-contract-additions-schema-2-additive) for validation and routes.

`<state dir>/journal-v2.enc` holds the owner's journal answers with the same envelope and Keychain key: `{version: 1, behaviours: [key] or null, entries: [{date, answers: {key: bool}, updated_at}]}`. `behaviours` null means the defaults. Writes use atomic rename under `journal.lock`; the collector and the activity routes never touch it. Every write drops entries dated more than 400 days before the London date of now. A missing file means the defaults and no answers. No behaviour key or answer is ever written in plaintext. See [journal-spec.md](../goop/journal-spec.md) §5.

Activity and journal writes allow up to 16 MiB of encrypted data per file. Readers accept files up to 64 MiB, including files made by earlier builds. `ghoops activities compact` can shrink the activity file under `activities.lock` by removing phone estimates from activities that ended more than 30 days ago. Compaction keeps the activities, edits and ratings. If the result still exceeds 16 MiB, the command leaves the file byte for byte as it was.

New saves authenticate the file's role as well as its profile. Earlier activity files still open if they contain `activities`. Earlier journal files must contain both `entries` and `behaviours`. The next save adds the role using the existing key.

Edits are overrides keyed by recorded workout id or `goop-<uuid>`, in the same file and under `activities.lock`. The collector never touches either array. `version` stays 1, and older readers ignore `edits`. Each edit stores `{id, exercise_type: string?, start: Time?, end: Time?, notes: string?, hidden: bool, merge_with: string[], updated_at: Time}`. Start and end are both null or both present. Notes are trimmed, 1–500 characters; null means none. `merge_with` has at most four recorded or goop ids. Identical PUTs keep `updated_at` unchanged.

An all-null edit with `hidden: false` and `merge_with: []` is removed. Restore deletes the override and unmerges its absorbed entries. Orphans are retained and ignored. Edits older than 400 days are dropped on the next write. Permanent activity deletion removes that activity's `goop-<uuid>` edit and removes its id from every `merge_with`, atomically under the same lock.

Activity POST accepts optional `origin` and `notes`. Origin defaults to `live`, including existing records without it. `added` requires `live` to be absent. Stored records and response objects always contain origin and nullable notes. Notes are trimmed, 1–500 characters. The lower start bound is now `now − 30 days`; end remains at most five minutes ahead. Past windows without live samples and with missing or empty pauses are valid. Idempotency compares the whole body, including the new fields. See [edit-spec.md §5–§6](../goop/edit-spec.md#5-data-model).

Sleep edits are one override per London wake date, stored as `{date, start, end, updated_at}` in `sleep_edits`, under the same lock and atomic rename. Both endpoints are whole-minute RFC 3339 times. The array is empty when absent in an older file; `version` stays 1. A PUT equal to the stored window keeps its timestamp and writes nothing. A PUT equal to Google's current window removes the override. A precondition is checked after this replay comparison, before any write.

An edit applies only when that date has a main sleep whose Google interval overlaps the edited window. Otherwise it is an orphan, retained and listed with `applies: false`; it applies again if the night returns. Neither selection of the main sleep nor Google's raw record changes. Sleep edits older than 400 days after `updated_at` are dropped on the next write, including an activity write. The collector never touches `sleep_edits`. See [sleep-edit-spec.md §4.7–§4.9](../goop/sleep-edit-spec.md#47-data-model).

Ratings are one per workout id, stored as `{id, rpe, updated_at}` in `ratings`, sorted by id, under the same lock and atomic rename. `rpe` is a whole number from 0 to 10. A PUT with the stored value writes nothing. A rating applies while its id is a visible workout; a hidden, absorbed or missing entry keeps its rating stored and ignored, and it shows again when the entry returns. Merging moves no rating. Permanent activity deletion removes `goop-<uuid>`'s rating in the same write. Ratings older than 400 days after `updated_at` are dropped on the next write. The array is empty when absent in an older file; `version` stays 1. A binary from before ratings rewrites the file without them, so the Mac is never rolled back once ratings exist. No score reads a rating. See [effort-rating-spec.md §4](../goop/effort-rating-spec.md#4-the-mac).
