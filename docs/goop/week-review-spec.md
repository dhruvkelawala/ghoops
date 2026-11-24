# ghoops: Week in Review (issue #4)

Status: draft for the lead, and the owner's approval of the mockup. Written 2026-11-22 against `main` at `b99a4e9`. The mockup is [mockups/week-review.html](mockups/week-review.html), rendered per phone in `mockups/screens/week-review-<key>.png`. The build steps are in [week-review-plan.md](week-review-plan.md). Nothing in this document changes a score, a golden or `score_version`.

## 0. In plain words

The Mac adds up each Monday-to-Sunday week: the week's average Recovery, Strain, Sleep Performance, hours, consistency, HRV and resting HR; its zone minutes, strength time and steps; and how many workouts of each sport. Each number sits next to last week's. Three weekly targets say `met`, `not met`, `so far` or `no data`:

- 7 hours of sleep on 5 or more nights;
- 150 zone minutes, where a minute in zones 4–5 counts twice;
- strength on 2 or more days.

The targets are Mac settings with these defaults. The owner changes them with `ghoops config set`.

In the app, a **WEEK IN REVIEW** card at the top of the Trends tab shows this week's three targets. Tapping it opens a sheet with the targets, one section per pillar, and a THIS WEEK / LAST WEEK switch. The app shows only what the Mac sent.

## 1. Decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | The Mac computes the week. A new read route `GET /v2/week` and command `ghoops week` serve it (§4). | The app could average `days` rows, but the targets, the sport counts and an assistant's weekly post all need the Mac. The `days` rows have no sport counts and no target settings. One computation on the Mac keeps the app, the CLI and assistants in agreement (issue #4: "The app only shows what the Mac computed"). |
| D2 | A week is Monday to Sunday in London. A week that has not ended is counted through today's ghoops day and marked `complete: false`. | WHOOP's Weekly Plan runs "on a Monday-Sunday schedule" and shows progress during the week ([R2]). |
| D3 | "Last week" means **the same days** one week earlier. For a finished week that is the whole previous week. On a Tuesday it is last Monday and Tuesday. | A three-day total next to a seven-day total looks like a drop. Comparing like with like needs no extra rule for partial weeks. |
| D4 | `--date D` picks the week that contains D, as `day --date` does. The issue's `--end D` is dropped. | `--end` suggested a cut-off inside a past week. No screen or agent needs that, and it would add a third kind of week. |
| D5 | The activity target counts **zone minutes = zones 1–3 + 2 × zones 4–5** against one number, 150. | WHO's guideline is 150 minutes of moderate activity, 75 of vigorous, "or an equivalent combination" ([R5]). Garmin counts vigorous minutes twice for the same reason ([R4]). The issue's two separate thresholds (150 or 75) miss mixed weeks: on the preview fixture's last week, 120 + 51 minutes fails both, but it is 222 zone minutes. WHOOP also splits zones 1–3 as moderate and 4–5 as vigorous ([R2]). |
| D6 | A target is `met`, `open`, `not_met` or `no_data` (§3.3). `open` exists only while the week runs. `no_data` means missing days could have changed the answer. | The issue lists three states. A Tuesday cannot honestly say `not_met`. A finished week with a missing night can't say `not_met` when that night might have met it (The Honest Number Rule). |
| D7 | Target settings live in the Mac's config file under `week_targets`. They appear in the `config` output and the `week` body, **not** in `score_config`. | They change no score. Keeping them out of `score_config` leaves every existing golden unchanged. |
| D8 | The entry point is a card at the top of the **Trends** tab, above the metric picker, on the tab root only. | The issue places it there. DESIGN.md bans a Plan card on Home. Trends is where the owner already looks back. |
| D9 | The sheet is an info sheet (`GoopSheet`). A `GoopRangeSelector` switches THIS WEEK and LAST WEEK. | The user commits nothing. Two exclusive options are a range selector (DESIGN.md). LAST WEEK covers the Monday recap ([R2]: "Monday recap … a final weekly summary"); THIS WEEK covers the Sunday evening look. |
| D10 | Values show as WHOOP's contributor rows do: this week's value, a triangle, and last week's value under it in grey, with a legend strip above (`GoopValue`, `GoopLegend`). | DESIGN.md: "Do show change as value, triangle and prior value (`GoopValue`)". The owner already reads this idiom on Recovery and Strain. |
| D11 | The app shows `—` for a value with no data, and a row note says how many nights or days are missing. | The Missing-Is-Grey Rule. |
| D12 | No new score, so `score_version` stays as it is on `main`. `schema_version` stays 2: the route and keys are additive. | contract.md §1.2. |

