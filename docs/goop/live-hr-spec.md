# ghoops: live heart rate keeps its own state (issue #12)

Status: approved. The lead approved it on 2026-11-17 (§11), and the owner approved the prototype the same day ("Build it"). Written 2026-11-17 against `main` at `c8bfb16`, after #11. The build plan is [live-hr-plan.md](live-hr-plan.md). The prototype is [mockups/live-hr.html](mockups/live-hr.html).

The Live Activity shows `NO HR` under a live heart rate whenever the zone is unknown (`ios/Shared/Goop/GoopLiveActivityView.swift:65`). The zone is unknown when the phone lacks the Mac's resting or maximum heart rate, or, since #11, its `score_constants`. The sweep found the same mix-up in three other forms:
- a lost signal that still looks live;
- unknown zone time shown as `0:00`;
- missing values drawn in colour.

This spec makes heart rate, zone and pause three separate facts and fixes every live surface. Screens not named below stay as they are.

## 0. Precedence and decisions

This spec extends [activity-spec.md](activity-spec.md) §3, §7 and §10, [parity1-spec.md](parity1-spec.md) §2.3, and [DESIGN.md](../../DESIGN.md) (The Missing-Is-Grey Rule and The Two Voices Rule). Where they disagree, this spec wins. The plan updates those documents in the step that changes the behaviour they describe.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | One GHealthCore value, `LiveReadout`, decides each live surface's heart state, number, unit, meter zone and words. Views only map its states to tokens. | The bug is a view that builds its own label from the zone. One tested function stops that mix-up coming back, and Core tests cover it without a Simulator. |
| D2 | Heart rate has three states: live, lost and none. The zone is either known or unknown. Pause is a third, separate fact. | They come from three sources: the band, the Mac and the owner. activity-spec §3 already says heart rate keeps updating while paused. |
| D3 | When the heart rate is live and the zone is unknown, the bpm shows as usual. The meter shows its empty track, and the label reads `ZONE —` in `text2`. | The Missing-Is-Grey Rule writes a missing value as `—` in `text2`, and a missing ring shows its track only. The Live Activity keeps its height, so nothing jumps when the Mac's numbers arrive mid-session. WHOOP's Live Activity also keeps its zone track on screen. |
| D4 | When the signal is lost, the last bpm, its heart, its unit and the meter show at `Goop.Opacity.stale`. The label reads `RECONNECTING` in `caution`. | Apple Workout greys out the last reading when it lapses. ghoops' stale idiom is 55% opacity. Amber means staleness, and the live screen's chip already uses it. |
| D5 | Before any heart rate arrives, the heart is `text2` and the value is `—` in `text2` with no unit. The meter shows its empty track, and the label reads `NO HR` in `text2`. | Garmin shows a heart above two dashes. The Two Voices Rule leaves the unit out after `—`. |
| D6 | The Live Activity's content carries a stale date 10 s after the last reading, and its views read `context.isStale`. | When the band drops, iOS may suspend ghoops, so the content stops changing and the Lock Screen keeps showing the last bpm as live. iOS marks the activity stale at that date without waking the app. 10 s is the live screen's existing `RECONNECTING` threshold (activity-spec §3). |
| D7 | A value the phone computed (Strain, Est. Day Strain, average and maximum heart rate, zone time) never dims with the signal. When it is missing, it shows `—` in `text2`. | DESIGN.md: "Don't dim a value the phone computed exactly." |
| D8 | The expanded Dynamic Island shows the status line only when the heart rate is lost or absent. | The expanded view has no zone row, and a dimmed number alone does not say why. DESIGN.md requires every state to say why in words. |
| D9 | `NO HR` and `RECONNECTING` appear only in GHealthCore. A new goop-lint rule, `hrword`, fails `make check` when a view writes either. | The owner's rule is to fix every instance and make the fix hold. |

Rejected:
- **Hiding the zone row when the zone is unknown.** The Live Activity would change height mid-session, and iOS may truncate it above 160 pt (DESIGN.md, Live Activity with a target).
- **A blinking heart while searching**, as Garmin does. ghoops has no blinking idiom, and a Live Activity animates only between updates.
- **`heart.slash` in the Live Activity.** A grey heart keeps the row's width. The live screen's chip keeps its `heart.slash`.
- **Tinting the heart in the zone colour**, as WHOOP's current Live Activity does. That would be a new feature, not this fix.

## 1. Facts this design relies on

