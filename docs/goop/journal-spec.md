# ghoops: Journal

Status: approved by the lead on 2026-11-22 (spec commit `d0492fc`): the default five stand as the proposal for the owner to confirm, and there is no significance test. Written 2026-11-22 for issue #3. The build plan is [journal-plan.md](journal-plan.md); the mockup is [mockups/journal.html](mockups/journal.html).

Every morning the owner answers a few yes/no questions about the day before: alcohol, late caffeine, a late meal. The Mac stores the answers encrypted. Once a behaviour has enough "yes" and "no" mornings, ghoops shows how Recovery after "yes" compares with Recovery after "no". It always calls this an association, never a cause.

## 0. Precedence and decisions

- This spec extends [spec.md](spec.md), [contract.md](../v2/contract.md), [scores.md](../v2/scores.md), [data.md](../v2/data.md) and [DESIGN.md](../../DESIGN.md). Where they disagree, this spec wins for the features described here.
- **It reopens Journal.** [spec.md §16](spec.md) put Journal out of scope. The owner listed #3 for the build on 2026-11-22, which brings it back in.
- **Two slices.**
  - Slice 1, logging: the Mac stores answers (CLI and HTTP), and the phone asks the questions and saves the answers.
  - Slice 2, the relation to Recovery: the Mac computes each behaviour's difference, and the phone shows it.
- **Owner-decision defaults (2026-11-22), until the owner says otherwise:**
  1. Journal answers stay on the Mac and the paired phone. They are left out of `brief`, `day`, `days` and every other body that agents read (§6.4).
  2. The default behaviour list in §2 is a proposal. The owner confirms it later and can change it with one command (§5.4).
  3. The owner approves the mockup before the flag goes live. Until then the phone screens stay behind `GoopFeature.journal`, which is on in Debug and off in Release (§8.5).
- **Changes from the issue's sketch**, each explained in §11:
  - the behaviour list lives in the encrypted journal file, not in `config.json`;
  - `day.journal` becomes `snapshot.journal`, so the `day` body that agents read stays free of answers;
  - `brief` carries nothing from the journal, not even directions;
  - there is no `journal impact` command, because `journal show` carries the impact;
  - assistant changes are out of scope until the owner decides about agents.
- **Mockup:** [mockups/journal.html](mockups/journal.html), one phone per key, rendered to `mockups/screens/journal-<key>.png`:

  | Key | Screen |
  | --- | --- |
  | `recovery` | Recovery detail for today, scrolled to the Journal section: answers card, ANSWER JOURNAL and BEHAVIOUR IMPACT |
  | `sheet` | The JOURNAL task sheet with three of five answered and SAVE ANSWERS enabled |
  | `waiting` | The Journal section after a save the Mac has not received yet |
  | `first` | The Journal section on first use: nothing answered and no impact yet |

  The renders use synthetic values. Layout, colours, type, copy and icons must match.
- Points the lead should check are marked **(lead?)**.

## 1. What WHOOP and Oura do

| | WHOOP Journal | Oura tags | ghoops |
| --- | --- | --- | --- |
| When | A morning prompt "about the day before", once sleep has processed ([WHOOP Journal][w-journal]) | Any time, for the current or a past day ([Oura, Using Tags][o-tags]) | From Recovery detail, about the day before that Recovery |
| Answer | Yes or no; some behaviours add a time or quantity | A tag is present or absent | Yes or no |
| Unanswered | Not counted | No way to say "no": an untagged day looks the same as an unlogged one | Not counted |
| Past days | Editable up to 14 days back | Editable from the calendar | The Mac's edit horizon (`status.edit_limits.horizon_days`) |
| List | 300+ behaviours in a library, plus custom ones | 100+ searchable tags, plus custom tags of up to 32 characters | 10 built-in behaviours, 5 on by default (§2) |
| Result | After at least 5 "yes" and 5 "no" answers within 90 days, which behaviours "are associated with higher or lower Recovery, and by how much" ([Behavior Insights][w-behaviour]) | Tags "don't directly change your daily scores"; you look for patterns in Trends | WHOOP's rule, with both counts on every row (§4) |
| Wording | "associations in your own data, not causes" | none | "Associated with", never "causes" |

Borrowed: WHOOP's morning yes/no about the previous day, its 5-and-5-in-90-days rule, and its habit of showing the counts next to the result. ghoops does not use Oura's presence-only tags, because a missing tag cannot tell "no" from "forgot to log".

