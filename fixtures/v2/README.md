# fixtures/v2

Synthetic data only. No value here comes from a real account. Stores, responses and score vectors carry `"synthetic_fixture": true`. These synthetic files leave the flag out:

- `activities/*.json`: activity POST bodies, valid and invalid.
- `edits/book_*.json`, `edits/requests/*.json`: edit books and request bodies.
- `sleep_edit/book_*.json`, `sleep_edit/requests/*.json`: sleep-edit books and request cases.
- `live/*.json`: live heart-rate sessions for the Debug app.
- `scores/trend.json`: pure trend cases.

The synthetic person: London, 30 years old (profile `age`), one fitness band, sleeps about 23:15 to 07:10, boxes. The reference day is **2026-03-10** (GMT, no DST), and "now" is **2026-03-10T14:30:00Z** unless a row says otherwise. The band last synced at 14:08Z and the last collect run finished at 14:16:02Z.

Specs: [data](../../docs/v2/data.md), [scores](../../docs/v2/scores.md), [contract](../../docs/v2/contract.md), [app](../../docs/v2/app.md).

## Input stores (`inputs/`)

Plaintext versions of the decrypted v2 store (data.md §3), plus a top-level `"synthetic_fixture": true`. The Go test helper loads them directly; production code never reads plaintext stores.

| File | Contents |
| --- | --- |
| `store_full.json` | 43 days (2026-01-27 to 2026-03-10) of daily HRV, resting HR, respiratory rate, SpO2, skin temperature, heart-rate zones and main sleeps. Nights ending 2026-03-05 and 2026-02-26 are missing (band not worn: no sleep, HRV, respiratory rate, SpO2 or temperature; resting HR present). Night ending 2026-03-10 has a full stage timeline, 6 short awakenings, a respiratory-rate sleep summary and 5-minute HRV samples. A 28-minute nap on 2026-03-09 15:10–15:40Z. Minute heart-rate roll-ups for 2026-03-09 00:00Z to 2026-03-10 14:08Z with a charging gap 2026-03-09 09:30–11:00Z. Exercises: a 35-minute walk 2026-03-09 17:30Z and a kickboxing hour 2026-03-10 12:00Z. An unrecorded hard effort 2026-03-09 19:40–20:25Z (becomes a detected effort). Daily roll-ups for 2026-03-09 and 2026-03-10. All user resources `ok`. |
| `store_sleep_unstaged.json` | `store_full` with only the main night ending 2026-03-10 extended to 07:41. Its 22 stages still end 06:29, asleep stays 415, awake becomes 94, period 509 and stages status null. Rebuild with `python3 -I scripts/sleep_fixture_store.py`. |
| `store_no_sleep.json` | `store_full` without the night ending 2026-03-10: no main sleep, daily HRV, respiratory rate, SpO2, temperature, sleep summary or HRV samples for that date, and no heart rate from 2026-03-09 23:00Z to 2026-03-10 08:15Z. Resting HR still present. |
| `store_calibrating.json` | Only 2026-03-01 to 2026-03-10 (night ending 2026-03-05 missing), so recovery has 8 HRV and 9 resting-HR baseline values. |
| `store_new_user.json` | Only 2026-03-07 to 2026-03-10 (3 baseline values). Profile, settings, paired devices and IRN are `permission_missing` (scopes not yet granted), so maximum HR comes from the Fitbit zone peak and device freshness is unknown. |
| `store_one_name.json` | 13 recorded workouts on 2026-03-10: all 12 ghoops sports with differing watch names, including `WALKING` named `Walk`, plus unlisted `SKIING` named `Downhill Ski`. One resting heart-rate minute; all four user resources `never`. |

## Golden responses

The Go builder must reproduce these from the input store with the stated command and `now`. Injected values for the test: `server.version` `"0.2.0"`, `server.revision` `"synthetic"`, `collector.schedule_installed` `true`, default `score_config`, and `auth` as stated. Compare decoded JSON: same keys, same array order, strings and integers exact, decimals within one unit of the last decimal place.