- `ActivityContentState.bpm` is the last sample at any age, and `zone` is that sample's zone (`ios/GHealthCore/Sources/GHealthCore/Live/ActivityContentState.swift:18-19`, `LiveEstimator.swift:34`).
- `ActivitySession.hrState(at:)` returns `.live` within 10 s of the last sample, `.reconnecting` after that, and `.none` when there are no samples (`ActivitySession.swift:26-29`).
- `LiveEstimator` has no zone and no Strain unless it has resting heart rate, a maximum above it and `score_constants.strain` (`LiveEstimator.swift:21-23`, `:35`). The fixture set `engine_none` removes `score_constants`.
- `LiveEstimate.zones` stays all zeros when the estimator cannot run, so the live screen prints `0:00` for ZONES 4–5 (`ios/GHealth/Live/LiveActivityScreen.swift:71`). `LocalActivity` already treats that case as unknown (`LiveEstimator.swift:54`).
- `ActivityLiveStatus` sends `staleDate: nil` (`ios/GHealth/Live/ActivityLiveStatus.swift:15`, `:25`). It sends at most one update every 2 s, and only when the content changes (`:19`).
- ActivityKit sets `context.isStale` once the content's `staleDate` passes and redraws the Lock Screen and Dynamic Island views without waking the app. StandBy shows the Lock Screen view, and Apple Watch shows the compact views in its Smart Stack, so both get this fix too.
- The Lock Screen accessory widgets (`ios/Shared/WidgetViews/LockScoresView.swift`) carry no live data. The Live Activity is the Lock Screen's only live surface.
- The preview host copies the widget's compact and minimal island code (`ios/GHealth/Debug/LiveActivityPreview.swift:37-43`), so the two copies can drift apart.
- This design run computed the fixture values with the engine's formulas:
  - `boxing_23m` on `fresh` at launch: Strain 7.9, average 146, maximum 161, ZONES 4–5 `0:11`, Est. Day Strain 14.1;
  - `paused` on `fresh`: Strain 5.6, average 145, maximum 161, ZONES 4–5 `0:05`, Est. Day Strain 13.5.

  The last `boxing_23m` reading is 158 bpm, which is zone 4 (148–167).

## 2. The sweep

This table lists every place on the live surfaces that mixes up no heart rate, no zone and no Strain, at `c8bfb16`. The state columns are:
- **K**: live, zone known;
- **U**: live, zone unknown;
- **N**: no heart rate yet;
- **L**: lost (stale);
- **P**: paused.

| # | Where | K | U | N | L | P | Fault |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | Live Activity heart, bpm and unit, `ios/Shared/Goop/GoopLiveActivityView.swift:51-53` | orange heart, `158` white, `bpm` | same | orange heart, `—` white, `bpm` | `158` at full strength | as K | N shows a white dash with a unit; L looks live |
| A2 | Live Activity meter, `:64` (`ActivityZoneMeter`, `:4-23`) | lit to 4, glow, marker | empty track | empty track | lit to 4 at full strength | as K | L not dimmed |
| A3 | Live Activity label, `:65-67` | `ZONE 4` in zone 4 | **`NO HR`** in `text2` | `NO HR` in `text2` | `ZONE 4`; `RECONNECTING` in `text2` only when the zone is also unknown | `ZONE 4` | the bug; a known zone hides L |
| A4 | Live Activity STRAIN, `:72`, `:80` | `7.9` `strainLight` | `—` `strainLight` | `—` `strainLight` | `7.9` | `5.6` | dash in colour |
| A5 | Live Activity EST. DAY STRAIN, `:74` (target layout) | value, white | `—` white | `—` white | value | value | dash in white |
| A6 | Live Activity AVG HR, `:86` | `146` | `146` | `—` white | `146` | `145` | dash in white |
| A7 | Live Activity freshness, `ios/GHealth/Live/ActivityLiveStatus.swift:15`, `:25` | | | | while iOS has ghoops suspended, the content never changes, so K stays on screen | | no stale date |
| I1 | Island compact leading, `ios/GHealthWidgets/ActivityWidget.swift:20-23` | orange heart, `158` | same | orange heart, white `—` | `158` as if live | as K | no state |
| I2 | Island minimal, `:27` | orange heart | same | orange heart | orange heart | same | no state |
| I3 | Island expanded, `:17` | A1, A4–A6 | same | same | same, with no word for L | same | as A1 and A4–A6; no status |
| I4 | Preview island, `ios/GHealth/Debug/LiveActivityPreview.swift:37-43` | copies I1 and I2 | | | | | duplicate code |
| L1 | Live screen chip, `ios/GHealth/Live/LiveActivityScreen.swift:42-43`, `:47` | `LIVE` mint | `LIVE` | `NO HR` `text2`, `heart.slash` | `RECONNECTING` amber | `LIVE` | correct; its words move to Core (D9) |
| L2 | Strain number, `:17` | `7.9` | `—` white | `—` white | `7.9` | `5.6` | dash in white |
| L3 | Dial caption, `:18` | `ACTIVITY STRAIN` | `ACTIVITY STRAIN` when only `score_constants` is missing | `ACTIVITY STRAIN` | same | `PAUSED` | it checks the rates but not the model, so it gives no reason after #11 |
| L4 | Est. Day Strain, `ios/GHealth/Live/LiveTargetRow.swift:15` | `14.1` | `—` white | `—` white | `14.1` | `13.5` | dash in white |
| L5 | Heart, bpm and unit, `LiveActivityScreen.swift:51-53` | as A1 | as A1 | as A1 | as A1 | as A1 | as A1 |
| L6 | Zone name, `:56` | `ZONE 4` in zone 4 | `—` in `zone0` (near white) | `—` in `zone0` | `ZONE 4` at full strength | `ZONE 4` | dash in colour; L not dimmed |
| L7 | Zone range, `:57-61` | `148–167 BPM` `iconMuted` | `—` `iconMuted` | `—` `iconMuted` | full strength | same | dash not grey |
| L8 | Meter, `:64` | lit to 4, glow | empty | empty | full strength | same | L not dimmed |
| L9 | AVG HR and MAX HR, `:67`, `:69` | `146`, `161` | same | `—` white | same | `145`, `161` | dash in white |
| L10 | ZONES 4–5, `:71` | `0:11` | **`0:00`** | **`0:00`** | `0:11` | `0:05` | unknown shown as zero |
| H1 | Home live row bpm, `ios/GHealth/Live/GoopLiveRow.swift:23` | `158` over `BPM` | same | `—` white over `BPM` | `158` as if live | as K | as A1 |