## 2. Behaviours

The Mac holds a fixed catalogue. Each behaviour has a key, a name and a question. The phone shows the Mac's name and question and keeps no copy.

| Key | Name | Question | On by default |
| --- | --- | --- | --- |
| `alcohol` | Alcohol | Did you drink any alcohol? | yes |
| `late_caffeine` | Late caffeine | Any caffeine after 14:00? | yes |
| `late_meal` | Late meal | A large meal close to bedtime? | yes |
| `screen_in_bed` | Screen in bed | Used a phone or screen in bed? | yes |
| `stress` | Stress | Did you feel stressed? | yes |
| `sick` | Feeling ill | Did you feel ill or run down? | no |
| `travel` | Travel | Did you travel? | no |
| `sauna` | Sauna | Did you use a sauna? | no |
| `cold_exposure` | Cold exposure | An ice bath or a cold shower? | no |
| `melatonin` | Melatonin | Did you take melatonin? | no |

- All ten appear in WHOOP's or Oura's lists. The five defaults are things the band cannot see that commonly move overnight heart rate and HRV. Training is left out because Strain already measures it.
- The enabled set is always shown in catalogue order.
- Custom behaviours are out of scope. Adding one to the catalogue is a one-line Mac change.
- **(lead?)** The owner confirms the default five.

## 3. Dates

- An answer belongs to a **journal date** E: the London date of the day it describes.
- It may affect the Recovery of cycle date **E + 1**, the morning after. Recovery for date D comes from the night ending on D (scores.md §2.1).
- **Allowed dates:** `default_date − horizon_days ≤ E ≤ default_date`, where `horizon_days` is `status.edit_limits.horizon_days` (contract §5.11). This is the edit horizon applied to the Recovery date E + 1. E = `default_date` lets the CLI log an evening before it ends.
- Anything outside that range is `not_found`, the same as a sleep edit outside its horizon.

## 4. The relation to Recovery (slice 2)

Pure function in `internal/score`. For each enabled behaviour b, as of `default_date` D:

```
window = Recovery dates R from D − (JournalWindowDays − 1) to D
for each R in window:
    a = the answer for b on journal date R − 1      # true, false or absent
    v = Recovery(R).value                             # the reported integer, or null
    if a is present and v is not null: add v to yes (a true) or no (a false)
status = "ok" if len(yes) ≥ JournalMinAnswers and len(no) ≥ JournalMinAnswers else "insufficient"
if ok:
    yes_mean = mean(yes), no_mean = mean(no)          # 1 dp in output
    difference = round1(mean(yes) − mean(no))         # from unrounded means
    direction = "higher" if difference > 0, "lower" if < 0, "same" if 0.0
```

- **Constants:** `JournalWindowDays = 90` and `JournalMinAnswers = 5`, from WHOOP's rule. They are display constants: no score uses them, so `score_version` does not change (scores.md §0).
- **They reach the phone** in `score_constants.journal` (§6.3). The phone never copies them.
- **Recovery values:** the reported integer, so a reader can recompute the result from `days` rows (scores.md §1.1). A calibrating Recovery with a value counts. A null Recovery does not count, and neither does its answer.
- **Honesty rules:**
  - No mean, difference or direction is reported until both sides reach the minimum.
  - Both counts are always reported, and the phone shows them on every row.
  - The copy says "associated with" and never "causes", "improves" or "hurts".
  - The footnote says that fewer mornings make the difference less certain.
- **Not done:** significance tests, confidence intervals, effects on Sleep or Strain, quantities and times. §11 decision 6 says why.

## 5. Mac: store and CLI (slice 1)

### 5.1 Store

- **File:** `<state dir>/journal-v2.enc`, beside `activities-v2.enc`. It uses the same AES-256-GCM envelope (header `ghealth-cache-v2\n`, the header and service as additional data) and the same Keychain key.
- **Plaintext inside the envelope:**

  ```json
  { "version": 1,
    "behaviours": ["alcohol", "late_caffeine", "late_meal", "screen_in_bed", "stress"],
    "entries": [ { "date": "2026-03-09", "answers": { "alcohol": false, "late_meal": true }, "updated_at": "2026-03-10T07:42:00Z" } ] }
  ```

  `behaviours` null means the defaults. `answers` maps catalogue keys to booleans. A key with no answer is absent.