| Fixture | Input | Command | Notes |
| --- | --- | --- | --- |
| `day_full.json` | `store_full` | `day --date 2026-03-10` | recovery 73 (high), strain 12.8 in progress, sleep performance 94 |
| `day_strain_sparse.json` | `store_full` with only the March 10 noon heart-rate minute | `day --date 2026-03-10`, now `2026-03-11T14:30:00Z` | Closed cycle, 1 of 1,478 minutes covered, Strain 0.2, no target position (`low_coverage`). Used by the `strain_sparse` Simulator fixture. |
| `day_no_sleep.json` | `store_no_sleep` | `day --date 2026-03-10` | recovery null `pending` `no_sleep`; cycle starts at the typical-wake fallback; strain coverage 0.84 |
| `day_calibrating.json` | `store_calibrating` | `day --date 2026-03-10` | recovery 76, `calibrating`, confidence `medium` |
| `day_new_user.json` | `store_new_user` | `day --date 2026-03-10` | recovery null `insufficient_baseline`; `max_hr_source` `fitbit_zone_peak`; device fields null |
| `sleep_full.json` | `store_full` | `sleep --date 2026-03-10` | hypnogram, respiratory rate by stage, overnight series |
| `sleep_unstaged.json` | `store_sleep_unstaged` | `sleep --date 2026-03-10` | asleep 487, in bed 509, efficiency 96, performance 100, unstaged 72 minutes in one span 06:29–07:41 |
| `day_unstaged.json` | `store_sleep_unstaged` | `day --date 2026-03-10` | same sleep summary, Recovery sleep component 100, cycle starts 07:41 |
| `days_unstaged.json` | `store_sleep_unstaged` | `days --from 2026-03-04 --to 2026-03-10` | previous cycle Strain 11.2; final row carries the new sleep values |
| `sleep_no_sleep.json` | `store_no_sleep` | `sleep --date 2026-03-10` | nulls and empty arrays |
| `workouts_full.json` | `store_full` | `workouts --from 2026-03-09 --to 2026-03-10` | walk, detected effort, kickboxing, with `hr_series` |
| `names/workouts.json` | `store_one_name` | `workouts --from 2026-03-10 --to 2026-03-10` | Listed types use the ghoops name, including `Walking`; the unlisted type keeps its watch name. |
| `names/workouts_edited.json` | `store_one_name` | Same query, with each workout's end extended one minute | Time-only saved edits retain the same names. Shared with the GHealthCore overlay test. |
| `days_full.json` | `store_full` | `days --from 2026-03-04 --to 2026-03-10` | strain null `no_heart_rate` before 2026-03-08 because the store has no older heart rate |
| `status_full.json` | `store_full` | `status` | `auth`: authorized, refreshable, no missing scopes |
| `status_new_user.json` | `store_new_user` | `status` | `auth.missing_scopes`: profile, settings, irn, location; `partial_permissions` true |
| `brief_full.json` | `store_full` | `brief --date 2026-03-10` | status only |
| `brief_full_values.json` | `store_full` | `brief --date 2026-03-10 --include-values` | |
| `week_full.json` | `store_full` | `week --date 2026-03-08` | Mon 2 to Sun 8 Mar, complete. The missing night of 5 Mar leaves sleep at 4 of 5 with 1 missing: `no_data`. Zones exist only on 8 Mar: activity `no_data` with 6 days missing. No strength: `not_met`. |
| `week_current.json` | `store_full` | `week` | Mon 9 to Tue 10 Mar, `complete: false`. Activity `met` at 173 zone minutes; sleep and strength `open`. Kickboxing, Walking and one detected effort. |
| `brief_week.json` | `store_full` | `brief --date 2026-03-08 --part week` | status only: the week's dates, target statuses and workout counts; no `metrics` and no target counts |
| `brief_week_values.json` | `store_full` | `brief --date 2026-03-08 --part week --include-values` | adds `metrics` and each target's settings and counts |
| `week_config.json` | `store_full` | `week --date 2026-03-08` with `week_sleep_nights` 4 | Sleep flips from `no_data` to `met`. With 6 it is `not_met` (4 + 1 missing < 6), which the HTTP test checks. |
| `scores/recovery.json`, `scores/strain.json`, `scores/sleep.json` | none | pure functions | scores.md §9 |

## Preview fixtures (`preview/`)

Made from a richer 31-day synthetic store that is not committed. Use them for SwiftUI previews, simulator screenshots and decode tests. The Go builder only checks that its own types decode them.

