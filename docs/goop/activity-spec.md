# ghoops: Start Activity

Status: design spec, approved by the owner on 2026-11-12. The build plan is [activity-plan.md](activity-plan.md).

ghoops gains a WHOOP-style **Start Activity** flow. The owner picks a sport and taps Start. The phone then shows a live timer, heart rate, zone and an estimated Strain, read from the Fitbit Air over Bluetooth. When the owner ends the activity, the phone saves it to the Mac. The Mac computes the official Strain from the band's heart rate once the band has synced.

## 0. Precedence and owner decisions

- This spec extends [spec.md](spec.md) (ghoops), [contract.md](../v2/contract.md), [scores.md](../v2/scores.md) and [data.md](../v2/data.md). Where they disagree, this spec wins for the features described here. Update those documents as the plan says.
- **Mockups:** [mockups/activity.html](mockups/activity.html). Per-screen renders are in `mockups/screens/activity-a.png` to `activity-f.png`.
  - A: Home with Start Activity, superseded by `add-start-card.png` in [add-start-spec.md](add-start-spec.md) §2.
  - B: START sport picker. This pre-switch render remains valid; add-start-spec §4 adds the eligible target row.
  - C: live screen
  - D: Lock Screen Live Activity
  - E: Home while recording
  - F: saved workout before the band syncs

  The renders use example values. Layout, sizes, colours, type and icons must match.
- **Owner decisions (2026-11-12):**
  1. A finished activity is saved **on the Mac only**. ghoops never writes to Google, and its scopes stay read-only.
  2. The six mockup screens are approved.
- Everything else in this file was decided while writing the spec and is listed in §12.

## 1. Facts this design relies on

- **Live heart rate from the band.** Google documents that the Fitbit Air can share real-time heart rate over the standard Bluetooth Heart Rate Profile. To turn it on: Google Health app → Connections (top left) → the band → **Share heart rate** → **Get started**. Source: support.google.com/googlehealth/answer/14236705, read 2026-11-12. These have not been tested and are recorded on first real use:
  - whether sharing stays on between sessions;
  - whether the band serves ghoops and the Google Health app at the same time;
  - whether the band sends RR intervals.
- **Official values come later.** The Mac sees the band's heart rate only after the band syncs to Google and the 30-minute collector runs. The live numbers are therefore an estimate, and the final Strain arrives later. That is screen F.
- **Workout Strain** is scores.md §3.8 applied to the activity's window. Day Strain already contains those minutes, so a ghoops activity never changes Day Strain.

## 2. User flow

1. **Home (A).** Today's activities card offers equal unfilled **ADD ACTIVITY** and **START ACTIVITY** entry buttons, side by side when both fit and stacked otherwise. The pair follows the default ghoops date, including after midnight. While a session runs, **END <SPORT>** appears alone. Reachable past days offer ADD alone. [add-start-spec.md](add-start-spec.md) §2 fixes availability, layout and identifiers.
2. **START sheet (B).** A `GoopTaskSheet` titled `START ACTIVITY`, with × on the right and no mode switch. From the top:
   1. The heart-rate banner (§4.3), 4 below the header.
   2. The Mac's Day Strain and target, 16 below the banner, when `SessionTarget.make` returns a target (add-start-spec §4.3).
   3. A search field.
   4. `RECENT`: the two most recent distinct sports from the last 30 days of workouts of kind `recorded` or `goop`, each with `Last: <weekday short>`.
   5. `ALL ACTIVITIES`: the list in §2.1, excluding recent sports.

   The first recent sport is preselected; with no history, Boxing is. Tapping a row selects it. The bottom commit is **START <SPORT>**. Starting without live heart rate is allowed (§4.3). ADD has its own task sheet (add-start-spec §3) and never starts Bluetooth.