- **Writes:** atomic rename under its own advisory lock, `journal.lock`. The collector and the activity routes never touch this file.
- **Retention:** every write drops entries whose date is more than 400 days before the London date of `now`.
- **Missing file:** the defaults and no entries.
- **Unknown keys:** answers for a key that is no longer enabled stay stored and are ignored, so turning a behaviour back on restores its history.
- **The server** reloads the file when its modification time or size changes, as it does for activities (contract §7.4).
- **No behaviour key or answer appears in plaintext** on disk, in logs or in error messages.

### 5.2 `ghoops journal show [--days N]`

Prints the `journal` body (§6.1). N is 1 to 90, default 30; the range ends at `default_date`.

### 5.3 `ghoops journal set [--date D] KEY=yes|no|clear …`

- Reads the stored entry for D, applies each argument, and stores the result. `clear` removes that answer. An entry left with no answers is removed.
- `--date` defaults to `default_date − 1`, the evening before today's Recovery.
- Validation matches the PUT (§6.2): a key outside the catalogue, a value other than `yes`, `no` or `clear`, or no `KEY=` argument at all is usage exit 2 with `Invalid journal field: answers.`. A date outside §3 is exit 2 `not_found`.
- Prints the `journal_entry` body. It sends no precondition.

### 5.4 `ghoops journal behaviours [set KEY[,KEY…] | reset]`

- Without a subcommand, prints `journal_behaviours`: every catalogue behaviour in order as `{key, name, question, enabled, default}`.
- `set` replaces the enabled set: 1 to 10 distinct catalogue keys, otherwise exit 2 with `Invalid journal field: behaviours.`.
- `reset` stores null, which means the defaults.
- This is a Mac setting, so there is no HTTP route for it (DESIGN.md: settings live on the Mac).

## 6. Mac: HTTP and bodies (schema 2, additive)

### 6.1 `GET /v2/journal` and the `journal` body

Query: `days` (optional, 1 to 90, default 30). Any other parameter is `invalid_request`.

| Field | Type | Rule |
| --- | --- | --- |
| envelope | | contract §5.1, `kind: "journal"`, with `score_version` and without `score_config` |
| `default_date` | Date | |
| `from`, `to` | Date | `to = default_date`, `from = to − (days − 1)` |
| `behaviours` | array | the enabled set in catalogue order, each `{key, name, question}` |
| `entries` | array | stored entries with `from ≤ date ≤ to`, ascending, each `{date, answers, updated_at}`. Dates with no entry are absent. |
| `impact` | object | slice 2 (§6.3). Absent from a slice-1 Mac. |

`ghoops journal show` prints the byte-identical body (contract §1.1).

### 6.2 `PUT /v2/journal/<date>`

```json
{ "answers": { "alcohol": false, "late_caffeine": true, "late_meal": true }, "if_updated_at": null }
```

- **Transport:** bearer authentication, `application/json`, at most 64 KiB, no query string. Any other method on this path is `method_not_allowed` with `Allow: PUT`. `/v2/journal/` is `not_found`.
- **Replace:** the body's `answers` becomes the stored entry for the date. The phone therefore sends every answer it wants kept, including answers for behaviours it does not show (§8.3). `{}` removes the entry.
- **Lookup:** a malformed date or one outside §3 is 404 `not_found`.
- **Validation:** 400 `invalid_request` with `Invalid journal field: <field>.`:

  | Field | Fails when |
  | --- | --- |
  | `body` | not a JSON object |
  | `answers` | missing, not an object, a key outside the catalogue, or a value that is not `true` or `false` |
  | `if_updated_at` | present, non-null and not RFC 3339 |

- **Order of checks** under `journal.lock`, as for sleep edits (contract §7.2):
  1. Validate.
  2. If the answers equal the stored ones, answer 200 with the stored entry. A replay after a lost answer never trips the check.
  3. Otherwise, if `if_updated_at` is present and does not match, answer 409 `conflict` with `This day's journal changed on your Mac.`. Null means "I expect no entry"; a time must equal the stored `updated_at` truncated to the second.
  4. Otherwise store the answers with `updated_at = now`.
- **Response 200:** the envelope with `kind: "journal_entry"`, `date`, and `entry: {date, answers, updated_at}`, or `entry: null` after `{}`.
- **No DELETE route.** `{}` does the same job.

### 6.3 Slice 2 additions

