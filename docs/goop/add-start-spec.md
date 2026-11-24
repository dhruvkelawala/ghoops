# ghoops: ADD ACTIVITY and START ACTIVITY on Home (issue #18)

Status: final. The lead approved it on 2026-11-18 (§16). The owner saw the mockups and answered §13 that day: the task sheet, the target row yes, and past-day ADD yes. Build A1 to A7, with A4 and without A4B. Written 2026-11-18 against `main` at `759a9e6`. The build plan is [add-start-plan.md](add-start-plan.md). The mockup is [mockups/add-start.html](mockups/add-start.html), rendered per screen in `mockups/screens/add-start-<key>.png`.

Home's activities card has one START ACTIVITY button. It opens a task sheet with a LIVE/PAST switch, and adding a past activity sits behind PAST. On 2026-11-18 the owner compared this with WHOOP and said WHOOP's entry points are better. The lead decided (#18): two entry points on the card, ADD ACTIVITY going straight to an add sheet and START ACTIVITY going straight to the live start, in ghoops' own design system.

This spec settles the details:
- the card: the pair of buttons, END during a session, the empty state, large text sizes, and the DESIGN.md rule change (§2, §8);
- the ADD sheet, built from today's PAST content (§3);
- the START sheet, and why it stays a task sheet (§4);
- what happens to the LIVE/PAST switch, its ids, tests, fixtures and docs (§5);
- how this fits with #17, #14 and the other open work (§6).

The owner's three questions are in §13. The spec is written to the recommended answers, and §13 says what changes for each other answer.

## 0. Precedence and decisions

This spec extends [activity-spec.md](activity-spec.md) §2, [edit-spec.md](edit-spec.md) §2.8 (as changed by [instant-saves-spec.md](instant-saves-spec.md) §4.7 and [edit-limits-spec.md](edit-limits-spec.md) §5.3–§5.4) and [DESIGN.md](../../DESIGN.md). Where they disagree, this spec wins for the activities card, the ADD sheet and the START sheet. The plan updates each document in the step that changes the behaviour it describes.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | Today's card shows two in-card buttons on one row: ADD ACTIVITY (`plus`) on the left, START ACTIVITY (`stopwatch`) on the right, 12 apart, equal width. Neither is filled. | The lead's decision, after WHOOP's card. Both are ways to log an activity, so they carry equal weight, and DESIGN.md allows one filled action per screen. Measured with the app's font: START ACTIVITY needs 142.5 pt (label 118.5, symbol 15, gap 9) and each half is 160 pt at 390 pt wide (§1). |
| D2 | The pair stacks, ADD above START, full width and 12 apart, whenever either label would not fit on one line at its full size. `ViewThatFits` decides. | The One-Line Title Rule forbids a wrapped label, and shrinking two labels side by side looks like a mistake. `GoopPair` already falls back to one column at accessibility sizes. |
| D3 | While a session runs, today's card shows `END <SPORT>` alone at full width, exactly as today, and no ADD. The pair comes back when the session ends. | `END WEIGHTLIFTING` needs 172 pt and does not fit half the card. One session runs at a time, and an activity added during it could overlap it. The alternative is in §14. |
| D4 | On a past day that ADD can reach, the card shows ADD ACTIVITY alone at full width. START never shows on a past day. (Owner question 3.) | WHOOP's add works on any day. A missed workout is usually noticed a day later, and ghoops' four-day DAY row already allows it. |
| D5 | ADD opens its own task sheet, built from the PAST content. No sport is preselected, and the commit stays disabled until a sport is chosen. | The lead's brief, after WHOOP's add sheet. A preselected sport is easy to save by mistake while the owner is checking the times. |
| D6 | The ADD sheet opens on the day it was opened from. On the default date the window is the 60 minutes ending now. On a past day it is that day's latest untracked effort, or 18:00 to 19:00. The EFFORT row snaps to any effort. | The brief asks for the last hour ending now. On today the likely case is "I just finished". A past day has no "now", and the band's effort is the best guess there. This changes PAST, which opened on the most recent day with an untracked effort and snapped to it. |
| D7 | When the window is not snapped to an effort, the EFFORT row reads `1 found` or `<n> found` instead of `Custom`. | With D6, the sheet opens unsnapped on a day with efforts. `Custom` would describe a choice the owner never made. |
| D8 | START and END time rows show the date before the time (`Thu 12 Mar`) whenever the window's start and end fall on different London dates. This applies to the ADD sheet and the Edit sheet. | The brief asks for dates across midnight, and WHOOP shows them. A ghoops day runs from wake to wake (#17), so 23:40 and 00:40 can belong to the same day on different dates. The Edit sheet has the same gap, and the owner's rule is to fix every instance. |
| D9 | START stays a task sheet: today's LIVE content without the switch. (Owner question 1.) | §4.1. |
| D10 | The START sheet shows today's Day Strain and target under the band banner, only when a session started now would carry a target. (Owner question 2.) | §4.3. The owner decides how hard to box from this, and WHOOP shows its target before START. |
| D11 | The LIVE/PAST switch goes away entirely (§5). No deep link opens either sheet. | Each sheet now has its own entry point. No link or widget ever opened PAST. |
| D12 | The visible changes ship dark behind `GoopFeature.addAndStart` and go live in the plan's last step (§10). | AGENTS.md, "Unfinished features ship dark". |
| D13 | No Mac, contract, CLI or score change. | Everything uses data the phone already has. |

Rejected:
- **A full-screen START view** (option B, §4.4). It would be WHOOP's layout, but it needs a second DESIGN.md exception and a new phase in the live cover. It also makes changing the sport cost one more tap. It is specified in §4.4 in case the owner picks it.
- **A SPORT row on START that opens a sub-step with USE** (option C, §4.1). Changing the sport would take five taps instead of three.
- **Shrinking the labels to keep the pair side by side** (`minimumScaleFactor`). It still breaks at accessibility sizes, and two shrunk labels side by side look like a mistake.
- **Shorter labels, `ADD` and `START`.** The card would no longer say what they add or start. The issue and WHOOP use the full words.
- **WHOOP's strain-target switch on START.** DESIGN.md has no switches on the phone, and the intent is the Mac's `strain_intent` setting.
- **WHOOP's A–Z sport list.** ghoops has 12 sports in a fixed order (activity-spec §2.1).
- **Keeping the sport preselected on ADD.** See D5.

## 1. Facts this design relies on

`A/` is `ios/GHealth/`, `C/` is `ios/GHealthCore/Sources/GHealthCore/`. Line numbers are at `759a9e6`.

- **The card.** `GoopActivitiesCard` (`A/Components/Goop/GoopActivities.swift:93`) draws one button when `start` is non-nil. It is 40 tall, with an `activityRow` fill, radius 12, `stopwatch` at 15 pt, a 9 pt gap and `labelCard`, 12 below the rows. During a session it reads `END <SPORT>` with `stop.fill` at 12 pt in `zone5` and a 1 pt `zone5` stroke at 33%. Its ids are `activity-end-open` and `activity-open-picker`.
- **Who draws the card.** `HomeScreen.activitiesCard` (`A/Screens/HomeScreen.swift:101`) passes `start` and `live` only when `selectedDate == GoopFormat.dateKey(model.now)`. #17 changes that to `model.defaultDate`. The loading card (`:70`) and the Strain screen (`A/Screens/StrainScreen.swift:26`) pass neither.
- **The sheet.** `ActivityPicker` (`A/Live/ActivityPicker.swift`) is one `GoopTaskSheet` whose `GoopRangeSelector` switches `LIVE` and `PAST` (ids `activity-mode-LIVE`, `activity-mode-PAST`).
  - LIVE has the `HeartRateBanner`, search, `RECENT` and `ALL ACTIVITIES`, with the commit `START <SPORT>` (`activity-start`).
  - PAST has, in order: the SPORT row (into `ActivitySportStep` with prefix `add`), DAY, EFFORT (into an effort step), the values, the chart, the hint, and the START and END rows. Its commit is `ADD <SPORT>` (`add-commit`), enabled once heart rate has loaded and the Mac answers.
- **Opening the sheet.** `AppModel.openActivityPicker` calls `ActivityController.openPicker(workouts:)`. That sets `recentWorkouts`, presents the sheet and starts Bluetooth scanning (`source.start()`). It then reads 30 days of workouts for `RECENT`.
- **`AddDraft`** (`C/Edit/AddDraft.swift`):
  - `days` are the four cycle dates ending on the default date, filtered by the Mac's horizon.
  - The first day is the most recent of them with an untracked effort, else the default date.
  - `sport` is the most recent named sport of the last 30 days, else Boxing.
  - The default window is the day's latest effort. Failing that, it is the 60 minutes ending now on the default date, clamped to the cycle start, and 18:00 to 19:00 on a past day.
  - Bounds come from `EditBounds.add` and `status.edit_limits` (edit-limits-spec §5.2).
- **`ChangeBuilder.add(_:heartRate:serverURL:now:)`** (`C/Changes/ChangeBuilder.swift:54`) reads `draft.upload`, which always has a sport today.
- **Time rows.** `GoopTimeRow` holds a compact `DatePicker(.hourAndMinute)` in London time. `ActivityTime.picker(_:within:)` maps a picked `HH:mm` onto the date inside the span, so a span across midnight already resolves 00:40 to the next date. Nothing on screen says which date.
- **Target.** `SessionTarget.make(day:sessionStart:)` (`C/Live/SessionTarget.swift:15`) returns a target only when the day is the current cycle and `strain_target.status` is `ok`. `LiveTargetRow` (`A/Live/LiveTargetRow.swift`) draws `EST. DAY STRAIN` and `TARGET` on the live screen.
- **Debug.** `-GHealthEditFixture add` calls `openActivityPicker()` (`A/App/ActivityEditing.swift:106`). The picker then switches to PAST and picks 2026-03-11 and Boxing (`ActivityPicker.swift:49`, `:141`).
- **Deep links.** `ghealth://activity` opens the running session or the last local entry, and `ghealth://today` opens Home (`A/App/GHealthApp.swift:38`). Neither opens the picker or PAST.
- **No flag file.** `A/App/GoopFeature.swift` does not exist on `main`.
- **Measured label widths.** Nunito Sans 750 at 12.5 with 0.10em tracking, using the app's own font file in headless Chrome:

  | Label | Width (pt) |
  | --- | --- |
  | `START ACTIVITY` | 118.5 |
  | `ADD ACTIVITY` | 104.4 |
  | `END BOXING` | 91.3 |
  | `END KICKBOXING` | 125.3 |
  | `END MARTIAL ARTS` | 143.1 |
  | `END WEIGHTLIFTING` | 151.0 |

  Half the card at 390 pt wide is (390 − 32 − 26 − 12) / 2 = 160.

## 2. The card

### 2.1 Today, no session (`card`)

"Today" is `model.selectedDate == model.defaultDate` (#17). The title, rows and expand button are unchanged. Twelve below the last row, or below the empty sentence, comes the pair:

| | ADD ACTIVITY | START ACTIVITY |
| --- | --- | --- |
| Symbol | `plus`, 15 pt, white | `stopwatch`, 15 pt, white (unchanged) |
| Label | `ADD ACTIVITY`, `labelCard` | `START ACTIVITY`, `labelCard` (unchanged) |
| Id | `activity-open-add` | `activity-open-picker` (unchanged) |
| Accessibility label | "Add activity" | "Start activity" |
| Opens | the ADD sheet on the default date (§3) | the START sheet (§4) |

- Each button is the existing in-card action: `activityRow` fill, `radiusButton` (12), `frame(maxWidth: .infinity, minHeight: 40)`, symbol and label centred 9 apart, plain style.
- Labels are `lineLimit(1)` with no scale factor.
- The pair is `ViewThatFits(in: .horizontal)` over two candidates, ADD first in both:
  - side by side: a new `GoopEqualPair` layout (spacing 12) that gives both buttons the wider button's ideal width, so its ideal width is twice the wider button plus 12;
  - stacked: a `VStack(spacing: 12)`.

  A plain `HStack` would not do. Its ideal width is the sum of the two labels, so it would stay side by side while START is already too wide for its half, and START would be cut off. With `GoopEqualPair`, the pair stacks as soon as the wider label no longer fits half the row. VoiceOver reads ADD, then START.
- At 390 pt the pair sits side by side at the default text size (D1). It stacks at accessibility sizes (`card-ax5`) and at whichever larger standard size `ViewThatFits` finds too narrow. Plan step A3 records that switch point.

### 2.2 Today, session running (`card-live`)

- The live row at the top, then the rows, then `END <SPORT>` alone at full width. All of this is unchanged from today, including the `zone5` stroke and `activity-end-open`.
- No ADD (D3).
- The row limit stays 3 including the live row, as today.

### 2.3 Empty and loading

- With no rows, the card keeps `No activities yet` (`bodyMid`, `text2`) and puts the pair 12 below it. DESIGN.md wants every empty state said in words.
- The loading card has no buttons, as today.
- At 55% stale opacity, the buttons stay at full strength. They are controls, not values.

### 2.4 Past days (`card-past`, owner question 3)

- When the selected date is one of the ADD sheet's days other than the default date (`AddDraft.days(defaultDate:limits:)`, the three days before it that the Mac's horizon allows) and no session runs, the card shows ADD ACTIVITY alone at full width. It opens the ADD sheet on that day.
- The title stays `ACTIVITIES` and there is no live row, as today.
- Older days show no button, as today.

### 2.5 Strain screen

The Strain screen's activities card has no buttons, and keeps none.

## 3. The ADD sheet

### 3.1 Opening

- **Entry points.** The card's ADD opens the sheet on the default date, or on the past day it sits on (§2.4).
- **Presentation.** A new `AddActivitySheet` (`A/Live/AddActivitySheet.swift`) inside its own `GoopTaskSheet`: large detent and grabber. The title is `ADD ACTIVITY`, with × on the right (`activity-add-close`). The container id is `activity-add`.
- **What it starts.** It never starts Bluetooth scanning, since activity-spec §4.2 scans only for START or a running session. It sets `activity.recentWorkouts` from the displayed snapshot and reads 30 days of workouts, as `openActivityPicker` does, so the sport step's `RECENT` is the same.
- **Draft.** It builds `AddDraft(…, entry: .addSheet, day: <day>)` (§7).

### 3.2 Content (`add`, `add-midnight`)

Same order and spacing as PAST, without the switch:

1. **Error banner** (`add-error`), unchanged.
2. **SPORT row** (`add-sport-row`). The value is `Choose` in `text2` until a sport is chosen, then the sport's name as a `GoopRowValue`. It opens the sport sub-step (§3.3).
3. **DAY row**, unchanged: four days limited by the horizon, or `Today` when only one day is left. It opens on the day the sheet was opened for.
4. **EFFORT row** (`add-effort-row`), unchanged except for the value:

   | Window | Value |
   | --- | --- |
   | snapped to an effort | `<start> to <end>` (unchanged) |
   | not snapped, the day has efforts | `1 found` or `<n> found`, `textSoft` |
   | the day has no efforts | `None found`, `text2`, no chevron (unchanged) |

5. **Values, chart and hint**, unchanged (edit-spec §2.8, edit-limits-spec §5.4).
6. **START and END rows** (`add-start`, `add-end`), unchanged, plus dates across midnight (§3.4).

**Commit**, pinned:

| State | Title | Enabled |
| --- | --- | --- |
| no sport chosen | `ADD ACTIVITY` | no (40%) |
| sport chosen, heart rate loading | `ADD <SPORT>` | no |
| sport chosen, heart rate loaded | `ADD <SPORT>` | yes |
| the heart-rate read failed (§3.5) | as above | no |

The symbol is `plus` and the id is `add-commit`. Accessibility labels are "Add activity" and "Add Boxing". Tapping an enabled ADD does what instant-saves-spec §4.7 says: the sheet closes, the new workout opens on its day, and a refusal rolls back.

### 3.3 Sport sub-step

- `ActivitySportStep` with prefix `add`, unchanged.
  - With no sport chosen yet, no row is selected.
  - `RECENT` is the two most recent distinct sports of 30 days, with `Last: <Wkd>`, and `ALL ACTIVITIES` is the rest.
- **Commit.** `USE ACTIVITY` is disabled until a row is tapped, then reads `USE <SPORT>` with the sport's symbol (`add-sport-use`).
- **Leaving.** `chevron.left` returns without changing anything, and × closes the sheet.
- Opening the step again with a sport chosen selects that sport, as today.

### 3.4 Default window and dates

**Default window** (D6):

| Day | Window |
| --- | --- |
| default date | The 60 minutes ending at `ActivityWindow.minute(now)`, clamped to the cycle start, then `bounds.clamp`. Not snapped. |
| past day | The day's latest untracked effort that the bounds allow; otherwise 18:00 to 19:00 clamped to the cycle (today's rule). |

