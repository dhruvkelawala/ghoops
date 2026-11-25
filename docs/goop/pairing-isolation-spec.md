# ghoops: keep each Mac's data with that Mac (issue #32, pairing isolation)

Status: approved. The lead approved it on 2026-11-22, with both §6 calls as recommended. Written 2026-11-22 against `main` at `09fe785`. The build plan is [pairing-isolation-plan.md](pairing-isolation-plan.md). The mockup is [mockups/pairing-isolation.html](mockups/pairing-isolation.html), rendered per screen in `mockups/screens/pairing-isolation-<key>.png`. The problem statement is [oss-release-plan.md](oss-release-plan.md) §3.

A phone paired with Mac A, then re-paired with Mac B, can send A's offline workout to B and can fill B's cache with A's snapshot. This spec ties every piece of phone-side work to the Mac it was made for, so nothing crosses a switch. It is the smallest change that does that. Unsent work stays on the phone for its own Mac, and the person can send it on or discard it.

## 1. Where data crosses today

`A/` is `ios/GHealth/`, `C/` is `ios/GHealthCore/Sources/GHealthCore/`. Line numbers are at `09fe785`.

| # | Path | What goes wrong | Code |
| --- | --- | --- | --- |
| X1 | Offline workout | `activities-local.json` rows carry no Mac. `retry` sends every pending row to whichever API the last refresh supplied. | `A/App/AppModel.swift:185`, `C/Live/ActivityStore.swift:59` |
| X2 | Live session | `live-session.json` carries no Mac. A session started for A that ends after a switch saves a row that then goes to B. | `A/Live/ActivityController.swift:94` |
| X3 | Display | A's local rows merge into B's Today, workout pages and activity picker. | `A/App/InstantChanges.swift:35` |
| X4 | Shared refresh | `SnapshotRefresher.shared` hands A's in-flight result to a caller asking for B. | `C/API/SnapshotRefresher.swift:9` |
| X5 | Late refresh | `refresh()` applies whatever comes back, after a switch too. The response is written to disk first. | `A/App/AppModel.swift:191`, `C/API/APIClient.swift:136` |
| X6 | Torn cache | `snapshot.json` and `snapshot-meta.json` are two writes. The app and the widget are two processes, so their writes can interleave and pair one Mac's body with the other's URL. | `C/Cache/SnapshotStore.swift:51-52` |
| X7 | Widget | A fetch that started before a switch is shown after it. | `GHealthWidgets/ScoresProvider.swift:41` |
| X8 | Other late reads | Activity history and Test connection apply results that arrive after a switch. | `A/App/AppModel.swift:171`, `:263-267` |
| X9 | Token rotation | A 401 marks a pending activity `rejected` for good. A workout queued while the owner runs `ghoops pair --rotate` is never sent. | `C/Live/ActivityStore.swift:74` |

Already safe, and unchanged by this spec:
- **The edit queue.** Edits and ADD carry `serverURL` (`C/Changes/ChangeQueue.swift:30`), and a switch clears the queue.
- **Day bundles.** They are guarded by `bundleRevision`.
- **Accepted-change reads.** They are guarded by `changePass`.
- **Trends.** `TrendStore` is rebuilt for each snapshot.