3. **Live screen (C).** Full screen, presented over the tabs. From the top:
   - **Nav row:** `chevron.down` (minimise), sport symbol and uppercase name, and at the right a connection chip. The chip reads `LIVE` in mint with the antenna symbol while samples arrive, `RECONNECTING` in amber when none have arrived for 10 s, and `NO HR` in grey when started without heart rate.
   - **Elapsed time:** `h:mm:ss`, S 44. Pauses are excluded.
   - **Activity Strain dial:** detail dial geometry scaled to 232/15, with the ghoops wordmark, the live estimate (§5) and the label `ACTIVITY STRAIN`.
   - **Target row:** when the session has a target, EST. DAY STRAIN and TARGET sit below the dial, with a mint checkmark when within. Exact spacing, projection and accessibility: [parity1-spec §2.2](parity1-spec.md#22-live-activity-screen-live-target).
   - **Heart-rate card:**
     - heart symbol in Zone 5 orange, the current bpm in S 46, and `bpm`;
     - at the right, the current zone name in that zone's colour and its bpm range;
     - a 5-segment zone meter: segments 1 to the current zone are filled with their zone colours, and the current segment has a glow;
     - the last 10 minutes of heart rate as an area chart in Zone 4 orange, ending in a dot at `NOW`;
     - three stats: `AVG HR`, `MAX HR` and `ZONES 4–5` (time as `h:mm`).
     - Lost, unknown and missing values follow [live-hr-spec.md](live-hr-spec.md) §4.3.
   - **Controls:**
     - Pause, a 64×58 square: `pause.fill`, which turns into `play.fill` for Resume.
     - **HOLD TO END**: the press fills from the left in `#FD713833` over 1.2 s. Releasing early cancels; completing ends the session with a success haptic.

   While paused, the timer stops, the dial label reads `PAUSED`, and heart rate keeps updating.
4. **Minimise.** `chevron.down` returns to the tabs. Home then shows the live row (E) at the top of TODAY'S ACTIVITIES, and an **END <SPORT>** button replaces START ACTIVITY.
   - The live row has a blue 1.5 pt outline, a gradient fill, the live strain estimate in the value block, the name, `● LIVE · h:mm:ss` and the current bpm at the right.
   - Tapping the live row reopens C. END <SPORT> opens C with the hold control highlighted.
5. **Lock Screen and Dynamic Island (D).** A Live Activity runs from Start to End (§7).
6. **End.**
   - **Too short:** a session with less active time than the Mac's `active_min_minutes` is discarded, and Home shows the banner `Too short to save.` for 4 s. The session takes the limit from the cached snapshot's `status.edit_limits` when it starts. Without it, only a session with no active second is discarded ([live-polish-spec.md](live-polish-spec.md) §3).
   - **Otherwise:**
     1. The phone stores the session locally (§6.3) and sends it to the Mac (§8).
     2. It pushes the workout screen for the new entry (F).
     3. It ends the Live Activity, showing the final state for 15 minutes.
7. **Saved workout (F).** This is the existing workout screen (spec.md §8.5) with these changes:
   - **Subtitle:** `<start> to <end> · Started in ghoops`.
   - **Banner** under the nav, with a blue tint and `arrow.triangle.2.circlepath`. Its text depends on state:
     - phone not yet uploaded: `Saved on your phone. It will be sent to your Mac when it can be reached.`
     - uploaded, band data not in yet: `Live estimate. Final Strain arrives when your band syncs with your Mac, usually within 30 minutes.`
     - final: no banner.
   - **Values:** while the banner shows, the numbers, chart and zones come from the phone's live session (§6.3). Once final, they come from the Mac's workout entry.
   - **Final means:** the Mac's entry exists and its `hr_coverage` is at least 0.80, or the activity ended more than 6 hours ago (then the Mac's values are used whatever their coverage).
   - **Delete:** at the bottom, an outline button **DELETE ACTIVITY** (spec.md §5.25; label and border in `#FD7138`). It shows only for kind `goop`, with an alert "Delete this activity? This removes it from ghoops on your phone and your Mac." Delete/Cancel. Delete calls §8.3 and removes the local session.

### 2.1 Sports