- Choosing a day applies that day's rule again, and so does the heart rate arriving, as today.
- The 60 minutes and 18:00 to 19:00 are app-owned defaults, not Mac limits (edit-limits-spec §2.2). `EditBounds` clamps them to the Mac's `active_max_minutes` and horizon (The Mac's-Limits Rule).

**Dates on the time rows** (D8):

- **When.** `GoopFormat.dateKey(window.start) != GoopFormat.dateKey(window.end)` in London time. Then both rows show their own date before the time picker. Otherwise neither does, because the DAY row already names the day.
- **Format.** `GoopFormat.dateLabel(<key>, format: "EEE d MMM")` (`en_GB`), for example `Thu 12 Mar`. Style `bodySmall`, `textSoft`, 8 before the picker. Dates are Nunito (The Two Voices Rule).
- **Ids.** `add-start-date` and `add-end-date`. In the Edit sheet, `edit-start-date` and `edit-end-date`.
- **VoiceOver.** The row reads "Start, Thursday 12 March, 23:40".
- **Example.** With default date Thu 12 Mar and now Fri 13 Mar 00:40 (`add-midnight`): START `Thu 12 Mar` 23:40, END `Fri 13 Mar` 00:40.

The date only labels the picked time. `ActivityTime.picker` already maps a picked time onto the right date inside the span.