Checked and unchanged:
- The compact trailing timer (`ActivityWidget.swift:25`), and the Live Activity's timer pill and `PAUSED` (`GoopLiveActivityView.swift:55-61`).
- The ten-minute chart (`LiveActivityScreen.swift:65`, `:80-106`). It ends at the last reading, so a lost signal already shows as a gap before `NOW`.
- `● LIVE ·` and `PAUSED ·` in the Home live row (`GoopLiveRow.swift:18`). They describe the recording, not the heart rate.
- The Home live row's Strain block (`GoopLiveRow.swift:12`). Its white `—` on blue matches every activity row's value block (`ios/GHealth/Components/Goop/GoopActivities.swift:31`); see §10.
- `HeartRateBanner` in the activity picker. It reports the Bluetooth connection before a session starts.
- The Lock Screen, Home and HRV widgets (`ios/Shared/WidgetViews/`). They show no live data.

## 3. The state model (GHealthCore)

### 3.1 `LiveReadout`

New file `ios/GHealthCore/Sources/GHealthCore/Live/LiveReadout.swift`:

```swift
/// What a live surface shows for heart rate and zone (live-hr-spec §3).
public struct LiveReadout: Equatable, Sendable {
    public enum Heart: Equatable, Sendable { case live, lost, none }
    public enum Status: Equatable, Sendable { case zone(Int), zoneUnknown, reconnecting, noHeartRate }
    public let heart: Heart
    /// The reading shown; nil exactly when `heart == .none`.
    public let bpm: Int?
    /// The zone the meter lights; nil when unknown or when `heart == .none`.
    public let zone: Int?
    public init(bpm: Int?, zone: Int?, hr: ActivityHRState, isStale: Bool = false)
}
```

The initialiser applies these rules in order:
1. `heart` is `.none` when `hr == .none` or `bpm == nil`. Otherwise it is `.lost` when `hr == .reconnecting` or `isStale`, and `.live` in every other case.
2. `bpm` and `zone` keep their inputs when `heart != .none`; otherwise both are nil.
3. `status` is `.noHeartRate` for `.none` and `.reconnecting` for `.lost`. For `.live` it is `zone.map(Status.zone) ?? .zoneUnknown`.

Derived properties:

| Property | live, zone 4 | live, no zone | none | lost, zone 4 | lost, no zone |
| --- | --- | --- | --- | --- | --- |
| `value: String` | `158` | `158` | `—` | `158` | `158` |
| `showsUnit: Bool` | true | true | false | true | true |
| `dimmed: Bool` | false | false | false | true | true |
| `status` | `.zone(4)` | `.zoneUnknown` | `.noHeartRate` | `.reconnecting` | `.reconnecting` |
| `statusText` | `ZONE 4` | `ZONE —` | `NO HR` | `RECONNECTING` | `RECONNECTING` |
| `statusSpoken` | `Zone 4` | `Zone unknown` | `No heart rate` | `Reconnecting` | `Reconnecting` |
| `zoneText` | `ZONE 4` | `ZONE —` | `ZONE —` | `ZONE 4` | `ZONE —` |
| `zoneSpoken` | `Zone 4` | `Zone unknown` | `Zone unknown` | `Zone 4` | `Zone unknown` |
| `chipText` | `LIVE` | `LIVE` | `NO HR` | `RECONNECTING` | `RECONNECTING` |
| `chipSpoken` | `Live` | `Live` | `No heart rate` | `Reconnecting` | `Reconnecting` |
| `spoken` | `158 bpm` | `158 bpm` | `No heart rate` | `158 bpm, reconnecting` | `158 bpm, reconnecting` |

`.zone(0)`, below zone 1, reads `ZONE 0` and `Zone 0`, as today.

Builders:
- `public init(session: ActivitySession, estimate: LiveEstimate?, now: Date)`. Here `bpm` is the last sample rounded, as `ActivityController.bpm` computes it; `zone` is `estimate?.zone`; and `hr` is `session.hrState(at: now)`.
- `ActivityContentState.readout(isStale: Bool) -> LiveReadout` returns `LiveReadout(bpm: bpm, zone: zone, hr: ActivityHRState(rawValue: hrState) ?? .none, isStale: isStale)`.

### 3.2 Session, estimator and estimate

- `ActivitySession.liveWindow: TimeInterval = 10` (static). `hrState(at:)` uses it in place of the literal `10`.
- `ActivitySession.liveUntil: Date?` is the last sample's time plus `liveWindow`, or nil when there are no samples. It is the Live Activity's stale date.
- `LiveEstimator.isAvailable: Bool` is true exactly when resting heart rate, a maximum above it and the model are all present. `zone(bpm:)` and `estimate` keep their own guards.
- `LiveEstimate.zones45Minutes: Int?` is nil when `strain == nil`, and `Int(zones45Seconds / 60)` otherwise. This matches `LocalActivity`'s rule for `zonesMinutes`.