- `journal.impact`:

  | Field | Type | Rule |
  | --- | --- | --- |
  | `from`, `to` | Date | the Recovery dates of §4's window |
  | `behaviours` | array | one per enabled behaviour, in `behaviours` order |
  | `….key` | string | |
  | `….status` | string | `ok` or `insufficient` |
  | `….yes_mornings`, `….no_mornings` | int | the counts of §4, always present |
  | `….yes_mean`, `….no_mean` | `num?` | 1 dp; null unless `ok` |
  | `….difference` | `num?` | 1 dp; null unless `ok` |
  | `….direction` | string? | `higher`, `lower`, `same`; null unless `ok` |

- `score_constants.journal` = `{window_days: int, min_answers: int}`, on every body that carries `score_constants` (contract §5.1.1). A Mac built before slice 2 omits it. A client then treats both numbers as unknown.

### 6.4 Where answers appear, and where they never do

- **They appear** only in `journal` and `journal_entry` bodies and in `snapshot.journal`. `snapshot.journal` equals `ghoops journal show` (default `days`) with the same `now`.
- **They never appear** in `day`, `days`, `sleep`, `workouts`, `status`, `heart_rate` or `brief`. `brief` gains nothing, not even directions.
- **Agent rule,** added to contract §9: agents must not read `journal`, `journal_entry` or `snapshot.journal`, or pass them to a model, until the owner decides otherwise. Assistant setups outside this repo are not changed.
- **Older Macs:** a Mac without this feature omits `snapshot.journal` and answers `not_found` on the journal routes. The phone then hides the Journal section.

### 6.5 Contract bookkeeping

- Envelope `kind` list (§5.1): add `journal`, `journal_entry` and `journal_behaviours`.
- Methods (§7.1): add `PUT /v2/journal/<date>`. Request bodies: add the journal PUT.
- CLI table (§3): add the three commands.
- `status.edit_limits.horizon_days` (§5.11): add "It also bounds journal dates (journal-spec §3)."
- Errors (§6): add the journal messages.
- data.md: add the `journal-v2.enc` paragraph after the activities one.

## 7. Fixtures (Go)

- **`fixtures/v2/journal/book_basic.json`:** a plaintext journal book for tests, `"synthetic_fixture": true`. It holds the defaults and entries for 2026-02-08 to 2026-03-09, built so that over `store_full` at the reference `now`:
  - one behaviour is `ok` and `higher`, one `ok` and `lower`;
  - one is `insufficient` with 4 "yes" mornings;
  - one has answers only on dates whose Recovery is null;
  - one has no answers.
- **Goldens:** `journal/journal_basic.json` (`journal show`) and `journal/journal_empty.json` (no file). Slice 2 regenerates both with `impact`.
- **Shared vectors:** `fixtures/v2/scores/journal.json`, pure cases for §4 (minimum edges, a null Recovery, rounding half away from zero, `same`). The Go tests and GHealthCore's decoder test read them.
- **Requests:** `fixtures/v2/journal/requests/*.json`, each with the body, the expected status and the field or message. They cover every row of §6.2, the horizon edges, the precondition, replay and `{}`.
- **Preview:** `scripts/goop_preview_fixtures.py` gains `add_journal`, which writes `snapshot.journal` into `preview/snapshot_fresh.json` and `snapshot_stale.json` from `journal_basic.json`, re-dated to the preview `default_date`. Slice 2 adds `score_constants.journal` in the same way.

## 8. Phone

### 8.1 Where it shows

- On **Recovery detail**, below the insight card and the CALIBRATING card, above Weekly Trends.
- A `heading` titled `Journal`, 30 above, as for Weekly Trends.
- Shown only when `GoopFeature.journal` is on and `snapshot.journal` exists. Journal date E is the selected date minus one. If E is outside `snapshot.journal`'s `from…to`, the whole section is hidden.

### 8.2 The section (mockup `recovery`, `waiting`, `first`)

1. **Answers card** (`GoopCard`):
   - Title row: the date as `MON 9 MAR` (`labelCard` white). At the right, `3 OF 5 ANSWERED` (`labelSmall`, `textSoft`); when nothing is answered, `NOT ANSWERED`.
   - One `GoopSheetRow`-style row per enabled behaviour: the Mac's name in `bodyMid` `legendText`, and at the right `YES` or `NO` in `labelSmall` white, or `—` in `text2`.
   - A `GoopFootnote`: `About the day before this Recovery. Your answers stay on your Mac.`