### 3.5 Offline

- **The sheet needs the Mac.** Its preview needs `GET /v2/heart-rate`, and opening it without the Mac is out of scope (instant-saves-spec §14). When the read fails:
  - the caution banner `Can't reach your Mac. Edits are saved on your Mac, so try again when it can be reached.` shows above the content;
  - the controls dim to 40%, and the chart area shows `Needs a connection to your Mac`;
  - the sheet retries when the app becomes active.

  This is unchanged from PAST.
- **The card's ADD stays visible offline.** The sheet explains the problem.
- **An add made before the Mac went away** queues and retries as instant-saves-spec §3.2 says, unchanged.
- **START needs no Mac.** A live session saves on the phone and uploads later (activity-spec §6.3). The target row reads the cached snapshot.

## 4. START

### 4.1 Recommendation: keep the task sheet (owner question 1)

| | A: task sheet (recommended) | B: full-screen start (§4.4) | C: sheet with a SPORT row |
| --- | --- | --- | --- |
| Taps to start, same sport as last time | 2 (START ACTIVITY, START BOXING) | 2 | 2 |
| Taps to start another sport | 3 (START ACTIVITY, the sport, START) | 4 (START ACTIVITY, the header, the sport, START) | 5 (START ACTIVITY, SPORT, the sport, USE, START) |
| Band state | the banner at the top, as today | the heart card in the middle | a panel in the middle |
| Presentation | task sheet, as today | full-screen cover before the session | task sheet |
| DESIGN.md | no change | the full-screen cover also before a session | no change |
| Code | remove the switch, add the target row | a ready phase in the live cover, and a sport sheet over the cover | a new sub-step |