## 2. Decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | A pairing is identified by its server URL, `credentials.url.absoluteString`. | The snapshot cache and the edit queue already key on it. `pair --rotate` keeps the URL, so rotation stays the same pairing. Keying on the token would strand work at every rotation. |
| D2 | Activities and the live session record their Mac, `PairedMac {url, name}`, when they are created. A session passes its Mac to the activity it saves. A row without one has an **unknown origin**. That covers every row written before this change. | The name is only for display ("Saved for <name>"). Equality is by URL. |
| D3 | The activity store holds the binding, the bound Mac with its API. It uploads only that Mac's pending rows and re-checks the binding before each one. When the binding changes, the pass stops. | One owner for the binding, so a Mac and an API from different pairings can never meet. Today the API is set from four places in `AppModel`. |
| D4 | Pending rows for another Mac, or of unknown origin, are **unsent**. They are kept and never shown on Today, workout pages or the picker. They are never sent automatically. Re-pairing with their Mac sends them. A new page under More lists them, with SEND TO \<this Mac\> and DISCARD ALL. | The plan allows keeping or discarding. Unknown rows need an explicit choice, because the phone can't tell whether the current Mac is their original one or the next one. SEND TO is offered for every group, not just unknown rows. The usual switch is one person moving to a new or renamed Mac, and an explicit tap is not an automatic send. Pattern: Strava's watch app lists unsent work under Settings › Unsynced, with a manual sync. |
| D5 | A 401 on upload leaves the row pending and ends the pass. It used to mark the row `rejected`. Every other 4xx is unchanged. | This keeps token rotation working for queued workouts. After re-pairing with the new link, the row is sent. It amends [activity-spec.md](activity-spec.md) "Uploading". |
| D6 | Pairing with a different Mac is refused while an activity runs for another Mac. The message is "Finish your activity before you pair with another Mac." Re-pairing with the same URL (rotation) is allowed. Unpair is allowed, and the session keeps its Mac. | The live estimate and target come from the paired Mac's day. Switching mid-session would mix B's heart-rate profile into A's activity. The sentence uses the existing pairing-error slot: the Pairing screen when unpaired, Home's error banner when paired. That is where a failed Replace pairing shows today. |
| D7 | The snapshot cache becomes one file, `snapshot-cache.json`, holding meta and body in one atomic write. The store reads the paired URL from the App Group defaults. `load` returns nothing for another Mac. `save` for another Mac throws `CancellationError` and writes nothing. The old two files are deleted on the first save and not read. | One write can't tear. The paired-URL check stops late writes in both processes. Not migrating costs one refresh after the update; the widget refetches when it has no cache. |
| D8 | The refresher joins only a flight for the same URL. A request for a different URL cancels the old flight and starts its own. A finished flight clears only its own slot. | Today a finished flight clears whichever flight is in the slot. |
| D9 | The app drops any result whose pairing changed while it waited: refresh, activity history and Test connection. The widget re-checks the paired URL before it shows a cache. | Late responses never reach B's screens. Cancelled and dropped results show no error (`ErrorCopy` already returns nil for cancellation). |
| D10 | The edit queue is unchanged: a switch still discards unsent edits and ADDs. The Replace pairing and Unpair alerts now count them, and count the activities that stay for the old Mac. | Confirming the alert becomes the explicit discard. Keeping A's edits for later would mean replaying them against A's records and edit horizon after an unknown gap. |
| D11 | Flag `GoopFeature.unsentActivities` covers the More row, the Unsent page and the new alert sentences. Everything else is the fix and ships unflagged. | With the flag off, unsent rows are kept and simply not listed. |

- **D1.** When both pairings have a profile ID, the IDs determine whether they identify the same Mac. When either ID is absent, compare URLs.
- **D2.** Activities and sessions store the profile ID when available. The first successful status or snapshot fills it in on pending rows and sessions for that address. The edit queue also keeps its changes when the same profile moves to a new address.
- **D7.** The snapshot cache records the profile ID from its status body. Cache reads and writes use the same comparison as the queues. The app and widget read the paired Mac from the Keychain record.

Rejected:
- **Adopting unknown rows into the current pairing at first launch.** The release plan forbids it, and the phone can't tell the original Mac from the next one.
- **Deleting the old Mac's cache on a switch.** Isolation doesn't need it, because the cache is never shown for another Mac. Clearing local data is part of the separate privacy-text item.
- **A Home banner for unsent rows.** It would nag about a rare state that the alert has already explained. The More row is enough.

## 3. Behaviour

### 3.1 Data

- `PairedMac` (Core): `url: String`, `name: String`, Codable, Sendable. Two values are equal when their URLs are equal.
- `LocalActivity.mac` and `ActivitySession.mac`: `PairedMac?`, encoded as `mac: {url, name}`. A row without the key decodes with `nil`. `LiveEstimator.localActivity` copies the session's Mac.
- `PairingError.activityRunning`, with the description "Finish your activity before you pair with another Mac."

### 3.2 Activity store (`C/Live/ActivityStore.swift`)

| Call | Does |
| --- | --- |
| `bind(_ mac: PairedMac?, api: (any ActivityAPI)?)` | Sets the binding. `nil` means unpaired. |
| `retry(now:)` | Uploads pending rows whose Mac equals the bound Mac, oldest first. Before each row it checks that the binding is still the one it started with, and it stops if not. Each row uses the current binding's API, so a rotated token takes effect mid-pass. A 401 leaves the row pending and stops (D5). Other results are unchanged. |
| `delete(id:now:)` (from the Mac) | Uses the bound API. It refuses (`ClientError.unauthorized`) when a local row with that id belongs to another Mac or has no Mac. With no local row, it deletes on the bound Mac as today. |
| `held(now:)` | Pending rows whose Mac is not the bound Mac, including `nil`. |
| `adopt(ids:now:)` | Sets the bound Mac on those unsent rows. The next `retry` sends them. |
| `discard(ids:now:)` | Deletes those rows from the phone only. |