## 4. What each surface shows

Tokens used below:
- `zone5` for the heart;
- `text1` (white), `text2` (grey) and `iconMuted` (units and captions);
- `caution` (amber) and `positive` (mint);
- `Goop.Opacity.stale` (55%).

**Paused** never changes the heart, the number, the label or the meter; they follow the heart state. Pause changes only the timer, which freezes and shows `PAUSED` in the pill, and the live screen's dial caption.

### 4.1 Lock Screen Live Activity (`GoopLiveActivityView`)

| State | Heart, number, unit | Meter | Label under the meter | Bottom row |
| --- | --- | --- | --- | --- |
| K | `zone5` heart, `158` in `text1`, `bpm` | segments 1–4 in their zone colours, glow and white marker on 4 | `ZONE 4` in zone 4's colour | STRAIN `7.9` `strainLight`, AVG HR `146` `text1` |
| U | same | empty track: five `plotGrid` segments, no glow, no marker | `ZONE —` `text2` | STRAIN `—` `text2`, AVG HR `146` |
| N | `text2` heart, `—` `text2`, no unit | empty track | `NO HR` `text2` | STRAIN `—` `text2`, AVG HR `—` `text2` |
| L | heart, `159` and `bpm`, all at 55% | as K, or as U when there is no zone, with the whole meter at 55% | `RECONNECTING` `caution`, full strength | as K, full strength |
| P | as its heart state | as its heart state | as its heart state | as its heart state; the pill shows `12:40` and `PAUSED` |

With a target (parity1-spec §2.3), the three cells follow the same rule: a value of `—` is `text2`, and any other value keeps its colour (`strainLight` for STRAIN, `text1` for the others).

### 4.2 Dynamic Island

- **Compact leading:** the heart and number as in §4.1, in `valueIsland` with no unit (as today). The pair dims for L.
- **Compact trailing:** the timer, unchanged.
- **Minimal:** the heart in `zone5`, or in `text2` for N. It dims for L.
- **Expanded:** §4.1 without the meter row (as today). For L and N only, the status line (`RECONNECTING` or `NO HR` in `labelTiny`, coloured as in §4.1) sits centred 7 pt under the top row. K, U and P show no status line.

### 4.3 Live screen (`LiveActivityScreen`)

| Part | K | U | N | L | P |
| --- | --- | --- | --- | --- | --- |
| Chip | antenna, `LIVE` `positive` | same | `heart.slash`, `NO HR` `text2` | antenna, `RECONNECTING` `caution` | as its heart state |
| Strain number | `7.9` `text1` | `—` `text2` | `—` `text2` | `7.9` | `5.6` |
| Dial caption | `ACTIVITY STRAIN` | `STRAIN NEEDS YOUR MAC` | `ACTIVITY STRAIN` | `ACTIVITY STRAIN` | `PAUSED` |
| Est. Day Strain | `14.1` | `—` `text2` | `—` `text2` | `14.1` | `13.5` |
| Heart, number, unit | as §4.1, in `valueLiveHR` | as §4.1 | as §4.1 | as §4.1, at 55% | as its heart state |
| Zone name | `ZONE 4` in zone 4's colour | `ZONE —` `text2` | `ZONE —` `text2` | `ZONE 4` at 55% | as its heart state |
| Zone range | `148–167` then `BPM`, `iconMuted` | `—` `text2`, no unit | `—` `text2` | `148–167 BPM` at 55% | as its heart state |
| Meter | lit 1–4, glow | empty | empty | lit 1–4 at 55% | as its heart state |
| AVG HR, MAX HR | `146`, `161` | `146`, `161` | `—`, `—` `text2` | `146`, `161` | `145`, `161` |
| ZONES 4–5 | `0:11` | `—` `text2` | `—` `text2` | `0:11` | `0:05` |

The dial caption is `PAUSED` when paused. Otherwise it is `ACTIVITY STRAIN` when `estimator.isAvailable`, and `STRAIN NEEDS YOUR MAC` when not. In N the Mac's numbers are present, so the caption stays `ACTIVITY STRAIN` and the chip gives the reason.

### 4.4 Home live row (`GoopLiveRow`)

The bpm and its `BPM` follow §4.1. In N the value is `—` in `text2` with no `BPM`, and in L both are at 55%. Nothing else in the row changes.

## 5. Code changes

### 5.1 Shared (`ios/Shared/Goop/GoopLiveActivityView.swift`)

- Add `extension LiveReadout` with the token mapping that every view below uses:
  - `heartColor`: `text2` for `.none`, else `zone5`;
  - `valueColor`: `text2` for `.none`, else `text1`;
  - `opacity`: `Goop.Opacity.stale` when `dimmed`, else 1;
  - `statusColor`: `Goop.zones[z]` for `.zone(z)`, `caution` for `.reconnecting`, `text2` otherwise;
  - `zoneColor`: `Goop.zones[zone]` when `zone` is set, else `text2`;
  - `chipColor`: `positive` for `.live`, `caution` for `.lost`, `text2` for `.none`.