| Label | `exercise_type` | Symbol |
| --- | --- | --- |
| Boxing | `BOXING` | `figure.boxing` |
| Kickboxing | `KICKBOXING` | `figure.kickboxing` |
| Martial Arts | `MARTIAL_ARTS` | `figure.martial.arts` |
| Walking | `WALKING` | `figure.walk` |
| Running | `RUNNING` | `figure.run` |
| Weightlifting | `WEIGHTLIFTING` | `figure.strengthtraining.traditional` |
| Cycling | `BIKING` | `figure.outdoor.cycle` |
| HIIT | `HIIT` | `figure.highintensity.intervaltraining` |
| Yoga | `YOGA` | `figure.yoga` |
| Swimming | `SWIMMING` | `figure.pool.swim` |
| Hiking | `HIKING` | `figure.hiking` |
| Other | `OTHER` | `figure.mixed.cardio` |

The `exercise_type` values are Google's names, so scores.md §3.8 categories apply unchanged. Search matches the label case-insensitively.

## 3. Scope of one session

- Only one session runs at a time.
- Start Activity is unavailable on past days.
- A session ends automatically when its active time reaches the Mac's `active_max_minutes`, or 12 hours after its start, the phone's recording span, whichever comes first. Its end is the moment the limit was reached ([live-polish-spec.md](live-polish-spec.md) §3).
- The Home date control and tabs keep working while minimised.

## 4. Live heart rate (iOS)

### 4.1 Source

There is a `HeartRateSource` protocol in GHealthCore with two implementations:

- **`BluetoothHeartRateSource`** (app target, CoreBluetooth). It uses service `0x180D` and characteristic `0x2A37` (Heart Rate Measurement), subscribing to notifications.
  - **Parsing the flags byte:**
    - bit 0: 0 means the heart rate is a UInt8 at byte 1; 1 means it is a UInt16 little-endian at bytes 1–2;
    - bits 1–2: sensor contact;
    - bit 3: energy expended present (skip 2 bytes);
    - bit 4: RR intervals present (ignore them).
  - **Validity:** a value of 0, or above 250, is dropped. When contact is supported and reports no contact, the sample is dropped.
  - **Parser location:** a pure function in GHealthCore so it can be unit-tested.
- **`FixtureHeartRateSource`** (Debug only). It replays a bundled 1 Hz series and is selected with `-GHealthLiveFixture <name>` (§10).

### 4.2 Finding the band

- **Connecting:** on opening sheet B, scan for peripherals that advertise `0x180D`.
  - If a remembered peripheral is found, connect to it.
  - If exactly one is found, connect to it and remember it.
  - If several are found, list them by name in the banner and connect to the one the owner taps.
- **Remembering:** the remembered peripheral identifier is kept in App Group defaults (`goop.hr.peripheral`).
- **When to scan:** only while B is open or a session is running, with no background scanning otherwise.
- **Background use:** `CBCentralManager` uses restore identifier `io.ghealth.app.hr`, and the app adds `bluetooth-central` to `UIBackgroundModes`, so a running session keeps receiving samples with the screen locked.
- **Info.plist:** `NSBluetoothAlwaysUsageDescription` = "ghoops reads your live heart rate from your Fitbit Air while you record an activity."

### 4.3 Heart-rate banner (sheet B)

The banner is a rounded 12 card: fill is the state colour at 12 %, with a 1 pt outline at 25 %. It has a symbol, a `labelCard` title and a `bodyMid` line.

| State | Colour | Title | Line |
| --- | --- | --- | --- |
| searching | `text2` | `LOOKING FOR YOUR BAND` | `Keep your Fitbit Air close to your phone.` |
| connected | `mint` | `FITBIT AIR CONNECTED` (peripheral name uppercased if it is not a Fitbit Air) | `Live heart rate <bpm> bpm` |
| not found after 10 s | `warn` | `NO LIVE HEART RATE` | `In Google Health, open Connections, choose your Fitbit Air and tap Share heart rate. You can still start; Strain will come from your band later.` |
| Bluetooth off | `warn` | `BLUETOOTH IS OFF` | `Turn on Bluetooth to see live heart rate.` |
| permission denied | `warn` | `BLUETOOTH NOT ALLOWED` | `Allow Bluetooth for ghoops in Settings.` plus a `Settings` link button |

