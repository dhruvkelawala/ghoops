# ghoops: Edit Activity

Status: design spec, written 2026-11-12 from the mockups the owner approved that day. The build plan is [edit-plan.md](edit-plan.md).

The owner can correct what the band recorded. Every activity detail gets a `pencil` that opens an **Edit** task sheet with these controls:
- change the sport;
- move the start and end on the heart-rate graph;
- merge a session the band split in two;
- add notes;
- delete, with Undo on Home;
- restore the band's version.

The same sheet names a detected effort. A separate **ADD ACTIVITY** task sheet logs an activity afterwards ([add-start-spec.md](add-start-spec.md) §3). A one-time Mac setting shows every band Kickboxing as Boxing. All edits live on the Mac. Google Health is never written to.

## 0. Precedence and owner decisions

- This spec extends [activity-spec.md](activity-spec.md), [contract.md](../v2/contract.md), [scores.md](../v2/scores.md), [data.md](../v2/data.md) and [DESIGN.md](../../DESIGN.md). Where they disagree, this spec wins for the features described here. Update those documents as the plan says.
- **Mockups:** [mockups/edit.html](mockups/edit.html), rendered per screen in `mockups/screens/edit-<key>.png`:

  | Key | Screen |
  | --- | --- |
  | `detail` | Detail of an edited band record. The pencil opens Edit; the subtitle says Edited. |
  | `edit` | Edit task sheet |
  | `sport` | Sport sub-step |
  | `merge` | Merge sub-step |
  | `delete` | Delete alert over the Edit sheet |
  | `undo` | Home with the Undo banner |
  | `effort` | Detected-effort detail with the pencil |
  | `add` | ADD sheet, superseded by `add-start-add.png` in add-start-spec §3 |

  The renders use example values. Layout, sizes, colours, type and icons must match. Fixture values differ, and that is expected.
- **DESIGN.md is stale on one point.** It calls `edit.html` rejected and says not to use it. That describes an earlier set. The current `edit.html` and its eight renders were approved on 2026-11-12 (commit `98ff1fe`). Step E1 corrects the two sentences.
- **Owner decisions (2026-11-12):**
  1. The eight screens are approved. The scope is everything WHOOP supports, plus the improvements on those screens.
  2. Edits are saved on the Mac only. Google Health is never written to, and the band's record stays in Google.
  3. "Always show the band's Kickboxing as Boxing" is a one-time Mac setting in `ghoops config`. The phone only mentions it in a footnote.
  4. Home rows are unchanged by edits. A row shows the edited values and carries no "edited" marker.
- **Launch.** Activity editing and the separate ADD and START sheets are enabled in Release. The earlier editing and ADD/START launch flags have been removed. See [add-start-spec.md](add-start-spec.md) §10.
- **Design-system dependency.** This feature ships after the design cleanup ([design-cleanup-spec.md](design-cleanup-spec.md), written in parallel). It uses the components that cleanup creates; §3.1 names them as that spec defines them (its §4 and §11). If the cleanup as built differs, use its names and keep the behaviour described here.
- Everything else in this file was decided while writing the spec and is listed in §12. Points that may need the owner's call are marked **(owner?)** there.

## 1. Facts this design relies on

- **Workout ids.**
  - A band (recorded) workout's `id` is the last segment of the Google exercise `name`. Duplicate merging keeps the representative's id (scores.md §3.8). The id is stable across collects.
  - A ghoops entry's id is `goop-<uuid>`.
  - A detected effort's id is `effort-<start>`. It changes whenever its start minute changes, so it is not a stable key.
- **Scores are views.** Workout strain is computed from the store at read time over the workout's window (scores.md §3.8). Moving the window and recomputing is the whole of an edit's effect on numbers. Day Strain never changes.
- **The config file is read per request.** `ghoops serve` loads `~/.config/ghealth/config.json` on every request (`internal/serve/server.go`), so a new setting applies without a restart.
- **The activities store already exists.** `<state dir>/activities-v2.enc` is written by `internal/activities`, is encrypted like the main store, and has its own lock (`activities.lock`). The collector never touches it. Readers decode `{version, activities}` into a struct and ignore unknown keys. A new top-level key is therefore invisible to older binaries.
- **Detected efforts disappear on their own.** scores.md §3.9 step 4 drops an effort that ghoops entries overlap by at least 50 %. A ghoops entry posted over an effort's window therefore replaces it with no extra rule.
- **The snapshot already has the data for Add past.** It holds 14 days of workouts, including detected efforts, so it covers the ADD sheet's four days, filtered by the Mac's edit horizon.
- **`hr_series` covers covered minutes inside the window only.** The live preview needs minutes around the window. That is a new read (§6.4).

## 2. Flows, screen by screen

Times on screen are London `HH:mm` (`GoopFormat.time`). Durations are `h:mm`. Names come from the sports table (activity-spec §2.1), or from the band's `display_name` when its type is not in that table.

### 2.1 Activity detail (`detail`, `effort`)

This is the existing `WorkoutScreen` with the changes below. It applies to entries of kind `recorded`, `goop` and `detected`.

1. **Header.**
   - `GoopWorkoutHeader` keeps `chevron.left`, the sport symbol (30 pt), the title and the subtitle. It gains `trailing: .edit { … }`: the `pencil` at 21 pt `iconMuted` in a 44×44 target, label "Edit activity", id `edit-button`.
   - The symbol is `ActivitySport.sport(type).symbol` when the type is in activity-spec §2.1, so Kickboxing shows `figure.kickboxing`. Otherwise it is `GoopActivity.workoutSymbol`.
   - **The pencil shows when** the entry's `cycle_date` is within the edit horizon, the 30 days ending on the default date. For a ghoops entry it also needs the workout screen to show no save banner (activity-spec §2 step 7). While a phone estimate is on screen, the page keeps today's DELETE ACTIVITY button and shows no pencil.
2. **Subtitle.** `<start> to <end>`, using the effective times, followed by one suffix:

   | Entry | Suffix |
   | --- | --- |
   | recorded, `edited` true | ` · Edited` |
   | recorded, not edited | none |
   | goop, `edited` true | ` · Edited` |
   | goop, `origin` `live` | ` · Started in ghoops` (unchanged) |
   | goop, `origin` `added` | ` · Added in ghoops` |
   | detected | none |
3. **Body.** Stats, chart, MAX HR / DURATION and zone rows are unchanged. They show the Mac's values for the effective window.
4. **Notes.** When `notes` is non-null, a section follows the zone rows, as in the mockup:
   - the label `NOTES` (`labelSmall`, `iconMuted`), 22 above;
   - the text (`bodyMid`, `bodyText`), id `workout-notes`.
5. **Footnotes.** `bodySmall` `iconMuted`, 8 apart, 16 below the notes or zone rows, in this order. Show only the lines whose condition holds.
   1. **Provenance line** (id `workout-edited-footnote`):
      - recorded, edited: `Edited in ghoops. Google Health keeps the band's version: <OrigName>, <origStart> to <origEnd>.`
      - recorded, edited, with merged entries: `Edited in ghoops. Google Health keeps the band's versions: <OrigName>, <s> to <e>; <Name2>, <s2> to <e2>.` The list covers the entry's own original first, then each merged band record by start. Merged ghoops entries are not listed.
      - recorded, not edited, whose `exercise_type` differs from `original.exercise_type` (a sport alias applies): `Shown as <Name> by your ghoops config on the Mac. Google Health keeps the band's label: <OrigName>.`
      - goop, edited: `Edited in ghoops. First saved as <OrigName>, <origStart> to <origEnd>.`
      - detected: `Not logged as a workout. ghoops found a stretch of high heart rate. Edit it to give it a sport.`
   2. The existing zones line, unchanged: `Zones use heart rate reserve (resting <r>, max <m>). Change max HR on the Mac with ghoops config.`
   3. The existing `Fitbit says: …` line, now only for recorded entries that are **not** edited. The provider's numbers describe the band's window, not an edited one.
   4. The existing `Based on <n>% heart-rate coverage.` line, now only when `hr_coverage` is below 0.80.

   The mockups show these lines at full coverage, which is why the last two conditions exist.
6. **DELETE ACTIVITY on the page** is shown only while the save banner shows (pending, estimate or rejected local entries). That keeps the existing flow (activity-spec §2 step 7). Everywhere else, Delete lives in the Edit sheet.
7. **Tapping the pencil:**
   - on recorded and goop entries, it opens the Edit sheet (§2.2) on its first step;
   - on a detected effort, it opens the Edit sheet with the Sport sub-step already showing (§2.7).

### 2.2 Edit sheet (`edit`)

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §4.1.