**Recommended: A.**
- DESIGN.md keeps one meaning for the full-screen cover: a session is recording. A task is a task sheet, so a glance tells the owner whether the band is recording.
- The sports stay in view, so changing sport costs 3 taps instead of 4 or 5.
- The band's state is already the first thing on the sheet.
- The tested live flow does not change.

B would bring WHOOP's look and a start that turns into the live screen without a second animation. §4.4 specifies it so the owner can choose it.

### 4.2 The START sheet (`start`)

- **Frame.** `GoopTaskSheet` titled `START ACTIVITY`, × on the right (`activity-picker-close`), container `activity-picker`. There is no switch.
- **Content, from the top:**
  1. The `HeartRateBanner` (`heart-rate-banner`), 4 below the header. It takes the place the switch held.
  2. The target row (§4.3), 16 below the banner, when it shows.
  3. Search, `RECENT` and `ALL ACTIVITIES`, unchanged.
- **Commit.** `START <SPORT>` (`activity-start`), unchanged. The preselected sport is the most recent one, else Boxing, as today.
- **The band's state**, the middle of WHOOP's start view, is the banner's six states, unchanged (activity-spec §4.3, live-hr-spec):

  | State | Title | Sentence |
  | --- | --- | --- |
  | searching | `LOOKING FOR YOUR BAND` | `Keep your Fitbit Air close to your phone.` |
  | connected | `FITBIT AIR CONNECTED` | `Live heart rate <bpm> bpm`, or `Waiting for the first heart rate reading.` |
  | not found | `NO LIVE HEART RATE` | today's instruction to share heart rate |
  | Bluetooth off | `BLUETOOTH IS OFF` | today's sentence |
  | not allowed | `BLUETOOTH NOT ALLOWED` | today's sentence, with the Settings link |
  | several bands | `CHOOSE YOUR BAND` | today's sentence, with the device buttons |

  START stays enabled in every state.

### 4.3 Target row on START (owner question 2)

- **Layout.** `LiveTargetRow`'s layout and styles, with no card or fill:
  - left: the Mac's `day.strain.value` (1 dp), captioned `DAY STRAIN`, or `—` in `text2` when it is null;
  - a 1×40 `cardDivider` rule;
  - right: `<low>–<high>` captioned `TARGET`, with the mint checkmark when `low ≤ value ≤ high`.