Start is always enabled. Starting without a connection begins the session in `NO HR` mode; it attaches to the band if it connects later.

## 5. Live estimate (GHealthCore, pure)

**Inputs** come from the cached snapshot's `day` for today:
- `strain.resting_hr_bpm` and `strain.max_hr_bpm` (contract §5.4);
- `score_config.trimp_profile`, mapped to `TrimpA/TrimpB` as in scores.md §0.1;
- `StrainK = 10` and `StrainTrimpCap = 700`, mirrored as constants.

**Minutes and TRIMP:**
- Samples are grouped into UTC-minute buckets (scores.md §3.4). Paused spans are excluded.
- A bucket with at least 1 sample is covered, and its value is the mean of its samples.
- TRIMP follows scores.md §3.5 over completed buckets. The current, unfinished bucket adds its contribution × (seconds elapsed in it ÷ 60).
- Strain follows scores.md §3.6, rounded to 1 decimal for display.

**Zones:**
- Zones come from `hrr` (scores.md §3.5); `below` is shown as `ZONE 0`.
- The bpm range of zone k is `ceil(rest + lo_k × (max − rest))` to `ceil(rest + hi_k × (max − rest)) − 1`, using the same `hrr` edges. Zone 5 shows `<lo>+` and Zone 0 shows `<<hi>`. This matches the existing workout zone rows.

**Stats:**
- `AVG HR` is the mean of covered bucket means; `MAX HR` is the highest single sample.
- `ZONES 4–5` counts covered minutes in z4 and z5, with the current bucket pro-rated.

**When rest or max HR is missing:**
- the dial shows `—` with the label `STRAIN NEEDS YOUR MAC`;
- the zone name and range read `—` and the meter is empty;
- heart rate, time, avg and max still show.

**Parity:** fed the minute averages of `fixtures/v2/scores/strain.json` (every case and the `trimp_to_strain` table), the estimator must return the same `trimp`, `strain` and `zones_minutes` as the Go goldens.

## 6. Session model (GHealthCore)

### 6.1 States

```
idle ──start(sport, now)──▶ running ⇄ paused (pause/resume)
running|paused ──end(now)──▶ ended(saved | discardedTooShort)
```

`ActivitySession` holds:
- `id` (UUID, lowercase), `exerciseType`, `displayName`;
- `start`, `end?` and `pauses: [{start, end?}]`;
- the samples: 1 Hz, `[(t, bpm)]` capped at the recording span, `ActivitySession.recordingSpan` (12 h);
- `activeMin?` and `activeMax?`, the Mac's activity length limits taken at start;
- `hrState` (`live`, `reconnecting`, `none`).

Times are wall-clock UTC in whole seconds, as uploads carry them. The elapsed time shown is `(now or end) − start − total paused`.

### 6.2 Persistence while running

- The session is written to `live-session.json` in the App Group container every 15 s and on every state change. The file uses complete file protection, and samples are delta-encoded.
- On launch, a running or paused session in that file is restored, its Live Activity reattached and Bluetooth reconnected.
- A session with no file update for the recording span (12 h) is ended automatically at its last sample time, and one restored past the Mac's maximum ends where it reached it.

### 6.3 After End

The ended session goes into `activities-local.json` in the App Group. It holds:
- the request body of §8.2;
- the live summary: `strain_estimate`, `avg_hr_bpm`, `max_hr_bpm`, `zones_minutes` and a 5 s-resolution HR series;
- `upload_state` (`pending` or `uploaded`).

