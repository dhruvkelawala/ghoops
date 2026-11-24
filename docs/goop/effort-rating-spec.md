# ghoops: rate how hard each session felt (issue #28)

Status: final. The lead approved it on 2026-11-22 (§13). Build R1 to R4 dark; R5 waits for the owner's mockup approval, R6 for 14 rated sessions in one category. Written 2026-11-22 against `main` at `b99a4e9`. #18 (ADD and START) has landed. The build plan is [effort-rating-plan.md](effort-rating-plan.md). The mockup is [mockups/effort-rating.html](mockups/effort-rating.html), rendered per screen in `mockups/screens/effort-rating-<key>.png`.

The owner rates a session 0 to 10 after it ends. ghoops stores the rating on the Mac beside the session and shows it on the workout page. **Nothing uses it yet.** Strain, every score and `score_version` stay as they are. Once enough sessions are rated, a later check compares Strain with the ratings, by category (§9).

[strain-model-research.md](../v2/strain-model-research.md) §4 and §7 give the reason. No public method fixes Strain for lifting or boxing from heart rate alone. The one validated check that needs no reference device is a 0 to 10 rating of the whole session (Foster's session RPE).

**Mockup keys.** Example values in the style of the test data.

| Key | Screen |
| --- | --- |
| `ask` | Right after END BOXING: the workout page opens and the rating sheet opens over it, nothing chosen |
| `chosen` | The same sheet with 7 chosen; `SAVE RATING` is enabled |
| `rated` | The workout page after saving: `HOW HARD IT FELT` reads `7 · Very hard` |
| `unrated` | A band-recorded session nobody rated: the row reads `Rate` |

## 0. Precedence and decisions

This spec extends [contract.md](../v2/contract.md) §3, §5.8, §5.11 and §7.2, [data.md](../v2/data.md) "ghoops activities", [instant-saves-spec.md](instant-saves-spec.md) and [DESIGN.md](../../DESIGN.md). Where they disagree, this spec wins for ratings.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | A rating is a whole number from 0 to 10 on Foster's modified CR-10 scale, shown with Foster's words. | The research's check is built on it ([S14] in the research). Garmin and Apple both use 1 to 10; Foster's 0 means rest. |
| D2 | The rating is optional. A session always saves without one, and nothing waits for it. | Owner default for tonight. |
| D3 | It feeds nothing now: no score, no Strain, no recompute, no `score_version` change, nothing in `brief`. | Garmin says the same of its rating: it does "not feed into training or performance metrics" [garmin]. The check in §9 decides whether anything should change. |
| D4 | The Mac stores ratings in `activities-v2.enc`, in a new `ratings` array keyed by workout id. It is separate from activity edits. | A rating describes how the session felt, not the band's record. RESTORE BAND'S VERSION keeps it. The edit PUT and its `if_updated_at` stay as they are. An app build that predates ratings cannot wipe one by saving an edit. |
| D5 | Where: a `HOW HARD IT FELT` row on the workout page of every recorded and ghoops session, which opens the rating sheet. | One sheet and one entry point. The sheet needs no heart-rate read, so it works when the Mac can't be reached. Apple changes a rating from the workout summary [apple]. |
| D6 | Asked once: right after END and right after ADD, the workout page opens as today and the rating sheet opens over it by itself. × skips. Nothing asks again: no banner, badge or reminder. | Apple asks when the workout ends [apple]; Garmin asks after the workout [garmin]. The issue says "ask once, never nag, allow skipping". |
| D7 | The Edit sheet and the ADD sheet don't change. | The issue suggested both. The workout page row covers editing, and asking after ADD covers adding. Adding a row to both sheets would give one value three entry points. |
| D8 | Ratings use the edit horizon: the Mac's edit lookup and `horizon_days`. Outside it, the row shows a stored rating without a chevron, and an unrated session shows no row. | No new limit. Recall of an old session is not a valid rating anyway. |
| D9 | `status.edit_limits.rpe_scale` (`"cr10"`) names the scale. The app offers ratings only when it is present. | It tells the app the Mac takes ratings and which words belong to the numbers. An older Mac omits it. |
| D10 | Detected efforts can't be rated: their ids change. Naming one makes a ghoops session, which can. | Same reason activity edits refuse `effort-` ids. |
| D11 | The app can change a rating but not remove it. The CLI removes one. | A wrong tap is fixed by choosing again. Removing is rare; it doesn't earn a button. |
| D12 | No precondition: the last write wins. | One value with nothing to merge. A replayed PUT sets the same value. |
| D13 | The UI ships dark behind `GoopFeature.effortRating`. The Mac route and the CLI land first, unflagged. | AGENTS.md: unfinished features ship dark; routes may land early. |

Rejected:
- **`rpe` inside the activity edit.** RESTORE would wipe the rating, and a PUT from an older app build, which never sends `rpe`, would too.
- **`rpe` in the ADD POST body.** A ghoops session would then hold its rating in two places.
- **A rating row inside the Edit and ADD sheets.** Both need the Mac's heart rate to open (§1).
- **A slider or a strip of 11 numbers.** DESIGN.md has no slider ("Not in the system: toggles, steppers and sliders"). Eleven cells across 358 pt are 30 pt wide, under the 44 pt minimum.
- **Borg's 6 to 20 scale.** WHOOP's Strain scale is "inspired by" it [whoop-strain], but session RPE is validated on CR-10.
- **Garmin's second question** ("how you felt", a smiley [garmin]). The check doesn't need it.
- **Zone colours on the rows.** They mean heart-rate zones only (The Score Owns Its Colour Rule).

## 1. Facts this design relies on

Line numbers are at `b99a4e9`. `A/` is `ios/GHealth/`, `C/` is `ios/GHealthCore/Sources/GHealthCore/`.

- **END opens the workout page.** `ActivityController.finish()` calls `onSaved`; `AppModel.configureActivity()` (`A/App/AppModel.swift:140-148`) waits 350 ms, then pushes `.workout(id: "goop-<id>", date:)`.
- **ADD opens the workout page.** `AddActivitySheet.add()` (`A/Live/AddActivitySheet.swift:131-143`) submits the change, dismisses and pushes `.workout(id: "goop-<draft.id>", date:)`.
- **The Edit and ADD sheets need the Mac to open.** Both load heart rate first, and show `Needs a connection to your Mac` when they can't (`A/Edit/EditSheet.swift:79`, `:142-164`; `AddActivitySheet.swift:80`, `:119-130`).
- **Live uploads go before queued changes.** `ChangeQueue.drain` calls `uploads()` before it sends any change (`C/Changes/ChangeQueue.swift:58`). The queue sends changes in order. A rating on a session that is still uploading waits behind the upload.
- **Locks.** `lockedWorkouts` is every target of a pending change (`A/App/InstantChanges.swift:6`). A locked local session is replaced by its change's patch on screen (`InstantChanges.swift:35`).
- **The store writes named arrays.** `Store.save` rebuilds the file from `Activities`, `Edits` and `SleepEdits` (`internal/activities/activities.go:233-255`). A new array has to be added there, or the next write drops it.
- **The edit lookup.** `Engine.EditTarget` (`internal/score/edits.go:35-51`) finds a recorded or ghoops entry whose original `cycle_date` is inside the horizon. 404 otherwise.
- **The engine gets the book in five places**: `internal/cli/read_v2.go:34`, `internal/serve/server.go:196`, `internal/cli/edit.go:74` and `:103`, `internal/cli/sleep_edit.go:85`, plus the two edit routes (`internal/serve/edits.go:73`, `sleep_edits.go:73`).
- **`GoopChoiceRow`** (`A/Components/Goop/GoopTaskSheet.swift:64-83`) leads with an SF Symbol in a 34 pt slot. Sport and effort lists stack these rows with no gap.

## 2. What others do

| App | When it asks | Scale and words | Can you change it? | Does it feed a score? |
| --- | --- | --- | --- | --- |
| **Garmin** (watch self evaluation) [garmin] | After a completed workout, on some activity profiles | 1 to 10 "how hard the workout was", then a smiley for how you felt | Uploaded "as part of the activity" | "do not feed into training or performance metrics" |
| **Apple Watch** [apple] | When you tap End: "Turn the Digital Crown to indicate your effort, then tap Done" | 1 to 10, grouped Easy, Moderate, Hard and All Out [sun] | "tap Effort, then make a change" in the summary | Yes, Training Load (the formula isn't published) |
| **WHOOP** [whoop-rpe] | Doesn't ask. Its articles explain RPE and say Strain replaces it. | Strain's 0 to 21 is "inspired by" Borg's 6 to 20 [whoop-strain] | — | — |
| **Oura** | No public description of a session rating was found. | — | — | — |
| **Foster's session RPE** [haddad] | About 30 minutes after the session (research [S18]) | 0 Rest, 1 Very, very easy, 2 Easy, 3 Moderate, 4 Somewhat hard, 5 Hard, 7 Very hard, 10 Maximal; 6, 8 and 9 have no word | — | Rating × minutes is the session load |

**Borrowed:** Apple's moment (at the end) and its way back (from the session's page); Garmin's promise that the rating changes no metric; Foster's numbers and words. ghoops asks at the end rather than 30 minutes later, because that is when the phone is in hand. A rating can be changed for as long as the session can be edited.

## 3. The app

### 3.1 The row on the workout page (`rated`, `unrated`)

A `GoopRow`, 16 from the screen edges, 14 below the `MAX HR` / `DURATION` line and 8 above the zone rows. Id `workout-rating-row`.

| Session | Row |
| --- | --- |
| Rated, inside the horizon | `HOW HARD IT FELT`, value `7 · Very hard` (`GoopRowValue`), chevron. Tap opens the sheet. |
| Unrated, inside the horizon | `HOW HARD IT FELT`, value `Rate` in `bodySmall` `text2` (as ADD's `Choose`), chevron. |
| Rated, outside the horizon | The value, no chevron, not a button. |
| Unrated, outside the horizon | No row. |
| Detected effort; a live session the Mac refused; flag off; no `rpe_scale` | No row. |

A session still uploading after END can be rated: its row shows, and the change waits behind the upload (§1). A pending change on the session doesn't lock the row, unlike the pencil: a rating has no precondition, and the queue sends changes in order. (Found in R3: the ADD change is still pending when the ask opens, so a lock would hide the sheet whenever the Mac can't be reached.)

- The value is words with a number inside, so it is Nunito (The Two Voices Rule). For 6, 8 and 9 the value is the number alone.
- The row sits above the zones so it is on the first screen, next to the Strain it will be checked against.
- VoiceOver: "How hard it felt, 7, very hard. Button." Unrated: "How hard it felt, not rated. Button."

### 3.2 The rating sheet (`ask`, `chosen`)

A `GoopTaskSheet` titled `HOW HARD IT FELT`, × on the right (`rating-close`), large detent, grabber. Container id `rating-sheet`. From the top:

1. **Prompt**, `bodyMid` `legendText`, 4 below the header: `How hard was the whole session?`
2. **Eleven rows**, 12 below, 0 at the top to 10 at the bottom, no gap: `GoopChoiceRow` with a number in place of the symbol (§6). Number in Sofia `valueRow` (23), `textSoft`, or `strainLight` when selected. Title: Foster's word in uppercase (`REST`, `VERY, VERY EASY`, `EASY`, `MODERATE`, `SOMEWHAT HARD`, `HARD`, `VERY HARD`, `MAXIMAL`). Rows 6, 8 and 9 have no title. No note. Ids `rating-0` … `rating-10`.
3. **Footnote**, `bodySmall` `text2`, 16 below the rows: `Your rating stays on your Mac. It doesn't change Strain.`
4. **Commit**, pinned: `checkmark` + `SAVE RATING` (`rating-save`). Disabled at 40% until a row is chosen and differs from the stored rating.

The stored rating, if any, is selected when the sheet opens. Tapping a row selects it; tapping the selected row keeps it. The eleven rows (572 pt) fit without scrolling at the default text size on a 6.1-inch phone; at larger sizes the content scrolls as every task sheet does.

× or a swipe closes without saving and without a question.

### 3.3 Asking once (`ask`)

- `AppModel` gains `ratingPrompt: String?`, a workout id held in memory only.
- It is set when END saves a session (`activity.onSaved`) and when ADD submits, just before the push, if the flag is on and `edit_limits.rpe_scale` is `"cr10"`.
- `WorkoutScreen`, on appear, finds `ratingPrompt == id`, clears it and opens the sheet after the push settles (350 ms, as the push itself waits).
- Nothing else sets it. Naming a detected effort, editing, merging and opening a session from Home or Strain never ask. A relaunch never asks. Band-recorded sessions are never asked; their row is the way in.

### 3.4 Saving

A rating is one more change in the pending-changes queue (instant-saves-spec §2).

| Moment | Screen |
| --- | --- |
| Tap `SAVE RATING` | The sheet closes. The row shows the new value at once. |
| Saving (after 0.6 s) | The Home row shows `SAVING`, as for any change on that session. |
| Waiting | The workout page shows the existing strain banner, `Saved on your phone. It will be sent to your Mac when it can be reached.` (`change-waiting-banner`). Home shows `WAITING FOR MAC` and its waiting banner. |
| Settled | The Mac's body replaces the overlay. Nothing else changes: no score is `UPDATING`, because none depends on the rating. |
| Refused | The old value comes back with a `NOT SAVED` banner (§3.5). |

- **Kind** `rate`. **Request** `PUT /v2/ratings/<id>` with `{"rpe": n}`. **Targets** `[id]`. **`cycleDates`** `[cycle_date]`. **Patch** upserts the displayed workout with `rpe` set; `updating` is empty.
- **Replays are safe.** The same PUT twice stores one rating.

### 3.5 Errors, in ghoops' own words

| Case | What the owner sees |
| --- | --- |
| The Mac refuses (400) | `NOT SAVED`: `Your Mac couldn't save your rating for Boxing. It's back as it was.` |
| The session is gone or outside the horizon on the Mac (404) | `NOT SAVED`: `Boxing changed on your Mac. It's back as it was.` (the existing default sentence) |
| The Mac can't be reached | The change waits (§3.4). |
| The phone can't write its waiting changes | #24's `ErrorCopy` with a new `Save rating` context, inside the sheet: `ghoops couldn't save your rating on this phone. Try again.` The sheet stays open. |

Banners follow instant-saves §6: `change-rollback-banner` on the page, `change-rollback-banner-<n>` on Home.

### 3.6 Accessibility

- Rows: "7, very hard"; "6"; selected rows add the selected trait, as every `GoopChoiceRow`.
- At accessibility sizes the rows grow with their text, and the sheet scrolls. The row on the workout page wraps its value under the label as `GoopRow` does.
- `testAccessibilityTour` adds the sheet at AX5.

## 4. The Mac

### 4.1 Data model

`activities-v2.enc` gains a top-level array. `version` stays 1.

```json
"ratings": [ { "id": "7300000000000000101", "rpe": 7, "updated_at": "2026-03-12T09:00:00Z" } ]
```

| Field | Type | Rule |
| --- | --- | --- |
| `id` | string | A recorded id or `goop-<uuid>`. One rating per id. |
| `rpe` | int | 0 to 10. |
| `updated_at` | Time | Set on write. A PUT with the stored value changes nothing and writes nothing. |

- **Applies** when the id is a visible workout. A hidden, absorbed or missing entry keeps its rating stored and ignored (an orphan). Restoring or unmerging brings it back with its rating.
- **Merge** doesn't move ratings. The absorber shows its own.
- **Permanent delete** of a ghoops activity removes `goop-<uuid>`'s rating, in the same write that removes its edit.
- **Retention.** Dropped 400 days after `updated_at` on the next write, as edits.
- **Lock.** Written under `activities.lock`, atomically with the rest of the file. `collect` never touches it.
- **Older binaries.** A Mac binary from before this change rewrites the file without `ratings`, so rolling the Mac back loses them. Install the Mac forwards only.

### 4.2 The workout object (contract §5.8)

A new field on every workout object, in `day.workouts`, `snapshot` and `workouts`, after `notes`:

| Field | Type | Rule |
| --- | --- | --- |
| `rpe` | `int?` | The stored rating for this id; null when none, and always null for detected entries. |

`brief` doesn't change. No score reads `rpe`.

### 4.3 `status.edit_limits` (contract §5.11)

| Field | Type | Rule |
| --- | --- | --- |
| `rpe_scale` | string | `"cr10"`: `rpe` is a whole number from 0 to 10 on Foster's modified CR-10 scale. Added 2026-11-22; absent on older Macs, and then the app offers no rating. |

The range is schema, like Strain's 0 to 21, so the app may hold it. `ReportedLimits().RPEScale` is the constant `RPEScale = "cr10"` in `internal/activities`, beside `RPEMin = 0` and `RPEMax = 10`.

### 4.4 Routes

**`PUT /v2/ratings/<id>`.** Bearer authentication, `application/json`, at most 64 KiB, no query string. Body `{"rpe": 7}`; unknown keys are ignored.

| Check | Result |
| --- | --- |
| `id` empty, holds `/`, or starts with `effort-` | 400 `invalid_request`, `Invalid edit field: id.` |
| body not a JSON object | 400, field `body` |
| `rpe` missing, null, not a whole number (`7.5`, `"7"`), below 0 or above 10 | 400, field `rpe` |
| `id` not found by the edit lookup (§1): not a recorded or ghoops entry, or its original `cycle_date` outside the horizon | 404 `not_found` |
| the stored rating already has this `rpe` | 200 with the stored rating, `updated_at` unchanged |
| otherwise | stored; 200 |

`7.0` counts as a whole number. Response 200: envelope, `kind: "rating"`, `id`, `rating: {id, rpe, updated_at}`.

**`DELETE /v2/ratings/<id>`.** 200 with `rating: null`; 404 when none is stored. No lookup and no horizon, as `DELETE /v2/edits/<id>`. A body is `invalid_request`.

**Transport.** `/v2/ratings/<id>` takes `PUT` and `DELETE`; a 405 sets `Allow: PUT, DELETE`. `/v2/ratings` and `/v2/ratings/` are `not_found`. Logs carry method, path, status and duration only.

The phone refreshes after a 200 as for edits. The response carries no recomputed scores, since none change.

### 4.5 CLI

Same code path as HTTP, schema-2 JSON, `kind: "rating"`:

| Command | Effect |
| --- | --- |
| `ghoops activity rate --id ID --rpe N` | As PUT. |
| `ghoops activity rate --id ID --clear` | As DELETE. |

Exactly one of `--rpe` and `--clear`, else usage exit 2. `ghoops workouts` shows `rpe` on every row, so no list command is added.

## 5. GHealthCore

- **Models.** `Workout.rpe: Int?`. `EditLimits.rpeScale: String?`. Both decode as nil from an older Mac.
- **`EffortScale`** (`C/Edit/EffortScale.swift`, pure):
  - `supported(_ limits: EditLimits?) -> Bool`: `rpeScale == "cr10"`;
  - `values`: `0...10`, the CR-10 range (schema; a lint allow marker names contract §5.11 if `enginenumber` flags it);
  - `word(_ rpe: Int) -> String?`: Foster's word, nil for 6, 8 and 9;
  - `rowValue(_ rpe: Int) -> String`: `7 · Very hard`, or `6`;
  - `spoken(_ rpe: Int) -> String`: `7, very hard`.
- **Requests.** `RatingBody {rpe: Int}`. `EditAPI.putRating(id:_:)`, in `APIClient` and `FixtureEditAPI`. The app sends no DELETE.
- **Changes.** `PendingChange.Kind.rate`; `Request.putRating(String, RatingBody)`; `ChangeBuilder.rate(_ workout:, rpe:, serverURL:, now:)` builds §3.4's change. `RollbackNotice.text` for `.rate`: the 404 sentence is the default one; any other refusal is `Your Mac couldn't save your rating for <name>. It's back as it was.`
- **Errors.** `ErrorCopy.Context.saveRating`: `ghoops couldn't save your rating on this phone. Try again.`

## 6. DESIGN.md changes

Plan step R3 applies these word for word.

1. **Components → Modal.** After `` `SleepEditSheet` (EDIT SLEEP task sheet) `` add `` `EffortRatingSheet` (HOW HARD IT FELT task sheet) ``.
2. **Form rows and pickers → Task controls.** After the `GoopChoiceRow` sentence ending "Unselected rows have a `contributorBorder` hairline." add:

   > A choice between numbers, such as the effort rating, puts the number in the symbol slot in Sofia `valueRow`, `textSoft`, or `strainLight` when selected, with the number's word as the title.

No rule changes. The rating uses a task sheet, choice rows, a `GoopRow` that opens a sheet and the existing pending states.

## 7. Fixtures

- **Book** `fixtures/v2/edits/book_rated.json`: `book_edited.json` plus `ratings: [{id: "7300000000000000101", rpe: 7, updated_at: "2026-03-12T09:00:00Z"}]` (the edited Boxing on 2026-03-10).
- **Golden** `fixtures/v2/edits/snapshot_rated.json`: `snapshot` over `store_edit` with that book. Boxing 101 has `rpe: 7`; every other workout has `rpe: null`.
- **Every golden** with a workout object gains `"rpe": null`; every golden with `edit_limits` gains `"rpe_scale": "cr10"`. No value changes, and `score_version` stays.
- **Requests.** `fixtures/v2/edits/requests/rate.json` is `{"rpe": 7}`. The refused rows of §4.4 are table tests in Go (`internal/activities`, `internal/serve`), because some of them, such as a body that isn't JSON, can't be stored as JSON files.
- **App.** The edit fixture takes two more keys (built in R3 in place of a separate launch argument): `-GHealthFixture edit -GHealthEditFixture rated` loads `snapshot_rated` and opens Boxing `7300000000000000101`; `ask` opens Kickboxing `7300000000000000102` (2026-03-10, unrated) and opens the sheet as after END. Waiting and refusal use `-GHealthMutationMode offline` and `reject-400`. Seeded `-GHealthLiveFixture ended_*` sessions don't ask: only a real END does.

Every value is synthetic.

## 8. Tests

The plan lists each with its step. In summary:

- **Go.** Every row of §4.4; replay without a write; DELETE and 404; transport (405 with `Allow`, query, trailing slash); horizon; a hidden entry's rating is kept and not shown; permanent delete removes a ghoops rating; retention; `save` keeps `ratings`; CLI and HTTP give the same body; the goldens.
- **GHealthCore.** `EffortScale` words and values; decoding against an older Mac (`rpe` and `rpe_scale` nil); the `rate` change: patch, lock, settle, both rollback sentences.
- **UI.** The row's four states; the sheet; asking after END and after ADD, and not after a relaunch; waiting and refusal; AX5. The full suite passes with its one skip by design.

## 9. Later: checking Strain against the ratings

Not built in this plan's first five steps. Step R6 builds it once the owner has rated at least 14 sessions in one category, the number the research gives for detecting r 0.7.

**`ghoops strain check [--days N]`** (default 180, at most 400), `kind: "strain_check"`. It reads `workouts` over the range and prints counts and coefficients only, never a session, a time or a value:

| Field | Meaning |
| --- | --- |
| `categories` | For `combat`, `strength`, `walking`, `cardio`, `other`: `{rated, needed_r07: 14, needed_r05: 30, rho_load, rho_intensity}` |
| `rho_load` | Spearman's ρ of `rpe × active minutes` against `trimp`, 2 dp; null under 5 rated sessions |
| `rho_intensity` | Spearman's ρ of `rpe` against `trimp / active minutes`, 2 dp; null under 5 |
| `walks_rated_3_plus_strain_under_1` | A count. Walks the owner rated 3 or more that scored under 1 Strain: the floor cliff of #29 on real sessions. |

- **Why both.** `rpe × minutes` and TRIMP both grow with duration, so `rho_load` is partly minutes against minutes. `rho_intensity` removes that (research §7, "Two traps").
- **What it can't show.** Neither number tests `StrainK` or `StrainTrimpCap`, because any increasing map keeps the same order (research §7).
- **What a gap leads to.** A low `rho_intensity` for `strength` with high ratings would show the resistance gap of research §4 on the owner's own data. The answer would be a separate spec, for example a strength add-on. The research recommends none until the data shows the gap. For walking: on 2026-11-22 the lead kept the floor's cliff (#29) and will review it if the ratings show walks ranked wrongly against how they felt. Walking's `rho_intensity` and the count above are that evidence.
- **Who runs it.** The lead, as a counts-only read under AGENTS.md. Its output carries counts and coefficients only, so it can be recorded in `acceptance.md`.

The 14 and 30 are the research's power numbers (80% power, two-sided 5%), not engine numbers; they appear only in this CLI body.

## 10. Owner questions

1. **Approve the mockup** ([effort-rating.html](mockups/effort-rating.html)) before the flag goes live. The build runs dark until then.
2. **Agree to rate sessions.** The check needs about 14 rated sessions per category before it says anything.

## 11. Decisions for the lead

Each is written into the spec as recommended. **(lead?)** marks the ones to check.

1. **The workout page row replaces rows in the Edit and ADD sheets** (D5, D7). **(lead?)** The issue listed the Edit sheet and the ADD sheet. The alternative adds a `HOW HARD IT FELT` row to both, which needs the Mac to open either sheet and a second place for the value.
2. **Ask after ADD as well as after END** (D6). **(lead?)** Two sheets in a row after ADD (the ADD sheet, then the rating). The alternative asks after END only and leaves ADD to the row.
3. **A separate `ratings` array, not a field on the edit** (D4).
4. **Ratings follow the edit horizon** (D8).
5. **No remove button in the app** (D11).
6. **`rpe_scale` in `edit_limits`** as the sign that the Mac takes ratings (D9).
7. **The row sits above the zones** (§3.1), not with the notes at the bottom.

## 12. Open questions

1. **Asking 30 minutes later**, as Foster does, would need a notification. Not built; the rating can be changed for 30 days.
2. **Band-recorded sessions are never asked** (§3.3). If the owner mostly records boxing on the band, few sessions get rated. A counts-only read of `rpe` against `kind` after two weeks shows whether that happens.

## 13. Lead review (2026-11-22)

The lead approved the spec at `1d703fe` and accepted both §11 calls marked **(lead?)**: the `HOW HARD IT FELT` row on the workout page instead of rows in the Edit and ADD sheets, and one ask after ADD as well as after END. Build R1 to R4 dark, one commit each. R5 waits for the owner's approval of the mockup; R6 waits for the rated sessions. Neither is built tonight.

## Sources

Retrieved 2026-11-22.

- **[garmin]** Garmin Support. "What Is the Self Evaluation Feature on My Garmin Watch?" https://support.garmin.com/en-US/?faq=8nISJXqSZVAI3Td4IWRqsA
- **[apple]** Apple Support. "Start a workout on Apple Watch", section "Rate your effort". https://support.apple.com/guide/watch/start-a-workout-apdd16e8761a/watchos
- **[sun]** Sun Apps. "Apple Watch Effort Score vs METs". https://www.sun-apps.com/en/blog/apple-watch-effort-score-vs-mets. Search excerpt only: "grouped as Easy, Moderate, Hard and All Out".
- **[whoop-rpe]** WHOOP. "Perceived vs Objective Strain: RPE vs WHOOP Strain." 2026-06-15. https://www.whoop.com/us/en/thelocker/perceived-vs-objective-strain-in-the-whoop-population/
- **[whoop-strain]** WHOOP. "How does WHOOP Strain work?" 2026-07-21 (research [S21]). https://www.whoop.com/us/en/thelocker/how-does-whoop-strain-work-101/
- **[haddad]** Haddad M, Stylianides G, Djaoui L, Dellal A, Chamari K. Session-RPE method for training load monitoring. *Front Neurosci* 2017, Table 1, the modified CR-10 scale by Foster et al. (2001) (research [S15]). https://pmc.ncbi.nlm.nih.gov/articles/PMC5673663/
- Research sources [S14], [S15], [S16] and [S18] in [strain-model-research.md](../v2/strain-model-research.md).