2. **ANSWER JOURNAL:** a full-width outline `GoopButton`, 12 below the card, as EDIT SLEEP sits under the night card. It opens the task sheet.
   - It shows only when E + 1 is editable: `EditLimits.editable(cycleDate: E + 1, …)`. Without `edit_limits`, the bound is dropped and the button always shows (edit-limits-spec).
   - It is hidden while a journal change for E is unsettled.
3. **BEHAVIOUR IMPACT card** (slice 2), 12 below. It shows only when `journal.impact` exists and the selected date is `default_date`. Impact is computed as of today, so it never appears under a past Recovery.
   - Title `BEHAVIOUR IMPACT` (`labelCard`).
   - One row per behaviour, split by `GoopDivider`:
     - **ok:** the name in `labelCard`. Under it, a `rowNote` in `text2`: `6 yes · 9 no`. At the right, the signed difference in Sofia `valueMid` (`+6.2`, `−8.8`, `0.0`) and the `GoopComparison` triangle using Recovery's colours (higher is mint and up, lower is amber and down, same is the neutral dot).
     - **insufficient:** the same name and counts. When `min_answers` is known, the note becomes `3 yes · 9 no · needs 5 of each`. The value is `—` in `text2`.
   - A `GoopFootnote` at the bottom: `Average Recovery after yes minus after no, over the last 90 days. Associated with, not caused by. Fewer mornings make it less certain.`. "90" is `window_days`. Without `score_constants.journal`, the first sentence is left out.
4. **Pending states** use the instant-saves vocabulary (DESIGN.md "Empty, loading and pending states"):
   - The answers card shows the phone's answers at once.
   - Its right-hand label becomes `SAVING` (`labelMicro` `text2`, after 0.6 s) or `WAITING FOR MAC` (`labelMicro` `caution`).
   - While the change waits, a `.strain` tinted `GoopBanner` with `arrow.triangle.2.circlepath` takes ANSWER JOURNAL's place: `Saved on your phone. It will be sent to your Mac when it can be reached.` (the activity-spec §2 sentence).
   - The impact card's title row shows `UPDATING` (`labelMicro` `text2`) while any journal change is unsettled, and keeps the Mac's last values.
   - A refusal shows Home's existing `NOT SAVED` banner naming `Journal, Mon 9 Mar`, and puts the Mac's answers back.

### 8.3 The JOURNAL task sheet (mockup `sheet`)

- A `GoopTaskSheet` titled `JOURNAL`, with × on the right.
- A `GoopSectionLabel` with the full date: `MONDAY 9 MARCH`.
- One row per enabled behaviour, 8 apart: a `controlFill` slab with radius 10 and padding 10×14.
  - On the left, the name in `labelCard` and the question below it in `rowNote` `text2`.
  - On the right, a `GoopRangeSelector` with `YES` and `NO`, and no segment selected while unanswered.
  - At accessibility sizes, the selector sits under the text.
- An answer can be switched but not cleared on the phone; `ghoops journal set KEY=clear` clears it. This keeps `GoopRangeSelector` unchanged.
- **Commit:** `SAVE ANSWERS` with `checkmark`, enabled when an answer differs from the stored entry.
- **Saving** follows instant saves:
  - The sheet closes on the tap.
  - The change goes to the existing `ChangeQueue` as kind `journal`, with request `putJournal(date, body)` and a `JournalPatch` applied over `snapshot.journal`.
  - The body holds every stored answer for E, including answers for behaviours the phone does not show, with the sheet's answers on top.
  - `if_updated_at` is the stored entry's `updated_at`, or null when there is none.
- **Offline: queued, like activities and edits.** See §11 decision 4.

### 8.4 GHealthCore

- **Models:**
  - `Journal`, `JournalBehaviour` and `JournalEntry` (answers `[String: Bool]`);
  - `JournalImpact` (slice 2);
  - `Snapshot.journal: Journal?`;
  - `ScoreConstants.journal: JournalConstants?` (slice 2).
- **Saving:**
  - `JournalDraft` (stored answers, sheet answers, `changed`, `body`);
  - `JournalPatch`, and `Overlay` support for it;
  - `PendingChange.Kind.journal`, `Request.putJournal` and `journalPatch`;
  - `EditAPI.putJournal(date:_:)` on `APIClient` and `FixtureEditAPI`.
- **Presentation:** `JournalText` builds the answered count, the impact notes and the footnote from the Mac's numbers. The goop lint's `enginenumber` rule must stay clean.

### 8.5 Flag and fixtures