Rejected:
- **Building the week in the app from `days` and `workouts`.** It duplicates the Mac's rules in Swift, leaves assistants without a command, and the app would need the target settings anyway.
- **Adding `week` to `snapshot`.** It would make the card instant offline, but it grows the app's single request and its cache for a card that only Trends shows. Trends already fetches on demand.
- **Week navigation with ‹ › arrows.** More states (oldest week, disabled arrows) for little gain. The four weeks before feed `usual` (§3.2), and agents can ask for any week with `--date`.
- **A progress bar per target.** It needs a new component and a colour for "progress". A count beside its target says the same thing.

## 2. References

All retrieved on 2026-11-22.

| | What it does | What ghoops takes |
| --- | --- | --- |
| [R1] WHOOP, *Weekly Plan* (The Locker) | Goals such as "HR Zones 4-5", "Strength activity", Sleep Performance and steps. "At the end of each week, you receive a performance summary showing where you met goals and opportunities to improve." "Missing goals is normal … without judgment." | The weekly summary against goals, in neutral words. |
| [R2] WHOOP support, *Weekly Plan* | "Weekly Plans operate on a Monday-Sunday schedule." Time goals for "HR Zones 1-3 (Moderate)" and "HR Zones 4-5 (Vigorous)". Activity goals by "how many days per week". Progress on Home under "My Plan", a Friday check-in and a "Monday recap". | Monday-to-Sunday weeks; zones 1–3 and 4–5 as the two intensities; strength as days per week; progress during the week; the LAST WEEK view as the recap. |
| [R3] Oura, *Oura Reports* | "Each report shows your weekly average Readiness, Sleep, and Activity scores, and trend charts for contributors including resting heart rate, HRV, total sleep time". | Weekly means of the three scores and their main contributors. |
| [R4] Garmin, *Intensity Minutes* | Weekly moderate and vigorous minutes; "Vigorous intensity minutes are counted twice (x2)". | Zone minutes with zones 4–5 counted twice (D5). |
| [R5] WHO 2020 guidelines on physical activity, adults 18–64 | 150–300 minutes of moderate or 75–150 of vigorous aerobic activity a week, "or an equivalent combination", and muscle-strengthening "on 2 or more days a week". | The activity and strength defaults. |
| [R6] Watson et al. 2015, AASM and SRS consensus, *J Clin Sleep Med* 11(6) | Adults should sleep 7 or more hours a night on a regular basis. Already cited in [scores.md](../v2/scores.md). | The sleep default of 7 hours. "5 nights" is ghoops's choice, from the issue. |

WHOOP's older Weekly Performance Assessment may no longer exist; [whoop-parity.md](whoop-parity.md) §6 treats the Weekly Plan summary as its successor.

URLs: [R1] https://www.whoop.com/us/en/thelocker/set-and-reach-your-goals-with-weekly-plan/ · [R2] https://support.whoop.com/s/article/Weekly-Plan · [R3] https://support.ouraring.com/hc/en-us/articles/360046061373-Oura-Reports · [R4] https://www.garmin.com/en-US/garmin-technology/health-science/intensity-minutes/ · [R5] https://www.who.int/publications/i/item/9789240015128 · [R6] https://doi.org/10.5664/jcsm.4758

## 3. Rules

### 3.1 The week

For a date D (default: the default date, scores.md §3.1):

| Name | Rule |
| --- | --- |
| `from` | the Monday on or before D |
| `week_end` | `from + 6`, a Sunday |
| `to` | `min(week_end, default_date)`, the last day counted |
| `days_counted` | `to − from + 1`, 1 to 7 |
| `complete` | `week_end < default_date`: Sunday's cycle has closed |
| last week | `from − 7` to `to − 7` (D3) |
| usual | `from − 28` to `from − 1`, the four weeks before |

Every value comes from the `days` rows of contract §5.10 for those dates, so edits, hidden workouts and the unstaged-sleep rule apply exactly as they do on the day screens. The current day's row is in progress and counts as it is.

### 3.2 Metrics

Each metric is `{value, available_days, last_week, change, usual}`.

