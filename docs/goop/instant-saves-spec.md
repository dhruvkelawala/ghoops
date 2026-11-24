# ghoops: Instant saves

Status: approved. The lead approved it on 2026-11-16 (§15), and the owner approved the mockup the same day. Written 2026-11-16 for issue #9. The build plan is [instant-saves-plan.md](instant-saves-plan.md); the mockup is [mockups/instant-saves.html](mockups/instant-saves.html).

> **Lead decision, 2026-11-16: offline behaviour (§3).**
> Decided: keep a change on the phone when the Mac can't be reached, retry it, and roll it back only when the Mac refuses it. This is §3.2 as recommended; §3.5 does not apply.
> Reason: on cellular a dropped request would otherwise throw away a finished edit, and new live activities already wait on the phone this way.
> Rejected alternative: roll back as soon as the Mac can't be reached (the issue's wording). It is simpler but loses work to a network blip.
> §3.5 lists what changes in this spec if the lead picks the alternative.

Today every change waits for the Mac before the screen moves. This spec makes the phone apply the change first and sync after. The sheet closes on the tap, the screen shows the result straight away, and the Mac's answer replaces it a moment later. It also removes three costs the measurements found (§1): a new connection for every request, a date parser that takes 166 ms to read one snapshot, and an uncompressed 51–61 KB snapshot.

## 0. Precedence and decisions

- This spec extends [edit-spec.md](edit-spec.md), [activity-spec.md](activity-spec.md), [contract.md](../v2/contract.md) and [DESIGN.md](../../DESIGN.md). Where they disagree, this spec wins for the flows described here.
- **What it replaces in edit-spec.md:**
  - §2.2 "Saving" (success and failure) and step 12's "While the request runs, the commit is disabled";
  - §2.4 step 6 "Success and failure behave like SAVE";
  - §2.5 steps 3 to 5, including the text `Undo didn't reach your Mac. Try again.`;
  - §2.6 "Success behaves like SAVE";
  - §2.7 step 6;
  - §2.8 steps 5 and 6;
  - §2.9's last line, "A failed save, delete, merge, restore or add shows the error from §4.3 and changes nothing";
  - §9.4 (refresh after a mutation);
  - §12 decision 9 and the §13 line "Queuing edits offline".

  The §4.3 banners stay for the one failure that still happens inside a sheet: its heart-rate read when it opens.
- **What it replaces in contract.md:** the §7.1 Compression row, and §7.2's edit request gains one optional key (§8).
- **Mockup:** [mockups/instant-saves.html](mockups/instant-saves.html), one phone per key:

  | Key | Screen |
  | --- | --- |
  | `saving` | Workout screen right after SAVE, while the Mac has not answered for 0.6 s |
  | `waiting` | The same screen after the request failed because the Mac can't be reached |
  | `home-waiting` | Home with a named effort waiting for the Mac |
  | `updating` | Strain screen while a change to a strength workout is syncing |
  | `rollback` | Home after the Mac refused an edit |
  | `delete-waiting` | Home right after a delete, with the Mac out of reach |

  The owner approves the mockup before the build starts (plan, "Gate"). Layout, colours, type and copy must match. The values are fixture values.
- **Patterns borrowed** (research notes in §13 decision 1):
  - WHOOP's black sync strip at the top of Home ("DATA CAUGHT UP · SYNCED TO 13:46"). It becomes the waiting banner, shown only while something waits.
  - WHOOP's grey `--` with a "Pending" word while a score is being calculated. It becomes `—` with `UPDATING` under it.
  - Garmin Connect's circular-arrows sync glyph. ghoops already uses `arrow.triangle.2.circlepath` on the workout save banner, so the waiting banners use it too.
  - Garmin's progress line and spinning glyph are not borrowed: DESIGN.md has no progress bars, and the only motion it allows is the ring animation.
- **Dark launch.** The visible behaviour lands behind `GoopFeature.instantSaves` (§10) and goes live in the plan's last step. The transport and decoding fixes (§7) and the server changes (§8) land without a flag, because nothing on screen changes except speed.
- Decisions made while writing are in §13. Points the lead should check are marked **(lead?)**.

## 1. What the measurements say