A `GoopTaskSheet` titled `EDIT ACTIVITY`, with `xmark` on the right, large detent and a visible grabber. Content is padded 16. From the top:

1. **`SPORT` row** (`GoopRow("SPORT", value:, disclosure: .push)` inside a `Button`, id `edit-sport-row`).
   - The value is the selected sport's name.
   - On a detected effort before a sport is chosen, the value is `Choose` in `text2`.
   - Tapping it shows the Sport sub-step (§2.3).
2. **Values**, 24 below: three columns, `STRAIN` (`strain` colour), `DURATION` and `AVERAGE HR` (white), ids `edit-value-strain`, `edit-value-duration`, `edit-value-avg-hr`. Each is a `GoopValue`-style block:
   - a `labelSmall` caption;
   - the value in `valueStat` (34);
   - a triangle in `neutral` when the rounded value differs from the prior (up when larger, down when smaller);
   - the prior value beneath in `compareRow` `text2`.

   The prior line keeps its height when empty, so nothing jumps. Values follow §8. The priors are:
   - recorded: the band's version, meaning the original window;
   - goop: the saved window when the sheet opened;
   - detected: the effort's window.
3. **Chart**, 22 below (`edit-chart`), drawn as in §8.4. The two dashed edges are drag handles, ids `edit-handle-start` and `edit-handle-end`.
4. **Legend**, recorded entries only: a 13×13 swatch (`typicalFill` with `typicalEdge` `[3,2]` sides), `BAND'S VERSION` (`labelSmall` `textSoft`), and the original times at the right (`time` style, `text2`), for example `18:05 to 19:02`.
5. **Hint** (`bodySmall` `text2`): `Drag a dashed edge, or set the times below.`
6. **`START` and `END` rows**, 24 below. Each is a `GoopRow` whose trailing view is a system `DatePicker(.hourAndMinute)` in compact style, tinted `strain`, ids `edit-start` and `edit-end`. The time mapping rules are in §8.5.
7. **Merge rows.** At most two `GoopRow`s, each with a trailing value and `chevron.right`:
   - `MERGE WITH PREVIOUS` (`edit-merge-previous`) and `MERGE WITH NEXT` (`edit-merge-next`), when a candidate exists (§5.6);
   - the value is `<Name> <start>`, for example `Kickboxing 19:16`;
   - tapping one shows the Merge sub-step (§2.4);
   - there are no merge rows for detected efforts.
8. **`NOTES`**: a section label (`labelCard` `iconMuted`, 24 above), then a multi-line text field (`edit-notes`).
   - The field is a `controlFill` slab with radius 10, minimum height 50 and 15×12 padding, using `bodyMid` and the `strain` cursor.
   - The placeholder is `Add a note` in `text3`.
   - Input is capped at 500 characters. Leading and trailing whitespace is trimmed on save, and an empty result means no note.
9. **Footnote** (`bodySmall` `text2`, 24 above):
   - recorded: `Edits stay on your Mac. Google Health keeps the band's record.`
   - goop: `Edits stay on your Mac.`
   - detected: `Saving adds this to ghoops on your Mac. Google Health is not changed.`
10. **`RESTORE BAND'S VERSION`** (`GoopButton`, outline, 12 below, `edit-restore`). It shows only for recorded entries whose `edit` is non-null, which includes a notes-only edit. See §2.6.
11. **`DELETE ACTIVITY`** (`GoopButton(role: .destructive)`, after the 30pt section gap, last item, `edit-delete`). It shows for recorded and goop entries. See §2.5.
12. **Commit**, pinned: `checkmark` symbol plus `SAVE <SPORT>`, id `edit-save`.
    - It is disabled (40 %) when the request body would equal the current state (§9.2).
    - On a detected effort with no sport chosen, it reads `SAVE ACTIVITY` and is disabled.
    - While the request runs, the commit is disabled (`enabled: false`).

**Saving:**
- Recorded and goop entries send `PUT /v2/edits/<id>` (§6.2).
- A detected effort sends `POST /v2/activities` (§2.7).
- On success:
  1. the sheet closes;
  2. the app refreshes the snapshot and drops its cached day bundles;
  3. the detail page shows the new values.

  After a save that involves `goop-<uuid>`, the local entry for that UUID is removed from `activities-local.json` (§9.3).
- On failure the sheet stays open. A caution `GoopBanner` appears above the SPORT row with the text from §4.3, and the controls keep their values.

**Closing without saving:** `xmark` or a swipe down discards the changes. There is no confirmation.

**Loading.** The values and the chart need the Mac (§6.4). Until the heart-rate request returns, the values show `—` and the chart area shows `GoopLoading`. On failure, see §2.9.

### 2.3 Sport sub-step (`sport`)

The sheet content is replaced in place; there is no second sheet.
- Header: `SPORT`, with `chevron.left` on the left (`sheet-back`) and `xmark` on the right (`edit-close`).
- Content, from the top:
  1. The search field (`edit-sport-search`), as in ActivityPicker.
  2. `RECENT`, at most 2 rows:
     - row 1 is the sport currently selected in the Edit step, with note `Last: <weekday>`. The weekday is that of the most recent other recorded or ghoops activity of that sport in the last 30 days; the note is blank when there is none;
     - row 2, for recorded entries whose original type differs from the selection, is the band's label, with note `Band's label`;
     - otherwise row 2 is the most recent other distinct sport from the last 30 days.
     - For a detected effort, or when nothing is selected, `RECENT` is the two most recent distinct sports (activity-spec §2 rule 2).
  3. `ALL ACTIVITIES`: activity-spec §2.1 in order, without the `RECENT` rows.
  4. **Footnote** (`bodySmall` `iconMuted`, 18 above). It shows only for recorded entries whose original type differs from the selection, and only when `score_config.sport_aliases` has no entry for the original type: `Your band logs this as <OrigName>. To show every band <OrigName> as <Selected>, set it once on your Mac with ghoops config.` The words `ghoops config` are in `textSoft`.
- Rows are ActivityPicker selection rows: 52 tall, with symbol, uppercase name and trailing note. The selected row has a 1.5 pt `strain` stroke, a 13 % `strain` fill and `checkmark.circle.fill`. Ids are `edit-sport-<TYPE>`; the band's-label row is `edit-sport-band`.
- **Band types outside §2.1.** The band's-label row uses the band's `display_name` uppercased and `GoopActivity.workoutSymbol`. Selecting it means "the band's sport", sent as `exercise_type: null`.
- **Commit:** the sport symbol plus `USE <SPORT>` (`edit-sport-use`). It returns to the Edit step with that sport selected. `chevron.left` returns without changing the selection.
- The search matches names case-insensitively, as in ActivityPicker.

For a detected effort with a suggestion, [parity1-spec §2.8](parity1-spec.md#28-sport-sub-step-with-a-suggestion-sport-suggest) overrides the RECENT rows: preselect the suggested sport with `Usual on <Wkd>`, then the latest distinct sport. USE is enabled immediately; SAVE still requires a separate tap. Efforts without a suggestion and recorded/goop entries keep the rules above.

### 2.4 Merge sub-step (`merge`)

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §4.2.

The header is `MERGE`, with `chevron.left` and `xmark`. Content, from the top:

1. **Explanation** (`bodyMid` `legendText`). For a next candidate X, with `n` = whole minutes between this entry's end and X's start:

   | X is | Text |
   | --- | --- |
   | recorded, and this entry is recorded | `The band split this session in two. Merging adds its <XName> from <xStart> to <xEnd> and the <n> minutes between.` |
   | goop | `Merging adds <XName> from <xStart> to <xEnd>, saved in ghoops, and the <n> minutes between.` |
   | detected | `Merging adds the effort ghoops found from <xStart> to <xEnd> and the <n> minutes between.` |

   - When `n` is 1, the ending reads `and the minute between.`
   - When `n ≤ 0`, the ` and the … between` clause is dropped.
   - For a previous candidate the same sentences apply, with `n` measured from X's end to this entry's start.
2. **Values**, as in §2.2. The values are the merged window. The priors are the Edit step's current values.
3. **Chart.** The window is the union of the Edit step's current window and X, shown as in §8.4.
   - Band strips are drawn for every recorded original involved.
   - Handles are disabled; the merged window is fixed here.
4. **Legend:** `BAND'S VERSION` with one band strip, `BAND'S VERSIONS` with more, and no trailing times. There is no legend when no recorded entry is involved.
5. **Rows** (`GoopRow`, value only, no chevron):
   - `THIS ACTIVITY`: `<Name>, <start> to <end>`, using the Edit step's current sport and window;
   - `NEXT ACTIVITY` or `PREVIOUS ACTIVITY`: `<XName>, <xStart> to <xEnd>`. A detected X is named `Detected effort`.
6. **Commit:** `arrow.triangle.merge` plus `MERGE INTO ONE <SPORT>` (`edit-merge-commit`).
   - This **saves immediately**: one `PUT /v2/edits/<id>` with the Edit step's sport and notes, the union window, and `merge_with: [X.id]` when X is recorded or goop (§5.6).
   - Success and failure behave like SAVE.

### 2.5 Delete and Undo (`delete`, `undo`)

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §2.8.

1. **DELETE ACTIVITY** opens a centred system `.alert`:
   - title `Delete this activity?`;
   - message, for a recorded entry: `This removes <Name> from ghoops on your phone and your Mac. Google Health keeps the band's record.`;
   - message, for a goop entry: `This removes <Name> from ghoops on your phone and your Mac.`;
   - buttons `Cancel` (cancel role) and `Delete` (destructive role).