- `ActivityZoneMeter` keeps its signature. Its accessibility label becomes `zone.map { "Zone \($0)" } ?? "Zone unknown"`.
- `GoopLiveActivityView` gains `var isStale = false` and `var identifier = "live-activity-view"`, after `showZone`. It builds `let readout = state.readout(isStale: isStale)`, then:
  - The heart, number and unit sit in one `HStack(spacing: 8)` with `.opacity(readout.opacity)`. It is one accessibility element (`children: .ignore`) with label `readout.spoken` and identifier `live-activity-bpm`. The heart uses `heartColor` and the number shows `readout.value` in `valueColor`. The unit appears only when `showsUnit`.
  - With `showZone`, the view shows `ActivityZoneMeter(zone: readout.zone, marker: true).opacity(readout.opacity)` with identifier `live-activity-zone-meter`. Under it is `Text(readout.statusText)` in `statusColor`, with label `statusSpoken` and identifier `live-activity-status`.
  - Without `showZone`, the view shows that same status `Text` only when `status` is `.reconnecting` or `.noHeartRate`, with `.padding(.top, 7)`.
  - `targetStat` and `stat` draw a value of `"—"` in `text2`.
  - The container's accessibility identifier is `identifier`.
- New `GoopIslandLeading(readout:)` is `HStack(spacing: 4)` holding the heart in `heartColor` and `Text(readout.value).goop(.valueIsland)` in `valueColor`. It takes `.opacity(readout.opacity)` and is one accessibility element with label `readout.spoken` and identifier `live-island-bpm`.
- New `GoopIslandMinimal(readout:)` is the heart in `heartColor` at `opacity`, with label `readout.chipSpoken` and identifier `live-island-minimal`.

### 5.2 Widget (`ios/GHealthWidgets/ActivityWidget.swift`)

- The Lock Screen view and the expanded view pass `isStale: context.isStale`. The expanded view also passes `identifier: "live-island-expanded"`.
- Compact leading becomes `GoopIslandLeading(readout: context.state.readout(isStale: context.isStale))`. Minimal becomes `GoopIslandMinimal` with the same readout.
- Compact trailing is unchanged.

### 5.3 Updates (`ios/GHealth/Live/ActivityLiveStatus.swift`)

- `request` and `update` pass `staleDate: session.liveUntil`. `end` keeps `nil`.
- Add `lastStaleDate`, set wherever `lastState` is set and cleared in `end`. Send an update when `state != lastState || staleDate != lastStaleDate`, at most once every 2 s. A target crossing still sends at once, as today.

### 5.4 App

- **`LiveActivityScreen`:**
  - `let readout = LiveReadout(session: session, estimate: activity.estimate, now: activity.now)` drives the chip and the heart card.
  - The chip keeps its symbols (`heart.slash` for `.none`, else the antenna) and its identifier `activity-hr-state`. Its text is `chipText` in `chipColor`. It becomes one accessibility element (`children: .ignore`) with label `chipSpoken`.
  - The Strain number is `text2` when it is `—`, with identifier `activity-strain`.
  - The dial caption follows §4.3, with identifier `activity-ring-caption` and a sentence-case accessibility label (`Paused`, `Activity Strain` or `Strain needs your Mac`).
  - In the heart card, the heart, number and unit form the same group as in §5.1, with identifier `activity-bpm`.
  - The zone name is `readout.zoneText` in `zoneColor`, with identifier `activity-zone-label` and label `zoneSpoken`.
  - The zone range is `activity.estimator.range(zone:)` followed by `BPM` when `readout.zone` is set. Otherwise it is `—` in `text2` without `BPM`. Its identifier is `activity-zone-range`.
  - The name-and-range stack and the meter take `.opacity(readout.opacity)`, and the meter gets `readout.zone`.
  - `stat` draws `—` in `text2`. ZONES 4–5 becomes `GoopFormat.duration(activity.estimate?.zones45Minutes)`, with identifier `activity-zones45`, and keeps its allow marker.
- **`LiveTargetRow`:** the estimate is `text2` when it is nil.
- **`GoopLiveRow`:** the bpm and `BPM` follow §4.4, using `LiveReadout(session:estimate:now:)`. The row's accessibility label appends `, \(readout.spoken)`.
- **`ActivityController.seedFixture`:** the source series is empty for `no_hr` and for the new `stale` seed.
- **`HeartRateBanner`** (`ios/GHealth/Live/HeartRateBanner.swift`, the `.connected` message): with a reading, the text stays `Live heart rate \(bpm) bpm`. A number inside a sentence keeps the sentence's voice (#10 D4). Before the first reading, the text is `Waiting for the first heart rate reading.`, so it never shows `— bpm`. The new text comes from a GHealthCore function, `HeartRateBannerText.connected(bpm:)`, which `LiveReadoutTests` covers for both cases.

The app reconnects to the last chosen heart-rate monitor when it finds it. Every unfamiliar monitor appears in **Choose your band**, even when it is the only one nearby. Tap its name to connect. The phone remembers it after a successful connection.

### 5.5 Preview host (Debug)