| Kind | Keys, in order | `value` and `last_week` | `usual` |
| --- | --- | --- | --- |
| mean | `recovery`, `strain`, `sleep_performance`, `asleep_minutes`, `sleep_consistency`, `hrv_rmssd_ms`, `resting_hr_bpm` | mean of the non-null row values in the window, 1 dp; null when the window has none | mean over the usual window, 1 dp |
| total | `zones_1_3_minutes`, `zones_4_5_minutes`, `strength_minutes`, `steps` | sum of the non-null row values, an integer; null when the window has none | the usual window's daily mean × `days_counted`, rounded half away from zero |

- `available_days` counts non-null values from `from` to `to`.
- `usual` is null when the usual window has fewer than `min_days` values (`ComparisonMinDays`, 7, reported in the body).
- `change` is `value − last_week`, with the same decimals; null when either is null.

### 3.3 Targets

| Key | Setting (default) | Counts | Missing |
| --- | --- | --- | --- |
| `sleep` | `week_sleep_minutes` (420) and `week_sleep_nights` (5) | `met_nights`: nights with `asleep_minutes ≥ week_sleep_minutes` | `missing_nights`: nights with `asleep_minutes` null |
| `activity` | `week_activity_minutes` (150) | `credit_minutes`: Σ `zones_1_3_minutes` + `vigorous_weight` × Σ `zones_4_5_minutes` over non-null days; null when no day has zones | `missing_days`: days with `zones_1_3_minutes` null |
| `strength` | `week_strength_days` (2) | `met_days`: days with `strength_minutes > 0` | `missing_days`: days with `strength_minutes` null |

`vigorous_weight` is 2 (`score.WeekVigorousWeight`, D5). It is a rule of the target, not a setting, and the body reports it so the app never types it.

Status, checked in this order:

| Status | When |
| --- | --- |
| `met` | the count reaches its setting |
| `open` | not met and `complete` is false |
| `not_met` | not met, and the missing days could not have changed that: for `sleep` and `strength`, count + missing < setting; for `activity`, no day is missing |
| `no_data` | otherwise: the week has ended, the target was not reached, and enough nights or days are missing that it might have been |

A week with no data at all ends as `no_data` for every target.

### 3.4 Workouts

Visible recorded and ghoops workouts whose `cycle_date` is in the week, with the effective sport after alias, edit and merge (contract §5.8). Hidden and absorbed entries never count. Detected efforts are counted on their own and never by sport.

## 4. Contract

These sections go into [contract.md](../v2/contract.md) in the steps that build them. Field names are final; values below are synthetic.

### 4.1 CLI and HTTP

| Command | Flags | `kind` | HTTP |
| --- | --- | --- | --- |
| `ghoops week` | `[--date D]`, default the default date | `week` | `GET /v2/week?date=D` (`date` optional) |
| `ghoops brief` | `--part week` added to `morning\|evening` | `brief` | `GET /v2/brief?part=week` |
| `ghoops config set \| unset` | new keys `week_sleep_minutes` (240 to 720), `week_sleep_nights` (1 to 7), `week_activity_minutes` (1 to 1000), `week_strength_days` (1 to 7); `unset` restores the default | `config` | none |

Errors follow contract §6: a malformed date or unknown parameter is `invalid_request`, a future date is `date_out_of_range`, a trailing slash is `not_found`. `week` reads only the store; no command calls Google.

### 4.2 `week` body (contract §5.16)

Envelope (§5.1) with `kind: "week"`, without `score_config` and `score_constants`, then:

```json
"freshness": { "...": "§4" },
"date": "2026-03-08",
"from": "2026-03-02", "to": "2026-03-08", "week_end": "2026-03-08",
"days_counted": 7, "complete": true,
"last_week": { "from": "2026-02-23", "to": "2026-03-01" },
"usual": { "from": "2026-02-02", "to": "2026-03-01", "min_days": 7 },
"metrics": {
  "recovery":       { "value": 57.3, "available_days": 6, "last_week": 59.0, "change": -1.7, "usual": 62.1 },
  "...": {},
  "zones_1_3_minutes": { "value": 120, "available_days": 7, "last_week": 127, "change": -7, "usual": 125 }
},
"workouts": {
  "total": 4, "last_week_total": 5, "detected_efforts": 0,
  "by_sport": [ { "exercise_type": "KICKBOXING", "display_name": "Kickboxing", "category": "combat", "count": 2 } ]
},
"targets": {
  "sleep":    { "status": "no_data", "min_minutes": 420, "nights": 5, "met_nights": 4, "missing_nights": 1 },
  "activity": { "status": "met", "minutes": 150, "vigorous_weight": 2, "credit_minutes": 222, "missing_days": 0 },
  "strength": { "status": "not_met", "days": 2, "met_days": 0, "missing_days": 0 }
}
```

