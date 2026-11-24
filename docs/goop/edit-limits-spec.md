# ghoops: edit sheets offer only what the Mac accepts (issue #13)

Status: approved. The lead approved it on 2026-11-17 (§10), and the owner approved the mockup the same day ("Build it"). Written 2026-11-17 against `main` at `c8bfb16`. The build plan is [edit-limits-plan.md](edit-limits-plan.md). The mockup is [mockups/edit-limits.html](mockups/edit-limits.html).

The Edit sheet and START ACTIVITY's PAST mode can offer changes that the Mac then refuses. Since instant saves ([instant-saves-spec.md](instant-saves-spec.md)), the owner learns this only from a `NOT SAVED` banner after the sheet has closed. This spec makes the Mac report its request limits, keeps every control inside them, and removes the copies the app holds today.

The issue says the app doesn't know the limits. It knows five of them, as copies (§2.2). The refusals come from places where a copy is missing or describes a different rule (§2.3).

## 0. Precedence and decisions

This spec extends [contract.md](../v2/contract.md) §5.11, §5.15 and §7.2, and [edit-spec.md](edit-spec.md) §2.2–§2.8, §5.6 and §5.7. Where they disagree, this spec wins. The plan updates each document in the step that changes the behaviour it describes.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | The limits travel in one new object, `status.edit_limits` (§3). It reaches the app inside every snapshot. | They describe the Mac as a server, like `collector.interval_minutes` and `server.version`, which already live in `status`. The app caches the snapshot, so the pencil and the first frame of each sheet have the limits offline. One copy per snapshot, read by one decoder. |
| D2 | Eight numbers are sent: `horizon_days`, `shift_minutes`, `merge_gap_minutes`, `merge_max_ids`, `notes_max_chars`, `active_min_minutes`, `active_max_minutes`, `heart_rate_span_max_minutes`. The other Mac checks are not sent (§2.1 M11, M13–M19). | Each sent number bounds a control. An unsent check is one the app can't reach: it stops at `now`, sends fixed names and ids, and never reads more than 30 days. |
| D3 | Rules without a number are contract rules, and the phone applies them always: the new window overlaps an original window, covers every absorbed window, a candidate that absorbs others is not merged, times sit on the minute grid, and the end stays at or before `now`. | They are part of what an edit means (contract §7.2), like the zone names in #11 D7. |
| D4 | One Core value, `EditBounds`, holds every bound for one sheet. The handles, the time rows, the merge rows and the Add-past days are all derived from it. `EditBounds.allows` mirrors the Mac's check, and a shared vector file proves Go and Swift agree (§7). | One place to get right, and one test that catches drift between the two languages. |
| D5 | The app keeps no copy (#11 D5). Without `edit_limits`, each control drops the bound whose number is missing: no age check on the pencil, no notes cap, no longest window, and the heart rate is read for the whole cycle. The merge rows are not shown, because a candidate is defined by the gap. The Mac may then refuse a change, and #9's `NOT SAVED` banner says so. | The brief asked for both "no copy" and "exactly as today against an older Mac". Both can't hold: today's sheets already copy five limits (§2.2). This keeps the #11 rule and the lead's install order (Mac first). It is product call 2 (§9). |
| D6 | The edges are quiet. A handle stops where the graph ends, the time pickers grey out times outside the range, and rows and days the Mac would refuse are not offered. Two sentences are added, both where a control stops and the reason isn't on screen: a full notes field and a missing pencil (§5.4). | Borrowed: WHOOP's Edit Activity sets times by scrubbing the heart-rate graph (WHOOP changelog, 25 June 2026), so the graph's end is the limit. WHOOP's Journal goes back "up to 14 days" by swiping, and its article describes no message at the edge (WHOOP Journal article). Apple Health's Add Data sets date and time with the system pickers (support.apple.com/108779); a system picker given a range greys out what's outside it, which `GoopTimeRow` already uses. Not borrowed: a character counter. None of these screens shows one, and 500 characters is far above any note the owner writes. |
| D7 | The live session's limits stay out of scope: the 12-hour auto-end, the 1-minute "Too short to save" and the Live Activity timer. | They run offline during a workout and inside the widget extension, which has no snapshot. A follow-up issue (§9). |
| D8 | The heart-rate read for an edit is capped at `heart_rate_span_max_minutes`, centred on the activity (§5.3). | Today a 12-hour activity with a neighbour asks for over 18 hours, and the sheet can't open (R5). |
| D9 | `score_version` stays `2.1.0` and `schema_version` stays 2. No dark-launch flag. | Additive key; no score changes. Each plan step is complete on its own. |

Rejected:
- **Beside `score_config` in the envelope**, or inside `score_constants`. These are not score-engine numbers, so `score_constants` would stop meaning one thing. The object would also repeat on seven body kinds that the sheets never read for it.
- **In the `heart_rate` body only.** The pencil is decided on the workout page, before any heart-rate read, and PAST needs the horizon before it picks a day.
- **A per-workout `editable` flag.** It changes every day without the workout changing. The shift, notes and length controls need numbers anyway.
- **The pre-reporting values as an older-Mac fallback** (30, 180, 15, 4, 500, 1, 720, 1080). Every Mac that omits `edit_limits` was built with exactly these values, so this copy can't drift, unlike #11's rejected fallback. It would make an older Mac behave better than today. Rejected only to keep #11's no-copy rule; the lead may prefer it (§9, call 2).
- **Always reading heart rate by `date=`**, which has no span limit. The shift range crosses into the next or previous cycle for an activity near wake time.

## 1. Facts this design relies on

- `status` (`internal/v2report/types.go:147`) is built by `Builder.Status` (`internal/v2report/report.go:262`). It is nested in `snapshot` and printed by `ghoops status --json`.
- The app reads the snapshot's `status` from `CachedSnapshot` (`ios/GHealthCore/Sources/GHealthCore/Models/Status.swift:3`). Unknown keys are ignored (contract §1.2), and decoding converts snake case.
- The Mac checks an edit in `activities.Edit.Validate` (`internal/activities/edits.go:145`), `score.Engine.EditTarget` (`internal/score/edits.go:35`) and `score.Engine.ValidateEdit` (`internal/score/edit_validation.go:18`). It checks a new activity in `activities.Upload.Validate` (`internal/activities/activities.go:55`) and a heart-rate read in `v2report.Builder.heartRate` (`internal/v2report/heart_rate.go:17`).
- The 1-minute and 12-hour activity lengths are literals in two places (`activities.go:81`, `edit_validation.go:107`). The other limits are constants in `internal/activities/edits.go:16-23`.
- Edit fixture facts (`fixtures/v2/edits/`, now `2026-03-12T20:30Z`, default date `2026-03-12`, London = UTC in March):
  - target `7300000000000000101` (Kickboxing → Boxing), original 18:05–19:02 on 2026-03-10; `snapshot_edited` has it at 17:56–19:12 with the note "Sparring, 6 rounds of 3 minutes." (32 characters);
  - neighbour `7300000000000000102` (Kickboxing) at 19:16–19:38, which `snapshot_merged` absorbs (window 17:56–19:38);
  - `7300000000000000100` (Boxing) on 2026-03-07; detected efforts on 2026-03-11 and 2026-03-12;
  - `heart_rate_tue.json` spans 15:05–20:30, rest 54 and max 186 bpm. For 17:56–19:12 it gives Strain 12.9, average 143, which the screenshot `screenshots/edit/edit-edit.png` shows.
- A probe at `c8bfb16` confirmed every vector in §6.2 against `ValidateEdit`, and that the target is found at now `2026-04-08T20:30Z` (default date 2026-04-08) and `not_found` at `2026-04-09T20:30Z`.

## 2. The sweep

`A/` is `ios/GHealth/`, `C/` is `ios/GHealthCore/Sources/GHealthCore/`. Line numbers are at `c8bfb16`.

### 2.1 What the Mac enforces

| # | Limit | Requests | Source | Refusal | Sent as |
| --- | --- | --- | --- | --- | --- |
| M1 | Edit horizon: the target's **original** `cycle_date` is within the 30 days ending on the default date | PUT `/v2/edits` | `internal/score/edits.go:37` (`EditHorizonDays`, `internal/activities/edits.go:17`) | 404 `not_found` | `horizon_days` |
| M2 | New-activity horizon: `start ≥ now − 30 × 24 h` | POST `/v2/activities` | `internal/activities/activities.go:66` | 400 `start` | `horizon_days` |
| M3 | Shift: the window lies in `[min original start − 180 min, max original end + 180 min]` over the target and its absorbed entries | PUT | `internal/score/edit_validation.go:81-86` (`EditMaxShiftMinutes`, `edits.go:18`) | 400 `start` / `end` | `shift_minutes` |
| M4 | Overlap: the window overlaps at least one of those original windows | PUT | `edit_validation.go:87-93` | 400 `start` | rule (D3) |
| M5 | Merge gap: a candidate is the nearest visible neighbour within 15 min of the saved window | PUT with `merge_with` | `internal/score/edits.go:54-65`, checked at `edit_validation.go:68-70` (`MergeMaxGapMinutes`, `edits.go:19`) | 400 `merge_with` | `merge_gap_minutes` |
| M6 | Cover: the window covers each absorbed entry's window | PUT | `edit_validation.go:69` | 400 `merge_with` | rule (D3) |
| M7 | Merge graph: target absorbed elsewhere; candidate absorbed elsewhere or absorbing others | PUT | `edit_validation.go:27-33`, `:48-60` | 409 `conflict` | rule (D3) |
| M8 | At most 4 ids in `merge_with` | PUT | `internal/activities/edits.go:178` (`MaxMergeIDs`, `:20`) | 400 `merge_with` | `merge_max_ids` |
| M9 | Notes: 1 to 500 Unicode code points after trimming | PUT, POST | `activities/edits.go:171-176`, `activities.go:87-90` (`NotesMaxRunes`, `edits.go:21`) | 400 `notes` | `notes_max_chars` |
| M10 | Active length: 1 minute to 12 hours, minus pauses | PUT, POST | `edit_validation.go:94-109`, `activities.go:72-83` (literals) | 400 `active_duration` | `active_min_minutes`, `active_max_minutes` |
| M11 | End at most 5 minutes after `now` | PUT, POST, heart rate | `activities/edits.go:166`, `activities.go:69`, `internal/v2report/heart_rate.go:43` | 400 `end`, `date_out_of_range` | not sent: the app stops at `now` |
| M12 | Heart-rate `start`/`end` span at most 18 hours | GET `/v2/heart-rate` | `heart_rate.go:43` (`HeartRateMaxSpanHours`, `edits.go:22`) | 400 `date_out_of_range` | `heart_rate_span_max_minutes` |
| M13 | Name 1 to 40 characters | POST | `activities.go:63` | 400 `display_name` | not sent: the app sends fixed sport names |
| M14 | Sport in the known list | PUT, POST | `activities.go:53`, `:60`; `activities/edits.go:150` | 400 `exercise_type` | not sent: schema (activity-spec §2.1); `C/Live/ActivityModels.swift:7-20` matches |
| M15 | Body at most 64 KiB | PUT, POST | `internal/serve/edits.go:49-55`, `internal/serve/activities.go:49-55` | 413 | not sent: unreachable with 500 code points |
| M16 | Ids (UUID; no `/`; not `effort-`); pauses ordered | PUT, POST | `activities.go:57`, `:74-80`; `activities/edits.go:147`, `:182` | 400 | not sent: the app builds ids, and the sheets send no pauses |
| M17 | Read range 1 to 90 days | GET `/v2/days`, `/v2/workouts` | `internal/v2report/report.go:143`, `:155` | 400 `date_out_of_range` | not sent: the sheets read 30 days (`A/App/AppModel.swift:142`); contract §6 fixes it (#11 D7) |
| M18 | Restore needs a stored edit; no horizon on DELETE | DELETE `/v2/edits` | `activities/edits.go:117-134` | 404 | not sent: RESTORE shows only with an edit |
| M19 | `if_updated_at` precondition | PUT | `activities/edits.go:96-104` | 409 | not sent: #9's check, not a limit |

### 2.2 Where the app copies a limit

Removed by this spec:

| # | Where | Copies | After |
| --- | --- | --- | --- |
| C1 | `A/Screens/WorkoutScreen.swift:122` | horizon, `-29` days, on the effective `cycle_date` | `EditLimits.editable` (§5.2) |
| C2 | `C/Edit/EditDraft.swift:49-50` | merge gap `15 * 60` | `merge_gap_minutes` |
| C3 | `C/Edit/EditDraft.swift:58` | shift `180 * 60`, used as the heart-rate read | `shift_minutes`, capped by `heart_rate_span_max_minutes` |
| C4 | `C/Edit/EditDraft.swift:8`, `:18`, `:60`; `A/Components/Goop/GoopNotesField.swift:8` | notes `500` | `notes_max_chars` through `EditNotes.capped` |
| C5 | `C/Edit/ActivityWindow.swift:9-16` | length `12 * 3600` and `60` | `active_max_minutes`, `active_min_minutes` through `EditBounds` |
| C6 | `A/Edit/EditSheet.swift:83-84` | `±60` in the time-row ranges | `EditBounds.startRange`, `endRange` |
| C7 | `A/Live/ActivityPicker.swift:107-108`, `:130` | `±60` | the same |
| C8 | `C/Edit/AddDraft.swift:58` | `±60` in the default-window clamp | `bounds.activeMin` |
| C9 | `DESIGN.md:739` | "capped at 500 characters" | §8 |
| C10 | `docs/v2/contract.md` §5.15 ("original start − 180 min"), `docs/goop/edit-spec.md` §5.7 | the numbers in prose | point at `edit_limits` (plan L1) |

Kept:

| Class | Where | Why |
| --- | --- | --- |
| Live session (D7) | `C/Live/ActivitySession.swift:20`, `:31`, `:34`, `:36`, `:47-55`, `:65`; `C/Live/ActivityStore.swift:15`; `A/Live/ActivityController.swift:157`, `:190`, `:194`; `ios/Shared/Goop/GoopLiveActivityView.swift:34` | follow-up |
| Recent-sport windows (30 days) | `A/Edit/ActivitySportStep.swift:15`, `A/Live/ActivityPicker.swift:23`, `C/Edit/AddDraft.swift:18`, `A/App/AppModel.swift:142` | app-owned "recent" lists; nothing they produce is refused |
| Add-past days `-3...0` | `C/Edit/AddDraft.swift:16` | app-owned (#11 §2.2); now also filtered by the horizon |
| Minute grid | `C/Edit/ActivityWindow.swift:18`; one-minute steps at `A/Components/Goop/GoopWindowChart.swift:50` | contract §1.5, edit-spec §8.5 |
| Local retention 7 days | `C/Live/ActivityStore.swift:26` | app-owned |
| Live Activity dismissal 15 min | `A/Live/ActivityLiveStatus.swift:32` | app-owned display time; not a request |
| Trend range 90 days | `C/Presentation/TrendStore.swift:29` | schema (#11 §2.2) |

### 2.3 Controls that can send a refused request today

Against today's Mac, using the fixtures of §1 where they apply. Case names refer to §6.2.

| # | Control | How | Mac answer |
| --- | --- | --- | --- |
| R1 | Edit: start handle, START row | The handle range is the fetched span, which starts at the earliest of the current start, the original start and the candidates' starts, minus 180. An edited start earlier than the original, or a previous candidate, puts it below the Mac's floor. With `snapshot_edited` the read starts at 14:56; the floor is 15:05. | 400 `start` (u2) |
| R2 | Edit: end handle, END row | The same at the end, from the next candidate's end. With `snapshot_edited` the read ends at 22:38; the ceiling is 22:02. | 400 `end` (u4) |
| R3 | Edit: either handle | The window can leave every original window: drag the end to 20:30, then the start past 19:02. | 400 `start` (u6, u8) |
| R4 | Edit: either handle on a merged activity | Shrinking past an absorbed window: with `snapshot_merged`, an end of 19:37. | 400 `merge_with` (m2, m4) |
| R5 | Opening the Edit sheet | An activity of 12 hours or more, with a neighbour, asks for more than 18 hours of heart rate: 12 h + a 15 min gap + a 1 h neighbour + 6 h is 19 h 15 min. The sheet shows the Mac's error and can't edit. | 400 `date_out_of_range` |
| R6 | MERGE WITH PREVIOUS / NEXT | The target already absorbs 4. | 400 `merge_with` |
| R7 | MERGE WITH … | The candidate absorbs others. | 409 `conflict` |
| R8 | MERGE WITH a detected effort | The union ends more than 180 min after the original end, or is longer than 12 hours. | 400 `end`, `active_duration` |
| R9 | Pencil | The copy checks the effective `cycle_date`; the Mac checks the original's. They differ when a saved edit moved the start across wake, on the horizon's last day. | 404 |
| R10 | SAVE on a detected effort (POST) | The start can be dragged 180 min before an effort that began close to `now − 30 × 24 h`. | 400 `start` |
| R11 | Notes, the length clamps, PAST days, PAST handles, the EFFORT step | Not refused today: the copies equal the Mac's values. Each is refused as soon as the Mac's value drops below the copy. The odd fixture (§6.1) shows all of them. | — |
| R12 | Sport step, Delete, Restore, Undo | No number involved. Delete re-sends the stored edit, which the Mac accepted. | — |

## 3. Contract

### 3.1 `status.edit_limits` (contract §5.11)

`status` gains `edit_limits` directly after `server`. It is present in every `status` body, including `snapshot.status`. Example from `fixtures/v2/status_full.json` after step L1:

```json
"edit_limits": {
  "horizon_days": 30,
  "shift_minutes": 180,
  "merge_gap_minutes": 15,
  "merge_max_ids": 4,
  "notes_max_chars": 500,
  "active_min_minutes": 1,
  "active_max_minutes": 720,
  "heart_rate_span_max_minutes": 1080
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `horizon_days` | int ≥ 1 | An edit's target needs its original `cycle_date` ≥ `default_date − (horizon_days − 1)`. A new activity needs `start ≥ now − horizon_days × 24 h`. |
| `shift_minutes` | int | An edited window lies in `[min original start − shift_minutes, max original end + shift_minutes]` over the target and every absorbed entry. |
| `merge_gap_minutes` | int | A merge candidate starts at most this long after the saved window ends, or ends at most this long before it starts (overlap counts as 0). |
| `merge_max_ids` | int | The most ids `merge_with` may hold. |
| `notes_max_chars` | int | The most Unicode code points a note may hold after trimming. |
| `active_min_minutes`, `active_max_minutes` | int | The shortest and longest window, minus pauses, inclusive. |
| `heart_rate_span_max_minutes` | int | The longest `start`/`end` heart-rate read. |

Add under the table: "`edit_limits` was added on <date of step L1>. A Mac built before then omits it. A client must treat a missing `edit_limits` as unknown and must not substitute its own values. The overlap, cover and merge-graph rules of §7.2 have no number and apply always."

### 3.2 Other contract text

- §5.15: replace "The phone asks for `[original start − 180 min, min(original end + 180 min, now))` for an edit, over the target and every candidate" with "For an edit, the phone asks for `[earliest start − shift_minutes, min(latest end + shift_minutes, now))` over the target, its originals and its candidates, at most `heart_rate_span_max_minutes` long (§5.11). It asks for `date=D` for Add past, and for an edit when the Mac sends no `edit_limits`."
- §7.2, after the paragraph that starts "The target's original cycle date must be within the 30 days": "These numbers are reported in `status.edit_limits` (§5.11)."

### 3.3 Against an older Mac

The phone may be updated before the Mac. `editLimits` decodes as optional, and §5.5 lists what each control does without it. The lead installs the Mac first, so the owner never sees §5.5.

## 4. Mac (Go)

1. `internal/activities/edits.go`: add `ActiveMinMinutes = 1` and `ActiveMaxMinutes = 720` to the constant block. Replace the literals at `activities.go:81` and `edit_validation.go:107` with `ActiveMinMinutes*time.Minute` and `ActiveMaxMinutes*time.Minute`. Values do not change.
2. New file `internal/activities/limits.go`:

   ```go
   // Limits is contract §5.11 `edit_limits`: the request limits the phone keeps its edit controls inside.
   type Limits struct {
   	HorizonDays             int `json:"horizon_days"`
   	ShiftMinutes            int `json:"shift_minutes"`
   	MergeGapMinutes         int `json:"merge_gap_minutes"`
   	MergeMaxIDs             int `json:"merge_max_ids"`
   	NotesMaxChars           int `json:"notes_max_chars"`
   	ActiveMinMinutes        int `json:"active_min_minutes"`
   	ActiveMaxMinutes        int `json:"active_max_minutes"`
   	HeartRateSpanMaxMinutes int `json:"heart_rate_span_max_minutes"`
   }

   // ReportedLimits returns the constants the validators use.
   func ReportedLimits() Limits
   ```

   `ReportedLimits` fills each field from its constant; the span is `HeartRateMaxSpanHours * 60`.
3. `v2report.Status` gains `EditLimits activities.Limits `json:"edit_limits"`` directly after `Server`. `Builder.Status` sets it to `activities.ReportedLimits()`.

## 5. App

### 5.1 Models (GHealthCore)

New file `Models/EditLimits.swift`:

```swift
/// The Mac's request limits (contract §5.11). Nil when the Mac predates them; never substitute values.
public struct EditLimits: Codable, Sendable, Equatable {
    public var horizonDays: Int
    public var shiftMinutes: Int
    public var mergeGapMinutes: Int
    public var mergeMaxIds: Int
    public var notesMaxChars: Int
    public var activeMinMinutes: Int
    public var activeMaxMinutes: Int
    public var heartRateSpanMaxMinutes: Int
    // public memberwise init
    public static func editable(cycleDate: String, defaultDate: String, limits: EditLimits?) -> Bool
    public func firstEditableDate(defaultDate: String) -> String   // GoopFormat.addingDays(1 - horizonDays, to: defaultDate)
    public func earliestStart(now: Date) -> Date                     // now − horizonDays × 86400 s
}

public enum EditNotes {
    /// The longest prefix of whole Characters whose Unicode scalar count is at most `max`; `value` when `max` is nil.
    public static func capped(_ value: String, max: Int?) -> String
}
```

- `editable` is `cycleDate >= limits.firstEditableDate(defaultDate:)`, or `true` when `limits` is nil.
- `capped` appends Characters while the running scalar count stays within `max`, so an emoji is never split.
- `Status` gains `public var editLimits: EditLimits?` after `server`.
- `AppModel` gains `var editLimits: EditLimits? { cached?.snapshot.status.editLimits }`.

### 5.2 `EditBounds` (new file `Edit/EditBounds.swift`)

```swift
public struct EditBounds: Sendable, Equatable {
    public var span: DateInterval          // where either edge may go
    public var activeMin: TimeInterval     // seconds
    public var activeMax: TimeInterval?    // nil: no longest window
    public var originals: [ActivityWindow] // overlap rule; [] when it doesn't apply
    public var covers: [ActivityWindow]    // windows the result must cover
    public init(span:activeMin:activeMax:originals:covers:)

    public static func edit(_ workout: Workout, heartRate: HeartRateBody, limits: EditLimits?, now: Date, merging candidate: Workout? = nil) -> EditBounds
    public static func name(_ effort: Workout, heartRate: HeartRateBody, limits: EditLimits?, now: Date) -> EditBounds
    public static func add(day: DateInterval, limits: EditLimits?, now: Date) -> EditBounds

    public func latestStart(end: Date) -> Date
    public func earliestEnd(start: Date) -> Date
    public func startRange(end: Date) -> ClosedRange<Date>
    public func endRange(start: Date) -> ClosedRange<Date>
    public func clipped(to visible: DateInterval) -> EditBounds
    public func allows(_ window: ActivityWindow, pauses: [ActivityPause]) -> Bool
    public func clamp(_ window: ActivityWindow, pauses: [ActivityPause]) -> ActivityWindow
}
```

`ActivityWindow` gains `static func ceilMinute(_ date: Date) -> Date` (the first whole minute at or after `date`). Below, `floor` is `ActivityWindow.minute`, `ceil` is `ceilMinute`, and `hr` is `[heartRate.start, min(heartRate.end, now)]`.

**Builders.**

| Builder | `originals` | `covers` | `span` before rounding |
| --- | --- | --- | --- |
| `edit` | the target's `original` window (its own window when `original` is nil), then each `merged` window. With `merging`, a recorded or goop candidate adds its `original` window (its own when nil). | each `merged` window; with `merging`, a recorded or goop candidate adds its own `start`–`end` | `[min originals.start − shift, max originals.end + shift] ∩ hr`; just `hr` when `limits` is nil |
| `name` (detected effort, POST) | `[]` | `[]` | `[effort.start − shift, effort.end + shift] ∩ hr ∩ [earliestStart(now), now]`; just `hr` when nil |
| `add` (PAST) | `[]` | `[]` | `day ∩ [earliestStart(now), now]`; just `day ∩ [−∞, now]` when nil |

- `shift` is `shiftMinutes × 60` s. A detected `merging` candidate changes nothing: the Mac stores no id for it.
- `span` is rounded inward: start `ceil`, end `floor`.
- `activeMin` is `activeMinMinutes × 60`, or 60 (one grid step) when `limits` is nil. `activeMax` is `activeMaxMinutes × 60`, or nil.

**Rules.**
- `latestStart(end:)` is `max(span.start, min(a, b, c))`, where:
  - `a = end − activeMin`;
  - `b = ceil(o) − 60`, with `o` the latest `w.end` among `originals` whose `w.start < end` (skipped when `originals` is empty or none qualifies);
  - `c = floor(min covers.start)` (skipped when `covers` is empty).
- `earliestEnd(start:)` is `min(span.end, max(a, b, c))`, where:
  - `a = start + activeMin`;
  - `b = floor(o) + 60`, with `o` the earliest `w.start` among `originals` whose `w.end > start`;
  - `c = ceil(max covers.end)`.
- `startRange(end:)` is `span.start ... max(span.start, latestStart(end:))`. `endRange(start:)` is `min(span.end, earliestEnd(start:)) ... span.end`.
- `clipped(to:)` returns a copy whose `span` is `span ∩ visible`.
- `allows` is true when all hold:
  - `span.start ≤ start` and `end ≤ span.end`;
  - `activeMin ≤ active ≤ activeMax`, where `active` is the window minus `pauses`, computed as `ActivityWindow.activeSeconds` does today (that function becomes internal, not private);
  - `originals` is empty, or the window overlaps one of them (`start < w.end && end > w.start`);
  - each cover lies inside the window.
- `clamp` returns `window` unchanged when `allows` is true. Otherwise it applies `moveStart(to: window.start)` and then `moveEnd(to: window.end)` to a copy.

**`ActivityWindow` moves.** `moveStart(to:within:pauses:)` and `moveEnd(to:within:pauses:)` are replaced by `moveStart(to:bounds:pauses:)` and `moveEnd(to:bounds:pauses:)`:

```text
moveStart: start = min(bounds.latestStart(end: end), max(bounds.span.start, floor(value)))
           if activeMax: while active > activeMax && start < bounds.latestStart(end: end) { start += 60 }
           while active < activeMin && start > bounds.span.start { start = max(span.start, start − 60) }
moveEnd:   end = max(bounds.earliestEnd(start: start), min(bounds.span.end, floor(value)))
           if activeMax: while active > activeMax && end > bounds.earliestEnd(start: start) { end −= 60 }
           while active < activeMin && end < bounds.span.end { end = min(span.end, end + 60) }
```

### 5.3 Drafts

**`EditDraft`**:
- `init(workout:workouts:heartRate:limits: EditLimits?, now: Date)` stores `limits`, `now` and `bounds`: `EditBounds.name` for a detected workout, `EditBounds.edit` otherwise. After setting `window`, it sets `window = bounds.clamp(window, pauses: workout.pauses)`.
- `notes` caps with `EditNotes.capped(_, max: limits?.notesMaxChars)` in `didSet` and in `init`. `cappedNotes` is deleted.
- `candidates(for:workouts:gapMinutes: Int)` replaces the `15 * 60` with `gapMinutes × 60`. `init` stores them as `saved`, or `(nil, nil)` when `limits` is nil.
- `previous` and `next` become computed: the saved candidate when `offers` is true, else nil.
- `public func offers(_ candidate: Workout) -> Bool` is false when `limits` is nil. Otherwise, with `union = ActivityWindow(start: min(window.start, candidate.start), end: max(window.end, candidate.end))`:
  - a detected candidate needs `bounds.allows(union, pauses: workout.pauses)`;
  - a recorded or goop candidate needs all of:
    - `(workout.edit?.mergeWith ?? []).count < limits.mergeMaxIds`;
    - `(candidate.edit?.mergeWith ?? []).isEmpty`;
    - `EditBounds.edit(workout, heartRate:, limits:, now:, merging: candidate).allows(union, pauses: workout.pauses)`.

  It uses the current window, as `mergeBody` does, so a row can disappear while a handle is dragged, but only at a length limit.
- `fetchSpan(for:workouts:limits: EditLimits, now:)`:
  1. Take the entries and their starts and ends as today, using `gapMinutes` for the candidates.
  2. `start = floor(min starts − shift)` and `end = floor(min(now, max ends + shift))`.
  3. If `end − start` is more than `cap = heartRateSpanMaxMinutes × 60`: let `mid` be the midpoint of the workout's `start`–`end`. Then `start = max(start, floor(min(mid − cap / 2, end − cap)))` and `end = min(end, start + cap)`.

**`AddDraft`**:
- `init(defaultDate:workouts:now:limits: EditLimits?, id:)` stores `limits`.
- `days` keeps the app's `-3...0` and drops any day before `limits.firstEditableDate(defaultDate:)`.
- `span: DateInterval` moves here from `ActivityPicker.span(_:)`, unchanged.
- `bounds` is `EditBounds.add(day: span, limits:, now:)`.
- `efforts` keeps only efforts whose window passes `bounds.allows(_, pauses: [])`.
- `setDefaultWindow` uses `bounds.activeMin` where it used 60, then `bounds.clamp`.

### 5.4 Controls

| Control | Bound | At the edge, the owner sees |
| --- | --- | --- |
| Start handle, START row (Edit, detected naming, ADD) | `moveStart(to:bounds:)`; row range `startRange(end:)` | The graph ends at the limit and the handle stops there. The picker greys out earlier times. No words. |
| End handle, END row | `moveEnd`; `endRange(start:)` | The same at the other end. |
| Window length | `activeMin`, `activeMax` | The moving edge stops; DURATION shows the limit. |
| Overlap and cover | `latestStart`, `earliestEnd` | The handle stops one minute inside the band's window, or at the merged piece's edge. The band's dashed window and strip already show where. |
| MERGE WITH PREVIOUS / NEXT | `offers` | The row is not shown. |
| Notes | `notes_max_chars` | Typing stops. A sentence appears under the field (below). |
| Pencil | `EditLimits.editable` | No pencil, and a footnote on the workout page (below). |
| ADD DAY | `AddDraft.days` | Days outside are not shown. With one day left, the row reads `DAY` with the value `Today`. |
| ADD EFFORT | `AddDraft.efforts` | Efforts outside are not listed; with none left, the row reads `None found`, as today. |
| Opening the sheet | `fetchSpan` cap | Nothing visible. |

**Sentences.** Both are Nunito, built from the Mac's number, and shown only with `edit_limits`. Neither is a banner.

| Where | When | Text | Style and id |
| --- | --- | --- | --- |
| Under `GoopNotesField`, 8 pt below | the note has `notes_max_chars` code points, or the last input was cut | `Notes can hold up to <n> characters.` | `bodySmall`, `text2`, leading; `edit-notes-limit` |
| First line of the workout page footnote (`WorkoutScreen.footnote`) | `editable` is false, `cycle_date ≤ default_date`, no save message and not locked: the horizon is the only reason the pencil is gone | `Only activities from the last <n> days can be edited.`; for `n == 1`: `Only today's activities can be edited.` | the footnote's style; `workout-edit-horizon` |

Product call 3 (§9) covers both sentences.

**Call sites.**
- `WorkoutScreen.canEdit`: replace the `-29` clause with `EditLimits.editable(cycleDate: workout.cycleDate, defaultDate: model.defaultDate, limits: model.editLimits)`.
- `EditSheet`:
  - `load()` captures `model.editLimits`. With limits it reads `heartRate(start:end:)` over `fetchSpan`; without, `heartRate(date: workout.cycleDate)`. It passes the limits and `model.now` to `EditDraft`.
  - The `span` property is removed.
  - The chart gets `bounds: draft.bounds`.
  - The time rows use `draft.bounds.startRange(end: window.end)` and `endRange(start: window.start)`.
  - `time(start:)` uses `ActivityTime.picker(value, within: bounds.span)` and the new moves.
  - `GoopNotesField(text:limit: draft?.limits?.notesMaxChars)`.
- `AddActivitySheet`: builds `AddDraft` with `model.editLimits`, uses `draft.span` and `draft.bounds` for the chart, the time rows and `time(start:)`, and deletes `span(_:)`. The one-day DAY row is `GoopRow("DAY", value: "Today")`.
- `GoopWindowChart`: `bounds` becomes `EditBounds?`.
  - The visible range is clamped to `bounds?.span` (else the heart-rate span).
  - A drag moves with `(bounds ?? EditBounds(span: heart-rate span, activeMin: 60, activeMax: nil, originals: [], covers: [])).clipped(to: range)`.
  - The merge preview and `ComponentGallery` pass nil.
- **`EditBounds` never traps.** When the inputs would give an empty or inverted range (for example, a phone clock earlier than the heart-rate data), the bounds collapse to the draft's current window: each handle's range is that single point, and nothing calls `DateInterval(start:end:)` or builds a `ClosedRange` with lower above upper. The sheet opens, the handles don't move, and the other controls work. A Core test, `editBoundsNeverInvert`, builds bounds with `now` an hour before the heart-rate start and with `activeMax` shorter than `activeMin`. It checks that both return a single-point range without trapping.
- `GoopNotesField` gains `var limit: Int?` and an `@State` "last input was cut" flag, and draws the sentence.
- Debug callers: `A/Debug/InstantFixture.swift:29` and `:37` pass `model.editLimits` and the model's `now` to `EditDraft`. `A/Debug/ComponentGallery.swift`'s edit example is independent of the gallery's fixture set. It passes its own `snapshot_edited.json`'s `status.editLimits` and `generatedAt`, so its clock and limits match its heart-rate body (lead, 2026-11-17). `ComponentGallery` adds a second notes field holding a 40-character note with `limit: 40` and identifier `gallery-notes-limit`, so the gallery shows the sentence.
- The new `EditDraft` and `AddDraft` parameters have no defaults, so every caller passes them.

### 5.5 Without `edit_limits` (D5)

| Control | Today (copies) | With no `edit_limits` |
| --- | --- | --- |
| Pencil | hidden after 30 days | shown at any age; the Mac answers 404 after its horizon |
| Heart-rate read and handles | ±180 min | the whole cycle (`date=`); handles bounded by the cycle and the rules of D3 |
| Merge rows | within 15 min | not shown |
| Notes | 500 cap | no cap and no sentence |
| Window length | 1 min to 12 h | one grid step to no maximum |
| PAST | 4 days, 12 h cap | 4 days, no cap |

## 6. Fixtures

### 6.1 Odd limits

New `fixtures/v2/edits/odd_limits.json` (synthetic, hand-made). Every value differs from the default, and each is chosen to bind on the edit fixture:

```json
{
  "synthetic_fixture": true,
  "edit_limits": {
    "horizon_days": 3,
    "shift_minutes": 60,
    "merge_gap_minutes": 3,
    "merge_max_ids": 2,
    "notes_max_chars": 40,
    "active_min_minutes": 5,
    "active_max_minutes": 150,
    "heart_rate_span_max_minutes": 600
  }
}
```

| Limit | Effect on the edit fixture |
| --- | --- |
| horizon 3 | 2026-03-10 is editable; the 2026-03-07 Boxing has no pencil; PAST offers TUE, WED and THU, not MON |
| shift 60 | the start stops at 17:05 (18:05 − 60); the end ceiling is 20:02 |
| active max 150 | after the start reaches 17:05, the end stops at 19:35, DURATION 2:30 |
| gap 3 | the Kickboxing at 19:16 is 4 min after 19:12, so MERGE WITH NEXT is not offered |
| notes 40 | the 32-character note takes 8 more characters |

- `FixtureEditAPI` gains `limits: LimitsFixture = .mac` (`enum LimitsFixture: Sendable { case mac, odd, none }`). `snapshot()` sets `status.editLimits` to `odd_limits.json`'s value for `.odd` and to nil for `.none`. It is applied after the state's snapshot is read, so refreshes keep it.
- A new launch argument `-GHealthEditLimits odd|none` is read in `configureEditFixture` and passed to `FixtureEditAPI`.
- A new `-GHealthEditFixture old` key pushes `7300000000000000100` on 2026-03-07, with state `edited`.
- `fixtures/v2/edits/*.json` is already copied into the app bundle, so `ios/project.yml` does not change.
- `fixtures/v2/README.md` gains an "Edit limits" section describing the file, the two launch arguments and §6.2.

### 6.2 Shared limit cases

New `fixtures/v2/edits/limit_cases.json` (synthetic). It uses the default limits, target `7300000000000000101`, and times on 2026-03-10 UTC. `state` names `book_<state>.json` for Go and `snapshot_<state>.json` for Swift. Each case is `{name, state, start, end, merge_with, accepted, field}`; `field` is null when the case is accepted.

| name | state | window | `merge_with` | accepted | field |
| --- | --- | --- | --- | --- | --- |
| u1 | unedited | 15:05–19:02 | [] | yes | |
| u2 | unedited | 15:04–19:02 | [] | no | start |
| u3 | unedited | 18:05–22:02 | [] | yes | |
| u4 | unedited | 18:05–22:03 | [] | no | end |
| u5 | unedited | 19:01–19:30 | [] | yes | |
| u6 | unedited | 19:02–19:30 | [] | no | start |
| u7 | unedited | 17:00–18:06 | [] | yes | |
| u8 | unedited | 17:00–18:05 | [] | no | start |
| u9 | unedited | 18:05–18:06 | [] | yes | |
| m1 | merged | 17:56–19:38 | [102] | yes | |
| m2 | merged | 17:56–19:37 | [102] | no | merge_with |
| m3 | merged | 19:16–19:38 | [102] | yes | |
| m4 | merged | 19:17–19:38 | [102] | no | merge_with |
| m5 | merged | 15:05–19:38 | [102] | yes | |
| m6 | merged | 15:04–19:38 | [102] | no | start |
| m7 | merged | 17:56–22:38 | [102] | yes | |
| m8 | merged | 17:56–22:39 | [102] | no | end |
| n1 | unedited | 18:05–19:38 | [102] | yes | |
| n2 | unedited | 18:05–19:37 | [102] | no | merge_with |
| n3 | unedited | 15:05–22:38 | [102] | yes | |
| n4 | unedited | 15:04–22:38 | [102] | no | start |

`[102]` is `["7300000000000000102"]`. The file stores full RFC 3339 times.

### 6.3 Goldens and previews

- `$GO test ./internal/v2report -update-goldens` regenerates the 11 goldens that carry a `status` body: `status_full`, `status_new_user`, `parity/snapshot` and the eight `edits/snapshot_*`. Each may only gain `edit_limits`; plan L1 checks this.
- `scripts/goop_preview_fixtures.py` gains `add_edit_limits(body, status)`. Any dict with `kind == "status"` and no `edit_limits` gets `status_full.json`'s `edit_limits` inserted after `server`. `update()` runs it on each body.

## 7. Tests

**Go** (`make check`):
- `TestReportedEditLimitsAreEnforced` (new, `internal/serve/limits_test.go`). It uses `newEditServer` and reads `L` from `GET /v2/status`'s `edit_limits`, never from the constants. So a constant changed without its report fails. Steps, in order:

  | # | Request | At the limit | One step past |
  | --- | --- | --- | --- |
  | 1 | PUT target, window `18:05 − L.shift` to 19:02 | 200 | one minute earlier: 400 `Invalid edit field: start.` |
  | 2 | PUT target, window 18:05 to `19:02 + L.shift` | 200 | one minute later: 400 `end` |
  | 3 | PUT target, window 18:05 to `19:16 − L.gap − 1 min`, then PUT merge (18:05–19:38, `merge_with` [102]) | | merge: 400 `merge_with` |
  | 4 | PUT target, window 18:05 to `19:16 − L.gap`, then PUT merge | merge: 200 | |
  | 5 | DELETE `/v2/edits/<target>` | 200 | |
  | 6 | PUT notes `"  " + "é" × L.notes + "  "` (window null) | 200, and the stored note has `L.notes` code points | `"é" × (L.notes + 1)`: 400 `notes` |
  | 7 | PUT window 18:05 to `18:05 + L.activeMin` | 200 | end one second earlier: 400 `active_duration` |
  | 8 | POST, end 2026-03-12T20:00Z, start `end − L.activeMax` | 201 | start one minute earlier: 400 `Invalid activity field: active_duration.` |
  | 9 | POST, start `end − L.activeMin` | 201 | start one second later: 400 `active_duration` |
  | 10 | POST notes `"é" × L.notes` | 201 | `+ 1`: 400 `notes` |
  | 11 | POST, start `now − L.horizon × 24 h`, one hour long | 201 | start one second earlier: 400 `start` |
  | 12 | GET heart rate, `end` 2026-03-12T20:00Z, `start = end − L.span` | 200 | start one minute earlier: 400 `date_out_of_range` |
  | 13 | set `now` to `2026-03-10T20:30Z + (L.horizon − 1) days`; PUT target notes "Horizon" | 200 | `now` one day later: 404 `not_found` |

  Every POST uses a fresh lowercase UUID, `BOXING`, `Boxing` and `origin: "added"`. Every PUT carries the six keys of contract §7.2.
- `TestMergeIDsAtTheReportedLimit` (new, `internal/activities`): `Edit{ID: "x", MergeWith: n distinct ids}.Validate(now)` is nil for `n = ReportedLimits().MergeMaxIDs` and a `merge_with` error for `n + 1`.
- `TestEditLimitCases` (new, `internal/score`): for each case in §6.2, build the engine from `fixtureState(t, "edit")` at `2026-03-12T20:30:00Z`. Set `Activities` and `Edits` from `book_<state>.json`, call `ValidateEdit`, and compare the result with `accepted` and `field`.
- `TestStatusReportsEditLimits` is covered by the `status_full` golden; no extra test.

**Python** (`make check`): in `scripts/goop_preview_fixtures_test.py`, `remove_parity` also pops `edit_limits`. After `update`, each snapshot's `status.edit_limits` equals `status_full.json`'s.

**GHealthCore** (`make ios-core-test`), new file `EditLimitTests.swift`. "Default" is `status_full.json`'s `edit_limits`; "odd" is §6.1's. Heart rate is `heart_rate_tue.json` with `start` set to 2026-03-10T12:00Z and `end` to 2026-03-11T00:00Z, unless stated. `now` is 2026-03-12T20:30Z.

| Test | Asserts |
| --- | --- |
| `statusDecodesEditLimits` | `status_full.json` decodes to `(30, 180, 15, 4, 500, 1, 720, 1080)`. With the key removed, `editLimits` is nil and the rest is unchanged. `preview/snapshot_fresh.json`'s status carries the defaults. |
| `limitCasesMatchTheMac` | For each §6.2 case: `EditBounds.edit` for the state's target with default limits. For `n*` cases, use `merging:` the unedited `7300000000000000102`. `allows(window, pauses: [])` equals `accepted`. |
| `boundsUseTheMacsShiftAndLength` | `snapshot_edited` target, window 17:56–19:12. **Default:** span 15:05–22:02; `moveStart(to: 14:00)` gives 15:05, `moveEnd(to: 23:00)` gives 22:02. **Odd:** span 17:05–20:02; `moveStart(to: 14:00)` gives 17:05, then `moveEnd(to: 23:00)` gives 19:35. **Nil:** span 12:00–00:00 and no maximum. |
| `overlapAndCoverStopTheHandles` | Edited target, default: from 17:56–19:12, `moveStart(to: 19:30)` gives 19:01; from 17:56–19:12, `moveEnd(to: 17:00)` gives 18:06. Merged target (17:56–19:38): `moveEnd(to: 19:20)` gives 19:38, `moveStart(to: 19:30)` gives 19:16. `startRange(end: 19:12)` is 15:05…19:01, and `endRange(start: 17:56)` is 18:06…22:02. |
| `addBoundsUseTheMacsHorizonAndMinimum` | `EditBounds.add(day: 2026-03-09T07:00Z…2026-03-10T07:00Z, limits: odd, now:)` has span start 2026-03-09T20:30Z. On the day span 2026-03-11T07:00Z…2026-03-12T07:00Z, from 18:00–19:00 on 2026-03-11, `moveStart(to: 18:59)` gives 18:59 with default limits and 18:55 with odd. |
| `fetchSpanUsesTheMacsShiftAndCap` | `snapshot_edited` target and its workouts. Default: 14:56–22:38. Odd: 16:56–20:12, with no candidate. Default with `heartRateSpanMaxMinutes = 300`: 16:04–21:04. |
| `mergeRowsUseTheMacsLimits` | Edited target: `next` is `7300000000000000102` with default limits and nil with odd. Unedited target whose `edit.mergeWith` has 4 ids: `next` is nil; with 3 ids it is offered. A candidate whose `edit.mergeWith` is `["x"]` is not offered. A detected candidate 19:10–23:00 next to the unedited target is not offered; at 19:10–22:00 it is. With nil limits there are no candidates. |
| `notesStopAtTheMacsLimit` | `capped("é" × 600, 500)` has 500 scalars; `capped(39 × "a" + "👍🏽", 40)` is the 39 a's; `capped(x, nil) == x`. `EditDraft` with odd limits caps a 60-character note at 40. |
| `horizonUsesTheMacsDays` | `editable` for 2026-03-10 and 2026-03-09 with odd: true, false. For 2026-02-11 and 2026-02-10 with default: true, false. With nil: true. `AddDraft.days`: default `[03-09 … 03-12]`; odd `[03-10, 03-11, 03-12]`; nil the four days. |
| `controlsStayInsideTheMacsLimits` | For `snapshot_edited` and `snapshot_merged`, with default and odd limits: from the saved window, every `moveStart` and every `moveEnd` to each 5-minute time from 12:00 to 00:00 gives a window that `allows`. Every pair (end move, then start move) on a 30-minute grid does too. |

Existing tests (`EditTests.swift:85-177`, `ChangeTests.swift:10`, `:43`, `:49`, `:116`) pass the default limits from `status_full.json` and `now` to `EditDraft` and `AddDraft`, and `gapMinutes: 15` taken from those limits to `candidates(for:workouts:)`. The `moveStart(to:within:)` checks at `EditTests.swift:169-177` use `EditBounds(span: <their span>, activeMin: 60, activeMax: 43200, originals: [], covers: [])`, built from the default limits. Their expected values do not change.

**UI** (`testEditLimitsFromMac`, new), five launches:

1. `-GHealthFixture edit -GHealthEditFixture edit -GHealthEditLimits odd`:
   - The chart exists and `edit-merge-next` does not.
   - Drag `edit-handle-start` to the chart's left edge three times: the label is `Start, 17:05`.
   - Drag `edit-handle-end` to the right edge three times: `End, 19:35`, and `edit-value-duration` is `2:30`.
   - Reveal `edit-notes` and type ` Good session today.`: the field holds 40 characters, and `edit-notes-limit` reads `Notes can hold up to 40 characters.`
   - Capture `edit-limits-odd-sheet`.
2. `… -GHealthEditFixture old -GHealthEditLimits odd`: `edit-button` does not exist, and `workout-edit-horizon` reads `Only activities from the last 3 days can be edited.` Capture `edit-limits-odd-old`.
3. `… -GHealthEditFixture add -GHealthEditLimits odd`: `add-day-2026-03-09` does not exist, and `add-day-2026-03-10`, `-11` and `-12` do. Capture `edit-limits-odd-past`.
4. `… -GHealthEditFixture edit -GHealthEditLimits none`: the chart exists (read by date), and `edit-merge-next` does not. Capture `edit-limits-none-sheet`.
5. `… -GHealthEditFixture old -GHealthEditLimits none`: `edit-button` exists, and `workout-edit-horizon` does not.

`testEditFlow`, `testEditMergeDeleteUndo`, `testNameEffortAndAddPast` and the instant-saves tests keep every assertion; they now run with the default limits from the goldens.

## 8. Rule text

**AGENTS.md**, "Hard rules", after the score-engine bullet:

> - The same holds for the Mac's request limits. The edit sheets read the edit horizon, shift, merge gap and count, notes length, activity length and heart-rate span from `status.edit_limits` and keep no copy. Without them a control drops that bound ([edit-limits-spec.md](docs/goop/edit-limits-spec.md)).

**DESIGN.md**:
- Form rows → Notes: replace "Input is capped at 500 characters and trimmed on save; an empty result means no note." with "Input stops at the Mac's `notes_max_chars` and is trimmed on save; an empty result means no note. At the limit, `Notes can hold up to <n> characters.` appears 8pt below in `bodySmall` `text2`."
- Charts with selection, a new named rule after the provisional handle extension:

  > **The Mac's-Limits Rule.** A task sheet offers only what the Mac accepts. Handles, pickers, merge rows and day choices stop at `status.edit_limits` without words: the graph ends where the limit is. Add a sentence only where a control stops and nothing on screen says why, as for a full notes field and a missing pencil (edit-limits-spec.md §5.4).
- Don't, after the score-engine line:

  > **Don't** copy one of the Mac's request limits (edit horizon, shift, merge gap or count, notes length, activity length, heart-rate span) into the app. Read `status.edit_limits`, and drop the bound when the Mac sends none.

## 9. Product calls for the lead, residuals and follow-ups

Calls:
1. **Contract location (D1):** `status.edit_limits`. The main alternative, beside `score_config`, is rejected in §0.
2. **Older Mac (D5).** "Exactly as today" needs a copy, because today's sheets copy five limits. This spec keeps no copy, so an older Mac gets §5.5: the pencil at any age, no notes cap, no longest window, no merge rows, and a whole-cycle read. The alternative is the frozen pre-reporting values (§0, rejected list), which can't drift. With the Mac installed first, neither is ever seen.
3. **The two sentences (D6):**
   - `Notes can hold up to <n> characters.` under a full notes field. Alternatives: a counter, or silence as today.
   - `Only activities from the last <n> days can be edited.` on an old workout with no pencil. The alternative is silence as today.
4. **The live session (D7)** keeps its 12-hour and 1-minute copies. Recommend a follow-up issue: "Live sessions read the Mac's activity length".
5. **Not sent (D2):** the future tolerance, the name length, the body size, the 90-day read range and the restore and precondition rules.
6. **Detected naming** uses `shift_minutes` for how far its graph reaches. The Mac has no shift rule on POST; this keeps today's ±180 behaviour from the Mac's number.
7. **Clamp on open (§5.3).** If the Mac's limits shrink below a saved edit, the sheet opens with the window moved inside them and `SAVE` enabled. Any save of that activity would otherwise be refused.

Residuals (refusals still possible; #9's banner reports them):
- A change waiting in #9's queue while its activity leaves the horizon.
- The pencil checks the effective `cycle_date`; the Mac checks the original's (R9).
- An absorbed entry that had its own time edit before it was merged. The phone checks cover against its original window; the Mac checks it against the edited one.
- A goop activity trimmed earlier and extended again: pauses outside the saved window are unknown to the phone. Its active length is then larger than the Mac's, which only matters at `active_min`.

Follow-ups, not in this issue: the live-session limits (call 4), filed as #15.

## 10. Lead decisions (2026-11-17)

- **Decisions in §0, and calls 1 to 7 in §9,** are approved as written:
  - the contract location is `status.edit_limits`;
  - against an older Mac, no copy (§5.5);
  - the two sentences;
  - the live session out of scope;
  - the not-sent rules;
  - detected naming uses `shift_minutes`;
  - clamp on open.
- **Why no copy against an older Mac.** The frozen pre-reporting values could not drift. But they would add a second code path that is never used in practice: the lead always installs the Mac before the phone, so a phone never talks to an older Mac. The app keeps no copy, consistent with #11.
- **The residuals in §9 are accepted.** #9's NOT SAVED banner reports them.
- **The live-session limits** (call 4) are filed as #15, to start after #12 and #13.
- **Owner.** The owner approved the mockup on 2026-11-17, including both sentences.
- **Answer to the L4 question (2026-11-17).** The gallery's edit example uses its own snapshot's `status.editLimits` and `generatedAt` (§5.4). The crash showed that an inverted range traps, so §5.4 now also requires `EditBounds` never to trap, with the test `editBoundsNeverInvert`. Build both in L4, before the full suite runs again.