- **When it shows.** Only when `SessionTarget.make(day: <cached snapshot day>, sessionStart: model.now)` is non-nil. That is exactly when the session START begins would carry a target (parity1-spec §5.2). There is no row when the Mac sends no target, when the target is pending, or when the cached day is not the current cycle.
- **Ids.** `start-target`, `start-target-value`, `start-target-range` and `start-target-within`.
- **VoiceOver.** "Day Strain, 8.1. Target 13.3 to 16.3", plus ", reached" when within.
- **Not a phone estimate.** The value is the Mac's number. The live screen keeps its own row (`EST. DAY STRAIN`, ids `activity-target*`), unchanged.
- **Not on Home.** DESIGN.md's "no strain target on Home" still holds. This is a sheet.

### 4.4 Option B, if the owner picks the full-screen start (`start-full`)

- **Presentation.** START ACTIVITY opens the `fullScreenCover` that hosts `LiveActivityScreen`, in a new `ready` phase. `START <SPORT>` begins the session in the same cover, which switches to today's live content without closing.
- **Header (50).**
  - Left: the live screen's heart-rate chip (`LiveReadout.chipText`: `LIVE`, `NO HR` or `RECONNECTING`, with its symbol and colour), moved to the left because × takes the right.
  - Centre: one button (`start-sport`) holding the sport symbol (22), the name in `labelNav` and `chevron.down` (11, semibold). It opens a `GoopSheet` titled `SPORT` with search, `RECENT` and `ALL ACTIVITIES`. Tapping a row applies it and closes the sheet, as the Trends `METRIC` sheet does.
  - Right: `xmark` (`start-close`), which cancels and stops scanning.
- **Middle.** The live screen's heart card in its before-start form, driven by `LiveReadout(bpm: <connected bpm>, zone: estimator.zone(bpm:), hr: bpm == nil ? .none : .live)`. It shows the heart, bpm, zone name and range, and the zone meter, with no chart and no stats. Under it sits the `HeartRateBanner` in every state except "connected with a reading".
- **Bottom.** The §4.3 row, 22 above the pinned `START <SPORT>`, in the commit style.
- **DESIGN.md, in addition to §8.** In Sheets and modals, the Full-screen cover line becomes "Only for a running session, and for the START view just before one."
- **Tests.** `testActivityFlow`, `testActivitySearchAndShortDiscard` and `testActivityScreensTour` pick the sport through `start-sport`.

## 5. The LIVE/PAST switch goes away

It goes away entirely in plan step A7. Until then Release keeps it (§10).

| Item | Today | After A7 |
| --- | --- | --- |
| `activity-mode-LIVE`, `activity-mode-PAST` | the switch in `ActivityPicker` | removed |
| `ActivityPicker` | LIVE and PAST | START only (§4.2) |
| PAST content and state | `ActivityPicker` | `AddActivitySheet` (§3) |
| `add-*` ids | PAST | kept: `add-sport-row`, `add-sport-search`, `add-sport-<TYPE>`, `add-sport-use`, `add-day-<date>`, `add-effort-row`, `add-effort-<id>`, `add-effort-use`, `add-chart`, `add-handle-start`, `add-handle-end`, `add-start`, `add-end`, `add-commit`, `add-error`, `add-value-*` |
| START ids | | kept: `activity-open-picker`, `activity-end-open`, `activity-picker`, `activity-picker-close`, `activity-start`, `activity-search`, `activity-sport-<TYPE>`, `heart-rate-banner` |
| New ids | | `activity-open-add`, `activity-add`, `activity-add-close`, `add-start-date`, `add-end-date`, `edit-start-date`, `edit-end-date`, `start-target`, `start-target-value`, `start-target-range`, `start-target-within` |
| `-GHealthEditFixture add` | opens the picker, which switches to PAST and picks 2026-03-11 and Boxing | opens the ADD sheet through `openAddActivity(day: "2026-03-11")`, with no sport chosen. No existing test on the key asserts the sport, so every assertion holds. The `edit-add` capture now shows `Choose`. |
| `ComponentGallery` | a `LIVE`/`PAST` `GoopRangeSelector` (`gallery-mode-*`) | a `MON TUE WED THU` example (`gallery-day-*`), so the gallery still shows the string selector |
| `testNameEffortAndAddPast` | taps `activity-mode-PAST`; expects `Add Walking` | taps `activity-open-add`. On 2026-03-11 the effort still snaps (past-day rule). Expects `Add activity` disabled, then `Add Boxing` after choosing Boxing. |
| `testEditScreensTour` (`add`), `testEditLimitsFromMac` (launch 3) | the `add` key | unchanged assertions |
| `testActivityFlow`, `testActivitySearchAndShortDiscard`, `testActivityScreensTour` | `activity-open-picker` | unchanged; the `activity-a` capture now shows the pair |
| Deep links | none opens the picker | unchanged, and no new link |
| `.agents/skills/verify-ios/features/edit-activity.md` | lists `activity-mode-LIVE`, `activity-mode-PAST` | lists `activity-open-add`, `activity-add`, `activity-add-close` and the date ids |
| `.agents/skills/verify-ios/features/start-activity.md` | opens the picker | same ids; adds the target row and "no LIVE/PAST" |
| Renders | `edit-add.png` (PAST), `activity-a.png` (Home with START) | marked superseded by `add-start-add.png` and `add-start-card.png` in edit-spec §0 and activity-spec §0. `activity-b.png` predates the switch and stays valid. |
| Documents | activity-spec §2 steps 1–2; edit-spec intro, §0 "Dark launch", §2.8 steps 1–2 and 7, §3.1–§3.2 "LIVE/PAST", §4.1 rows "Start/Add sheet titles" and "Mode options"; instant-saves-spec §6.6 "Start Activity, PAST"; edit-limits-spec §5.4 `ActivityPicker` | each says ADD sheet or START sheet, in the plan step that changes the behaviour |