- `AppModel`: `liveWidgetPreview` and `targetWidgetPreview` become `var livePreview: LivePreview?`. `-GHealthWidgetPreview <name>` sets it when `LivePreview(rawValue:)` matches, and sets `fixtureSet = .fresh` and `widgetPreview = true`, as today.
- `WidgetPreviewHost`: `if let live = model.livePreview { LiveActivityPreview(preview: live) }`.
- `LiveActivityPreview(preview:)` takes its session, content and `isStale` from `preview.make(now:)` (§6.1). The Lock Screen view, the compact pair (`GoopIslandLeading` plus the timer), `GoopIslandMinimal` and the expanded view all use that one readout and `isStale`. The expanded view passes `identifier: "live-island-expanded"`. The copied island code and its two `goop-lint: allow symbol` markers are deleted.

## 6. Fixtures

### 6.1 Live Activity preview sets (`-GHealthWidgetPreview`)

New file `ios/GHealthCore/Sources/GHealthCore/Fixtures/LivePreview.swift`, inside `#if DEBUG`:

```swift
public enum LivePreview: String, CaseIterable, Sendable {
    case live, liveTarget = "live_target", liveNoZone = "live_no_zone", liveNoHeartRate = "live_no_hr", liveLost = "live_stale", livePaused = "live_paused"
    public func make(now: Date) -> (session: ActivitySession, state: ActivityContentState, isStale: Bool)
}
```

Each set builds `ActivitySession(sport: .all[0], now: start)` and adds the sample. It then builds `ActivityContentState(session:estimate: nil, now: now)` and sets the fields below. Each set mirrors an in-app fixture, so the Lock Screen and the live screen show the same numbers.

| Set | Mirrors | Start | Sample | Zone | `strainEstimate` | `avgHR` | Other | `isStale` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `live` | `boxing_23m` on `fresh` | now − 1394 s | 158 at now | 4 | 7.9 | 146 | | false |
| `live_target` | the parity1 mockup | now − 1394 s | 158 at now | 4 | 10.8 | 152 | today's overrides: `bpm` 161, `dayStrain` 12.0, target 11.6–14.6, `targetWithin` true, `elapsed` 48:10 | false |
| `live_no_zone` | `boxing_23m` on `engine_none` | now − 1394 s | 158 at now | nil | nil | 146 | | false |
| `live_no_hr` | `no_hr` | now − 1394 s | none | nil | nil | nil | | false |
| `live_stale` | `stale` | now − 1394 s | 159 at now − 26 s | 4 | 7.9 | 146 | | true |
| `live_paused` | `paused` | now − 760 s | 158 at now, added after `pause(at: now)` | 4 | 5.6 | 145 | | false |

The `live` set's Strain changes from 6.4 to 7.9 to match the fixture it mirrors. The existing `live` captures (`activity-d` and `activity-island`) change by that value and by §4.

### 6.2 Live seed `stale`

`fixtures/v2/live/stale.json` is `boxing_23m.json` with `bpm` cut to its first 1369 values. `sport` and `startOffset` (1394) stay the same. At launch the last reading (159 bpm, zone 4) is therefore 26 s old, and the fixture source sends nothing more (§5.4). Generate the file with a one-off Python command from `boxing_23m.json`, keeping its JSON formatting; do not edit it by hand. activity-spec §10 lists it (§8).

## 7. Tests

**GHealthCore** (`make ios-core-test`), new `ios/GHealthCore/Tests/GHealthCoreTests/LiveReadoutTests.swift`:
- **`readoutKeepsHeartRateApartFromZone`.** It takes the §3.1 table as arguments, plus these cases:
  - `(158, 0, .live)` reads `ZONE 0`;
  - `(nil, 4, .live)` is `.none`;
  - `(nil, nil, .none, isStale: true)` is `.noHeartRate`;
  - `(158, 4, .live, isStale: true)` equals `(158, 4, .reconnecting)`.

  For every case with `bpm != nil` and `hr != .none`, it also checks that `statusText` and `chipText` are not `NO HR`. The test fails if `NO HR` ever stands for a missing zone.
- **`readoutFollowsTheSessionClock`.** The session has one sample at `t`.
  - With a full estimator, `LiveReadout(session:estimate:now:)` is `.live` with zone 4 at `t + 9.9`, and `.lost` at `t + 10`.
  - With no samples, it is `.none`.
  - After `pause(at:)` and a later fresh sample, it is `.live`.
  - With `LiveEstimator(restingHR: nil, …)`, and again with `model: nil`, the status is `.zoneUnknown` and the value is `158`.
  - `liveUntil == t + 10`, and it is nil without samples.