2. **Delete** sends `PUT /v2/edits/<id>` with the entry's **current stored** edit (from the workout's `edit` field, not the unsaved sheet state) and `hidden: true`. With no stored edit, the body is all nulls, `hidden: true`, `merge_with: []`. Unsaved changes in the sheet are discarded.
3. **On success:**
   1. the sheet closes;
   2. the detail pops;
   3. the app switches to the Home tab at its root, keeping Home's selected date;
   4. Home shows the Undo banner in the banner slot, where `Too short to save.` appears (`HomeScreen`). The banner is a neutral `GoopBanner` with:
      - the `trash` symbol in `iconMuted`;
      - the text `<Name> deleted.`;
      - the trailing text action `UNDO`.

      Ids: banner `activity-undo-banner`, action `activity-undo`.
   5. The app refreshes the snapshot.
4. **Banner lifetime:** 10 seconds. It also ends when another Undo banner replaces it, when the app goes to the background, or when UNDO is tapped. In Debug fixture state `undo` it does not expire (§10).
5. **UNDO** sends the request that restores the state before the delete:
   - `PUT /v2/edits/<id>` with the stored edit and `hidden: false` when an edit existed;
   - `DELETE /v2/edits/<id>` when none did.

   On success the banner disappears and the app refreshes. On failure the banner text becomes `Undo didn't reach your Mac. Try again.` with UNDO still there, and the 10 seconds restart.
6. After the banner has gone, the deletion stays. It can still be reversed on the Mac with `ghoops activity unhide --id <id>` (§7).

### 2.6 Restore the band's version

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §4.5.

**RESTORE BAND'S VERSION** opens a centred system `.alert`:
- title `Restore the band's version?`;
- message `This removes your edits and notes for <Name> from ghoops on your Mac. Anything merged into it comes back.`;
- buttons `Cancel` and `Restore` (default role).

`Restore` sends `DELETE /v2/edits/<id>`. Success behaves like SAVE. The detail then shows the band's sport, times and values, and no `· Edited`.

### 2.7 Naming a detected effort (`effort`)

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §4.6.

1. The effort detail's pencil opens the Edit sheet with the Sport sub-step showing.
2. `USE <SPORT>` returns to the Edit step, where the commit reads `SAVE <SPORT>`.
   - `chevron.left` without choosing returns to the Edit step with `Choose` and a disabled commit.
3. The owner may move the edges and add a note.
4. `SAVE <SPORT>` sends `POST /v2/activities` with:
   - `id`: a new lowercase UUID, generated when the sheet opened, so retries replay the same body;
   - `exercise_type` and `display_name` from §2.1 of activity-spec;
   - `start` and `end`: the Edit step's window;
   - `pauses: []`, `origin: "added"`, and `notes` when given.
5. The new ghoops entry covers the effort, so scores.md §3.9 step 4 drops the effort.
6. On success, the sheet closes and the app refreshes. The detail page then replaces the effort with the new entry, `goop-<uuid>`: the app replaces the navigation path's workout id.

### 2.8 ADD activity (`add`)

[add-start-spec.md](add-start-spec.md) §3 owns the sheet, and [instant-saves-spec.md](instant-saves-spec.md) §4.7 owns its immediate save.

1. **Entry.** Home's ADD ACTIVITY opens `AddActivitySheet`, a `GoopTaskSheet` titled `ADD ACTIVITY` with × on the right. It opens on the card's selected day. START uses a separate sheet without a mode switch.
2. **Content**, 4 below the header:
   1. **SPORT** (`add-sport-row`) initially says `Choose`. The Sport sub-step has no selection and a disabled USE ACTIVITY commit until a sport is chosen.
   2. **DAY** offers the four dates ending on the default date, filtered by the Mac's horizon. It selects the requested day when reachable, otherwise the default date.
   3. **EFFORT** (`add-effort-row`) opens a task sub-step. It shows the snapped window, `<n> found` when unsnapped, or `None found` without a disclosure when empty. Choosing an effort snaps the window.
   4. STRAIN, DURATION and AVERAGE HR appear without priors, followed by the window chart and hint.
   5. START and END use native compact time pickers. When the ends have different London dates, both rows show their own date and speak the full date (add-start-spec §3.4).
3. **Default window.** On the default date, the 60 minutes ending now, truncated to the minute, clamped to the cycle start and Mac bounds, without snapping. On a past day, the latest allowed untracked effort, otherwise 18:00 to 19:00 clamped to the cycle and bounds. Choosing a day or receiving its heart rate applies its default again.
4. **Heart rate.** Choosing a day reads `GET /v2/heart-rate?date=<D>` and caches the result for the sheet's life. Loading and offline behavior follow add-start-spec §3.5.
5. **Commit.** ADD ACTIVITY is disabled without a sport. After selection, ADD <SPORT> queues a POST with a new UUID, the chosen sport/window, `pauses: []`, `origin: "added"` and no `live`. It closes immediately and opens the queued workout on the chosen cycle date.
6. **Failure.** Mutation rejection follows instant-saves-spec §3; opening heart-rate errors stay in the sheet.
7. **Bluetooth.** ADD never scans. The heart-rate banner belongs only to the START sheet.

### 2.9 Offline and errors

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §3.

**Edits are refused while the Mac is unreachable; nothing is queued (§12 decision 9):**
- The pencil and PAST stay visible.
- When the heart-rate request fails, the sheet shows the caution `GoopBanner` `Can't reach your Mac. Edits are saved on your Mac, so try again when it can be reached.` above its content.
- All controls except `xmark` and `chevron.left` are disabled at 40 %, and the chart area shows the placeholder `Needs a connection to your Mac`.
- The sheet retries once when the app returns to the foreground.

A failed save, delete, merge, restore or add shows the error from §4.3 and changes nothing.

## 3. Components

### 3.1 From the design cleanup (design-cleanup-spec.md §4)

| Component | API there | Used for |
| --- | --- | --- |
| `GoopTaskSheet` + `GoopCommit` | `GoopTaskSheet(title:, back:, closeIdentifier:, commit: GoopCommit(title:, symbol:, identifier:, enabled:, action:)) { content }`. `back` draws `chevron.left` (id `sheet-back`); the right `xmark` uses `closeIdentifier`. A sub-step is the same sheet with another title, `back` and commit. | Edit sheet (`closeIdentifier: "edit-close"`), its Sport and Merge sub-steps, the separate ADD and START sheets |
| `GoopSectionLabel`, `GoopSearchField`, `GoopChoiceRow` | as there; `GoopChoiceRow(symbol:, title:, note:, selected:, identifier:, action:)` | NOTES label, sport search, sport rows with `Last: Sat` / `Band's label` |
| `GoopRow`, `GoopRowValue`, `GoopTimeRow` | `GoopRow(_ label, value:, disclosure: .none \| .push)`, `GoopRow(_ label) { trailing }`, `GoopTimeRow(_ label, time:, range:, identifier:, date: String? = nil)` | SPORT, merge and EFFORT rows (in a `Button`, `.push`), DAY (trailing selector), THIS/NEXT ACTIVITY (value only), START/END with dates across midnight |
| `GoopBanner` + `GoopBannerAction` | `GoopBanner(text:, title:, symbol:, tone:, symbolColor:, action: GoopBannerAction(title:, identifier:, perform:))` | Undo banner (`symbol: "trash"`, `symbolColor: iconMuted`), sheet error banners (`tone: .caution`) |
| `GoopButton(role:)` | `GoopButton(title:, role: .outline \| .destructive, busy:, identifier:, action:)` | RESTORE BAND'S VERSION (`.outline`), DELETE ACTIVITY (`.destructive`) |
| `goopDestructiveAlert` | `.goopDestructiveAlert(title, isPresented:, verb:, message:, perform:)`. The orange verb depends on the cleanup's D8 probe; whatever it settles applies here. | Delete alert. Restore is not destructive and uses a plain `.alert`. |
| `GoopWorkoutHeader` + `GoopHeaderButton.edit` | `GoopWorkoutHeader(symbol:, title:, subtitle:, back:, trailing: .edit { … })`; the pencil's id is `edit-button`, label "Edit activity" | detail pencil |
| Tokens | `Goop.Gradient.sheet`, `Goop.Color.strainLight`, `Goop.Color.sheetBottom`, `Goop.Opacity.disabled`, `Goop.Metric.radiusSheet`, `radiusButton`, plus the existing `neutral`, `typicalFill`, `typicalEdge` | throughout |