## 6. How this fits with other work

- **#17 (today is `model.defaultDate`).** This spec depends on it.
  - The pair, the live row and END follow `model.defaultDate`, so they stay after midnight until the night's sleep starts a new day.
  - ADD opens on the default date, so after midnight its last hour crosses midnight and shows dates (§3.4).
  - A session that runs past midnight stays on its day's card from start to end.
  - The plan's gate requires #17 on `main`, and A6 reuses #17's fixture.
- **#14 (live polish, approved soon).** No behaviour overlaps.
  - #14 changes the value block in `GoopActivityRow` and `GoopLiveRow`. This spec changes the buttons in `GoopActivitiesCard`. Both edit `GoopActivities.swift`, so whichever lands second rebases.
  - The mockup's live row shows a Strain value, so it looks the same before and after #14.
- **#13 (edit limits).** ADD keeps `EditBounds.add` and the horizon-filtered days. The new 60-minute default is app-owned and clamped, and nothing new is copied from the Mac.
- **#15 (live limits).** START is unchanged, so the live session's limits stay #15's.
- **#16 (one name).** Every sport name on the card, the sheets and the commits comes from `ActivitySport`, so it follows The One Name Rule.
- **#12 and parity1.** The banner and `LiveReadout` are unchanged. The START target row is a new place for the target (owner question 2), not Home.

## 7. GHealthCore

**`AddDraft`:**
- Add `public enum Entry: Sendable { case pastMode, addSheet }` and an `entry: Entry` parameter, with no default. Every caller passes it. `pastMode` keeps today's behaviour exactly, and A7 deletes it.
- Add `public static func days(defaultDate: String, limits: EditLimits?) -> [String]`, the four days filtered by the horizon, and use it in `init`. `HomeScreen` calls it for §2.4 without building a draft.
- Add a `day: String?` parameter. In `addSheet` the first day is `day` when it is in `days`, else `defaultDate`. In `pastMode` it is ignored.
- `sport` becomes `String?`. `pastMode` sets it as today; `addSheet` leaves it nil.
- `upload` becomes `ActivityUpload?`, nil while `sport` is nil.
- `ChangeBuilder.add` becomes `-> PendingChange?`, nil without a sport. The commit is disabled then anyway.
- `setDefaultWindow` in `addSheet` follows §3.4. `effortLabel` in `addSheet` follows §3.2 step 4. `hint` is unchanged.

**`ActivityTime`:**
- `static func dateLabels(_ window: ActivityWindow) -> (start: String, end: String)?` returns nil when both ends fall on one London date. Otherwise it returns both `EEE d MMM` labels.
- `static func spokenDate(_ date: Date) -> String` returns `EEEE d MMMM`, for example "Thursday 12 March".

## 8. DESIGN.md rule change

The rule stays as narrow as it can: one named exception for one pair on one card. Plan step A3 applies these edits word for word. Line numbers are at `759a9e6`.

**Line 486 (Overview).** Old:

> Capsule pills, text nav buttons, steppers, switches, toasts and side-by-side buttons remain outside this system.

New:

> Capsule pills, text nav buttons, steppers, switches, toasts and side-by-side buttons remain outside this system. The one pair that shares a row is the activities card's ADD ACTIVITY and START ACTIVITY (The Entry-Pair Rule).

**Line 646 (Components, Modal).** Old: `` `ActivityPicker` (task sheet) ``. New: `` `ActivityPicker` (START task sheet), `AddActivitySheet` (ADD task sheet) ``.

**Line 668 (Buttons, Shape).** Old:

> gently rounded (12, `rounded.button`) and full width. Each button sits alone on its row.

New:

> gently rounded (12, `rounded.button`) and full width. Each button sits alone on its row, except the activities card's entry pair (The Entry-Pair Rule).

**Line 672 (Buttons, In-card action).** Old:

> an `activityRow` fill, 40 tall, symbol plus `labelCard`, inside the activities card (START ACTIVITY / END ‹SPORT›; the END variant adds a 1pt `zone5` stroke at 33%).

New:

> an `activityRow` fill, 40 tall, symbol plus `labelCard`, inside the activities card. On today's card, ADD ACTIVITY (`plus`) and START ACTIVITY (`stopwatch`) share a row as the entry pair. During a live session, END ‹SPORT› replaces the pair at full width and adds a 1pt `zone5` stroke at 33%. On a past day that ADD reaches, ADD ACTIVITY sits alone at full width.

**After the Buttons list, a new named rule:**

> **The Entry-Pair Rule.** Two buttons share a row only as the activities card's ADD ACTIVITY and START ACTIVITY. They are two in-card actions of equal weight, neither filled, that open the two ways to log an activity. They stack, ADD first, whenever either label would not fit on one line, and END ‹SPORT› replaces them at full width while a session runs. Every other pair of actions stacks.

**Line 729 (Primary and secondary actions).** Unchanged. Add a bullet after it:

> The activities card's ADD ACTIVITY and START ACTIVITY are in-card actions, not secondary outlines, and are the one pair that shares a row (The Entry-Pair Rule).