**Uploading:** the app retries pending entries when it comes to the foreground, on pull to refresh, on background refresh, and 30 s after a failure while active. A 429 keeps the entry pending, ends the pass and defers retries until `Retry-After` has elapsed. If the header has no usable delay, the app waits 30 s. A 409 counts as uploaded. A 401 keeps the entry pending and ends the pass so it can go after pairing again ([pairing-isolation-spec.md](pairing-isolation-spec.md) D5). Other 4xx responses mark the entry `rejected` and F shows `Your Mac could not save this activity.` An entry saved for another Mac waits for that Mac (D4). The first launch after the update resets previously rejected entries to pending once.

**Clean-up:** entries are removed 7 days after `end` once uploaded.

**Pending on Home:** Home rows for pending entries come from this file, with the chip `WAITING FOR MAC` (`labelSmall` `warn`) in place of the times.

## 7. Live Activity (widget extension, ActivityKit)

- **Attributes:** `id`, `exerciseType`, `displayName`, `start`.
- **Content state:** `bpm?`, `zone?` (0–5), `strainEstimate?`, `avgHR?`, `pausedTotal` (seconds), `isPaused` and `hrState`, plus optional `dayStrain`, `targetLow`, `targetHigh` and `targetWithin` (nil without a target; parity1-spec §8.4).
- **Lock Screen (D):**
  - **Top row:** heart (Zone 5 orange) and bpm in S 40 with `bpm`; at the right, a capsule with a stopwatch and the elapsed time. The time is `Text(timerInterval:)` from `start + pausedTotal`, so it counts without updates. While paused it shows a fixed elapsed time with the label `PAUSED`.
  - **Middle:** a zone meter with a white marker at the current zone, and the zone name below it. The label reads `ZONE —` without a zone, `NO HR` without heart rate and `RECONNECTING` when the signal is lost (live-hr-spec §4.1).
  - **Bottom:** `STRAIN` estimate in `strain` blue, the ghoops wordmark between hairlines, and `AVG HR`.
  - **With a target:** the bottom row is three equal cells, STRAIN / EST. DAY STRAIN / TARGET, with 22pt values and two 1×23pt rules. It replaces the wordmark and AVG HR without adding height. The expanded Island follows the same layout. See [parity1-spec §2.3](parity1-spec.md#23-live-activity-lock-live-haptic-and-alert).
  - **Background:** `#101418` at 93 % with a 1 pt white 8 % outline.
- **Dynamic Island:**
  - compact: leading heart + bpm, trailing timer;
  - minimal: heart;
  - expanded: the Lock Screen's top and bottom rows, plus the status line when heart rate is lost or absent (live-hr-spec §4.2).
- **Updates:** local `activity.update` at most once every 2 s, and only when a field or the stale date changes. The stale date is 10 s after the last reading (live-hr-spec D6).
- **Target crossing:** once per session, entering the target from below sends the Live Activity alert immediately, outside the 2s throttle, and plays a success haptic when the app is active. No notification permission prompt. Crossing rules and exact alert copy: parity1-spec §5.2 and §2.3.
- **On End:** the final state is shown, with `dismissalPolicy` set to `.after(end + 15 min)`.
- **No Live Activities:** if the owner has turned Live Activities off, the session still runs; only the Lock Screen view is missing.

## 8. Mac side: contract additions (schema 2, additive)

### 8.1 Transport changes (contract.md §7.1)

- **Methods:** GET on every endpoint as now, plus `POST /v2/activities` and `DELETE /v2/activities/<id>`. Any other method or path combination is `method_not_allowed`.
- **Request bodies:** allowed only on that POST, as `application/json` of at most 64 KiB (`payload_too_large`, 413, a new error code). A wrong content type is `invalid_request`.
- **Authentication and logging:** the same bearer authentication. Logs never include the body.

### 8.2 `POST /v2/activities`

Request body:

```json
{ "id": "3f0c…-uuid", "exercise_type": "BOXING", "display_name": "Boxing",
  "start": "2026-03-10T18:05:12Z", "end": "2026-03-10T19:02:40Z",
  "pauses": [ { "start": "2026-03-10T18:30:00Z", "end": "2026-03-10T18:32:10Z" } ],
  "live": { "strain_estimate": 11.6, "avg_hr_bpm": 151, "max_hr_bpm": 176, "samples": 3410 } }
```

**Validation.** Any failure is `invalid_request` naming the field.
- `id`: a lowercase UUID.
- `exercise_type`: one of §2.1.
- `display_name`: 1–40 characters.
- Interval: `start < end`. Active duration (`end − start − pauses`) from 60 s to 12 h.
- Time bounds: `end ≤ now + 5 min` and `start ≥ now − 30 days`, extended by [edit-spec.md §5.2](edit-spec.md#52-changes-to-ghoops-activities-post-body) for naming efforts and adding past activities.
- `pauses`: inside the interval, ordered, non-overlapping, each with an `end`.
- `live`: optional. When present, it is stored as given and shown only as the phone's estimate, never used for scores.

**Idempotency.**

| Request | Response |
| --- | --- |
| New `id` | 201 with the stored activity |
| Same `id`, same body | 200 with the stored activity |
| Same `id`, different body | 409 `conflict` (a new error code) |

**Response body:** the envelope plus `kind: "activity"` and `activity: {id, exercise_type, display_name, start, end, pauses, created_at}`.

### 8.3 `DELETE /v2/activities/<id>`

Returns 200 with `kind: "activity_deleted"` and `id`, or 404 `not_found`. Deleting is permanent.

### 8.4 Storage (data.md)

- **File:** `<state dir>/activities-v2.enc`. It uses the same AES-256-GCM envelope and Keychain key as `records-v2.enc`, holding `{version: 1, activities: [...]}`.
- **Writes:** atomic rename under its own advisory lock, `activities.lock`. The collector never touches this file.
- **Reading:** the server reloads it on mtime or size change, the same way as the store (contract §7.4).
- **Retention:** 400 days, the same as the store.
- **Missing file:** read as no activities.

### 8.5 CLI

These go in `internal/cli`, with schema-2 JSON out:
- `ghoops activity list [--days N]`;
- `ghoops activity add --type T --start RFC3339 --end RFC3339 [--name S]`, which uses the same validation and generates the `id`;
- `ghoops activity delete --id ID`.

They are for testing and for assistants.

### 8.6 Workouts and scores (scores.md §3.8 and §3.9)

- **A third kind of workout entry:** `kind: "goop"`, `source: "goop"`, provider fields null, `id: "goop-<uuid>"`, `exercise_type` and `display_name` from the activity, and `category` from the §3.8 table.
- **Its window** is `[start truncated to the minute, end)` minus its paused spans, with paused minutes removed from the slots. Strain, TRIMP, coverage, confidence, averages and zones then follow §3.4–§3.7.
- **New field on every workout entry:** `paused_minutes` (int; 0 for recorded and detected entries).
- **Dedupe:** a ghoops entry hides any recorded workout or detected effort whose overlap with it is at least 50 % of the shorter of the two. Detected-effort step 4 counts ghoops entries as recorded.
- **Counts and Day Strain:** day rows count ghoops entries in `workouts`, and Day Strain is unchanged.
- **Brief:** `brief` lists ghoops entries like recorded ones.
- **App decoding:** the app already decodes `kind` as a string. Rows of kind `goop` use the recorded-workout row style (spec.md §5.9) and tap to the workout screen.

## 9. App changes outside the new screens

- **API client:** `APIClient` gains `postActivity(_:)` and `deleteActivity(id:)`.
- **Recent sports:** these need the last 30 days of workouts. The snapshot holds 14 days of workouts (contract), so fetch `GET /v2/workouts?days=30` when sheet B opens, falling back to the snapshot's 14 days when offline.
- **Merging:** the activity list on Home and in the full-list sheet merges server entries with local pending and unsettled entries by `id`, where `goop-<uuid>` matches the local UUID. A local entry replaces nothing that the server returned final.
- **Pull to refresh** also retries uploads.

## 10. Fixtures and Debug launch arguments

- **Go fixtures:**
  - `fixtures/v2/activities/` holds a valid POST body, each invalid case and an encrypted-store round trip.
  - Preview bodies gain one `goop` workout in `snapshot_fresh`: Boxing, overlapping a detected effort that must be hidden.
  - Goldens are regenerated with the existing update flag, and the diff is reviewed.
- **`-GHealthLiveFixture <name>`** (Debug): starts the app with a running session seeded from `Fixtures/live/<name>.json`, which holds a sport, a start offset in seconds before launch, and a 1 Hz bpm series that continues to play.
  - `boxing_23m`: Boxing, started 23 min 14 s ago, currently Zone 4 at 158 bpm. It matches mockup C.
  - `no_hr`: Boxing, `NO HR` mode.
  - `stale`: Boxing; the band was lost 26 s before launch, and the last reading was 159 bpm.
  - `paused`: paused at 0:12:40.
- **`-GHealthLiveFixture ended_pending`** opens F in the not-yet-uploaded state; **`ended_estimate`** opens it in the uploaded-but-not-final state.
- **`-GHealthWidgetPreview <set>`** renders the Live Activity Lock Screen and Dynamic Island views in the preview host. The sets are `live`, `live_target`, `live_no_zone`, `live_no_hr`, `live_stale` and `live_paused` (live-hr-spec §6.1).
- **Release builds** must not contain these fixtures or flags. Extend the Release check in plan.md.

## 11. Tests

- **Go.** Tests go through the binary and HTTP (the serve and black-box smoke patterns):
  - POST create, replay, conflict, each validation error, auth, 413 and wrong method;
  - DELETE;
  - the encrypted file round trip, with no plaintext on disk;
  - a ghoops entry's strain from `boxing_hour` minutes equal to the golden;
  - paused minutes excluded;
  - dedupe against a detected effort and against a recorded workout;
  - `days` and `brief` counts;
  - logs without bodies.
- **GHealthCore:**
  - the Heart Rate Measurement parser (UInt8, UInt16, energy present, RR present, no contact, out of range);
  - the session state machine (pause, resume, the Mac's length limits, the recording span, restore from file);
  - live estimate parity with `strain.json`;
  - zone bpm ranges matching the Go workout zones for the same rest and max;
  - the upload queue (pending, 201, 200, 409, 4xx rejected, retry);
  - merging local and server entries;
  - decoding `kind: "goop"` and `paused_minutes`.
- **UI tests** use the fixture launch arguments. The flow test covers Home A → sheet B → select → start → C → minimise → E → reopen C → hold to end → F (pending). Screenshot tours capture A–F plus `no_hr` and `paused`, and widget preview `live`.

## 12. Decisions made in this spec (not specified by the owner)

1. The live strain is an estimate on the phone, and the official value is the Mac's. The workout screen switches to the Mac's values at 80 % coverage, or 6 hours after the activity ends.
2. Starting without live heart rate is allowed, so a session is never blocked by Bluetooth.
3. Pauses are excluded from active time and Strain, both live and on the Mac.
4. A ghoops activity hides overlapping recorded workouts and detected efforts (overlap ≥ 50 % of the shorter one), so a session the band also auto-logs appears once, with the owner's label.
5. Sessions shorter than the Mac's minimum are discarded, and sessions end automatically at its maximum or at the 12-hour recording span ([live-polish-spec.md](live-polish-spec.md) §3).
6. Activities are stored in a separate encrypted file, so writes never contend with the collector.
7. **Not mocked, using existing components:** DELETE ACTIVITY on the workout screen, the `WAITING FOR MAC` chip, the `Too short to save.` banner and the banner states in §4.3. These use existing styles.
8. Recent sports come from the last 30 days of workouts.
9. Adding an activity after the fact and editing times are specified in [edit-spec.md](edit-spec.md). Writing to Google, GPS distance and pace, calories, Apple Watch and audio cues remain out of scope.