- `date` echoes D. `metrics` keys follow §3.2's order; `by_sport` is sorted by `count` descending, then `display_name`.
- `targets.sleep.min_minutes`, `nights`, `activity.minutes` and `strength.days` echo the settings in force.
- Go structs, not maps, so key order is stable.

### 4.3 `brief --part week`

The morning brief's fields, plus `week` after `health_flags`, for the week containing `--date`:

| Field | Always | Only with `--include-values` |
| --- | --- | --- |
| `week` | `{from, to, days_counted, complete, targets: {sleep, activity, strength: {status}}, workouts: {total, detected_efforts, by_sport: [{exercise_type, count}]}}` | `metrics` as §4.2; each target's settings, counts and missing counts |

`review` stays evening-only. In status-only mode the value keys are absent, not null.

### 4.4 `config`

`values` and `defaults` gain `week_targets: {sleep_minutes, sleep_nights, activity_minutes, strength_days}`. The config file stores the same object. `score_config` on the read bodies keeps its current keys (D7).

## 5. App

Behind `GoopFeature.weekReview` (on in Debug, off in Release) until the owner approves the mockup and the lead turns it on.

### 5.1 Trends card

On the TRENDS tab root, 14 pt under the header and above the metric picker. Not on TREND VIEW pushed from a score screen.

- A `GoopCard`, whole card a button, `chevron.right` 12 pt `textSoft` at the end of the title line.
- Title `WEEK IN REVIEW` (`labelCard`). Under it, the week in `bodySmall` `textSoft`: `Mon 9 – Sun 15 Mar`, plus ` · so far` while `complete` is false.
- `GoopStatCells` with three cells, `SLEEP`, `ZONE MINUTES` and `STRENGTH`: the count in Sofia, then `of 5` in Nunito (`unitSmall`). Zone minutes use `h:mm` like every duration (`2:25` `of 2:30`). A met target adds a mint `checkmark` after its unit, as on the Live Activity's target cell. A null count is `—`.
- It loads this week's body when Trends appears and whenever the snapshot changes (`bundleRevision`).

States:
- Loading: the card keeps its frame with `GoopLoading` inside.
- No connection: `Needs a connection to your Mac` in `bodyMid` `caution` inside the card. The card stays tappable, and the sheet tries again.
- A Mac without the route (`not_found`): no card. Trends looks as it does today.
- `unauthorized`: the existing pairing flow (`invalidPairing`).
- Stale snapshot: values at `model.valuesOpacity`, as on Trends.

### 5.2 Sheet

`GoopSheet(title: "WEEK IN REVIEW")`, large detent, × on the right. From the top:

1. `GoopRangeSelector` with `THIS WEEK` and `LAST WEEK`, opening on THIS WEEK. Its 52 pt segments are too narrow for words, so it gains a full-width option in which each segment takes an equal share of the track. LAST WEEK requests `date = last_week.from`. The sheet keeps both bodies while it is open.
2. The week in `bodyMid` `legendText`: `Mon 2 – Sun 8 Mar`, or `Mon 9 – Sun 15 Mar · so far`.
3. A `GoopLegend`-style strip: the two triangles, the shown week, and the week it is compared with in `iconMuted`. On THIS WEEK it reads `This week` and `Same days last week`; on LAST WEEK, `Last week` and `Week before`.
4. **TARGETS** (`GoopSheetSection`), three target rows (§5.3).
5. **SLEEP**: Sleep performance, Hours of sleep, Sleep consistency.
6. **RECOVERY**: Recovery, HRV, Resting heart rate.
7. **STRAIN**: Day Strain, Zones 1–3, Zones 4–5, Steps.
8. **ACTIVITIES**: Strength activity time; Workouts (this week's count with the compared week's count under it, no triangle); one row per sport (`display_name`, count); `Detected efforts` only when above 0.
9. `GoopFootnote`: `Weeks run Monday to Sunday. Set the targets on your Mac with ghoops config set.`