`activities(now:)`, `save`, the session calls and the seven-day pruning of uploaded rows are unchanged. Non-pending rows for another Mac stay hidden. Uploaded ones age out as today, and rejected ones show again if that Mac is paired again.

`ActivityController` keeps a copy of the bound Mac. A new session takes it. `local` holds only the bound Mac's rows, and `held` holds the unsent ones. The four `activity.api = …` assignments in `AppModel` become `await activity.bind(credentials)`. In fixture mode the controller binds `PairedMac(url: "https://fixture.invalid", name: "Fixture Mac")` with no API.

### 3.3 Snapshots

- `SnapshotStore(directory:allowSynthetic:pairedURL:)`. `pairedURL` is a `@Sendable () -> String?` that every caller passes: the app and widget pass `PairingRepository.pairedURL()`, which reads `serverURL` from the App Group defaults; tests pass their own.
- `snapshot-cache.json` is `{"meta": SnapshotMeta, "snapshot": <body bytes>}`, written once, atomically, with the same file protection as today.
- `load()` returns `nil` when the file is missing, when `meta.serverUrl != pairedURL()`, or when nothing is paired. Decode failures throw as today.
- `save(_:serverURL:fetchedAt:)` throws `CancellationError` when `serverURL != pairedURL()`. Otherwise it writes the file and deletes `snapshot.json` and `snapshot-meta.json` if present.
- `SnapshotRefresher` follows D8. `FixtureTransport` passes its fixture URL.

### 3.4 App wiring (`A/App/AppModel.swift`, `GHealthWidgets/ScoresProvider.swift`)

- `pair(url)`: parse `PairingLink` first. If `activity.session` exists and its Mac's URL differs from the link's, report `PairingError.activityRunning` with the `.pair` context and return before any request. Otherwise it proceeds as today, then binds the activity store to the new Mac.
- `unpair()`: binds `nil` (it was `activity.api = nil`).
- `refresh()`, `loadActivityHistory()`, `testConnection()`: capture the URL before the request. When `credentials?.url` differs afterwards, return without touching state, errors or `invalidPairing`.
- Widget `load()`: after any refresh, keep `cached` only if `cached.meta.serverUrl == PairingRepository.pairedURL()`.

### 3.5 What the person sees (flag `unsentActivities`, except the D6 sentence)

- **More → MAC.** When there are unsent rows, a `GoopRow` `UNSENT ACTIVITIES` with value `<n>` and `.push` disclosure follows TEST CONNECTION. Tapping it pushes `Route.unsent`.
- **Unsent page.** `GoopDetailHeader("UNSENT")` with back. Groups are ordered by their newest row.
  - Label: `GoopSectionLabel` `SAVED FOR <NAME>`, or `SAVED BEFORE THIS UPDATE` for unknown origin.
  - Rows: one `GoopRow` per activity. Label: the sport name in uppercase. Value: `Tue 10 Mar · 18:05–19:02`, using `GoopFormat`'s existing day and time formats.
  - Caption: "Sent when this iPhone is paired with <NAME> again." for a known Mac, or "ghoops can't tell which Mac these were saved for." for unknown origin. `bodySmall` `text2`.
  - Button: outline `SEND TO <CURRENT NAME>`. It runs `adopt`, then `retry`. The rows move to Today as the current Mac's pending activities.
  - Last on the page: destructive `DISCARD ALL`, confirmed by `goopDestructiveAlert("Discard unsent activities?", verb: "Discard", message: "<n> activities are deleted from this iPhone. Nothing changes on any Mac.")`.
  - When the list becomes empty, the page pops back to More.
- **Replace pairing alert,** when the link's URL differs from the current one. The message is today's sentence, then up to two sentences:
  - "<n> unsent activit(y|ies) stay(s) on this iPhone for <NAME>." when the current Mac has pending rows.
  - "<m> unsent change(s) to <NAME> (is|are) discarded." when the edit queue holds changes not yet accepted.
  A same-URL link keeps today's message.
  - **Lead, 2026-11-24 (after the address check before contact and the profile binding):** the Replace alert opens before the phone contacts the new address, so the phone can't yet know whether that address serves the same Mac profile. If it does, the profile binding keeps the queued changes. Each counted sentence in the Replace alert therefore starts with "If this is a different Mac, " (for example, "If this is a different Mac, 2 unsent changes to <NAME> are discarded."). Address confirmation stays a single step. `PairingCopy` and test A9 follow this wording.