| Fixture | Notes |
| --- | --- |
| `preview/snapshot_fresh.json` | 30 days of trends, 14 days of workouts, everything fresh |
| `preview/snapshot_stale.json` | same store, `now` 2026-03-10T21:00:00Z: `collector_stale` and `device_stale` both true, flags `collector_stale` and `device_sync_stale` |
| `preview/days_30.json` | `days --from 2026-02-09 --to 2026-03-10` |
| `preview/week_this.json` | `week` for Mon 9 to Tue 10 Mar, written by `scripts/goop_preview_fixtures.py` from `snapshot_fresh.json`'s rows and workouts: every target `open` (1 of 5 nights, 145 zone minutes, 0 of 2 strength days) |
| `preview/week_last.json` | `week --date 2026-03-02`, same source: sleep `no_data` (4 of 5, 1 missing), activity `met` (222), strength `not_met`. The numbers in `docs/goop/mockups/week-review.html` are these files' numbers. |

Run `python3 -I scripts/goop_preview_fixtures.py` to add or refresh ghoops display fields in the three preview files. It preserves existing keys and values and is idempotent. It supplies `day.comparison`, `day.strength_minutes`, both sleep `stage_typical` objects, and the five day-row fields `zones_1_3_minutes`, `zones_4_5_minutes`, `strength_minutes`, `restorative_minutes` and `sleep_consistency`, using the synthetic rules in [ghoops spec §13.7](../../docs/goop/spec.md#137-fixtures).

Preview workout names use the ghoops sport list too. The fresh and stale snapshots carry `Walking` for each recorded `WALKING` workout.

## Command outputs and errors

`commands/` (`collect_ok`, `collect_partial`, `pair`, `schedule_status`, `config_show`, `export_tcx`) and `errors/` (one file per HTTP error code in contract §6). Shape references for decoders; the pairing token in `commands/pair.json` is a fake 48-character value.

## ghoops activities

`activities/valid.json` and `activities/invalid-*.json` cover POST validation. The HTTP suite writes and reopens the encrypted store in an isolated temporary directory and checks for plaintext. `snapshot_fresh` includes a ghoops Boxing workout in place of its overlapping detected effort. All workouts include `paused_minutes`.


## Activity editing

**`inputs/store_edit.json`** is a synthetic plaintext store. It is generated by `scripts/edit_fixture_store.py [--now T]`, committed with the reference now `2026-03-12T20:30:00Z` (Thursday, GMT).
- **Person:**
  - age 31, so the age-predicted maximum is 186;
  - resting HR 54 on 2026-03-07 to 2026-03-12;
  - the 42 days of daily baselines copied from `store_full` shifted forward 2 days.
- **Minute heart rate** from 2026-03-07 00:00Z to 2026-03-12 20:08Z (last band sync 20:08Z). It has a resting daily pattern plus these shapes, ported from `edit.html`'s `hrA`, `hrB`, `hrE` and `noise`:

  | Day | Content |
  | --- | --- |
  | Sat 2026-03-07 | band `BOXING` 18:30–19:30, id `7300000000000000100` (gives `Last: Sat`) |
  | Tue 2026-03-10 | `hrA` 17:30–19:50. Band `KICKBOXING` 18:05–19:02 (id `…0101`) and band `KICKBOXING` 19:16–19:38 (id `…0102`). The warm-up from 17:56 and the gap are not recorded. |
  | Wed 2026-03-11 | `hrB`: an unrecorded steady session that detection finds as exactly 18:04–19:04 |
  | Thu 2026-03-12 | main sleep 23:14–06:52; `hrE` giving a detected effort of exactly 07:10–07:41; band `WALKING` 12:31–13:04 (id `…0103`) |

  The generator shapes the series so detection yields exactly these windows. The golden test asserts them.
- With `--now T`, the same layout is anchored to the latest London 20:30 that is not after T. The verify run uses this so the data is recent, per edit-spec.md §11.1.

**`edits/`** holds the plaintext books, requests and goldens, all for now `2026-03-12T20:30:00Z`:

| File | Contents |
| --- | --- |
| `book_<state>.json` | the plaintext `{activities, edits, sleep_edits, ratings}` for each state below |
| `requests/edit.json` | `{"exercise_type":"BOXING","start":"2026-03-10T17:56:00Z","end":"2026-03-10T19:12:00Z","notes":"Sparring, 6 rounds of 3 minutes.","hidden":false,"merge_with":[]}` |
| `requests/merge.json` | the same with `end` `19:38:00Z` and `merge_with: ["7300000000000000102"]` |
| `requests/delete.json`, `requests/undo.json` | `edit.json` with `hidden` true, and `edit.json` again |
| `requests/add.json` | POST Boxing, 2026-03-11 18:04–19:04, `origin: "added"`, id `3f0c0000-0000-4000-8000-0000000000e2` |
| `requests/name.json` | POST Running, 2026-03-12 07:10–07:41, `origin: "added"`, id `3f0c0000-0000-4000-8000-0000000000e1` |
| `requests/rate.json` | `{"rpe":7}`, the body of `PUT /v2/ratings/7300000000000000101` |
| `snapshot_<state>.json` | the Go-built `snapshot` for each state |
| `heart_rate_tue.json` | `heart-rate --start 2026-03-10T15:05:00Z --end 2026-03-10T20:30:00Z` (−180 min before the first original start, +180 min capped at now) |
| `heart_rate_thu_effort.json` | the span around 07:10–07:41 |
| `heart_rate_day_<date>.json` | `heart-rate --date D` for 2026-03-09 … 2026-03-12 |
| `preview_parity.json` | [edit-spec.md §8.6](../../docs/goop/edit-spec.md#86-parity) |

The states are:

| State | Book |
| --- | --- |
| `unedited` | no edits |
| `edited` | `edit.json` on `…0101` |
| `merged` | `merge.json` |
| `deleted` | `delete.json` |
| `named` | `edited` plus `name.json` |
| `added` | `edited` plus `add.json` |
| `alias` | no edits, config `sport_aliases: {"KICKBOXING": "BOXING"}` |
| `rated` | `edited` plus a rating of 7 on `…0101`, `updated_at` 2026-03-12T09:00:00Z ([effort-rating-spec.md](../../docs/goop/effort-rating-spec.md) §7) |

Goldens are generated by a Go test with the existing `-update-goldens` flag. The diff is reviewed before commit.

Every workout object carries `rpe` (null unless rated) and every `edit_limits` carries `rpe_scale: "cr10"` since 2026-11-22. `edits/odd_limits.json` is hand-written and has neither, so the app offers no rating in that fixture.

`commands/config_show.json` gains `sport_aliases: {}`. `errors/payload_too_large.json` and `errors/conflict.json` are added or updated.

The app bundle copies `fixtures/v2/edits/*.json` to `Fixtures/edits/` in Debug only, through the same `project.yml` build phase that removes `Fixtures` in Release.

## Parity pack 1

`inputs/store_parity.json` is generated by `scripts/parity_fixture_store.py` from `store_full.json`. It adds only three band BOXING sessions, 19:30–20:30Z on Mondays 2026-02-16, 02-23 and 03-02, with ids `7400000000000000001` through `…003`. No minute heart rate changes. Repeated generation is byte-identical.

| Fixture | Input / command | Expected additions |
| --- | --- | --- |
| `day_full_config.json` | store_full; day 2026-03-10; strain_intent restore, wake_target 06:45 | target 10.3–13.3 within; config wake, bedtimes 21:57 / 23:15 / 00:33 |
| `brief_full_evening.json`, `brief_full_evening_values.json` | store_full; brief 2026-03-10 --part evening, without/with --include-values | review: 1 workout, 0 detected efforts, no new flags; value mode adds zone sums 27 / 33 |
| `parity/workouts.json` | store_parity; workouts 2026-03-09 through 03-10 | effort-2026-03-09T19:40:00Z suggests BOXING / Boxing, 3 matches in 56 days |
| `parity/snapshot.json` | store_parity; snapshot | same suggestion in nested workouts |
| `parity/heart_rate_effort.json` | store_parity; heart-rate 2026-03-09T16:40:00Z through 23:25:00Z | edit window around the detected effort |
| `parity/brief_0309.json` | store_parity; brief 2026-03-09 | detected effort suggests BOXING |
| `scores/strain_target.json` | pure target | all parity1-spec §5.1 cases; score_version 2.1.0 |
| `scores/sleep_plan.json` | planner vectors, keys goals / need / nights | parity1-spec §5.3, including rounding, DST, nap and unavailable cases |
| `scores/trend.json` | pure trend, values[30] and last_open | parity1-spec §5.5 above/below/near/flat, minimum days and open-strain exclusion |
| `scores/sleep_composite.json` | pure composite sleep performance (scores.md §4.5a) | composite-sleep-spec §4.1: half-way rounding, missing consistency or efficiency, both efficiency clamps, no sleep; score_version `<Version>+composite.1` |

All day bodies gain strain_target; sleep_plan is non-null only for open cycles. At the fixed reference now, full/no_sleep/calibrating plans are ok with 12/11/9 nights, and new_user is ok with 4. A closed 2026-03-09 cycle has no plan. Existing workouts gain suggested: null. The score version becomes 2.1.0, and score_config gains strain_intent and wake_target.

The preview script copies day_full’s strain_target and sleep_plan to fresh and stale snapshots and adds both score_config keys, preserving the preview score version. Debug bundles copy parity/*.json to Fixtures/parity/; Release removes every Fixtures directory. Full fixture rules are in [parity1-spec §10.1](../../docs/goop/parity1-spec.md#101-go-fixtures-fixturesv2).

## Recovery weights

`recovery/weights_40_30_30.json` and `recovery/no_weights.json` are synthetic Recovery bodies based on `preview/snapshot_fresh.json`'s `day.recovery`. The former reports 40% HRV, 30% resting HR and 30% sleep. Its weighted base is 73.7 and its score is 71. The latter omits weights to represent an older Mac, with weighted base 75.5 and score 73. The extra `synthetic_fixture` flag is ignored by decoders.

The Debug fixture sets `recovery_weights` and `recovery_no_weights` replace only `snapshot.day.recovery` in the fresh snapshot. Home therefore shows 71 in `recovery_weights` while the trend rows still hold 73 for that day. This mismatch is accepted because the set tests the Recovery sheet. Preview weights are copied from `day_full.json`, with no constants in the generator.

The Debug fixture set `missing_values` starts from the fresh snapshot and empties every value block at once: the Kickboxing Strain, a detected effort's Strain, time in bed, heart-rate coverage and the day's average heart rate ([live-polish-spec.md](../../docs/goop/live-polish-spec.md) §4.1). Its day is not self-consistent; the set exists to show empty blocks.

## Engine numbers

`engine/odd_constants.json` is a synthetic Mac model whose numbers differ from the defaults. The Debug `engine_odd` set applies it to the fresh snapshot's constants, calibration, vitals, plan, stage ranges, comparison window and collector interval. Changed windows and percentiles do not recompute the fixture's means or ranges; they prove the app prints what the Mac sends. `engine_none` removes the new optional fields to represent an older Mac.

## Edit limits

`edits/odd_limits.json` is a synthetic set of request limits chosen to bind on the edit fixture. Launch `-GHealthFixture edit -GHealthEditLimits odd` to use them, or `-GHealthEditLimits none` to omit the report. Omitting the argument uses the Mac's limits from the snapshots. The selection is applied after each snapshot read, including refreshes.

`-GHealthEditFixture old` opens the 2026-03-07 Boxing; `edit` opens the Edit sheet and `add` opens PAST mode. Combine these with either limits argument.

`edits/limit_cases.json` contains the 21 shared Go and Swift cases from [edit-limits-spec.md §6.2](../../docs/goop/edit-limits-spec.md#62-shared-limit-cases). Each case names its book/snapshot state, complete RFC 3339 window, merge ids, acceptance and refusal field.

## Health Monitor rule

`scores/vitals.json` holds the 17 synthetic cases in health-monitor-flag-spec.md §10. It covers wider ranges, log-space HRV, range edges, direction, gaps, short baselines, matching persistent keys, monitor states and ordered flag messages. Score version 2.2.0 changes the vitals rule. Recovery, Strain and Sleep values do not change.

## Sleep window rule

`scores/hrv_trend.json` holds the 12 synthetic cases in hrv-trend-spec.md §10: inside, below and above the range, the 4-night and 14-value minimums, the SD floor, the low edge from both sides, and an asymmetric range. Score version 2.4.0 adds `vitals.hrv_trend` and `score_constants.hrv_trend`. Existing whole-response goldens change only their version strings and those two additive fields; `vitals.json` and `strain_target.json` take the new version because their tests pin it. Older vector and preview envelopes keep their versions.

`sleep_edit/rule_cases.json` is the shared Go and Swift contract for the pure sleep-window rule (score version 2.3.1): untouched, no segments, Google and ghoops extensions, trims, earlier starts, middle gaps, classic sleep, naps and a no-op edit. Since 2.3.1 it also has a segment missing from the detail while Google's total keeps it (`internal_gap_counted`, extended and shortened), an end gap Google's total partly counts and a total longer than its window (scores.md §4.2a). Existing whole-response goldens change only their 2.2.0 version strings and additive unstaged fields; older vector and preview envelopes keep their versions.

## Sleep edits

`inputs/store_sleep_neighbours.json` is `store_full` plus a synthetic CLASSIC nap, 2026-03-09 21:30–22:30, asleep 50. Rebuild with `python3 -I scripts/sleep_fixture_store.py --variant neighbours`.

`sleep_edit/book_extended.json`, `book_shortened.json`, `book_earlier.json` and `book_orphan.json` apply windows 23:12–07:41, 23:12–05:59, 22:40–06:29 and a missing 2026-03-05 night. Their `sleep_*.json` goldens are built at the reference now over `store_full`. Extended sleep matches every computed value of `sleep_unstaged.json`; the raw session metadata, `google`, `edit` and `edit_range` may differ. The orphan changes no response.

`book_neighbours.json` adds Walking 07:30–08:00; `book_inside_workout.json` adds Walking 05:00–05:30 inside Google's night. The request files in `sleep_edit/requests/` carry the body, expected status and field, and any store/book needed for validation. They cover lookup, transport-independent validation, midnight, shift, minimum duration and neighbours. The shared `rule_cases.json` remains the Go and Swift rule contract.

## Journal

`journal/book_basic.json` is a plaintext journal book (journal-spec.md §7) with the five default behaviours and 35 synthetic entries from 2026-01-30 to 2026-03-09, every `updated_at` 2026-03-10T08:00:00Z. Over `store_full` at the reference now it gives alcohol 6 "yes" and 10 "no" mornings with a Recovery value, late caffeine 5 and 7, late meal 4 and 8, screen in bed answers only on dates whose next-day Recovery is null, stress no answers, and one answer for the disabled `sauna`.

`journal/journal_basic.json` and `journal/journal_empty.json` are `journal show` over `store_full` with that book and without a journal file. Their `impact` (scores.md §11c) gives alcohol `lower` −17.8 (51.8 against 69.6) and late caffeine `higher` +29.5 (78.6 against 49.1); late meal, screen in bed and stress are `insufficient`. `scores/journal.json` holds seven pure impact vectors: empty, 4 and 5 on each side, uneven counts, `same`, and an exact half rounded away from zero. `journal/requests/cases.json` holds the shared PUT cases: lookup, validation, the horizon edges and `{}`.

## Composite sleep mode (`composite/`)

Built from `store_full` at 2026-03-10T14:30:00Z with `sleep_score_mode: composite` ([composite-sleep-spec.md](../../docs/goop/composite-sleep-spec.md) §9). Every other golden is built in default mode and does not carry the composite.

| File | Command | What it shows |
| --- | --- | --- |
| `composite/day_full.json` | `day --date 2026-03-10` | `score_version` `2.3.3+composite.1`, `score_config.sleep_score_mode`, `score_constants.sleep.composite`, `sleep.performance_composite` (94: hours vs. needed 94, consistency 87, efficiency part 100), Recovery's sleep input 94, `comparison.metrics.sleep_performance_composite` |
| `composite/sleep_full.json` | `sleep --date 2026-03-10` | the same object at the top level of the sleep body |
| `composite/days_full.json` | `days --from 2026-03-04 --to 2026-03-10` | rows with `sleep_performance_composite`, null on 2026-03-05 (no sleep) |
| `composite/snapshot.json` | `snapshot` | all of the above in one body |
| `composite/brief_full_values.json` | `brief --date 2026-03-10 --include-values` | differs from `brief_full_values.json` only in `score_version` and the Recovery trend's `mean_30` (62.3 → 62.4), which follows Recovery (spec §6.6); `brief` carries no composite (spec D10) |

`store_full` sleeps regularly, so its composite stays close to hours vs. needed. `internal/score`'s `TestCompositeModeFeedsRecovery` moves two bedtimes and shows the composite lowering Recovery.

The Debug fixture sets `journal_first` (no journal entries) and `journal_none` (no `snapshot.journal`, an older Mac) start from `fresh`. `-GHealthJournalFixture answer|waiting|rollback` gives `fresh` a fixture Mac that stores journal answers, cannot be reached, or refuses them.