Full method and raw numbers are in [acceptance.md, "Instant saves: where the time goes"](acceptance.md#instant-saves-where-the-time-goes-2026-11-16-issue-9). Fixture data only.

| Action (past day) | Round trips today | Server write | Re-score | App decode | Total at 30 / 100 / 250 ms RTT |
| --- | --- | --- | --- | --- | --- |
| Edit, merge | 11 (3 + 5 + 3) | 14 ms | 66.5 ms | 200 ms | 0.61 / 1.38 / 3.03 s |
| Delete, undo | 8 (3 + 5) | 14 ms | 42.5 ms | 166 ms | 0.46 / 1.02 / 2.22 s |
| Restore | 11 | 8 ms | 66.5 ms | 200 ms | 0.60 / 1.37 / 3.02 s |
| Name an effort, add past | 11 | 7.5 ms | 66.5 ms | 200 ms | 0.60 / 1.37 / 3.02 s |
| Create (live) | 0 before the screen changes | 7.5 ms, in the background | none | none | 0.35 s fixed delay, then the workout screen |

The network dominates at every RTT: 54 % of the total at 30 ms, 80 % at 100 ms and 91 % at 250 ms. At 30 ms the single largest item is the app decoding the snapshot (166 ms).

The six findings behind the design:
1. **A new connection per request.** Every call site builds a new `APIClient`, and each builds its own `URLSession` (`APIClient.swift:35`). An edit opens 3 to 5 connections, and each costs a TCP and a TLS handshake (2 RTT) before its request. A proxy that counts connections saw 5 per edit flow.
2. **Three requests in a row.** The PUT, then `GET /v2/snapshot`, then (for a past day) the three day reads. The sheet closes only after the snapshot (8 RTT), and the detail page of a past day then shows `GoopLoading` for 3 more, because `dropDayData()` discards every loaded day.
3. **The snapshot is 51–61 KB uncompressed.** On a new connection that is 3 TCP flights instead of 1 (Tailscale MTU 1280, initial window 10 segments of 1,240 bytes). Gzip makes it 6.5–8 KB.
4. **Decoding is slow because of dates.** `JSONCoding.decoder()` builds two `ISO8601DateFormatter`s for every date string. Decoding the snapshot takes 166 ms on an M6 in an optimised build. The Edit sheet's heart-rate body takes 99 ms and an Add-past day takes 431 ms. With `Date.ISO8601FormatStyle` the same bodies take 2.7, 0.7 and 2.6 ms and parse to the same instants.
5. **The server is not the bottleneck.** A PUT takes 14 ms: 8 ms is the encrypted store write with two `fsync`s, and 3–8 ms builds the score engine for validation. A POST or DELETE takes 7.5–8 ms. The re-score happens in the reads after the write: 24–43 ms for the snapshot and 24 ms for a past day. A synthetic store with 400 days of minute data adds about 10 ms to each.
6. **Create is already local-first.** A live session saves on the phone and opens its workout screen after a fixed 0.35 s delay; the POST runs afterwards. This spec leaves it alone.

After this spec, every action updates the screen on the tap. The syncing state then lasts until the Mac has answered and the app has re-read its result. On a warm connection that takes 0.12 / 0.26 / 0.56 s at 30 / 100 / 250 ms RTT; on a cold one it takes 0.18 / 0.46 / 1.06 s.

## 2. The model: pending changes over the Mac's bodies

### 2.1 What the screen shows

The app keeps two layers:
- **The Mac's bodies:** the last snapshot and the loaded day bundles, exactly as the Mac sent them.
- **Pending changes:** an ordered list of the owner's changes that have not settled yet. Each carries a **patch**: the workouts to remove and the workouts to insert or replace, with the values the phone computed (§5).

The screen always shows the Mac's bodies with every pending patch applied in order, then the overlap rules (§5.3) for the dates those patches touch. Nothing else edits the displayed data. Putting the old state back after a refusal is therefore exact: the app drops the change and recomputes.

### 2.2 Life of a change

| State | Meaning | Marker |
| --- | --- | --- |
| `sending` | submitted, no answer yet | `SAVING` after 0.6 s (§6.1) |
| `waiting` | the last attempt failed in a way worth retrying (§2.4) | `WAITING FOR MAC` |
| `accepted` | the Mac answered 2xx; the app has not re-read the result yet | none, but its patch stays applied |
| removed | settled (§2.5), rolled back (§2.6) or cancelled (§2.8) | none |

### 2.3 Sending

- One sender runs at a time and sends changes one by one, oldest first.
- Each pass first runs the existing live-upload queue (`ActivityController.retryUploads()`), so new live activities reach the Mac before any edit.
- A change is sent as soon as it is submitted. Further passes start when the app becomes active, after `refresh()`, after a change settles, and every 30 s while the app is active and a change is `waiting`.
- When an attempt ends as `waiting`, the pass marks every later unsent change `waiting` too and stops. The Mac is out of reach, so there is no point trying the rest now.

### 2.4 How an answer is classified

| Result | Outcome |
| --- | --- |
| 200 or 201 | `accepted`. For a PUT, the patch's workout takes the response's `edit` (with the Mac's `updated_at`). |
| 2xx whose body fails to decode | `accepted`; the Mac applied it |
| 404 on `DELETE /v2/edits/<id>` | `accepted`: no stored edit is what the request wanted, so a replay after a lost answer is not an error |
| 400, 404, 409, 413 | rolled back (§2.6) |
| 401 | `waiting`. The existing invalid-pairing state already tells the owner what to do. |
| 429, any 5xx, a timeout, no route | `waiting` |

Every request is safe to replay. A PUT replaces the edit, and the same body again returns 200. A POST with the same id and body returns 200. A DELETE of an edit that is already gone counts as accepted.

### 2.5 Settling

When a sending pass has accepted at least one change, the app re-reads, at the same time:
- `GET /v2/snapshot`;
- the three day reads for each date in the accepted changes' `cycleDates` that has a loaded day bundle and is not the snapshot's default date.

When every read succeeds, the app stores the results and removes all changes that were accepted before the reads started. Only the re-read dates are replaced; other loaded days stay loaded. If a read fails, the accepted changes stay (no marker) and the re-read is tried again on the next trigger in §2.3.

### 2.6 Rollback

When the Mac refuses a change:
1. Remove it, and remove every later change that is not yet accepted and shares one of its `targets`. An Undo queued after a refused delete is an example.
2. Recompute the screen. The old state is back.
3. Add a rollback notice for the change, unless §2.8 suppresses it. The notice holds the kind, the name from §6.7 and the status. Home shows at most 3 notices, newest first. Notices are not saved to disk and end when dismissed or when the app goes to the background.
4. If the workout screen on top shows an id that no longer exists (a refused add or name), pop it. For a refused name, replace the route with the effort's id again.
5. Post the notice text as a VoiceOver announcement.

### 2.7 Locks

A workout id is **locked** while any change in the list (any state, including `accepted`) names it in `targets`. A locked workout:
- shows no pencil on its workout screen;
- is not offered as a merge candidate in another Edit sheet.

Locks are what keep the changes independent of each other. Two pending changes never touch the same workout, so one can be refused without changing what another means. The one deliberate chain is Undo after Delete (§2.8). Add past locks nothing until it has created its entry.

### 2.8 Delete and Undo

- **Delete:** the change is submitted, the sheet closes, the detail pops and Home shows the Undo banner at once (edit-spec §2.5 steps 3.1 to 3.4, without waiting). The banner's 10 s start at the tap.
- **UNDO** depends on where the delete is:

  | Delete is | UNDO does |
  | --- | --- |
  | not yet sent, or `waiting` | removes the delete from the list. No request is sent; the row is back at once. |
  | in flight | marks the delete "undo requested". If it is accepted, submit the Undo change. If it is refused or ends `waiting`, remove it and show no rollback notice, since the owner wanted it back anyway. |
  | `accepted` | submits an Undo change: `PUT /v2/edits/<id>` with the stored edit and `hidden: false`, or `DELETE /v2/edits/<id>` when there was no stored edit (edit-spec §2.5 step 5). Its patch puts back the workout exactly as it was before the delete. |

- The Undo banner disappears on UNDO. Undo never fails on screen: it queues like any change.

### 2.9 Saving to disk and relaunch

- The list is saved as `pending-changes.json` in the same directory as `activities-local.json`: the App Group container, or the fixture temp folder in fixture mode. It is written atomically with `.completeFileProtection` after every state change. It can hold notes text, so it gets the same protection as the activity file.
- Each patch stores the full projected workouts, so a relaunch can redraw them without the heart-rate data.
- **At launch** the app loads the list before it shows data, applies it over the cached snapshot, then starts a sending pass after `configureActivity()`. Changes left `accepted` trigger a re-read (§2.5).
- Each change records the paired server URL. Changes for another URL are dropped at load. Unpairing, or pairing with a different server URL, empties the list. Pairing again with the same server URL, for example after the token was revoked, keeps the list, and the next pass sends with the new token. A finished change is never dropped because the token changed.

## 3. Offline (lead decision needed)

### 3.1 What "offline" means here

The Edit sheet and PAST mode still need the Mac to open, because the preview needs `GET /v2/heart-rate` (edit-spec §2.9, unchanged). So the owner cannot start an edit with the Mac out of reach. The offline case is a change that was made while the Mac answered and then could not be sent: the phone left Wi-Fi, cellular dropped, Tailscale went off, or the Mac slept. Undo on Home is the other case, since it needs no preview.

### 3.2 Recommendation: keep it on the phone, roll back only when the Mac refuses

- **An edit made when the Mac stops answering** stays applied and is marked `WAITING FOR MAC` (§6). It is saved to disk and retried on the triggers in §2.3. It is rolled back only when the Mac answers with a refusal (§2.4).
- **Ordering against queued creates.** Each pass sends the live-upload queue first, then the changes oldest first, one at a time. A change never depends on an unsent create: the pencil is already hidden on a local entry that is not on the Mac (edit-spec §2.1 step 1), and a new entry from a pending name or add is locked (§2.7).
- **When the Mac's data moved underneath.** The Mac checks every change against its current state when it arrives. A band record that Google removed or re-merged gives 404; a merge partner absorbed elsewhere gives 409; a window that no longer fits gives 400. Each rolls back with a banner naming the activity. Edits made on the Mac (the CLI or an assistant) are protected by a new precondition (§8.2). A phone edit that has waited while the same activity was changed on the Mac gets 409 instead of silently overwriting it.
- **App relaunch with pending changes.** §2.9. Nothing is lost, and the screen looks the same after a relaunch.
- **No expiry and no discard button.** A change waits until the Mac answers. The edit horizon (30 days) ends its life: after that the Mac answers 404 and the change rolls back. **(lead?)**

### 3.3 Trade-offs

For it:
- A finished change is never lost to a dropped request, which matters most on cellular, where the owner says saves are slowest.
- Edits behave like new live activities, which already wait on the phone with "Saved on your phone. It will be sent to your Mac when it can be reached."

Against it:
- A change can wait for hours. The owner may then see a rollback long after making the change, so the banner names the activity.
- It needs a saved list, locks, the cascade in §2.6 and the server precondition (§8.2).
- The owner cannot correct a waiting change until it gets through (§2.7).

### 3.4 Rejected alternative: roll back when the Mac can't be reached

This follows the issue's wording. Nothing is saved to disk, nothing is retried, and there are no locks across launches. It was rejected because a network blip on cellular would undo an edit the owner had finished. They would have to open the sheet again, wait for the heart-rate read and redo the edit. It would also make edits behave differently from new activities for no reason the owner can see.

### 3.5 If the lead picks the alternative

- §2.4: the `waiting` rows become rollbacks, with the reason `Your Mac couldn't be reached.` and the outcome `It's back as it was.`
- §2.3 and §2.9: no `waiting` state, no 30 s timer and no `pending-changes.json`. The list lives in memory and is emptied at launch.
- §6: drop `WAITING FOR MAC` on rows, the page banner and the Home waiting banner. The `waiting` and `home-waiting` mockups go away, and `delete-waiting` shows only the Undo banner.
- §2.8: keep edit-spec's `Undo didn't reach your Mac. Try again.`
- §8.2 becomes optional. Without a queue, a stale phone change is at most one request old.

## 4. Every action, moment by moment

"Tap" is the commit tap. "Saving" applies after 0.6 s without an answer (§6.1). "Settled" is §2.5. All values on the tap are the phone's projection (§5), which matches the Mac's for the fields listed in §5.1.

### 4.1 Edit (SAVE)

| Moment | Screen |
| --- | --- |
| Tap | The sheet closes. The workout screen shows the new sport, times, values, chart and notes, and the subtitle suffix ` · Edited`. Activity rows for that day (Home, Strain, Today's Activities) show the new name, strain and times. The pencil is hidden (§2.7). |
| Saving | The subtitle suffix becomes ` · Saving to your Mac`. Rows for the activity show `SAVING` in place of their times. |
| Waiting | The subtitle goes back to ` · Edited`. The page shows the waiting banner (§6.2). Rows show `WAITING FOR MAC`. Home shows the waiting banner (§6.4). |
| Settled | The Mac's bodies replace the projection. No marker. The pencil is back. |
| Rolled back | The old sport, times and values are back. A `NOT SAVED` banner shows at the top of the workout screen and on Home (§6.4). |

### 4.2 Merge (MERGE INTO ONE)

As Edit, plus on the tap the partner (`MERGE WITH NEXT` or `PREVIOUS`) disappears from every list and the window is the union. The footnote lists the partner's band version. A refusal brings the partner back.

### 4.3 Delete

| Moment | Screen |
| --- | --- |
| Tap (Delete in the alert) | The sheet closes, the detail pops, and Home shows the Undo banner. The row is gone from every list. |
| Saving | Nothing more: there is no row left to mark, and the Undo banner is showing. |
| Waiting | Home shows the waiting banner under the Undo banner. |
| Settled | No change on screen. |
| Rolled back | The row is back, and Home shows `NOT SAVED`. |

### 4.4 Undo

UNDO hides the Undo banner and puts the row back at once (§2.8). If an Undo change was submitted, it then follows the Edit moments for the row: `SAVING`, `WAITING FOR MAC`, settled or rolled back. A rolled-back Undo removes the row again and shows `NOT SAVED`.

### 4.5 Restore (RESTORE BAND'S VERSION, then Restore in the alert)

| Moment | Screen |
| --- | --- |
| Tap | The sheet closes. The workout screen shows the band's sport, times and values with no ` · Edited` and no notes. Entries it had absorbed are back in the lists. |
| Saving, waiting, settled, rolled back | As Edit. A refusal brings the edited version back and removes the returned entries again. |

### 4.6 Name a detected effort (SAVE on an effort)

| Moment | Screen |
| --- | --- |
| Tap | The sheet closes. The workout screen switches to the new entry (`goop-<uuid>`): the sport title, the subtitle `<start> to <end> · Added in ghoops`, and the values. The effort is gone from the lists, replaced by the new row. |
| Saving | Subtitle suffix ` · Saving to your Mac`; the row shows `SAVING`. |
| Waiting | As Edit. |
| Rolled back | The screen goes back to the detected effort (§2.6 step 4), and the effort row is back. |

### 4.7 Add a past activity (ADD on PAST)

| Moment | Screen |
| --- | --- |
| Tap | The sheet closes and the workout screen for the new entry opens on its day, as edit-spec §2.8 step 5. The efforts it covers leave that day's lists. |
| Saving, waiting | As Name. |
| Rolled back | The workout screen pops if it is on top. The row is gone, the efforts are back, and Home shows `NOT SAVED · … Nothing was added.` |

### 4.8 Create (live)

Unchanged: activity-spec §2 and the measurement in §1. Its rows keep their existing `WAITING FOR MAC` while the upload is pending.

## 5. Projected values

### 5.1 Projected workout fields

`WorkoutProjection.project(...)` (GHealthCore, pure) builds a `Workout` for a window, using the heart-rate body the sheet already holds and `WindowEstimator` (edit-spec §8.1). Edit-spec §8.6 proves the estimator equals the Mac for strain, TRIMP, average and peak heart rate, zones, coverage, elapsed and paused minutes.

| Field | Value |
| --- | --- |
| `id`, `kind` | the base workout's; for a new entry `goop-<uuid>` and `goop` |
| `exerciseType` | the selected sport. Restore: `score_config.sport_aliases[original type] ?? original type`. |
| `displayName` | the activity-spec §2.1 name when the type is in that table, else the base's or the original's `displayName` |
| `category` | when the type changed or the entry is new: `ActivitySport.category(for:)`, which is the mapping now inline in `ActivityModels.swift:93`, moved into one function. Otherwise the base's. |
| `cycleDate` | the base's; for Name the effort's; for Add `AddDraft.day`. A window moved across a cycle boundary moves days only when the Mac answers. |
| `start`, `end` | the window |
| `elapsedMinutes`, `strain`, `trimp`, `hrCoverage`, `avgHrBpm`, `peakHrBpm`, `zonesMinutes`, `pausedMinutes` | the estimate |
| `confidence` | from `hrCoverage`: ≥ 0.80 `high`, ≥ 0.50 `medium`, otherwise `low`; nil when `strain` is nil (scores.md §3.7) |
| `activeMinutes` | recorded: nil (edit-spec §5.4; also nil for restore until the Mac answers). Goop: elapsed minus paused. |
| `hrSeries` | each heart-rate minute `t` with `start` truncated to the minute ≤ `t` < `end` and not in a pause, as `{t, bpm: Int(avgBpm.rounded())}`. The body's averages have 2 decimals, so a rare minute may differ by 1 bpm from the Mac's series until it settles. |
| `notes` | the request's notes. For a goop base with no stored edit notes, its own notes. Restore: nil. |
| `edit` | the request as a `WorkoutEdit` with `updatedAt` = now, or nil when it normalises to empty (edit-spec §5.1). Replaced by the response's `edit` on acceptance. Restore: nil. |
| `edited` | `edit` is non-nil and has a sport, a window or a non-empty `mergeWith` |
| `merged` | the base's. Merge appends the partner's original as `WorkoutOriginal(id, kind, exerciseType, displayName, start, end)`, using the partner's `original` values when present, sorted by start. Restore: `[]`. |
| `origin` | the base's; new entries `"added"` |
| `original` | the base's; new entries `{exerciseType, displayName, start, end}` with nil id and kind |
| `pauses` | goop: the base's pauses clipped to the window; others `[]` |
| `provider`, `source`, `hasGps`, `suggested` | the base's. New entries: nil, `.goop`, false, nil. |

### 5.2 Patches by kind

| Kind | Request | Patch | `targets` | `cycleDates` |
| --- | --- | --- | --- | --- |
| Edit | `PUT /v2/edits/<id>` with `draft.body` | upsert T projected over `draft.window` | T | T's |
| Merge | `PUT` with `draft.mergeBody(X)` | upsert T over the union; remove X | T, and X when recorded or goop | T's |
| Delete | `PUT` with `draft.deleteBody` | remove T; keep T as it was, for Undo | T | T's |
| Undo | `PUT` with the stored edit and `hidden: false`, or `DELETE` | upsert the kept T | T | T's |
| Restore | `DELETE /v2/edits/<id>` | upsert T projected over its original window as the band's version. Upsert each entry in `T.merged`, projected over its own window with its kind and type (recorded types through the alias), category by the rule above and `cycleDate` of T. A recorded entry takes T's `source`, a goop entry `.goop`; `provider` is nil for both. | T and each merged id | T's |
| Name | `POST /v2/activities` (edit-spec §2.7 step 4) | remove the effort; upsert the new entry | the effort id and `goop-<uuid>` | the effort's |
| Add | `POST /v2/activities` (edit-spec §2.8 step 5) | upsert the new entry | `goop-<uuid>` | `AddDraft.day` |

- PUT bodies carry the precondition from §8.2: the workout's `edit.updatedAt` when it has an edit, else "no edit". An Undo PUT uses the `updated_at` from the accepted delete's response.
- **Undo after a delete whose answer could not be read** (§2.4, "2xx whose body fails to decode"). The delete's `updated_at` is unknown, so before the Undo PUT the sender replays the delete's exact request, with the same body and the same `if_updated_at`. This is safe by §8.2 step 2. The replay's result decides what happens next:
  - **200 with a decodable `edit`:** its `updated_at` becomes the Undo's precondition, and the Undo PUT is sent in the same pass.
  - **2xx whose body still fails to decode:** the Undo PUT is sent with `if_updated_at` absent, so the replay can't loop.
  - **Anything else:** classified by §2.4 as the Undo's own outcome. A 409, 404 or 400 rolls the Undo back with the Undo copy in §6.7. A 401, 429, 5xx, timeout or no route leaves the Undo `waiting`, and the replay runs again on the next pass.
- The heart-rate body for the projection is the Edit sheet's (`EditDraft.heartRate`, which covers T, its candidates and everything it absorbed) or the PAST day's (`AddDraft`'s body).

### 5.3 Overlap rules

After the patches, `OverlapRules.apply` runs on the workouts of each date in any pending change's `cycleDates`. Other dates are left exactly as the Mac sent them.
1. **Absorbed pairs.** A workout listed in another's `edit.mergeWith` never hides it or is hidden by it.
2. **Goop hides recorded** (edit-spec §5.5 step 5): remove a recorded workout when a goop workout overlaps it by at least 50 % of the shorter window.
3. **Efforts** (scores.md §3.9 step 4): remove a detected workout when the recorded and goop windows overlapping it sum to at least half its length.

The phone only removes. New efforts that a shorter window would uncover appear when the Mac answers.

### 5.4 Dependent values: UPDATING

- **The Strain screen's STRENGTH contributor** (`day.strengthMinutes`) is the one value on screen that depends on activities and that the phone does not compute. While a change listing its date in the patch's `updating` dates is in the list, it shows `—` with `UPDATING` (§6.5).
- A change lists its date in `updating` when any workout it removes, inserts or replaces has category `strength`, before or after the change.
- **Day Strain, Recovery and Sleep never change with an activity edit.** scores.md §3.8 and edit-spec §1 say Day Strain already counts every minute. The issue's "scores such as Strain show as updating" therefore applies to no dial. Sleep edits follow sleep-edit-spec §4.3. **(lead?)**
- The workout's own ACTIVITY STRAIN is the projection, which equals the Mac's, so it shows at full strength. The Strain insight sentence and the workout screen's comparison chip are computed on the phone from the displayed list and follow it.
- Trends are not overlaid. Their `days` rows (workout counts, strength minutes) update when the change settles and the snapshot's `days` seed the trend store again.

## 6. Screens and copy

### 6.1 Timing

- `SAVING` and `UPDATING` appear only when the change has been in the list for **0.6 s** without being accepted (`SAVING`) or settled (`UPDATING`). A save answered sooner shows no marker at all, which is the usual case at home.
- Once shown, a marker stays at least **0.5 s**, so it never flashes.
- `WAITING FOR MAC` and `NOT SAVED` show as soon as their state begins.
- Constants live in `ChangeTiming` (GHealthCore): `markerDelay = 0.6`, `markerMinimum = 0.5`, `retryInterval = 30`, `rollbackLimit = 3`.

### 6.2 Workout screen

- **Saving:** the subtitle suffix (edit-spec §2.1 step 2) is replaced by ` · Saving to your Mac`, for example `17:56 to 19:12 · Saving to your Mac`. The style is the existing subtitle (`bodySmall`, `textSoft`). There is no icon and no animation.
- **Waiting:** the subtitle keeps its normal suffix. Under the header, in the slot of the existing save banner, the page shows a `GoopBanner(tone: .strain)` with `arrow.triangle.2.circlepath` and the existing text `Saved on your phone. It will be sent to your Mac when it can be reached.`, id `change-waiting-banner`. It looks exactly like `activity-save-banner`.
- **Rolled back:** a `GoopBanner(tone: .caution)` with `exclamationmark.triangle`, title `NOT SAVED`, the §6.7 text and a dismiss ×, id `change-rollback-banner`, in the same slot. It shows only for the workout the notice names, and the Home notice is the same one: dismissing either dismisses both.
- **Values** always show at full opacity. The projection is exact, not stale.

### 6.3 Activity rows

`GoopActivityRow` has one status slot, the one that today shows `WAITING FOR MAC` in place of the times. It now takes a status:

| Status | Label | Colour |
| --- | --- | --- |
| none | the start and end times (today's) | `text2` |
| saving | `SAVING` | `text2` |
| waiting | `WAITING FOR MAC` | `caution` |

The label is `labelMicro`, at most 76 wide, as `WAITING FOR MAC` is today. A pending live upload keeps `WAITING FOR MAC`. The value block keeps its colour and full opacity.

### 6.4 Home banners

The Home banner slot stacks, 8 apart, in this order:
1. the existing `GoopHomeBanners`;
2. the Undo banner (edit-spec §2.5);
3. rollback notices, newest first, at most 3. Each is a `GoopBanner(tone: .caution)` with `exclamationmark.triangle`, title `NOT SAVED`, the §6.7 text and a dismiss ×, ids `change-rollback-banner-0`, `-1`, `-2`;
4. the waiting banner, while at least one change is `waiting`: a neutral `GoopBanner` with `arrow.triangle.2.circlepath` in `caution` and the §6.7 text, id `pending-changes-banner`. It has no action;
5. the existing "Too short to save." and activity error banners.

### 6.5 Strain screen STRENGTH row

`GoopMetricRow` gains `status: String?`. When it is set, the value is `—` in `text2`, and the comparison line under it (where the mean sits) shows the status in `labelMicro` `text2`. The row stays tappable. The Strain screen passes `UPDATING` for the STRENGTH row while §5.4 applies to the selected date.

### 6.6 Sheets

- **Edit sheet:** SAVE, MERGE INTO ONE, Delete and Restore close the sheet on the tap. The commit is never disabled for "busy". The §4.3 banner shows only when the heart-rate read fails on open (edit-spec §2.9).
- **ADD sheet:** ADD closes the sheet on the tap. The heart-rate read on choosing a day keeps its loading and error states.
- A sheet opened on a locked workout cannot happen, because the pencil is hidden (§2.7).

### 6.7 Copy

`<Name>` is the activity's name as shown before the change, from `displayName` (`Kickboxing`). `<Sport>` is the name of the sport being saved (`Running`).

| Where | Text |
| --- | --- |
| Subtitle suffix while saving | ` · Saving to your Mac` |
| Row status | `SAVING`, `WAITING FOR MAC` |
| Page banner while waiting | `Saved on your phone. It will be sent to your Mac when it can be reached.` |
| Home waiting banner, 1 change | `1 change is waiting for your Mac. It will be saved when your Mac can be reached.` |
| Home waiting banner, n > 1 | `<n> changes are waiting for your Mac. They will be saved when your Mac can be reached.` |
| Dependent value | `—` with `UPDATING` |
| Rollback title | `NOT SAVED` |

Rollback text is the reason, a space, then the outcome:

| Kind | Reason for 400 or 413 | Reason for 404 or 409 | Outcome |
| --- | --- | --- | --- |
| Edit, merge, delete, restore, undo | `Your Mac couldn't save the change to <Name>.` | `<Name> changed on your Mac.` | `It's back as it was.` |
| Name | `Your Mac couldn't save the detected effort as <Sport>.` | `The detected effort changed on your Mac.` | `It's back as it was.` |
| Add | `Your Mac couldn't add <Sport>.` | `Your Mac couldn't add <Sport>.` | `Nothing was added.` |

Example: `NOT SAVED` / `Kickboxing changed on your Mac. It's back as it was.`

### 6.8 Accessibility

- Row labels gain the status: "Boxing, strain 12.9, saving to your Mac" or "…, waiting for your Mac".
- The subtitle reads as written. The STRENGTH row reads "Strength, updating".
- Rollback notices are announced (§2.6 step 5).
- `testAccessibilityTour` captures the `home-waiting` and `rollback` states at accessibility 5 (plan I9).

## 7. Transport and decoding (app, no flag)

### 7.1 One URLSession per process

- `APIClient` stops building a session per instance. It uses one of two process-wide sessions: the app session (request timeout 15 s) and the widget session (10 s). Both keep today's configuration: ephemeral, `reloadIgnoringLocalCacheData`, `waitsForConnectivity = false`.
- `init(baseURL:token:widget:session:)` keeps the `session` parameter for tests.
- The token stays a per-request header. Nothing else about requests changes.
- Effect: requests after the first reuse the connection, and HTTP/2 through `tailscale serve` carries the three day reads on one connection.

### 7.2 Date decoding

- `JSONCoding.decoder()`'s date strategy parses with two static `Date.ISO8601FormatStyle` values, plain first and then with fractional seconds. The error for anything else is the existing `Invalid RFC 3339 time`.
- `Date.ISO8601FormatStyle` is `Sendable`, so no lock or `nonisolated(unsafe)` is needed.
- It accepts what today's parser accepts (`Z` and numeric offsets, with and without fractions). The one difference is that it keeps sub-millisecond fractions that today's parser rounds to milliseconds. Nothing compares times at that precision. Encoding is unchanged.

## 8. Contract changes (schema 2, additive)

### 8.1 Compression (contract §7.1)

Replace the Compression row with:

| Item | Value |
| --- | --- |
| Compression | gzip when the request's `Accept-Encoding` lists `gzip` with a non-zero q value and the body is at least 1,024 bytes. Such responses carry `Content-Encoding: gzip` and `Vary: Accept-Encoding`. Otherwise the body is identity. Applies to every route and to error bodies. |

- The log line is unchanged, and `duration_ms` includes the compression.
- URLSession sends `Accept-Encoding: gzip, deflate, br` and inflates on its own, so the phone needs no code.
- `curl` without `--compressed` and Python's `http.client` send no `Accept-Encoding`, so the smoke scripts, `same_body.py` and the CLI see identical bodies to today.
- `tailscale serve` is a reverse proxy that forwards the phone's `Accept-Encoding` and the compressed response unchanged. Plan I11 checks this once over the tailnet with the owner.
- Measured: the snapshot shrinks from 51–61 KB to 6.5–8 KB, which fits the first TCP flight. Compression costs 0.3 ms.

### 8.2 `if_updated_at` on `PUT /v2/edits/<id>` (contract §7.2 "Edits")

**Request** gains an optional seventh key:

| Key | Type | Meaning |
| --- | --- | --- |
| `if_updated_at` | Time, null, or absent | absent: no check (the CLI, older phones). null: the phone expects no stored edit. A time: the phone expects the stored edit's `updated_at`. |

**Order of checks**, under `activities.lock`:
1. Validate and normalise the body as today.
2. If the normalised edit equals the stored one, ignoring `updated_at`, answer 200 with the stored edit. A replay after a lost answer therefore never trips the check.
3. Otherwise, if `if_updated_at` is present and does not match, answer 409 `conflict` with the message `This activity changed on your Mac.` "Match" means both are null, or both are times equal after truncating to the second in UTC. The phone's encoder writes whole seconds.
4. Otherwise store as today.

**Other contract edits:**
- §6 Errors: the `conflict` row's "When" gains "or an edit PUT whose `if_updated_at` no longer matches"; the edit paragraph lists the new message.
- `DELETE /v2/edits/<id>` and `POST /v2/activities` take no precondition. Restore means "drop whatever is stored", and a POST is idempotent by id.
- `ghoops activity edit` does not send the key.

**Phone:** `EditBody` gains `precondition: EditPrecondition` (`.none`, `.noEdit`, `.updatedAt(Date)`). It encodes as an absent key, `null` or a time. `EditBody`'s `==` ignores it, so `hasChanges` and `FixtureEditAPI`'s body matching are unchanged.

### 8.3 Considered and not changed

- **Recomputed bodies in mutation responses.** They would save one round trip on a path the owner no longer waits for, at the price of a larger contract.
- **Caching built snapshots on the server.** 24–43 ms per read is not worth the cache-invalidation risk yet.
- **Fewer `fsync`s per write.** The 8 ms buys durability for the owner's edits.
- **Keychain reads per write on the real Mac.** Not measured: the harness uses an in-memory Keychain, and the live install is off limits. The acceptance record lists this as an open measurement.

## 9. App structure

### 9.1 GHealthCore (new folder `Sources/GHealthCore/Changes/`)

| Type | Role |
| --- | --- |
| `PendingChange` (Codable) | `id: UUID`, `kind` (`edit`, `merge`, `delete`, `undo`, `restore`, `name`, `add`), `request` (`putEdit(id, EditBody)`, `deleteEdit(id)`, `postActivity(ActivityUpload)`), `targets`, `cycleDates`, `name` (§6.7), `patch: WorkoutPatch`, `kept: Workout?` (delete only), `serverURL`, `createdAt`, `acceptedAt`, `attempts`, `state`, `undoRequested` |
| `WorkoutPatch` (Codable) | `remove: [String]`, `upsert: [Workout]`, `updating: [String]` (dates) |
| `WorkoutProjection` | §5.1 |
| `ChangeBuilder` | one static function per kind, returning a `PendingChange` from the draft, the workout, the day's displayed workouts, the aliases and now (§5.2) |
| `Overlay` | `apply(_ changes:, to snapshot:) -> Snapshot` and `apply(_ changes:, date:, day:, workouts:) -> (Day, [Workout])`. Patches apply to `snapshot.workouts.workouts`, `snapshot.day.workouts` and a bundle's day and workouts, keeping only workouts whose `cycleDate` belongs in that body. Then `OverlapRules` (§5.3). |
| `ChangeQueue` (actor) | the list and `pending-changes.json`: `load()`, `submit(_:)`, `drain(api:uploads:) -> DrainResult`, `cancel(id:) -> Bool`, `settle(acceptedBefore:)`, `clear()`. It owns §2.3, §2.4, §2.6 steps 1 and 3, and §2.8. |
| `RollbackNotice` | `changeID`, `kind`, `name`, `error: ClientError`, `text` (§6.7) |
| `ChangeTiming` | §6.1 constants, plus `markerVisible(change:, now:, shownAt:) -> Bool` |

`Workout` is already `Codable`. Applying a patch must be idempotent, because a re-read can land while a change is in flight.

### 9.2 AppModel

- `serverCached` and `serverBundles` hold the Mac's bodies. Everything that writes today's `cached` and `bundles` writes these instead, including `loadDay` and `refresh()`.
- `cached` and `bundles` keep their names and meaning for every view: what the screen shows. They are recomputed by one function, `applyOverlay()`, whenever the Mac's bodies or the list change.
- `pending: [PendingChange]` and `rollbacks: [RollbackNotice]` mirror the queue for views.
- `submit(_ change:)` adds a change, updates the screen and starts a pass. `settleAccepted()` runs the re-read in §2.5. It uses `applyServerSnapshot(_:keepBundles: true)`, which keeps loaded days other than the default date. A normal `refresh()` keeps today's behaviour, dropping every day bundle.
- `WorkoutScreen` looks its workout up in the displayed bundle. When that day's bundle is not loaded, it falls back to the displayed snapshot's 14 days of workouts, so an offline Add past still opens.
- `activity.recentWorkouts` is rebuilt from the displayed snapshot after each submit, as `didEdit` does today.
- In fixture mode the queue sends to `FixtureEditAPI`, and `settleAccepted()` reads the snapshot from `FixtureEditAPI.snapshot()` and rebuilds day bundles the way `loadDay`'s fixture branch does.
- On a rollback, `AppModel` performs §2.6 steps 2, 4 and 5.

## 10. Dark launch

- Add `ios/GHealth/App/GoopFeature.swift` (removed in the edit plan's E12):

  ```swift
  enum GoopFeature {
      #if DEBUG
      static let instantSaves = true
      #else
      static let instantSaves = false
      #endif
  }
  ```

- **Gated call sites, and only these:** `EditSheet.mutate`, `ActivityPicker.add` and `AppModel.undoActivity`. With the flag on they build a change and call `submit`; with it off they run today's await-then-dismiss code.
- Rows, banners, locks and UPDATING read the queue. With the flag off the queue is never fed, so they never show. Do not branch on the flag below the call sites.
- §7 and §8 land unflagged.
- The plan's last step deletes the flag, the three `else` branches and the code only they used: `didEdit`'s `dropDayData()`, the Undo failure text and the sheets' busy states.

## 11. Fixtures and Debug launch arguments

### 11.1 FixtureEditAPI modes

`FixtureEditAPI` gains `mutationMode`:

| Mode | Mutations (`putEdit`, `deleteEdit`, `postActivity`) |
| --- | --- |
| `.answer` | today's behaviour: match the body, switch state, return |
| `.hold` | match the body, then suspend until the task is cancelled |
| `.offline` | throw `ClientError.offline`. Heart-rate reads still answer. |
| `.offlineOnce` | throw `ClientError.offline` on the first mutation, then behave as `.answer` |
| `.reject(ClientError)` | match the body, then throw the given error |

- A body that matches no `requests/*.json` still gets 400, so a wrong body fails a test loudly. Bodies compare with `EditBody ==`, which ignores the precondition.
- Add `fixtures/v2/edits/requests/edit_strength.json`: `edit.json` with `exercise_type` `WEIGHTLIFTING`. It is used only with `.hold`, so it needs no golden.
- `-GHealthMutationMode answer|hold|offline|offline-once|reject-404|reject-409|reject-400` (with `-GHealthFixture edit`) sets the mode for a normal launch; the default is `answer`.
- In fixture mode, becoming active still starts a sending pass. Today `becameActive()` returns early for fixtures; only the refresh part keeps returning early.

### 11.2 `-GHealthInstantFixture <key>` (with `-GHealthFixture edit`)

Each key starts from a state, submits one change through the real `submit` path as if its commit had been tapped, and opens a screen:

| Key | Start state | Change and mode | Opens | Mockup |
| --- | --- | --- | --- | --- |
| `saving` | `unedited` | `edit.json`, `.hold`, then waits 0.7 s | workout screen for `…0101` on 2026-03-10 | `saving` |
| `waiting` | `unedited` | `edit.json`, `.offline` | the same workout screen | `waiting` |
| `home-waiting` | `edited` | `name.json`, `.offline` | Home on 2026-03-12 | `home-waiting` |
| `updating` | `edited` | `edit_strength.json`, `.hold`, then waits 0.7 s | Strain screen on 2026-03-10 | `updating` |
| `rollback` | `unedited` | `edit.json`, `.reject(.notFound)` | Home on 2026-03-12 | `rollback` |
| `delete-waiting` | `edited` | `delete.json`, `.offline` | Home on 2026-03-12 with the Undo banner, which does not expire in this key | `delete-waiting` |

- The heart-rate body each projection needs is the matching `heart_rate_*.json` that `FixtureEditAPI` already serves.
- Release builds must contain no `-GHealthInstantFixture`, no `FixtureEditAPI` and no `edit_strength`. The plan's Release check adds them.

## 12. Tests

### 12.1 Go

- **Gzip** (`internal/serve`): `Accept-Encoding: gzip` on the snapshot gives `Content-Encoding: gzip` and `Vary`, and the body inflates to the identity body byte for byte. No header gives identity. `gzip;q=0` gives identity. A body under 1,024 bytes (an edit PUT response) stays identity. Error bodies over the threshold are compressed. The log has no new fields.
- **Precondition** (`internal/activities`, `internal/serve`): a matching time stores; a stale time gives 409 with the message; null with a stored edit gives 409; null with none stores; an absent key stores (today's behaviour); a replay of the stored body with a stale time gives 200 (step 2 before step 3); a time with a different sub-second part matches. The CLI `activity edit` is unchanged.
- **Goldens:** `fixtures/v2/errors/` gains nothing (the code is still `conflict`); the edit fixtures are unchanged.

### 12.2 GHealthCore (`make ios-core-test`)

- **Decoding:**
  - every JSON body under `fixtures/v2/` (the app's fixture set) decodes with the new strategy;
  - its dates equal today's parser's to within 0.001 s;
  - a guard decodes `snapshot_edited.json` 20 times in under 1 s in a debug build (today about 5 s).
- **Session:** two `APIClient(baseURL:token:)` values share one session (`===`), and the widget variant uses the other.
- **Overlay against the Go goldens**, using the heart-rate fixtures for the projections:

  | Start | Change | Must equal |
  | --- | --- | --- |
  | `snapshot_unedited` | `edit.json` | `snapshot_edited` |
  | `snapshot_edited` | `merge.json` | `snapshot_merged` |
  | `snapshot_edited` | `delete.json` | `snapshot_deleted` |
  | `snapshot_deleted` | Undo | `snapshot_edited` |
  | `snapshot_edited` | Restore | `snapshot_unedited` |
  | `snapshot_edited` | `name.json` | `snapshot_named`, including `day.workouts` on 2026-03-12 |
  | `snapshot_edited` | `add.json` | `snapshot_added` |

  "Equal" means the same workout ids on every date, and for each changed workout the same `exerciseType`, `displayName`, `category`, `cycleDate`, `start`, `end`, `elapsedMinutes`, `strain`, `trimp`, `hrCoverage`, `confidence`, `avgHrBpm`, `peakHrBpm`, `zonesMinutes`, `notes`, `edited`, `origin`, and `edit` without `updatedAt`. Strain and TRIMP are compared to 1 decimal, coverage to 2, integers exactly.
- **Overlap rules:** the named and added cases remove their efforts; a goop window over a recorded one hides it; an absorbed pair never hides; dates outside `cycleDates` are untouched.
- **Patch idempotence:** applying a change over a body that already contains it changes nothing.
- **Queue,** with a stub `EditAPI` and a stub upload runner:
  - every row of §2.4;
  - uploads run before changes;
  - serial order;
  - stop-on-`waiting` marks the later changes;
  - the §2.6 cascade;
  - each row of the §2.8 table, including no notice after an undo-requested refusal;
  - Undo after a delete accepted with an undecodable body (§5.2): the replay comes first; a decodable 200 supplies the precondition; a second undecodable 2xx sends the Undo with no precondition; a 409 on the replay rolls the Undo back; a 5xx leaves it `waiting`;
  - settle removes only changes accepted before the re-read;
  - save, reload and relaunch with each state;
  - a different `serverURL` is dropped;
  - pairing again with the same `serverURL` keeps every change, and pairing with a different one empties the list;
  - `clear()`.
- **Timing:** `markerVisible` at 0.59 s and 0.61 s, and the 0.5 s minimum.
- **Precondition encoding:** absent, `null`, or a whole-second time; `==` ignores it.
- **Copy:** every row of the §6.7 rollback table, and the waiting banner for 1 and 3.

### 12.3 UI (XCUITest, fixture mode)

- **`testInstantEditFlow`** (`edit` + `unedited`, `-GHealthMutationMode hold`). The PUT never answers, so with today's code the sheet would stay open with a disabled commit.
  1. Pencil, Sport, search `box`, BOXING, USE BOXING, drag `edit-handle-start` left, type the note, SAVE BOXING.
  2. Within 2 s the sheet is gone, the subtitle starts `17:56` and the page shows `workout-notes`.
  3. The subtitle then reads `… · Saving to your Mac`, and the pencil is absent.
  4. `FixtureEditAPI` logged `edit`.
- **`testInstantStatesTour`:** captures each §11.2 key as `instant-<key>.png`.
- **`testInstantRollbackAndUndo`:**
  1. `rollback`: the Home banner text matches §6.7.
  2. Go back three days on Home's date control to 2026-03-10 and open the KICKBOXING row. The workout screen reads KICKBOXING `18:05 to 19:02` and shows the same `NOT SAVED` banner.
  3. Dismiss it there; back on Home it is gone too.
  4. Relaunch with `delete-waiting` and tap UNDO. The Undo and waiting banners are gone, the BOXING row is back on 2026-03-10, and `FixtureEditAPI` logged no request.
- **`testInstantWaitingClears`** (`edit` + `unedited`, `-GHealthMutationMode offline-once`):
  1. Edit and save as in `testInstantEditFlow`.
  2. Assert `change-waiting-banner` and the Home waiting banner.
  3. Send the app to the background and activate it again.
  4. Assert both banners are gone, the subtitle reads ` · Edited`, and the pencil is back.
- **Existing tests:** `testEditFlow`, `testEditMergeDeleteUndo` and `testNameEffortAndAddPast` still pass with the flag on. The Debug default is on, so they now run the new path; adjust only waits that assumed a delay.
- **Full suite:** only `testBackgroundRefreshProbe` is skipped.

## 13. Decisions made in this spec

1. **Research behind the mockup.**
   - WHOOP's Home sync strip ("DATA CAUGHT UP · SYNCED TO 13:46" with a check) and its "Sleep Pending" card with grey `--` and "Pending" values: Reddit screenshots of the current app, 2026-11-16.
   - Garmin Connect's My Day with the circular-arrows sync control and its progress line: a MakeUseOf guide screenshot.
   - Oura's Add-activity sheet (Oura help centre) shows no pending state, so there was nothing to borrow.
   - The patterns used are in §0. The mockup builds them only from `GoopBanner`, `GoopActivityRow`'s status slot and `GoopMetricRow`.
2. **Overlay model** (§2.1). Keep the Mac's bodies untouched and draw pending patches on top, rather than editing the cache in place. Rollback, relaunch and a re-read landing mid-flight are then all the same recomputation.
3. **Phone values are exact, so nothing dims** (§5.1, §6.2). The projection uses the parity-tested estimator. The workout's own values show at full strength with only a words marker. **(lead?)**
4. **UPDATING applies to STRENGTH only** (§5.4). Day Strain does not depend on activities, so the issue's example does not apply. **(lead?)**
5. **Markers wait 0.6 s** (§6.1), so saves at home show nothing. **(lead?)**
6. **Words, not a spinner** (§6.2, §6.3). DESIGN.md requires a sentence for every pending state and allows no motion beyond rings. `SAVING` reuses the `WAITING FOR MAC` slot.
7. **Locks while pending** (§2.7). They keep changes independent, so a refusal never cascades except Undo after Delete. The cost: no second edit of the same activity until the first is accepted and re-read, usually under half a second.
8. **Restore projects the absorbed entries too** (§5.2), so "Anything merged into it comes back" is true on the tap.
9. **Offline:** queue and retry (§3). **Lead decision needed.**
10. **No expiry or discard for waiting changes** (§3.2). **(lead?)**
11. **Precondition `if_updated_at`** (§8.2). It turns a silent overwrite of a Mac-side edit into a visible rollback. It is tied to decision 9 and becomes optional under the alternative. **(lead?)**
12. **Gzip** (§8.1). Justified by the 3-flight snapshot and the 83 KB heart-rate day body, which also block the two sheets as they open.
13. **Transport and decoding fixes ship unflagged** (§7). They change no screen, and every refresh, widget update and sheet open gets faster.
14. **Create stays as it is** (§4.8). It already shows its result before talking to the Mac.
15. **Trends are not overlaid** (§5.4); they update when the change settles.

## 14. Out of scope

- Opening the Edit sheet or PAST mode without the Mac. The preview needs heart rate.
- A list or screen of pending changes, a discard button, or editing a waiting change.
- Overlaying trends, `days` counts or the brief.
- Predicting new detected efforts uncovered by a shorter window.
- Background sending while the app is suspended. Changes send when the app is active, as live uploads do.
- Server-side snapshot caching, fewer `fsync`s, or Keychain caching (§8.3).
- Any change to Create (live), its banners or its 0.35 s delay.

## 15. Lead decisions (2026-11-16)

- **Offline (§3, decision 9).** Queue and retry, as recommended. The owner asked for saves that "sync with the Mac in the background", and a dropped cellular request must not undo a finished edit.
- **Re-pairing (§2.9), changed.** Pairing again with the same Mac keeps pending changes. Only unpairing, or pairing with a different Mac, empties the list.
- **Approved as written:**
  - decision 3: phone values at full opacity;
  - decision 4: UPDATING on the STRENGTH row only, since Day Strain does not depend on activities;
  - decision 5: the 0.6 s marker delay;
  - decision 7: locks;
  - decision 10: no expiry and no discard in this spec;
  - decision 11: `if_updated_at`;
  - decision 12: gzip;
  - decision 13: the transport and decoding fixes unflagged;
  - decision 14: Create unchanged;
  - decision 15: Trends not overlaid.
- **Rollback wording for a 404.** "<Name> changed on your Mac." is accepted for both 404 and 409. It is true from the owner's point of view, whether the band record changed or the activity was edited on the Mac.
- **Undo when the delete's answer could not be read (2026-11-16, raised by the build at I7).** The sender replays the delete to learn its `updated_at`, as §5.2 now says. A second unreadable 2xx sends the Undo with no precondition, so the replay can't loop. This is the only chain that needs a mutation's response. Every other precondition comes from the re-read snapshot, because locks (§2.7) hold a second change until the first settles.