- **`contentStateReadoutMatchesTheSession`.** For the same sessions, `ActivityContentState(session:estimate:now:).readout(isStale: false)` equals `LiveReadout(session:estimate:now:)`. A state decoded with `"hrState":"unknown"` reads `.none`.
- **`estimatorAvailabilityAndZoneTime`.** `isAvailable` is false without either rate, with `maximumHR <= restingHR`, and without the model. It is true with all three. `zones45Minutes` is nil for those estimators and for a session with no samples, and equals `Int(zones45Seconds / 60)` otherwise.
- **`livePreviewsMatchTheirFixtures`.** It decodes `preview/snapshot_fresh.json`, plus `live/boxing_23m.json`, `live/paused.json` and `live/stale.json` through a private `Seed` struct (`sport`, `startOffset`, `bpm`). It sets `now = snapshot.generatedAt`, builds a `LiveEstimator` from `snapshot.day`'s rates and `scoreConstants.strain`, and seeds sessions as `seedFixture` does: sample `i` at `start + i`, and `paused` paused at `start + 760`. Then:
  - `boxing_23m` gives Strain 7.9, average 146, maximum 161, zone 4 and `zones45Minutes` 11. `SessionTarget.make(day:sessionStart:)?.projected(liveTrimp:scale:)` gives 14.1.
  - `paused` gives 5.6, 145, 161, zone 4, 5 and 13.5.
  - `stale` gives last bpm 159, zone 4, Strain 7.9 and `hrState` `.reconnecting`.
  - Each `LivePreview` set's `bpm`, `zone`, `strainEstimate`, `avgHR` and `isPaused` match its row in §6.1. Its readout's `statusText`, in `allCases` order, is `ZONE 4`, `ZONE 4`, `ZONE —`, `NO HR`, `RECONNECTING`, `ZONE 4`.

  If the estimator returns numbers other than these, stop and report them to the lead, because the prototype shows these.

**UI** (`ios/GHealthUITests/GHealthUITests.swift`), new `testLiveHeartStates`:
- **Preview sets.** For each `LivePreview` raw value, launch `-GHealthWidgetPreview <set>` and wait for `live-widget-preview`. Inside `live-activity-view`:

  | Set | `live-activity-bpm` | `live-activity-status` |
  | --- | --- | --- |
  | `live` | `158 bpm` | `Zone 4` |
  | `live_target` | `161 bpm` | `Zone 4` |
  | `live_no_zone` | `158 bpm` | `Zone unknown` |
  | `live_no_hr` | `No heart rate` | `No heart rate` |
  | `live_stale` | `159 bpm, reconnecting` | `Reconnecting` |
  | `live_paused` | `158 bpm` | `Zone 4` |

  `live-island-bpm` has the same label as `live-activity-bpm`. Inside `live-island-expanded`, `live-activity-status` exists only for `live_no_hr` and `live_stale`. Capture `live-hr-<set>`, scroll up, and capture `live-hr-<set>-island`.
- **Live screen.** Launch each of these and wait for `activity-live-screen`:
  - `-GHealthFixture engine_none -GHealthLiveFixture boxing_23m`:
    - `activity-hr-state` is `Live`, and `activity-bpm` matches `^[0-9]{2,3} bpm$`;
    - `activity-zone-label` is `Zone unknown`;
    - `activity-zone-range`, `activity-zones45` and `activity-strain` are `—`;
    - `activity-ring-caption` is `Strain needs your Mac`.

    Capture `live-hr-app-no-zone`.
  - `-GHealthFixture fresh -GHealthLiveFixture stale`:
    - `activity-hr-state` is `Reconnecting`, and `activity-bpm` is `159 bpm, reconnecting`;
    - `activity-zone-label` is `Zone 4`;
    - `activity-zones45` matches `^[0-9]+:[0-9]{2}$`.

    Capture `live-hr-app-stale`.
  - `-GHealthFixture fresh -GHealthLiveFixture no_hr`:
    - `activity-hr-state` and `activity-bpm` are `No heart rate`;
    - `activity-zone-label` is `Zone unknown`, and `activity-zones45` is `—`;
    - `activity-ring-caption` is `Activity Strain`.

    Capture `live-hr-app-no-hr`.
  - `-GHealthFixture fresh -GHealthLiveFixture boxing_23m`:
    - `activity-hr-state` is `Live`;
    - `activity-zone-label` matches `^Zone [0-5]$`, and `activity-zones45` matches `^[0-9]+:[0-9]{2}$`.

    Minimise; the label of `activity-live-row` ends with ` bpm`.
  - `-GHealthFixture fresh -GHealthLiveFixture paused`: `activity-hr-state` is `Live`, and `activity-ring-caption` is `Paused`.
- `testActivityScreensTour` adds `stale` to its list and captures `activity-stale`.
- XCUITest cannot see colour, opacity or font. The accessibility labels encode the lost state, the Core tests pin the rules, and the plan compares screenshots with the prototype.

**Lint** (`scripts/goop_lint.py`):
- Add `"hrword": re.compile(r'"(?:NO HR|RECONNECTING)"')` to `RULES`. GHealthCore is already exempt from every rule except `enginenumber`, so Core may hold the words.
- `test_each_rule_fires_once` gains `"hrword": 'Text("NO HR")'`.
- After L3 the rule finds nothing, so it needs no baseline entry.

## 8. Rule text

**DESIGN.md:**
- Under Components, after "Live Activity with a target", add:

  > ### Live heart rate
  >
  > Heart rate, zone and pause are separate facts on every live surface: the Live Activity, the Dynamic Island, the live screen and the Home live row. `LiveReadout` in GHealthCore decides the number, unit, meter zone and words. Views only map them to tokens.
  > - **Live, zone known:** the bpm in `text1` after a `zone5` heart; the meter lit to the zone; `ZONE 4` in the zone's colour.
  > - **Live, zone unknown** (the Mac has not sent resting or maximum heart rate, or `score_constants`): the bpm as above; the meter's empty track; `ZONE —` in `text2`.
  > - **No heart rate yet:** a `text2` heart and `—` in `text2` with no unit; the empty track; `NO HR` in `text2`.
  > - **Lost** (no reading for 10 s, or iOS marks the Live Activity stale): the last bpm, its heart and unit, and the meter at `Goop.Opacity.stale`; `RECONNECTING` in `caution`. Values the phone computed keep full strength.
  > - **Paused** changes only the timer and the dial caption.
  >
  > **The Live Reading Rule.** `NO HR` means only that no heart rate has arrived. A missing zone or Strain never borrows it. Views never write `NO HR` or `RECONNECTING` themselves; the goop lint's `hrword` rule fails `make check` when they do.