Metric rows put the label on the left and `GoopValue(metric:value:mean:)` on the right at `valueMid`, with `compareRow` under it. `mean` is `last_week`. The triangle colours come from `ComparisonDirection.color(for:)`, so the app adds no new colour rule. Each row maps to an existing `TrendMetricKey`, which sets its format and unit. Counts get no triangle, because more workouts is neither good nor bad. Sport rows are plain `GoopSheetRow`s.

Missing data in a row: when `available_days < days_counted`, the row note says `1 night missing` (SLEEP and RECOVERY rows) or `2 days missing` (STRAIN and ACTIVITIES rows). A value with no data is `—` in `text2`. `usual` is not shown in this version; agents read it.

Loading, no connection and `unauthorized` are as on the card. The no-connection state adds `TRY AGAIN` (`GoopButton`, outline).

### 5.3 Target row (`GoopTargetRow`, new)

A `GoopSheetRow` with a status line in place of the note:

| Part | Content |
| --- | --- |
| label (`bodyMid`) | `Nights of 7 h or more` · `Zone minutes` · `Strength days`. Hours come from `min_minutes` (`7 h`, `7 h 30 min`). |
| status line | `labelMicro` word, then an optional `rowNote` detail in `text2` |
| value | the count in Sofia `valueMid`, then `of 5` in `unitSmall` `text2`; zone minutes as `h:mm` |

| Status | Word | Colour | Detail |
| --- | --- | --- | --- |
| `met` | `MET` | `positive` | none |
| `open` | `SO FAR` | `text2` | none |
| `not_met` | `NOT MET` | `text2` | none |
| `no_data` | `NO DATA` | `text2` | `· 1 night missing` / `· 2 days missing` |

The zone row adds a second note line, `Zones 4–5 count 2 times`, built from `vigorous_weight`. `NOT MET` is grey, not amber: amber means attention or error in ghoops, and WHOOP frames a missed goal "without judgment" ([R1]).

### 5.4 Copy and engine numbers

Every number in a label, unit or note comes from the body: the settings, `vigorous_weight`, the counts and the dates. Zone names (`Zones 1–3`, `Zones 4–5`) are names and carry the lint's existing allow marker, as `TrendMetricKey` does. `WeekText` in GHealthCore builds every string, so Core tests can check it.

### 5.5 Accessibility

- The card reads `Week in review, Monday 9 to Sunday 15 March, so far. Sleep, 1 of 5 nights. Zone minutes, 2 hours 25 of 2 hours 30. Strength, 0 of 2 days.`
- Each target row reads its label, status word and count.
- At accessibility sizes `GoopStatCells` stacks as rows (existing behaviour) and sheet rows stack their value under the label.

## 6. Fixtures and tests

- Goldens from `store_full`: `week_full.json` (`week --date 2026-03-08`: a finished week with the missing night of 2026-03-05 and no zone minutes before 2026-03-08, so at least the activity target ends `no_data`); `week_current.json` (`week`: Monday and Tuesday, every target `open`, the walk, kickboxing and detected effort); `week_config.json` (`week --date 2026-03-08` with a setting changed so a target flips between `met` and `not_met`); `brief_week.json` and `brief_week_values.json`.
- Previews for the app: `preview/week_this.json` and `preview/week_last.json`, derived from `preview/days_30.json` and `snapshot_fresh.json` workouts by the rules above. The mockup's numbers are these files' numbers.
- A Go table test covers each row of the status table in §3.3, including a week with no data.
- Core tests decode every week golden and preview, and check `WeekText` for each status, a missing night, a partial week and a changed setting.
- A UI test opens the card, checks the three cells, opens the sheet, switches to LAST WEEK and checks `NO DATA`, `MET` and `NOT MET`.

## 7. Not in this version

- Month and year reviews (whoop-parity gap 7 says they reuse the sheet later).
- The `usual` values on screen.
- Targets set from the phone. Settings live on the Mac (DESIGN.md).
- An assistant's Sunday-evening job. It lives outside this repo; once `brief --part week` ships, the owner points the job at `ghealth brief --json --part week --include-values`.

## 8. Questions for the lead

1. **D5.** Zone minutes with zones 4–5 counting twice, instead of the issue's "150 in zones 1–3 or 75 in zones 4–5". Every week that passes the issue's rule also passes this one. Keep D5?
2. **D4.** `--date D` instead of `--end D`. Keep?
3. **Owner.** Approve the defaults (7 h on 5 nights, 150 zone minutes, strength on 2 days), the Trends card, and the sheet in the mockup.