`GoopCommit` has no busy state. While a request runs, the commit is `enabled: false`.

### 3.2 New in this feature (each added to `ComponentGallery` at default size and accessibility 5)

The cleanup spec (§11) leaves the following elements to this feature.

- **`GoopRangeSelector`, made generic.** `GoopRangeSelector(options: [String], selection: Binding<String>, identifier: (String) -> String)`, keeping today's drawing (52×32 segments on a `rangeTrack` with radius 10). The Trends call site keeps working through a convenience init over `TrendWindow.Range`, and is pixel-identical. Used for DAY in the ADD sheet.
- **`GoopWindowChart`.** The workout chart with a movable window (§8.4). Inputs are minutes, the visible range, the window, the band strips, `editable` and an `onChange` callback.
- **`GoopEditValues`.** The three-column values with neutral triangles and prior lines. It is a composition of existing styles.
- **`GoopNotesField`.** The multi-line notes field described in §2.2 step 8.
- **`EditSheet`** (screen). It owns the step state (`edit`, `sport`, `merge(candidate)`) and swaps the title, `back`, commit and content of one `GoopTaskSheet`.

No other new chrome. The rules come from DESIGN.md:
- no pills, steppers, switches or toasts;
- one filled button per screen;
- destructive actions go last;
- dashes are only window edges and the typical-range (band's version) strip.

## 4. Copy

### 4.1 Screens

| Where | Text |
| --- | --- |
| Edit sheet title | `EDIT ACTIVITY` |
| Sport sub-step title | `SPORT` |
| Merge sub-step title | `MERGE` |
| Separate sheet titles | `START ACTIVITY`, `ADD ACTIVITY` |
| Row labels | `SPORT`, `START`, `END`, `DAY`, `EFFORT`, `MERGE WITH NEXT`, `MERGE WITH PREVIOUS`, `THIS ACTIVITY`, `NEXT ACTIVITY`, `PREVIOUS ACTIVITY`, `NOTES` |
| Value captions | `STRAIN`, `DURATION`, `AVERAGE HR` |
| Legend | `BAND'S VERSION`, `BAND'S VERSIONS` |
| Sport row before a choice | `Choose` |
| Effort row | `<start> to <end>`, `Custom`, `None found` |
| Notes placeholder | `Add a note` |
| Search placeholder | `Search activities` |
| Sport notes | `Last: <Sat>`, `Band's label` |
| Buttons | `SAVE <SPORT>`, `SAVE ACTIVITY` (disabled), `USE <SPORT>`, `MERGE INTO ONE <SPORT>`, `ADD <SPORT>`, `RESTORE BAND'S VERSION`, `DELETE ACTIVITY` |
| Detail notes label | `NOTES` |
| Undo banner | `<Name> deleted.` + `UNDO`; on failure `Undo didn't reach your Mac. Try again.` |

Sentences from §2 (hints, footnotes, merge explanations, provenance lines) are exact as written there.

### 4.2 Alerts

| Alert | Title | Message | Buttons |
| --- | --- | --- | --- |
| Delete, recorded | `Delete this activity?` | `This removes <Name> from ghoops on your phone and your Mac. Google Health keeps the band's record.` | `Cancel`, `Delete` (destructive) |
| Delete, goop | `Delete this activity?` | `This removes <Name> from ghoops on your phone and your Mac.` | `Cancel`, `Delete` (destructive) |
| Restore | `Restore the band's version?` | `This removes your edits and notes for <Name> from ghoops on your Mac. Anything merged into it comes back.` | `Cancel`, `Restore` |

### 4.3 Errors (caution `GoopBanner` inside the sheet)

| Cause | Text |
| --- | --- |
| offline, or a network error | `Can't reach your Mac. Edits are saved on your Mac, so try again when it can be reached.` |
| 400 | `Your Mac could not save this. Check the times and try again.` |
| 404 | `This activity changed on your Mac. Close and open it again.` |
| 409 | `This activity is now part of another one. Close and open it again.` |
| 401, 429, 503, other | the existing `ClientError.errorDescription` text |

Uppercase strings are passed already uppercased, with a sentence-case `accessibilityLabel`, for example "Save Boxing".

## 5. Data model

### 5.1 Edits: overrides in the activities store

Edits are stored in the existing encrypted file `<state dir>/activities-v2.enc` as a new top-level array:

```json
{ "version": 1,
  "activities": [ … ],
  "edits": [
    { "id": "7300000000000000101",
      "exercise_type": "BOXING",
      "start": "2026-03-10T17:56:00Z", "end": "2026-03-10T19:12:00Z",
      "notes": "Sparring, 6 rounds of 3 minutes.",
      "hidden": false,
      "merge_with": [],
      "updated_at": "2026-03-12T20:31:00Z" } ] }
```

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | The workout id the edit applies to: a recorded id or `goop-<uuid>`. One edit per id. |
| `exercise_type` | string? | One of activity-spec §2.1; null keeps the original sport, or the alias for recorded entries. |
| `start`, `end` | Time? | Both or neither. Null keeps the original window. |
| `notes` | string? | 1–500 characters after trimming; null means no note. |
| `hidden` | bool | true removes the entry, and everything merged into it, from every body. |
| `merge_with` | string[] | Recorded or goop ids absorbed into this entry, at most 4. `[]` when none. |
| `updated_at` | Time | Set on write. A PUT whose fields equal the stored edit leaves it unchanged. |

**Where they live, and why.**
- In the same file as activities, under the same lock. A merge or hide touching a ghoops activity and an override is then one atomic write.
- No second Keychain read or file reload is needed.
- `version` stays 1, because older readers ignore the new key. If the owner ever runs an older binary, the edits are ignored rather than breaking reads.

**Normalisation.**
- A PUT whose result has every field null, `hidden: false` and `merge_with: []` removes the edit instead of storing it.
- So "no edit" has one representation. Undo of a delete that had no prior edit is a `DELETE`.

**Restore** is `DELETE /v2/edits/<id>`. It removes the edit. Every entry it absorbed becomes visible again, because absorption lives only in the absorber's `merge_with`.

**Orphans.** An edit whose id matches no entry is kept and ignored. That happens when Google later removes a record. `ghoops activity edits` lists every edit with `applies: bool`.

**Retention.** Edits whose `updated_at` is older than 400 days are dropped on the next write, as activities are.

**Cascade.** `DELETE /v2/activities/<uuid>` (permanent delete, CLI and HTTP) also removes the edit with id `goop-<uuid>` and removes `goop-<uuid>` from every `merge_with`.

### 5.2 Changes to ghoops activities (POST body)

| Field | Change |
| --- | --- |
| `start` | The lower bound is `now − 30 days`, up from 7. Naming an effort or adding a past activity anywhere in the edit horizon must pass. The live upload queue is only made more lenient. |
| `origin` | New, optional: `"live"` (the default when absent) or `"added"`. `added` requires `live` to be absent (`invalid_request`, field `live`). |
| `notes` | New, optional: 1–500 characters after trimming. |

- Idempotency is unchanged and compares the whole body, including the new fields.
- The stored record and the response `activity` object gain `origin` (always present) and `notes` (nullable).
- **Existing records** without `origin` read as `live`.
- **Past windows with no live samples** are valid. `live` is optional, `pauses` may be `[]` or absent, and nothing requires samples. The Mac scores the window from the band's minutes.

### 5.3 Sport aliases (`ghoops config`)

**Key:** `sport_aliases` in `~/.config/ghealth/config.json`, an object from a band `exercise_type` to an activity-spec §2.1 `exercise_type`. The default is `{}`.

```sh
ghoops config set sport_alias.KICKBOXING BOXING     # show every band Kickboxing as Boxing
ghoops config unset sport_alias.KICKBOXING          # back to the band's label
ghoops config show                                  # values.sport_aliases lists them
```

**Validation:**
- the source matches `^[A-Z][A-Z0-9_]{0,39}$`;
- the target is in §2.1;
- the source and target differ;
- there are at most 20 aliases.

Anything else is the existing usage error (exit 2). `unset` of a missing alias succeeds and changes nothing.

**Effect.**
- At read time, every recorded entry whose band type has an alias reports:
  - `exercise_type` = the target;
  - `display_name` = the target's §2.1 label;
  - `category` from the target.
- This applies to past and future band records alike, because nothing is stored per record. Unsetting reverts every body on the next request, with no restart.
- `original` keeps the band's type and name.
- An edit's `exercise_type` wins over the alias.
- Aliases never apply to ghoops or detected entries.

**Echo.** `score_config` (contract §5.1) gains `sport_aliases`, because it echoes config, so the phone knows which aliases exist (§2.3 footnote).

**Version.** No `score_version` change: aliases change labels and categories, not formulas.

### 5.4 New fields on workout entries (contract §5.8)

| Field | Type | Rule |
| --- | --- | --- |
| `original` | object or null | `{exercise_type, display_name, start, end}`: the band's values before alias and edit (recorded), or the uploaded values (goop). Null for detected. |
| `edit` | object or null | The stored edit for this id, without `hidden` (a visible entry is never hidden): `{exercise_type, start, end, notes, merge_with, updated_at}`. Null when none. |
| `edited` | bool | `edit` is non-null and has a non-null `exercise_type`, a non-null window or a non-empty `merge_with`. Notes alone do not count. |
| `merged` | array | `[{id, kind, exercise_type, display_name, start, end}]`, the originals of absorbed entries ordered by start. `[]` when none. |
| `notes` | string? | The edit's notes, else the ghoops activity's notes, else null. |
| `origin` | string? | `"live"` or `"added"` for goop; null otherwise. |
| `pauses` | array | `[{start, end}]`: goop pauses that intersect the effective window, clipped to it. `[]` for others. The phone needs them for preview parity. |

Changed meanings, still additive:
- `start`, `end`, `exercise_type`, `display_name`, `category`, `cycle_date`, `elapsed_minutes` and every score field are the **effective** values, after alias, edit and merge.
- `active_minutes` is null for a recorded entry whose window was edited or merged, because the provider's value no longer describes it. For goop it is the effective window minus paused slots.
- `provider` and `source` are unchanged.
- `id` and `kind` never change.

### 5.5 Rules, in order (scores.md §3.8a, new)

For a range of cycles, with the edits and config:
1. **Build entries.** Build recorded entries (duplicate merge as now) and goop entries. Set `original` on each.
2. **Alias.** Apply `sport_aliases` to recorded entries.
3. **Edits.** Apply each edit whose id matches an entry:
   - the sport, with `display_name` from §2.1;
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

### 5.6 Merge

**Candidates** (phone, §2.2 step 7, and server validation), for entry T with effective window `[a, b)`:
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
- The overlap-hide rule skips the pair (§5.5 step 5).

**A detected neighbour.** The window is extended to the union and `merge_with` stays `[]`. The effort disappears through §5.5 step 6.

**Server checks for `merge_with`**, all `invalid_request` with field `merge_with` unless noted:
- each id is a visible recorded or goop entry, other than T, that is a candidate of T by the rule above using T's currently stored effective window;
- the new window covers each absorbed window entirely;
- no id is absorbed by another edit (409 `conflict`);
- no id has its own non-empty `merge_with` (409 `conflict`);
- T is not absorbed by anyone (409 `conflict`).

**Undoing a merge** is Restore, which removes the edit. There is no separate unmerge.

### 5.7 Limits (named constants in `internal/activities`)

| Name | Value | Rule |
| --- | --- | --- |
| `EditHorizonDays` | 30 | A target's **original** `cycle_date` must be within the 30 days ending on the default date. POST `start ≥ now − 30 days`. |
| `EditMaxShiftMinutes` | 180 | The edited window lies within `[min original start − 180 min, max original end + 180 min]` over T and every absorbed entry, and overlaps at least one of those original windows. |
| `MergeMaxGapMinutes` | 15 | §5.6 |
| `MaxMergeIDs` | 4 | `merge_with` length |
| `NotesMaxRunes` | 500 | notes length after trimming |
| `HeartRateMaxSpanHours` | 18 | §6.4 `start`/`end` form |
| `ActiveMinMinutes` | 1 | Shortest active window, minus pauses. |
| `ActiveMaxMinutes` | 720 | Longest active window, minus pauses. |

The phone reads these in `status.edit_limits` (contract §5.11, [edit-limits-spec.md](edit-limits-spec.md)).

The usual active-duration rule applies to the effective window: 60 s to 12 h, minus goop pauses.

These are validation limits, not score constants, so they are not in `internal/score/constants.go` and do not change `score_version`.

## 6. Contract changes (schema 2, additive)

### 6.1 Transport (contract §7.1)

- **Methods:** GET on reads. POST `/v2/activities`. DELETE `/v2/activities/<id>`. **PUT and DELETE `/v2/edits/<id>`.**
- **Request bodies** are allowed only on the activity POST and the edit PUT, as `application/json` of at most 64 KiB. Over that is 413 `payload_too_large`, whose message becomes `Request body exceeds 64 KiB.`; update `fixtures/v2/errors/`.
- A 405 sets `Allow` to the methods of that path:
  - `GET` on reads;
  - `POST` on `/v2/activities`;
  - `DELETE` on `/v2/activities/<id>`;
  - `PUT, DELETE` on `/v2/edits/<id>`.
- `/v2/edits` and `/v2/edits/` are `not_found`.
- Mutation routes take no query string (`invalid_request`).
- A DELETE with a body is `invalid_request`.
- Logs carry method, path, status and duration only, never the body.

### 6.2 `PUT /v2/edits/<id>`

**Request**, with all six keys required; unknown keys are ignored:

```json
{ "exercise_type": "BOXING", "start": "2026-03-10T17:56:00Z", "end": "2026-03-10T19:12:00Z",
  "notes": "Sparring, 6 rounds of 3 minutes.", "hidden": false, "merge_with": [] }
```

**Validation.** Any failure is `invalid_request` with the message `Invalid edit field: <field>.`:

| Field | Fails when |
| --- | --- |
| `id` | the path id is empty, has a `/`, or starts with `effort-` (detected efforts are named through POST) |
| `body` | the body is not a JSON object |
| `exercise_type` | not null and not in activity-spec §2.1 |
| `start` / `end` | only one is null; not RFC 3339; `start ≥ end`; `end > now + 5 min`; outside the §5.7 shift bound |
| `active_duration` | the effective window minus pauses is under 60 s or over 12 h |
| `notes` | not null and, after trimming, empty or over 500 characters |
| `hidden` | missing or not a bool |
| `merge_with` | not an array of strings; over 4; contains the target; fails a §5.6 check |

**Lookup.** The target is found among the entries built by §5.5 steps 1–2 (no edits applied) whose original `cycle_date` is in the edit horizon:
- `goop-<uuid>` must exist in the activities store;
- any other id must be a recorded entry.

If not found: 404 `not_found`.

**Conflicts.** 409 `conflict`:
- the target is absorbed by another edit: message `This activity is merged into another.`;
- an id in `merge_with` is absorbed elsewhere or absorbs others: message `A merged activity is already part of another.`

**Response 200.** The envelope plus:
- `kind: "edit"`;
- `id`;
- `edit`: the stored object (§5.1), or null when normalisation removed it.

**Idempotency.** PUT replaces the edit. The same body again gives 200 with the same `edit` and an unchanged `updated_at`. There is no 201 and no body conflict.

The phone refreshes the snapshot after any 200. The response does not carry recomputed scores.

### 6.3 `DELETE /v2/edits/<id>`

- 200: `kind: "edit"`, `id`, `edit: null`.
- 404 `not_found` when no edit is stored for that id.

This is permanent for the edit only. The band's record is untouched.

### 6.4 `GET /v2/heart-rate` (new read)

The per-minute heart rate around a window, for the live preview.

**Query.** Exactly one form; anything else is `invalid_request`:
- `date=D`: the whole cycle D, `[cycle_start, cycle_end)`. For an open cycle the end is `min(now, device_last_sync_at)`, as in scores.md §3.4. A `not_started` cycle returns no minutes.
- `start=T&end=T`: RFC 3339 times, each truncated to the minute.
  - `start < end`, else `invalid_request` naming `start`.
  - A span over 18 h is `date_out_of_range`.
  - `end > now + 5 min` is `date_out_of_range`.
  - A `start` before the store's oldest date is allowed and returns fewer minutes.

The phone asks for `[original start − 180 min, min(original end + 180 min, now))` for an edit, over T and every candidate, and `date=D` for Add past.

**Response.** The envelope (with `score_config`), `freshness`, then:

| Field | Type | Rule |
| --- | --- | --- |
| `cycle_date` | Date | the cycle containing `start` (or `date`) |
| `start`, `end` | Time | the span served |
| `resting_hr_bpm`, `max_hr_bpm` | `int?` | that cycle's §3.2 and §3.3 values; null with the reason in `rates_reason` |
| `max_hr_source` | string? | as in `strain` |
| `rates_reason` | Reason | `resting_hr_unknown`, `max_hr_unknown` or null |
| `minutes` | array | `[{t: Time, avg_bpm: num (2 dp), max_bpm: int}]`, covered minutes only, ascending |

- The body is about 45 bytes per minute, so under 60 KB for a 24-hour cycle.
- `ghoops heart-rate` prints the byte-identical body (contract §1.1).
- The `kind` list gains `edit`, `edits` (the CLI list, §7) and `heart_rate`.

### 6.5 Workouts, snapshot, days, brief

- These gain the §5.4 fields.
- Hidden entries are absent.
- Counts follow §5.5.
- `score_config` gains `sport_aliases`.
- The snapshot is unchanged otherwise. The expected size stays under 200 KB; notes are capped.

### 6.6 Documents to edit (step E1)

| Document | Sections |
| --- | --- |
| `docs/v2/contract.md` | §3: CLI table rows for `activity edit\|restore\|hide\|unhide\|merge\|edits` and `heart-rate`. §5.1: `kind` list gains `edit`, `edits` and `heart_rate`; `score_config` gains `sport_aliases`. §5.8: the new fields and effective-value meanings (§5.4). §5.13: brief excludes hidden. §5.14: `config` shape gains `sport_aliases`. New §5.15: `heart_rate` body. §6: `conflict` causes; `payload_too_large` message; `invalid_request` messages for edits. §7.1: methods, bodies, `Allow`. §7.2: the `heart-rate` row; a new "Edits" paragraph after the activity paragraph; the POST changes in §5.2. |
| `docs/v2/scores.md` | §0.1: `sport_aliases` row. §3.8: effective windows, `original`, alias. New §3.8a: the §5.5 rules and §5.6 merge. §3.9 step 4: visible or hidden, effective windows. |
| `docs/v2/data.md` | "ghoops activities" section: the `edits` array, normalisation, cascade, retention; POST `origin`/`notes`; the 30-day bound. |
| `DESIGN.md` | Replace the two "rejected `edit.html`" sentences (Overview and Don'ts) with a note that `edit.html` (2026-11-12) is approved. Under Form rows, add the notes field as an approved input. |
| `docs/goop/activity-spec.md` | §8.2: the start bound becomes 30 days, with a pointer to this spec. §12 item 9: adding after the fact and editing times are now in [edit-spec.md](edit-spec.md). |
| `fixtures/v2/README.md` | the edit fixtures (§10.1) |

## 7. CLI (`internal/cli/activity.go`, `read_v2.go`, `config.go`)

All of these print schema-2 JSON and use the same validation as HTTP (one code path in `internal/activities` and the score engine). Errors go to stderr: `invalid_request` and `not_found` exit 2, `conflict` exits 2, `store_unavailable` exits 1.

| Command | Effect | Output `kind` |
| --- | --- | --- |
| `ghoops activity edit --id ID [--type T \| --type band] [--start T --end T \| --band-window] [--notes S \| --clear-notes] [--merge-with ID[,ID]]` | Reads the current edit, applies only the flags given, then stores it as PUT would. `--type band` and `--band-window` set those fields to null. | `edit` |
| `ghoops activity merge --id ID --with ID` | Computes the union window as §5.6 and adds `--with` to `merge_with`, keeping sport and notes. | `edit` |
| `ghoops activity hide --id ID` / `unhide --id ID` | Sets `hidden` true or false, keeping everything else. | `edit` |
| `ghoops activity restore --id ID` | As `DELETE /v2/edits/<id>`. | `edit` (`edit: null`) |
| `ghoops activity edits [--days N]` | Lists stored edits, `updated_at` within N days (default 30), each with `applies: bool`. | `edits` |
| `ghoops activity add … [--origin added] [--notes S]` | Existing command, new optional flags; the default origin is `live`. | `activity` |
| `ghoops heart-rate --date D \| --start T --end T` | The §6.4 body. | `heart_rate` |
| `ghoops config set sport_alias.<TYPE> <TYPE>` / `config unset sport_alias.<TYPE>` | §5.3 | `config` |

An assistant can write `ghoops activity edit --id 7300000000000000101 --type BOXING` or `ghoops activity hide --id …`. Ids come from `ghoops workouts --days 7`. `activity delete --id goop-<uuid>` stays the permanent delete of a ghoops activity (§5.1 cascade).

`fixture-ghealth` (verify-ghealth) adds `activity` and `heart-rate` to its allowlist and a fixture `edit` (§10.1).

## 8. Estimator and preview rules (GHealthCore, pure)

### 8.1 Window estimator

`WindowEstimator` sits next to `LiveEstimator` and shares its TRIMP, strain and zone functions, moved into one `StrainMath` used by both. It takes:
- `minutes: [(t: Date, avg: Double, max: Int)]` from §6.4;
- `window: [a, b)`;
- `pauses: [ActivityPause]`;
- `rest` and `max` (optional);
- the `trimp_profile`.

It returns:
- **Slots.** UTC minute starts `t` with `a.truncatedToMinute ≤ t < b` (scores.md §3.4, as Go's `workoutScore` does for workouts). Slots that overlap a pause are removed and their count is `paused_minutes`.
- **`expected`** is the slot count. **`covered`** is the slots with a minute. **`hr_coverage`** is `covered / expected`, 2 dp, or nil when 0.
- **`trimp`** and **`strain`** follow scores.md §3.5 and §3.6 over the covered averages; strain is 1 dp. When rest or max is missing, or max ≤ rest, both are nil.
- **`avg_hr_bpm`** is `round(mean of covered avg)` and **`peak_hr_bpm`** is the max of covered `max`. Both are nil when nothing is covered.
- **`zones_minutes`** follows §3.5.
- **`elapsed_minutes`** is `(b − a) / 60`.

### 8.2 Displayed values

- STRAIN is `strain`, 1 dp, or `—`.
- DURATION is `h:mm` of `elapsed_minutes`, rounded to whole minutes, as the detail page shows.
- AVERAGE HR is `avg_hr_bpm`, or `—`.
- Values recompute on every minute snap of a drag and on every picker change.
- **Priors** are the same estimator over the prior window (§2.2 step 2), computed from the same minutes, so a prior and its value only differ through the window.

### 8.3 Rates

- Use the heart-rate body's `resting_hr_bpm` and `max_hr_bpm` (the target's cycle) and the body's `score_config.trimp_profile`.
- Never use today's `day.strain` for a past day.

### 8.4 Chart (`GoopWindowChart`)

- **Visible range:** the union of the original windows (T and absorbed candidates), the current window and, in Merge, X, plus 30 minutes each side. It is clipped to the fetched span, and recomputed when a drag ends. For Add, the range is the window ± 30 minutes clipped to the cycle.
- **Plot:** 190 tall.
  - Four grid lines in `plotGrid`, with three y labels in Sofia 11 `textSoft`.
  - The y range is `floor(min/10)×10 − 10` to `ceil(max/10)×10 + 10` over the visible minutes, as in `GoopWorkoutChart`.
- **Runs:** the in-window run is `workoutLine` 2 pt plus the `workoutArea` gradient. The run outside the window is `neutral` at 50 %, 1.6 pt.
- **Edges:**
  - white `[3,3]` dashed verticals with 2.5 pt baseline dots;
  - the start and end times in `axisTime` white under them;
  - hour ticks in `axis` `iconMuted`, hidden within 34 pt of an edge label.
- **Band strips:** for each recorded original, a 10-tall strip 6 below the baseline in `typicalFill`, radius 3, with `typicalEdge` `[3,2]` verticals at its ends. When strips exist, the time labels move 14 pt lower.
- **Handles:**
  - each edge has a 44 pt-wide invisible hit area and no visible knob;
  - dragging snaps to whole minutes, with a selection haptic on each new minute;
  - the start stays at least 1 minute before the end, and the active duration stays within 60 s to 12 h;
  - neither edge leaves the visible range.
- **Accessibility:** each handle is an adjustable element labelled "Start, 17:56" or "End, 19:12", where increment and decrement move 1 minute. The chart has an `accessibilityChartDescriptor`.

### 8.5 Time pickers

- A `DatePicker(.hourAndMinute)` value maps to the single instant within the fetched span that has that London `HH:mm`. The span is under 24 h, so there is at most one. With none, the value clamps to the nearer end of the span.
- Picker ranges stop at the other edge minus or plus 1 minute.
- Pickers and handles edit the same state.

### 8.6 Parity

The phone's preview must match the Mac's saved values exactly for the same window: strain and trimp to 1 dp, ints exact, coverage to 2 dp.

- **Case set 1.** Fed the minute averages of `fixtures/v2/scores/strain.json`, `WindowEstimator` returns that file's `trimp`, `strain` and `zones_minutes`.
- **Case set 2.** `fixtures/v2/edits/preview_parity.json`, generated by a Go golden test. It holds cases of `{heart_rate body, window, pauses, expected: {strain, trimp, avg_hr_bpm, peak_hr_bpm, zones_minutes, hr_coverage, elapsed_minutes, paused_minutes}}`. The expected values are read from the Go `workouts` body after applying the case's edit to `store_edit`. The cases:
  - the edited window;
  - the band's original;
  - the merged window;
  - the Wednesday effort;
  - a window containing a 20-minute gap;
  - a goop entry with a pause;
  - a cycle with no resting HR.

## 9. App changes outside the new screens

### 9.1 Models and client (GHealthCore)

- **`Workout`** gains `original: WorkoutOriginal?`, `edit: WorkoutEdit?`, `edited: Bool?`, `merged: [WorkoutOriginal]` (`@DefaultEmpty`), `notes: String?`, `origin: String?` and `pauses: [ActivityPause]` (`@DefaultEmpty`). All are optional, so bodies from an older Mac still decode.
- **`ScoreConfig`** gains `sportAliases: [String: String]` (default empty).
- **`ActivityUpload`** gains `origin: String?` and `notes: String?`, encoded only when non-nil. A live upload's body is then byte-identical to before.
- **`APIClient`** gains:
  - `putEdit(id:, _ body: EditBody) async throws -> WorkoutEdit?`;
  - `deleteEdit(id:) async throws`;
  - `heartRate(date:)` and `heartRate(start:end:) async throws -> HeartRateBody`.

  They follow the existing status handling. 400, 404 and 409 map to new `ClientError` cases `.rejected`, `.notFound` and `.conflict`, whose text is §4.3.
- **`EditAPI`** protocol: the edit calls plus `postActivity`. `APIClient` and the Debug `FixtureEditAPI` (§10.2) both conform.

### 9.2 Edit state (GHealthCore, pure, unit-tested)

- **`EditDraft`** is built from a `Workout`, the cached workouts of its cycle date, and a `HeartRateBody`. It holds:
  - the sport (nil = original);
  - the window;
  - the notes;
  - the prior window;
  - the band strips;
  - the merge candidates (§5.6).
- **`EditDraft.body`** produces the PUT body, using null for the sport and window when they equal the original. `hasChanges` compares it with `workout.edit`.
- **`deleteBody`**, **`undoRequest`**, **`mergeBody(candidate)`** and **`restore`** produce the bodies in §2.4–§2.6.
- **`AddDraft`** holds:
  - the four day options and the default day (§2.8);
  - the efforts per day;
  - snapping, `Custom` detection and the hint text;
  - the default window;
  - the POST body.
- Naming a detected effort uses `AddDraft`'s POST builder with the effort's window and `origin: "added"`.

### 9.3 Local ghoops entries

After any successful PUT on `goop-<uuid>`, merge into it, or POST that names an effort, `ActivityController` removes the local entry with that UUID from `activities-local.json`. Otherwise `ActivityMerge` would put the phone's stale or hidden copy back. The pencil is never shown while a local entry is still the one on screen (§2.1 step 1).

### 9.4 Refresh

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §2.5.

After every successful mutation the app:
1. calls `model.refresh()` (the snapshot);
2. bumps `bundleRevision` so day bundles reload;
3. clears the Strain screen's workout caches.

`WorkoutScreen` already re-reads from the bundle.

## 10. Fixtures and Debug launch arguments

### 10.1 Go fixtures (`fixtures/v2/`)

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
- With `--now T`, the same layout is anchored to the latest London 20:30 that is not after T. The verify run uses this so the data is recent (§11.1).

**`edits/`** holds the plaintext books, requests and goldens, all for now `2026-03-12T20:30:00Z`:

| File | Contents |
| --- | --- |
| `book_<state>.json` | the plaintext `{activities, edits}` for each state below |
| `requests/edit.json` | `{"exercise_type":"BOXING","start":"2026-03-10T17:56:00Z","end":"2026-03-10T19:12:00Z","notes":"Sparring, 6 rounds of 3 minutes.","hidden":false,"merge_with":[]}` |
| `requests/merge.json` | the same with `end` `19:38:00Z` and `merge_with: ["7300000000000000102"]` |
| `requests/delete.json`, `requests/undo.json` | `edit.json` with `hidden` true, and `edit.json` again |
| `requests/add.json` | POST Boxing, 2026-03-11 18:04–19:04, `origin: "added"`, id `3f0c0000-0000-4000-8000-0000000000e2` |
| `requests/name.json` | POST Running, 2026-03-12 07:10–07:41, `origin: "added"`, id `3f0c0000-0000-4000-8000-0000000000e1` |
| `snapshot_<state>.json` | the Go-built `snapshot` for each state |
| `heart_rate_tue.json` | `heart-rate --start 2026-03-10T15:05:00Z --end 2026-03-10T20:30:00Z` (−180 min before the first original start, +180 min capped at now) |
| `heart_rate_thu_effort.json` | the span around 07:10–07:41 |
| `heart_rate_day_<date>.json` | `heart-rate --date D` for 2026-03-09 … 2026-03-12 |
| `preview_parity.json` | §8.6 |

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

Goldens are generated by a Go test with the existing `-update-goldens` flag. The diff is reviewed before commit.

`commands/config_show.json` gains `sport_aliases: {}`. `errors/payload_too_large.json` and `errors/conflict.json` are added or updated.

The app bundle copies `fixtures/v2/edits/*.json` to `Fixtures/edits/` in Debug only, through the same `project.yml` build phase that removes `Fixtures` in Release.

### 10.2 Debug launch arguments

- **`-GHealthFixture edit`** is a new `FixtureSet` case. It loads `Fixtures/edits/snapshot_edited.json` with now `2026-03-12T20:30:00Z`, and installs `FixtureEditAPI` in place of the network.
  - `FixtureEditAPI` serves the `heart_rate_*` bodies by request.
  - It answers a PUT, DELETE or POST whose body equals one of the `requests/*.json` files (POST compared without `id`) by switching the cached snapshot to the matching state: `edit` → `edited`, `merge` → `merged`, `delete` → `deleted`, `undo` → `edited`, restore `DELETE` → `unedited`, `add` → `added`, `name` → `named`.
  - Any other request gets 400, so a wrong body fails the UI test loudly.
- **`-GHealthEditFixture <key>`** (with `-GHealthFixture edit`) opens a state directly:

| Key | Opens | Mockup |
| --- | --- | --- |
| `detail` | workout screen for `…0101` on 2026-03-10 (state `edited`) | `edit-detail` |
| `edit` | `detail` with the Edit sheet open | `edit-edit` |
| `sport` | Edit sheet showing the Sport sub-step, Boxing selected | `edit-sport` |
| `merge` | Edit sheet showing the Merge sub-step for `…0102` | `edit-merge` |
| `delete` | Edit sheet scrolled to its end, with the Delete alert shown | `edit-delete` |
| `undo` | state `deleted`, Home on the default date with the Undo banner (no expiry) | `edit-undo` |
| `effort` | workout screen for Thursday's 07:10 detected effort | `edit-effort` |
| `add` | ADD sheet, day 2026-03-11, snapped to 18:04–19:04, no sport chosen | `edit-add` |
| `unedited` | workout screen for `…0101` in state `unedited` (flow-test start) | n/a |
| `offline` | `edit`, but `FixtureEditAPI` fails every request as offline | n/a |
| `alias` | workout screen for `…0101` in state `alias` | n/a |

- **Release builds** must not contain `Fixtures/edits`, `FixtureEditAPI`, `-GHealthEditFixture` or the `edit` fixture set name in a launch-argument context. The Release check is extended (plan E10).

## 11. Tests

### 11.1 Go (through the binary, HTTP and the engine)

**Store:**
- the edits round trip;
- `version` stays 1;
- a file without `edits` reads;
- normalisation removes empty edits;
- retention;
- the goop-delete cascade;
- no plaintext on disk (grep the state dir for the notes text and get no match).

**POST:**
- `origin` and `notes`;
- `added` with `live` rejected;
- the 30-day bound;
- a body without the new fields is byte-identical in replay (200).

**PUT and DELETE edits:**
- 200, and a replay giving the same `updated_at`;
- each 400 field in §6.2;
- 404 for an unknown id and for an id outside the horizon;
- 409 for each conflict cause;
- 413;
- 405 with `Allow`;
- a query string giving 400;
- a wrong content type;
- DELETE 200 then 404;
- auth;
- logs without bodies.

**Rules (§5.5–§5.6) through the engine:**
- sport, window and notes;
- alias, and edit over alias;
- hidden excluded from `workouts`, `day.workouts`, `days` counts, `brief` and `strength_minutes`;
- recorded + recorded merge, recorded absorbs goop, goop absorbs recorded, extension over a detected effort;
- restore unmerges;
- a deleted entry neither reappears as an effort nor brings back a band record;
- an absorbed entry never hides its absorber;
- `cycle_date` moving across a cycle start;
- `active_minutes` null when edited;
- Day Strain unchanged in every case.

**`heart-rate`:**
- both forms;
- each error;
- rates per cycle (a past day uses that day's resting HR);
- CLI and HTTP bodies the same.

**Config:**
- `set`/`unset sport_alias.X`, each invalid case, and `show`;
- the server picking up a change without restart.

**Goldens:** `fixtures/v2/edits/*` and `preview_parity.json`.

### 11.2 GHealthCore (`make ios-core-test`)

- Decoding the new workout fields, and an older body without them.
- `score_config.sport_aliases`.
- `WindowEstimator` parity with `strain.json` and `preview_parity.json`, plus `LiveEstimator` still passing after the shared `StrainMath`.
- `EditDraft`:
  - body nulls when equal to the original;
  - `hasChanges`;
  - delete and undo bodies with and without a stored edit;
  - the merge body;
  - merge candidates (next, previous, the 15-minute gap, kinds, same cycle date);
  - notes trimming and the 500 cap.
- `AddDraft`:
  - day options and default day;
  - effort snapping, `Custom`, `None found` and the hint text;
  - the default window today and on a past day;
  - the POST body.
- The time-picker mapping (§8.5) across midnight.
- Client tests:
  - `putEdit` 200 with an edit and with null;
  - `deleteEdit` 200 and 404;
  - `heartRate` both forms;
  - 400, 404 and 409 mapped to the new errors.
- `ActivityMerge` after removing a local entry.

### 11.3 UI (XCUITest, fixture mode)

- **`testEditFlow`.** Launch with `edit` + `unedited`:
  1. detail;
  2. pencil;
  3. Sport;
  4. search `box`;
  5. BOXING;
  6. USE BOXING;
  7. drag `edit-handle-start` left and assert DURATION changed and its prior shows `0:57`;
  8. type the note;
  9. SAVE BOXING;
  10. assert `· Edited`, `workout-notes` and `workout-edited-footnote`;
  11. pencil, RESTORE, alert Cancel, then Restore;
  12. assert no `· Edited`.

  `FixtureEditAPI` asserts each body.
- **`testEditMergeDeleteUndo`.** Launch with `edit` + `detail`:
  1. pencil;
  2. MERGE WITH NEXT;
  3. MERGE INTO ONE BOXING;
  4. assert the end is 19:38;
  5. pencil;
  6. DELETE, alert Cancel, then Delete;
  7. Home with `Boxing deleted.`;
  8. UNDO;
  9. the banner is gone and the row is back.
- **`testNameEffortAndAddPast`.**
  1. Launch with `effort`.
  2. Pencil, and the Sport sub-step is showing.
  3. RUNNING, USE RUNNING, SAVE RUNNING.
  4. Assert the subtitle `· Added in ghoops`.
  5. Back to Home, START ACTIVITY, PAST, `add-day-2026-03-11`.
  6. Assert the effort row `18:04 to 19:04`.
  7. ADD BOXING, and the workout screen shows.
- **`testEditScreensTour`.** Captures `edit-detail` (+ `-2`, `-3` scrolled), `edit-edit` (+ `-2`), `edit-sport`, `edit-merge`, `edit-delete`, `edit-undo`, `edit-effort` (+ `-2`), `edit-add`, `edit-offline` and `edit-alias`.
- **Existing tests.**
  - `testAccessibilityTour` adds the Edit sheet at accessibility 5.
  - `testActivityScreensTour` re-captures `activity-b` with the LIVE/PAST selector. The comparison note records that difference.
  - `testActivityFlow` still deletes a pending entry from the page button.
- **Full suite:** only `testBackgroundRefreshProbe` is skipped.

## 12. Decisions made in this spec

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §15.

1. **Data model.**
   - Overrides keyed by workout id live in `activities-v2.enc` as an `edits` array, at version 1. One file and one lock make merges and hides atomic. Older readers ignore the key.
   - Overrides also apply to ghoops entries, so edit, hide and undo work the same for both kinds. The uploaded record stays immutable and the phone's POST replay stays idempotent.
   - Restore deletes the override, which also unmerges.
2. **Detected efforts are named by POSTing a ghoops activity** (`origin: "added"`), as proposed. The existing step 4 hides the effort, and no override is keyed on the unstable `effort-<start>` id. PUT rejects `effort-` ids.
3. **Merge.**
   - The entry being edited absorbs one adjacent entry within 15 minutes. Its window becomes the union, so the minutes between count, as the mockup says. The absorbed id is recorded in `merge_with` and hidden. This works for two band records and for a ghoops entry with a band record, in either direction.
   - A detected neighbour is merged by extending the window.
   - Merge saves at once, because its commit is the final action shown.
4. **Add past** uses the existing POST with `origin: "added"`. The POST bound moves from 7 to 30 days so every day in the edit horizon passes.
   - PAST offers the four cycle dates ending today, the most a `GoopRangeSelector` holds and what the mockup shows.
   - Untracked efforts come from the cached snapshot (14 days), so no extra request is needed beyond heart rate.
5. **Preview data** comes from a new read, `GET /v2/heart-rate`, rather than more points in the workout payload:
   - the snapshot stays small;
   - Add past needs whole days anyway;
   - the body carries the cycle's own resting and maximum heart rate, so past-day previews are right.

   The phone fetches ±180 minutes (the edit bound) once and shows ±30 minutes.
6. **API.**
   - `PUT/DELETE /v2/edits/<id>` with full-replace PUT semantics, which makes it idempotent with no 409 for replays.
   - 409 is reserved for merge-graph conflicts.
   - CLI parity is `activity edit|merge|hide|unhide|restore|edits` and `heart-rate`.
7. **Undo** sends the stored edit back with `hidden: false`, or DELETE when there was none, from a 10-second Home banner. Deletes from the sheet are hides, so they can be undone.
8. **Sport alias** is `sport_aliases` in config, set with `ghoops config set sport_alias.KICKBOXING BOXING`. It is applied at read time to every band record, past and future, echoed in `score_config`, and overridden by per-activity edits.
9. **Offline.** Edits are refused, not queued.
   - The preview cannot be computed without the Mac.
   - Edits are validated against Mac state (band windows, merges).
   - The Start Activity queue handles self-contained uploads only.

   This is the simpler option, and it fits.
10. Hidden entries keep suppressing detected efforts and still hide band records they overlap. Deleting something removes it, and nothing else appears in its place. **Owner confirmed 2026-11-12.**
11. The edit horizon is 30 days, and the pencil is hidden on older activities. **Owner confirmed 2026-11-12.**
12. On the detail page, `Fitbit says` is hidden once edited, and the coverage line shows only below 80 %, to match the approved renders. Default accepted.
13. Detected efforts have no Delete or Restore in the sheet. They can only be named (§13). **Owner confirmed 2026-11-12.**
14. Restore asks for confirmation, because it discards notes and merges. The mockups do not show that alert. It uses the existing system-alert pattern.
15. The page-level DELETE ACTIVITY remains only while a phone estimate is shown. Elsewhere Delete is in the Edit sheet.

## 13. Out of scope

Superseded by [instant-saves-spec.md](instant-saves-spec.md) §3.

- Writing anything to Google, or any change to the OAuth scopes.
- Dismissing or deleting a detected effort without naming it. Its id is not stable enough to key an override on.
- Splitting one activity into two. Editing pauses of a ghoops session (pauses are kept and clipped).
- Undo beyond the 10-second banner on the phone (the Mac's `activity unhide` covers it).
- Merging more than one neighbour in one step (repeat the merge).
- Sport alias management on the phone.
- Editing activities older than the 30-day horizon.
- Calories, distance, GPS and the provider's own figures for edited windows.
- Queuing edits offline.
- Home row markers for edited activities (owner decision 4).