- In Colors → Tertiary, the Amber bullet's second sentence becomes: "It is the symbol colour on banners, the WAITING FOR MAC chip, `RECONNECTING` on live surfaces, and error text."
- In Do's and Don'ts → Don't, add: "**Don't** show `NO HR` for a missing zone or Strain, or show a lost reading at full strength (The Live Reading Rule)."

**activity-spec.md:**
- §3, in the heart-rate card list, after the stats bullet, add: "Lost, unknown and missing values follow [live-hr-spec.md](live-hr-spec.md) §4.3."
- §7, at the end of the Lock Screen "Middle" bullet, add: "The label reads `ZONE —` without a zone, `NO HR` without heart rate and `RECONNECTING` when the signal is lost (live-hr-spec §4.1)."
- §7, the expanded Dynamic Island bullet becomes: "expanded: the Lock Screen's top and bottom rows, plus the status line when heart rate is lost or absent (live-hr-spec §4.2)."
- §7, the Updates bullet becomes: "**Updates:** local `activity.update` at most once every 2 s, and only when a field or the stale date changes. The stale date is 10 s after the last reading (live-hr-spec D6)."
- §10, add the seed "`stale`: Boxing; the band was lost 26 s before launch, and the last reading was 159 bpm." Replace the `-GHealthWidgetPreview live` line with: "**`-GHealthWidgetPreview <set>`** renders the Live Activity Lock Screen and Dynamic Island views in the preview host. The sets are `live`, `live_target`, `live_no_zone`, `live_no_hr`, `live_stale` and `live_paused` (live-hr-spec §6.1)."

## 9. Patterns borrowed

| Pattern | From | Built from |
| --- | --- | --- |
| Keep the zone track on screen and light only what is known | WHOOP's Live Activity keeps heart rate and the timer always visible. It shows a zone track with the current zone lit, a white marker, and the zone name under it (support.whoop.com, "How to Use the WHOOP iOS Widgets", 2026; Gadgets & Wearables, "Whoop Live Lock Screen", 2024). ghoops already follows this layout. | `ActivityZoneMeter` with no zone, and `labelTiny` |
| Grey out the last reading when the signal lapses | In Apple Watch Workout, owners describe "two gray dashes or a grayed out number where the heart rate should show up" (r/AppleWatchFitness, "Heart rate not always reading during workouts"). | `Goop.Opacity.stale` on the heart group and the meter |
| A heart above dashes when there is no heart rate | Garmin shows a "red solid heart above two dashes" when the sensor gives no value (Garmin Support, "My Garmin Watch Is No Longer Displaying Heart Rate Information"). | a `text2` heart and a `text2` `—` |
| Name the connection state | On Garmin, a flashing sensor icon means searching and a solid one means connected (Garmin manual, "Icons"). ghoops says it in words instead, as its live screen chip already does. | `RECONNECTING` in `caution` |

## 10. Product calls for the lead, and follow-ups

Calls in this spec:
1. **`ZONE —` with the empty track** for live heart rate without a zone (D3). The alternative, hiding the zone row, changes the Live Activity's height.
2. **A lost reading shows the last bpm at 55% with `RECONNECTING` in amber** (D4). It never switches to `—`, however long the loss lasts. The Lock Screen label moves from grey to amber to match the live screen's chip.
3. **The stale date is 10 s after the last reading** (D6), the same threshold the live screen uses.
4. **The expanded island shows a status line** for lost and absent heart rate only (D8).
5. **Paused keeps the heart rate's own state** (D2), as activity-spec §3 already says.
6. **The `live` preview's Strain changes from 6.4 to 7.9**, so the Lock Screen preview matches the in-app fixture it mirrors (§6.1).

No owner decision is needed beyond approving the prototype. This change touches only the phone; the Mac is unchanged.

Follow-ups, not in this issue:
- The Strain value block on activity rows and on the Home live row draws a missing Strain as a white `—` on `strain` blue (`GoopActivities.swift:31`, `GoopLiveRow.swift:12`). Making it grey needs a design for the block itself. Filed as #14.
- An ended Live Activity stays on the Lock Screen for 15 minutes with its last bpm. It could hide or grey the heart row once ended. Filed as #14.

## 11. Lead decisions (2026-11-17)

- **Decisions D1 to D9 and calls 1 to 6 in §10** are approved as written.
- **The picker banner moves into scope** (§5.4, `HeartRateBanner`). Before the first reading it said "Live heart rate — bpm", the same unit-after-dash fault this spec fixes. The owner's rule is to fix every instance. Build it in step L3.
- **The two remaining follow-ups**, the missing-Strain block and the ended Live Activity, are filed together as #14.
- **Owner.** The owner approved the prototype on 2026-11-17, including the faded last reading while the band is lost.