- **Unpair alert.** Today's message, then the same two sentences.
  - The Unpair alert keeps the counted sentences without the qualifier, because Unpair always leaves this Mac.
- **Blocked switch (unflagged, D6).** The sentence appears where pairing errors appear today.

The sentences are built by one Core function, `PairingCopy.switchMessage(base:activities:changes:mac:)`, so they can be tested.

## 4. Acceptance

**Two fake Macs.** The core tests use a host-routed `URLProtocol` with `mac-a.invalid` and `mac-b.invalid`. Each host has its own reply, its own request log, and a gate that holds a response until the test releases it. The tests use the real `APIClient`, `ActivityStore`, `SnapshotStore` and `SnapshotRefresher`, with temp directories and an injected paired URL. They make no other network call.

| # | Check | Pass |
| --- | --- | --- |
| A1 | Workout recorded offline for A stays with A | Save a pending row for A while A is offline, bind B with B online, then `retry`: B logs 0 `POST /v2/activities`, `held` has 1 row, and B's `local` is empty. Bind A online again and `retry`: A logs 1 POST for that id, and the row is `uploaded`. |
| A2 | In-flight A refresh can't fill B's cache | Start A's refresh with A's reply held. Switch the paired URL to B and refresh B to completion. Release A: A's call throws a cancellation, the store loads B's snapshot with meta URL B, and `snapshot-cache.json` holds B. Also in reverse order: when B's refresh is requested, A's gated request is cancelled. |
| A3 | Same-server offline recovery | A offline: `retry` leaves the row pending, `refresh` fails, `load` still returns A's earlier cache. A back: the row uploads and the refresh replaces the cache. |
| A4 | Token rotation | A answers 401 to the old token: the row stays pending (it isn't rejected) and the pass stops. Bind A with the new token: A's log shows `Authorization` with the new token and the row is uploaded. Two concurrent same-URL refreshes still make one request (the existing test). |
| A5 | Unknown origin never goes automatically | A row decoded from today's format (no `mac`), with B bound and online: `retry` makes 0 requests and the row is in `held`. After `adopt`, B logs 1 POST. After `discard`, the row is gone and no request is made. |
| A6 | Switch mid-pass | Two pending rows for A, with the first POST held. Bind B, then release: A logs exactly 1 POST and B logs 0. The second row stays pending. |
| A7 | Live session | A session started while A is bound finishes after `bind(nil)` and then `bind(B)`. The saved row's Mac is A, and it is in `held`. `ActivitySession.blocksPairing(with:)` is true for B and false for A. |
| A8 | Widget and cache reads | `load()` is `nil` when the paired URL is B and the cache is A's. Saving A's body while B is paired throws and leaves the file unchanged. |
| A9 | Copy | `PairingCopy` sentences for 0, 1 and 2 activities and changes, matching §3.5 exactly. |
| A10 | App, flag on (Debug) | An XCUITest with a DEBUG seed (two rows for "Other Mac", one of unknown origin) shows the More row with 3, the Unsent page with both groups, SEND TO moving one group onto Today, and DISCARD ALL emptying the page and removing the row. Screenshots are taken of each state. The Replace pairing alert, opened with a synthetic `https://mac-b.invalid` link on a fixture with one pending activity, shows the activity sentence. Fixture mode refuses to pair before any request. |
| A11 | App, flag off | A Release build shows no More row and today's alert text (`make ios-build` and a source check of the flag). |
| A12 | Regression | `make check`, `make ios-core-test`, and the full `make ios-test` on a Simulator created for the run, with only the known skip. |

## 5. Out of scope

- **The README and privacy-text corrections** in release plan §3, paragraph 2. They are a separate item.
- **A Mac whose URL changes. Resolved.** Re-pairing after a rename delivers its pending work when both pairings identify the same profile.
- **Clearing cached data on unpair.**

## 6. Calls for the lead

Answered 2026-11-22: both as recommended.

1. **D4.** Offer SEND TO for another Mac's rows as well, not only for unknown-origin rows. Recommended: yes.
2. **D6.** Refuse to switch Macs while an activity runs. The alternative ends the activity and saves it for the old Mac. Recommended: refuse.