- `ios/GHealth/App/GoopFeature.swift` is recreated:

  ```swift
  enum GoopFeature {
      #if DEBUG
      static let journal = true
      #else
      static let journal = false
      #endif
  }
  ```

  The flag stays off in Release until the owner approves the mockup and the lead turns it on in a later step that removes it.
- **Debug fixture sets:**
  - `fresh` carries `snapshot.journal` with entries and impact;
  - `journal_first` has no entries, and every behaviour `insufficient` with zero counts;
  - `journal_none` removes `snapshot.journal`, as an older Mac does;
  - `engine_none` also removes `score_constants.journal`.

## 9. Tests

- **Go,** through the binary and HTTP:
  - `set` then `show` returns the same answers;
  - no behaviour key in plaintext in `journal-v2.enc`;
  - entries older than 400 days are dropped on write;
  - every request fixture;
  - the precondition, replay and `{}`;
  - `behaviours set` and `reset`;
  - `journal_basic` and `journal_empty` goldens;
  - `snapshot.journal` equals `journal show`;
  - `day`, `days` and `brief` bytes do not change when a journal file exists;
  - logs carry no body.
  - Slice 2 adds the §4 vectors, the impact goldens, `score_constants.journal`, and a timing check (§10).
- **GHealthCore:**
  - decoding `snapshot.journal`, with and without `impact`;
  - `JournalDraft.body` keeps hidden answers;
  - `JournalPatch` over the snapshot;
  - the queue outcomes (accepted, waiting, refused) for `putJournal`;
  - `JournalText` with and without `score_constants.journal`;
  - the §4 vectors decode.
- **UI:** `testJournalFlow` with `fresh`: Recovery → ANSWER JOURNAL → answer → SAVE ANSWERS → the answers card updates. `testJournalHidden` with `journal_none`. Captures: `journal-recovery`, `journal-sheet` and `journal-first`, compared with the mockup.

## 10. Performance

Impact needs up to 90 Recovery values per snapshot. The builder computes Recovery only for dates R where E = R − 1 has an entry, and only Recovery, not whole day rows. Acceptance: `GET /v2/snapshot` on `store_full` with a 90-entry book is at most 20 ms slower than without a journal file, median of 20 runs (plan step J5).

## 11. Decisions made in this spec

1. **The list lives in `journal-v2.enc`, not in `config.json`.** `config.json` is plain JSON, and the list itself says something about the owner. Older binaries also reject unknown config keys (`DisallowUnknownFields`), so a rollback would break every route.
2. **`snapshot.journal`, not `day.journal`.** `day` and `days` are what agents read (contract §9.3). Keeping answers out of them keeps the owner's default. A new snapshot key is additive and leaves every existing body byte-identical.
3. **One journal body, three kinds.** `journal show` carries the impact, so `journal impact` would only repeat it.
4. **Offline answers are queued, like activities and edits.** The issue offered "queued like activities or refused like edits". Since instant saves (2026-11-16) edits are queued too: the lead decided then to keep a change on the phone, retry it, and roll it back only when the Mac refuses it, so a network blip never throws away finished work. A journal PUT replaces the whole day and is safe to replay. Its `if_updated_at` check stops a stale queued answer from overwriting a newer one made on the Mac. The cost is one request case and one patch type in the existing queue; no new phone store.
5. **The edit horizon bounds journal dates.** No new limit is needed. The answers are booleans, so there is no length limit.
6. **WHOOP's rule, with counts, and no statistics.** With 5 and 5 mornings a difference of a few points can be chance. A test would add a threshold and a wording problem that WHOOP does not take on either. Showing both counts on every row and saying "less certain" is the honest small version. **(lead?)** A Welch t-test gate is the next step if the owner wants one.
7. **No clearing on the phone.** A wrong answer is switched, not cleared. The CLI clears.
8. **Impact only under today's Recovery.** It is computed as of today, so a past Recovery screen would show today's association under an old date.
9. **No new score version.** Impact changes no score.

## 12. Out of scope

Custom behaviours, quantities and times, behaviour impact on Sleep or Strain, a journal widget, a morning notification, an assistant asking the questions or logging answers, and editing the behaviour list from the phone.

[w-journal]: https://www.whoop.com/us/en/thelocker/the-whoop-journal/
[w-behaviour]: https://www.whoop.com/us/en/thelocker/a-new-way-to-see-insights-on-which-behaviors-affect-your-recovery/
[o-tags]: https://support.ouraring.com/hc/en-us/articles/360038676993-Using-Tags