**Line 749 (Form rows, Time input).** Old:

> **Time input:** `GoopTimeRow` places a system compact `DatePicker(.hourAndMinute)` inside `GoopRow`, tinted `strain` and using the supplied date range.

New:

> **Time input:** `GoopTimeRow` places a system compact `DatePicker(.hourAndMinute)` inside `GoopRow`, tinted `strain` and using the supplied date range. When a window's start and end fall on different dates, each row shows its own date (`Thu 12 Mar`, `bodySmall` `textSoft`) 8pt before the time.

**Line 821 (Do).** Unchanged. It is about outline buttons.

**Line 834 (Don't).** Old:

> **Don't** place two buttons side by side, or put a button inside a row that is itself a button.

New:

> **Don't** place two buttons side by side, except the activities card's entry pair (The Entry-Pair Rule), or put a button inside a row that is itself a button.

## 9. App changes

| Where | Change |
| --- | --- |
| `GoopActivitiesCard` | Gains `add: (() -> Void)?`. With `start` and `add`, and no session, it draws the pair (§2.1). With a session it draws END at full width, as today. With `add` alone it draws ADD at full width (§2.4). The component reads no flag. |
| `GoopEqualPair` (new, `A/Components/Goop/`) | A `Layout` for two children: each gets the wider child's ideal width, with the given spacing, so its ideal width is twice the wider child plus the spacing. Used only by the entry pair. |
| `HomeScreen.activitiesCard` | Passes `add` per §2 when `GoopFeature.addAndStart` is on: on the default date with no session, and (§2.4) on a past day in `AddDraft.days` with no session. |
| `AppModel` | `openAddActivity(day: String)` sets `activity.recentWorkouts`, starts `loadActivityHistory()` and sets `addDay`. It does not call `ActivityController.openPicker`, so no scan starts. New property: `addDay: String?`. |
| `GHealthApp` | Presents `AddActivitySheet` while `addDay` is non-nil. Passes `ActivityPicker(modes: !GoopFeature.addAndStart, showsTarget: GoopFeature.addAndStart)`. |
| `AddActivitySheet` (new) | §3, starting from a copy of `ActivityPicker`'s PAST code. During the dark launch the two copies coexist; A7 deletes the old one. |
| `ActivityPicker` | `modes: Bool`: without it, no switch and no PAST. `showsTarget: Bool` draws §4.3. Both parameters go in A7. |
| `GoopTimeRow` | Gains `date: String? = nil`, drawn as §3.4. |
| `EditSheet` | Passes `ActivityTime.dateLabels(window)` to its time rows when its caller says so. `WorkoutScreen` passes `GoopFeature.addAndStart`. |
| `LiveTargetRow` | Gains `caption` (default `EST. DAY STRAIN`), `spokenCaption` (default `Estimated Day Strain`) and `identifier` (default `activity-target`), from which the child ids derive. The live screen is unchanged. |
| `ActivityEditing` (Debug) | The `add` key calls `openAddActivity(day: "2026-03-11")` when the flag is on, and `openActivityPicker()` otherwise. No sport is chosen, as on any ADD. |
| `ComponentGallery` | Adds: the pair; the pair forced stacked; END at full width; ADD alone; a time row with a date; the START target row. All at the default size and at accessibility 5. Replaces the LIVE/PAST selector example (§5). |

## 10. Dark launch

- **The flag.** Create `ios/GHealth/App/GoopFeature.swift`, or add the case if another feature has created it since:

  ```swift
  enum GoopFeature {
      #if DEBUG
      static let addAndStart = true
      #else
      static let addAndStart = false
      #endif
  }
  ```

- **Runtime gates, and only these:**
  - `HomeScreen.activitiesCard` (the `add` closure);
  - `GHealthApp` (the `ActivityPicker` parameters);
  - `WorkoutScreen` (the Edit sheet's dates);
  - the Debug `add` key.

  Nothing below them reads the flag.
- **Release.** With the flag off, Release shows today's card, today's picker with LIVE/PAST, and no dates on the time rows. `AddDraft(entry: .pastMode)` keeps PAST exactly as it is.
- **A7** deletes the flag, `ActivityPicker`'s switch and PAST code, `modes`, `showsTarget`, `AddDraft.Entry.pastMode`, and the Debug `else` branch. It deletes `GoopFeature.swift` too if nothing else uses it.

## 11. Fixtures and Debug launch arguments

- **No new Go fixture.** No Mac change.
- **The `add` key** keeps its day (2026-03-11) and leaves the sport unchosen, as every ADD does. The tests on the key assert the day and the effort, not the sport.
- **Across midnight.** A6 uses the fixture state that #17 adds, in which `default_date` is the day before the clock's calendar date. If that state cannot run with `-GHealthFixture edit` (which serves the heart rate the sheet needs), A6 adds a Debug argument, `-GHealthClock 2026-03-13T00:40:00Z`. It sets `model.now` and the edit fixture's default date stays 2026-03-12. Release must not contain it (plan, Release check).
- **The target row** uses `fresh`, whose `strain_target` is 13.3–16.3 (parity1-spec §2.1).
- **The live card** uses `-GHealthLiveFixture boxing_23m`.

## 12. Tests

The plan lists each test with its step. In summary:
- **GHealthCore.**
  - `AddDraft` in `addSheet`: the first day; no sport, and no upload or change without one; the default window on the default date (not snapped) and on a past day (snapped, or 18:00 to 19:00); `1 found` and `2 found`; the clamp to the Mac's limits.
  - `pastMode` stays unchanged.
  - `dateLabels` on one date, across midnight, and on the London clock change.
- **UI.**
  - The pair: side by side at the default size, stacked at accessibility 5, END alone during a session, and ADD alone on a past day.
  - The ADD sheet: no sport, the disabled commits, and dates across midnight.
  - The START sheet: no switch, and the target row on `fresh`.
  - The existing tests as §5 says.
  - The full suite passes with its one skip by design.

## 13. Owner questions

Each is one decision. The recommendation comes first, and the spec is written to it.

1. **START: keep the task sheet (recommended), or WHOOP's full-screen start?**
   - The sheet keeps the sports in view, so changing sport takes 3 taps. It also keeps the rule that full screen means recording.
   - The full-screen start (mockup `start-full`, §4.4) looks like WHOOP and turns straight into the live screen. Changing sport takes 4 taps, and DESIGN.md needs a second exception.
   - **If full screen:** §4.4 replaces §4.2, and plan step A4 is replaced by "A4B: full-screen start".
2. **Show today's Day Strain and target on the START sheet? Recommended: yes.**
   - It is the number the owner decides how hard to box from, and WHOOP puts its target on the start view.
   - It is a new place for the target beyond parity1's first slice, which is why this needs the owner.
   - **If no:** drop §4.3 and plan step A4. The target still shows on the live screen and the Live Activity.
3. **Show ADD ACTIVITY on the three days before today? Recommended: yes.**
   - A missed workout is usually noticed the next day. Today it means opening START and finding PAST.
   - **If no:** drop §2.4 and plan step A5. ADD is then only on today's card, and its sheet's DAY row still reaches the three days before.

## 14. Decisions for the lead

Each is written into the spec as recommended. **(lead?)** marks the ones to check.

1. **No ADD during a live session** (D3). **(lead?)** The alternative is to keep ADD above END, on its own row, and end the add window at the session's start so the two never overlap.
2. **On the default date, ADD opens on the last hour, not on the day's latest effort** (D6), as the brief says. PAST snapped to the latest effort. **(lead?)** The alternative is to snap first, which saves the owner three taps when the band caught the workout.
3. **`1 found` replaces `Custom` on the EFFORT row** (D7).
4. **Dates on time rows apply to the Edit sheet too** (D8). The owner's rule is to fix every instance.
5. **The empty card keeps `No activities yet` above the pair** (§2.3).
6. **The `add` Debug key keeps 2026-03-11 but no longer chooses a sport** (§5). It then shows the sheet as the owner sees it, and no existing assertion depends on the sport.

## 15. Patterns borrowed

- **WHOOP**, from the owner's phone on 2026-11-18, described in issue #18:
  - Home's activities card always shows `+ ADD ACTIVITY` and `START ACTIVITY` side by side, after midnight too. **Borrowed:** the pair, its order and its labels.
  - ADD opens a task sheet with a sport row, Start and End shown with dates across midnight, and a save that stays disabled until a sport is chosen. **Borrowed:** the empty sport and the disabled commit (D5), and the dates (D8).
  - START opens a full-screen view: the sport in the header opens a searchable list, the device's connection is in the middle, and the target and START sit at the bottom. **Borrowed:** the band state and the target before START (§4.2, §4.3). **Offered as option B:** the full-screen layout (§4.4). **Not borrowed:** the target switch and the A–Z list (§0, Rejected).
- **Oura**, "Record a Workout with Oura" (updated 2026-10-07) and "Edit or Manually Add an Activity" (updated 2026-08-07), support.ouraring.com, read 2026-11-18:
  - Oura's `+` menu holds two separate entries: "Start live activity", used before a workout, and "Add an activity", used after it.
  - The add screen lists the three most recent activities first and works for today or earlier days.
  - Oura warns that an activity added between midnight and 4 AM may appear on the previous day. ghoops makes that explicit instead: the day is the default date (#17), and the time rows show dates (D8).

  **Borrowed:** two separate entries (D1), recent sports first, and adding on earlier days (D4).
- **Garmin**, "Create a Manual Activity in Garmin Connect" (support.garmin.com FAQ), read 2026-11-18. "+ Manual Activity" is a separate entry from recording on the device. **Borrowed:** adding stays its own entry, separate from starting.
- **Apple**, "Start a workout in Fitness on iPhone" (iOS 27 user guide, support.apple.com), read 2026-11-18. The Workout screen puts "log a workout" and "connect a heart rate monitor" at the top, and asks for a heart-rate device to be connected before a workout starts. **Borrowed:** the heart-rate source state stays the first thing on START (§4.2).

## 16. Lead review (2026-11-18)

The lead accepts all six §14 decisions as written: no ADD during a live session (D3); on the default date, ADD opens on the last hour and offers the effort with `1 found` (D6, D7); dates on time rows in the Edit sheet too (D8); `No activities yet` above the pair; the `add` Debug key without a sport. The renders were checked by eye at one column; all eight fit the inline frame. The three §13 questions go to the owner one at a time with the mockup. The build starts after the answers are recorded here.

### Owner answers (2026-11-18)

The owner was shown each mockup and chose the recommended option all three times.

1. **START:** keep the task sheet (§4.2). The full-screen start (§4.4, `start-full`) isn't built, and plan step A4B doesn't apply.
2. **Day Strain and target on the START sheet:** yes. Build §4.3 and plan step A4 as written.
3. **ADD ACTIVITY on the three days before today:** yes. Build §2.4 and plan step A5 as written.

The spec is final. The build is plan steps A1 to A7, dark behind `GoopFeature.addAndStart`. A3 applies the Entry-Pair Rule exception from §8 to DESIGN.md.
