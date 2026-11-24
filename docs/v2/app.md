# ghoops v2: iPhone app

Status: design spec for the iOS builder. The app reads only the HTTP API in [contract.md](contract.md); it never talks to Google and never computes a score. Fixtures: [`fixtures/v2/`](../../fixtures/v2/README.md).

Visual design, navigation, screens and widget appearance are superseded by [docs/goop/spec.md](../goop/spec.md) (ghoops, approved 2026-11-12). Data, network, cache, freshness rules and fixture sets below still apply.

## 1. What it is

A dark, native SwiftUI app with Home Screen and Lock Screen widgets that answers three questions at a glance: how recovered am I (Recovery), how hard have I pushed today (Strain), how did I sleep (Sleep). It adds trends, workouts and an overnight health monitor. It works offline from its last snapshot and always says how old the data is.

It must not copy WHOOP's brand: no WHOOP name, logo, typeface, exact colour values, exact dial geometry or screen layouts. Traffic-light recovery bands and a 0–21 strain scale are generic and allowed; the look below is ghoops's own.

## 2. Project layout

Everything lives in the ghoops repo under `ios/`. The Xcode project is generated with XcodeGen (installed at `/opt/homebrew/bin/xcodegen`, 2.46.0); the generated `.xcodeproj` is not committed.

```
ios/
  project.yml                      XcodeGen spec (source of truth)
  GHealthCore/                     local Swift package: no UI, testable with `swift test` on the Mac
    Package.swift                  platforms: iOS 26, macOS 15; swift-tools-version 6.0; no dependencies
    Sources/GHealthCore/
      Models/                      Codable types mirroring contract.md §5 (one file per body)
      API/APIClient.swift          URLSession client (§6)
      API/Pairing.swift            link parsing, Keychain token storage
      Cache/SnapshotStore.swift    App Group file cache (§5)
      Presentation/                formatting, band→colour token mapping, reason texts (§7)
      Fixtures/FixtureLoader.swift DEBUG-only fixture sets (§11)
    Tests/GHealthCoreTests/        decodes every file in fixtures/v2 (except inputs/ and scores/)
  Shared/                          SwiftUI code compiled into BOTH the app and the widget target
    Theme.swift                    colour and type tokens (§9)
    Dial.swift                     the score dial (§9.3)
    WidgetViews/                   Small, Medium, Circular, Rectangular, Inline entry views (§10)
  GHealth/                         app target
    App/GHealthApp.swift           @main, scene phase handling, URL scheme, BG task registration
    Screens/                       Overview, RecoveryDetail, StrainDetail, WorkoutDetail, SleepDetail,
                                   Trends, HealthMonitor, Settings, Pairing
    Components/                    BandPill, FreshnessBanner, Hypnogram, RangeBar, ZoneBar, StatTile
    Debug/WidgetPreviewHost.swift  DEBUG only: renders Shared/WidgetViews at widget sizes (§11)
    Resources/Assets.xcassets      AppIcon, accent colour
    GHealth.entitlements
    Info.plist
  GHealthWidgets/                  widget extension (uses Shared/WidgetViews)
    GHealthWidgets.swift           WidgetBundle
    ScoresProvider.swift           AppIntentTimelineProvider
    GHealthWidgets.entitlements
    Info.plist
  GHealthUITests/                  XCUITest screenshot tour in fixture mode (§11)
  scripts/make_icon.swift          draws the 1024×1024 app icon with CoreGraphics (§9.4)
```

### 2.1 Targets and identifiers

The bundle IDs and App Group below are for the tracked Simulator profile. Device builds use the local identity described in §2.2.

| Item | Value |
| --- | --- |
| Team | Set by the local identity for device builds. The Simulator profile has no team. |
| App target | `GHealth`, bundle ID `io.ghealth.app`, display name `ghoops` |
| Widget target | `GHealthWidgets`, bundle ID `io.ghealth.app.widgets`, extension point `com.apple.widgetkit-extension` |
| UI test target | `GHealthUITests`, bundle ID `io.ghealth.app.uitests` |
| Deployment target | iOS 26.0 |
| Toolchain | Xcode 27.2, Swift 6 language mode, strict concurrency complete |
| App Group | `group.io.ghealth.app` (both targets) |
| Keychain access group | `$(AppIdentifierPrefix)io.ghealth.shared` (both targets) |
| URL scheme | `ghealth` (app target `CFBundleURLTypes`) |
| Background task ID | `io.ghealth.app.refresh` (`BGTaskSchedulerPermittedIdentifiers`; `UIBackgroundModes` = `fetch`) |
| Orientation | portrait only |
| Appearance | dark only (`UIUserInterfaceStyle` = `Dark`) |
| Signing | Automatic for device builds. |
| Versions | `MARKETING_VERSION` 2.0.0, `CURRENT_PROJECT_VERSION` = UTC timestamp `yyyyMMddHHmm` set by `make ios-build` |

### 2.2 Make targets (repo root `Makefile`)

For device builds, create `~/.config/ghealth/ios-identity` with mode `0600`, or set `GHOOPS_IOS_IDENTITY` to the path of another file. Use one `KEY=value` per line.

```ini
TEAM_ID=<Apple Developer Team ID>
BUNDLE_ID_PREFIX=<bundle ID prefix>
APP_GROUP=<registered App Group ID>
```

Use a prefix without the `.app` suffix. The generated bundle IDs append `.app`, `.app.widgets` and `.app.uitests` to that prefix.

| Target | Command |
| --- | --- |
| `ios-project` | Reads the device identity and generates `ios/GHealth.xcodeproj`. Reports a missing file or key before invoking XcodeGen. |
| `ios-core-test` | `cd ios/GHealthCore && swift test` |
| `ios-build` | Generates the Simulator project and builds the app and widget. |
| `ios-test` | Generates the Simulator project, runs `ios-core-test` and runs the iOS UI suite. Set `IOS_DESTINATION` to select a Simulator. |
| `ios-screenshots` | Generates the Simulator project, runs the `GHealthUITests` tour and exports attachments to `ios/build/screenshots/` with `xcrun xcresulttool export attachments` |

`ios/build/`, `ios/*.xcodeproj` and `ios/**/DerivedData` are added to `.gitignore`. `make check` (Go) does not depend on the iOS targets.

## 3. Navigation

`TabView` with four tabs:

| Tab | SF Symbol | Root screen |
| --- | --- | --- |
| Today | `circle.circle` | Overview (§4.1) |
| Trends | `chart.xyaxis.line` | Trends (§4.6) |
| Health | `waveform.path.ecg` | Health monitor (§4.7) |
| Settings | `gearshape` | Settings (§4.8) |

Detail screens push on the Today stack: Recovery, Strain, Sleep, Workout. When the app is not paired, every tab shows the Pairing screen (§4.9) instead.

## 4. Screens

All screens read the cached `snapshot` (contract §5.12). "Day" below means `snapshot.day`.

### 4.1 Overview (Today)

Top to bottom:

1. **Header**: weekday and date of `day.date` ("Tue 10 Mar"); if `day.is_current_cycle` is false, add "(previous day)". Right side: freshness pill (§8).
2. **Banners** (stacked, each dismissible for the session): one per `day.health_flags` entry with severity `attention`, then stale banners (§8).
3. **Three dials** in a row, equal width, each tappable:
   - Recovery: value `NN%` (or `—`), ring fill = value/100, colour = band colour; caption "Recovery". Status badges: `Calibrating`, `Low data`.
   - Strain: value `12.8` (1 dp), ring fill = value/21, colour `strain`; caption "Strain"; if `in_progress`, caption "Strain so far".
   - Sleep: value `NN%` (performance), ring fill = value/100, colour `sleep`; caption "Sleep".
   - Null value: empty ring track, `—`, and one short line of the reason text (§7) under the caption.
4. **Key stats row** (3 `StatTile`s): HRV `56 ms` (`day.vitals.metrics.hrv_rmssd.value`), Resting HR `56 bpm` (`day.vitals.metrics.resting_hr.value`), Hours of sleep `6:55` (`day.sleep.asleep_minutes` as `h:mm`). HRV and RHR tiles show a small up/down arrow when the value differs from `day.recovery.baseline.hrv.mean_ms` / `day.recovery.baseline.resting_hr.mean` by more than 5 %; no arrow otherwise or when either number is null.
5. **Activity card**: "Workouts" list of `day.workouts` (icon by `category`, name, time range in local time, duration, strain chip). Detected efforts show "Detected effort" with a dashed outline. Tap → Workout detail. Below the list: steps, active zone minutes, calories (labelled "Google estimate"), distance.
6. **Sleep line**: last night's "Needed 7:23 · Got 6:55" from `day.sleep.need.total_minutes` and `day.sleep.asleep_minutes`; hidden when there is no main sleep.

Pull to refresh triggers a snapshot fetch (§6.3).

### 4.2 Recovery detail

1. Big dial (same component, larger), band name ("High", "Medium", "Low"), status line.
2. **Contributors** list, one row each, showing the input value, the personal baseline and the component score as a horizontal bar (0–100):
   - HRV: `56.0 ms` vs `usual 52.1 ms` (from `baseline.hrv.mean_ms`), z, `hrv_score`; weight label "55 %".
   - Resting HR: `56 bpm` vs `usual 56.0`, z, `resting_hr_score`; "20 %".
   - Sleep performance: `94 %`; "25 %".
   - Respiratory rate: `15.2 /min`, z; penalty `−2.3` when > 0, else "no effect".
   - Skin temperature: `+0.15 °C`; penalty or "no effect".
   - Missing optional inputs show "not available" in place of the value.
3. **Calibration card** when `calibrating` or `reason == insufficient_baseline`: progress bar `min(hrv_values, resting_hr_values)` of 14 with a tick at 7; text from §7.
4. **30-day chart**: bars from `snapshot.days.days[].recovery`, coloured by band, gaps for null days, today highlighted.
5. **How this works** sheet: static text summarising scores.md §2 in plain English, plus `score_version`.

Null recovery: the dial shows `—`, the contributors list still shows whatever inputs exist, and the top line shows the reason text.

### 4.3 Strain detail

1. Big dial (value/21), band name, "so far" when `in_progress`.
2. Coverage line: "Based on 92 % of the day's heart rate" (`hr_coverage`); add "Low data" badge when confidence is `low`. For open cycles add "until 14:08" (`coverage_until`, local time).
3. Cycle line: "Since you woke at 06:29" (`cycle.start`), or "Since about 07:07 (no sleep recorded)" when `start_source == typical_wake_fallback`.
4. **Heart-rate zones** stacked bar from `zones_minutes` (z1–z5, with below-zone time as a muted segment), with a legend in minutes.
5. Max/rest line: "Max HR 187 (age-based) · Resting 56" with source labels: override → "your setting", age_predicted_profile → "age-based", fitbit_zone_peak → "from Fitbit zones", observed → "highest seen".
6. Workouts list (same rows as Overview).
7. **30-day chart**: strain bars from `days`.

### 4.4 Workout detail

From the matching entry in `snapshot.workouts.workouts` (has `hr_series`); if the workout is older than 14 days, it is not reachable.

- Title (`display_name`), date, local start–end, elapsed and active minutes.
- Strain dial (value/21) plus TRIMP and coverage.
- Heart-rate line chart from `hr_series` (Swift Charts `LineMark`, y-axis bpm, horizontal zone bands drawn from the cycle's resting and max HR using the zone edges of scores.md §3.5).
- Zone bar, average and peak HR.
- Provider card (recorded only): "Fitbit says: avg 156 bpm · 610 kcal · 96 active zone minutes".
- Detected efforts show the text "Not logged as a workout. ghoops found a stretch of high heart rate."

### 4.5 Sleep detail

From `snapshot.sleep` (contract §5.5):

1. Big dial (performance), band, "Asleep 6:55 of 7:23 needed".
2. **Need breakdown** row: baseline 7:30, + strain 0:05, + debt 0:16, − naps 0:28 = 7:23.
3. **Hypnogram**: four horizontal lanes top to bottom Awake, REM, Light, Deep; x-axis local time from `hypnogram.start` to `end`; each segment a rounded rectangle in its lane; short awakenings as thin ticks on the Awake lane; gaps left blank. `asleep`/`restless` (classic sessions) draw in the Light/Awake lanes respectively and the legend says "Classic sleep (no stages)".
4. **Stages** table: minutes and `pct_of_asleep` for Light, Deep, REM; Awake minutes and segments.
5. **Stats grid**: Time in bed, Efficiency, Fell asleep in (minutes), Disturbances (total with breakdown), Bedtime, Wake time.
6. **Consistency** card: score, band, "Bedtime varies ±13.5 min · Wake ±18.9 min", nights used.
7. **Breathing** card: full/deep/light/REM breaths per minute.
8. **Overnight** mini charts: heart rate (`overnight_hr`) and HRV (`overnight_hrv`).
9. **Naps** list.
10. 30-day chart: asleep minutes bars with a need line (`sleep_need_minutes`).

No main sleep: dial `—`, text from §7, need breakdown still shown ("Tonight's need so far"), other cards hidden.

### 4.6 Trends

- Metric picker (segmented, scrollable): Recovery, Strain, Sleep, Hours asleep, HRV, Resting HR, Steps.
- Range picker: 7 days, 30 days (from the snapshot), 90 days (fetches `GET /v2/days?days=90` on demand; shows a spinner; offline shows "Needs a connection to your Mac").
- Chart: bars for scores (band colours where defined), line with points for HRV/RHR, bars for steps and hours. Null days are gaps, never zero.
- Summary row from `days.summary`: average, min, max, days with data ("28 of 30 days").

### 4.7 Health monitor

1. **Overnight vitals** card for `day.date`: one row per `vitals.metrics` entry in the order HRV, Resting HR, Respiratory rate, SpO2, Skin temperature. Each row: name, value with unit, a `RangeBar` (range_low…range_high band with a marker at value), and a state word: "Within range", "Higher than usual", "Lower than usual", "Building baseline" (`no_baseline`), or the MetricStatus text. Rows in `adverse` use the `attention` colour; others neutral. Header: "4 of 5 within your range" (`metrics_with_range` − `len(outside_range)` of `metrics_with_range`).
2. **Flags** list (`health_flags`, all severities).
3. **Band** card from `status.device`: name, battery level and status, "Last synced to Fitbit 22 min ago"; `scope_missing` → "Band details need permission: run ghoops auth login on your Mac".
4. **Irregular rhythm notifications**: from `status.user_resources.irn_profile`: "Not set up in Fitbit" / "Enrolled" / "Needs permission"; when the flag `irn_alert_recorded` is present, show its message. Never interpret it.
5. **Cardio fitness**: `vo2_max` value, level, date, "estimated" badge; null → "Not available from your band yet".
6. Footer text: "ghoops shows estimates and your own ranges. It does not diagnose. Talk to a clinician about health concerns."

### 4.8 Settings

- **Mac**: paired name and URL; "Test connection" (GET `/v2/status`, shows latency and result); last successful fetch time; "Unpair" (deletes Keychain token and defaults after confirmation).
- **Collection** (from `status`): last collect time and status, LaunchAgent installed yes/no, calibration status, missing scopes with the line "Run `ghoops auth login` on your Mac to grant: Profile, Settings, Irregular rhythm, Location".
- **Scores**: `score_version`, `score_config` values (read-only; changed with `ghoops config set` on the Mac).
- **About**: app version, "Data stays on your Mac and this iPhone. ghoops is not a medical device."
- DEBUG builds only: "Fixture mode" picker listing the sets in §11.

### 4.9 Pairing

Shown when no token is stored. Text: "Pair with your Mac. On the Mac, run `ghoops pair`, then scan the code with the Camera app, or paste the link below." A text field accepting a `ghealth://pair?…` link and a "Pair" button. The flow and messages are contract §8.4. Opening a `ghealth://pair` URL while already paired asks "Replace the current pairing?".

## 5. Data and cache

| Item | Location | Contents |
| --- | --- | --- |
| Snapshot | App Group container `snapshot.json` | the last successful `/v2/snapshot` body, verbatim bytes |
| Meta | App Group container `snapshot-meta.json` | `{"fetched_at": Time, "server_url": string, "schema_version": 2}` |
| Server URL and Mac name | App Group defaults, keys `serverURL` and `macName` | |
| Token | Keychain, `kSecClassGenericPassword`, service `io.ghealth.app.token`, account `default`, access group `<prefix>io.ghealth.shared`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | so widgets can fetch while the phone is locked, after first unlock, and the token never syncs to iCloud |

Write both files atomically (`Data.write(to:options: .atomic)`) with file protection `.completeUntilFirstUserAuthentication`. Decode before writing; a body that fails to decode, has `schema_version != 2`, or (in release builds) carries `synthetic_fixture` is rejected and the old cache kept.

## 6. Network

### 6.1 Client

- `URLSession` with an ephemeral configuration, `timeoutIntervalForRequest` 15 s (widgets: 10 s), `waitsForConnectivity` false, `requestCachePolicy` `.reloadIgnoringLocalCacheData`.
- Header `Authorization: Bearer <token>`, `Accept: application/json`.
- Base URL from defaults; paths from contract §7.2.
- Errors map to: `unauthorized` (401) → show the pairing-invalid state; `rate_limited` → "Your Mac is getting too many requests. Try again in a minute."; `store_unavailable` → "Your Mac can't open its saved health data. Log in on your Mac, then try again."; transport errors → offline state; decode failure → "Your Mac and this phone run different versions of ghoops. Update both to the same version."

### 6.2 Decoding

- `JSONDecoder` with `keyDecodingStrategy = .convertFromSnakeCase` and a custom date strategy that accepts RFC 3339 with and without fractional seconds.
- Every enum from contract §2 decodes unknown strings to an `.unknown(String)` case instead of failing.
- Optional fields are Swift optionals; arrays default to empty if absent.

### 6.3 Refresh strategy

| Trigger | Action |
| --- | --- |
| App becomes active | fetch snapshot if the last successful fetch is older than 60 s |
| Pull to refresh | fetch snapshot now |
| `BGAppRefreshTask` `io.ghealth.app.refresh` | fetch snapshot, then schedule the next request with `earliestBeginDate` = now + 30 min; also scheduled every time the app moves to background |
| Widget timeline reload | widget fetches only when the cached snapshot is older than 30 min (§10) |
| After any successful fetch | write cache, then `WidgetCenter.shared.reloadAllTimelines()` |

Only one fetch runs at a time (an actor serialises them). A failed fetch never deletes the cache.

## 7. Text for missing data

### 7.1 Reason texts (`Presentation/ReasonText.swift`)

| `reason` | `pending` text | `unavailable` text |
| --- | --- | --- |
| `no_sleep` | "Waiting for last night's sleep" | "No sleep recorded" |
| `sleep_processing` | "Fitbit is still processing your sleep" | — |
| `no_hrv` | "Waiting for overnight HRV" | "No overnight HRV" |
| `hrv_conflict` | — | "Conflicting HRV values" |
| `no_resting_hr` | "Waiting for resting heart rate" | "No resting heart rate" |
| `rhr_conflict` | — | "Conflicting resting heart rate values" |
| `insufficient_baseline` | — | "Calibrating: N of 7 nights" (N = `min(hrv_values, resting_hr_values)`) |
| `cycle_not_started` | "Your day starts when you wake" | — |
| `resting_hr_unknown` | — | "No resting heart rate to measure strain" |
| `max_hr_unknown` | — | "Set your max heart rate: ghoops config set max_hr_override_bpm N" |
| `no_heart_rate` | "No heart rate yet today" | "No heart rate recorded" |
| `insufficient_nights` | — | "Needs 4 nights this week" |
| `no_data` | — | "Not available" |
| any other | "Waiting for data" | "Not available" |

### 7.2 MetricStatus texts

`missing` "No data", `not_synced` "Not collected yet", `unavailable` "Couldn't collect", `permission_missing` "Needs permission", `conflict` "Conflicting values".

### 7.3 Widgets with missing data

A null score renders `—` in the dial and no band colour. A widget never shows a value from a different day than `snapshot.day.date`.

## 8. Freshness display

Three ages, shown separately and never merged:

| Age | Source | Stale when | Shown as |
| --- | --- | --- | --- |
| Phone copy | `snapshot-meta.fetched_at` | older than 2 h | pill "Updated 3 h ago"; dim all values to 55 % opacity after 6 h |
| Mac collection | `freshness.collector_stale` / `collected_at` | contract §4 | banner "Your Mac last collected data 5 h ago" |
| Band sync | `freshness.device_stale` / `device_last_sync_at` | contract §4 | banner "Your band last synced 7 h ago. Open the Fitbit app to sync." |

When `device_sync_source` is `scope_missing`, the Health tab's Band card explains it; no banner. Freshness pill colours: neutral under 2 h, `attention` after. Relative times use `RelativeDateTimeFormatter` with `.short` style, measured against the device clock (fixture mode: against the fixture's `generated_at`).

## 9. Visual design

### 9.1 Colour tokens (`Theme.swift`)

| Token | Hex | Use |
| --- | --- | --- |
| `background` | `#0B0C0F` | app background |
| `surface` | `#15171C` | cards |
| `surfaceRaised` | `#1E2128` | pressed cards, sheet backgrounds |
| `track` | `#2A2E36` | empty dial track, bar backgrounds |
| `textPrimary` | `#F3F5F8` | numbers, titles |
| `textSecondary` | `#A3ABB8` | labels |
| `textTertiary` | `#626B7A` | captions, axis labels |
| `recoveryHigh` | `#34D399` | band high |
| `recoveryMedium` | `#F5B83D` | band medium |
| `recoveryLow` | `#F2555A` | band low |
| `strain` | `#4F8EF7` | strain dials and bars |
| `sleep` | `#A08CFF` | sleep dials and bars |
| `stageAwake` / `stageREM` / `stageLight` / `stageDeep` | `#F2F4F7` / `#7FD6FF` / `#6E86FF` / `#3A3FB8` | hypnogram |
| `attention` | `#FF9F43` | adverse vitals, attention flags, stale pill |
| `zone1`…`zone5` | `#5C6B80`, `#3FA7D6`, `#34D399`, `#F5B83D`, `#F2555A` | heart-rate zones |

### 9.2 Type

- Score numbers: `.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit()` in dials on Overview; 72 pt in detail dials.
- Section titles: `.system(.title3, design: .rounded).weight(.semibold)`.
- Labels and captions: `.subheadline` / `.caption` with `textSecondary`; small uppercase captions use `.caption2.weight(.semibold)` with tracking 0.6.
- All text except dial numbers supports Dynamic Type; dial numbers scale with the dial.

### 9.3 Components

- **Dial**: an open ring of 300° starting at 120° (gap at the bottom), line width 10 % of the diameter, round caps, track in `track`, progress in the score colour with a subtle same-hue glow (shadow radius 8, opacity 0.35). Animates from 0 to value with `.spring(duration: 0.8, bounce: 0.15)` on first appearance only; respects Reduce Motion (no animation).
- **Cards**: `surface`, corner radius 20, padding 16, no borders.
- **BandPill**: capsule, band colour at 18 % opacity background, band colour text.
- **RangeBar**: track with the personal range as a lighter capsule, a 10 pt circle marker at the value, marker colour `attention` when adverse else `textPrimary`.
- **Haptics**: light impact on pull-to-refresh completion only.

### 9.4 App icon

`ios/scripts/make_icon.swift` (run with `swift ios/scripts/make_icon.swift <out.png>`) draws a 1024×1024 PNG with CoreGraphics: background `#0B0C0F`; three concentric 300° arcs (gap at the bottom) of radii 380, 290, 200 px and line width 64 px in `sleep`, `strain`, `recoveryHigh` from outside in; round caps. Output goes to `GHealth/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with a single-size `Contents.json`.

### 9.5 Accessibility

- Dials: `accessibilityLabel` "Recovery, 73 percent, high" / "Strain, 12.8 of 21, moderate, so far" / "Sleep, 94 percent".
- Colour is never the only signal: bands also appear as words.
- Charts provide `accessibilityChartDescriptor` with the plotted values.

## 10. Widgets

`WidgetBundle` with two widgets:

| Widget kind | Families | Content |
| --- | --- | --- |
| `ScoresWidget` | `systemSmall`, `systemMedium` | Small: one dial chosen by an App Intent parameter `metric` (`recovery` default, `strain`, `sleep`) plus the age line. Medium: the three dials in a row plus the age line. |
| `LockScoresWidget` | `accessoryCircular`, `accessoryRectangular`, `accessoryInline` | Circular: `Gauge` (`.accessoryCircularCapacity`) of recovery with the number in the centre. Rectangular: three lines "Recovery 73%", "Strain 12.8", "Sleep 94%". Inline: "Rec 73% · Strain 12.8". |

Timeline provider (`ScoresProvider`):

1. Read `snapshot.json` and `snapshot-meta.json` from the App Group.
2. If paired and the snapshot is older than 30 min, try one fetch (10 s timeout). On success write the cache (same rules as the app). On failure keep the cache.
3. Build entries at now, +15, +30, +45, +60 min (so the age text updates), policy `.after(now + 30 min)`.
4. Entry view rules: values from `snapshot.day`; age line "now", "12m", "3h"; when phone-copy age > 6 h or `collector_stale`, values at 55 % opacity with a `clock.badge.exclamationmark` glyph; unpaired → "Open ghoops to pair"; no cache → "No data yet".
5. Lock Screen widgets use `widgetAccentable()` on the dial and render in vibrant mode without custom colours.
6. Tapping any widget opens the app on Today (`widgetURL` `ghealth://today`).

## 11. Fixture mode (DEBUG only)

Launch argument `-GHealthFixture <set>` (also selectable in Settings in DEBUG builds). A Debug-only XcodeGen `postBuildScripts` step on the app target (with `ENABLE_USER_SCRIPT_SANDBOXING: NO` on that target, and the script body wrapped in `if [ "$CONFIGURATION" = "Debug" ]; then … fi`) copies `fixtures/v2/preview/*.json`, `fixtures/v2/day_*.json`, `fixtures/v2/sleep_*.json` and `fixtures/v2/status_new_user.json` into `$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Fixtures/`, read at runtime with `Bundle.main.url(forResource:withExtension:subdirectory: "Fixtures")`. Release builds contain no fixture files and no fixture code (`#if DEBUG`).

| Set | Snapshot used | App state |
| --- | --- | --- |
| `fresh` | `preview/snapshot_fresh.json` | paired, fetched_at = `generated_at` |
| `stale` | `preview/snapshot_stale.json` | paired, fetched_at = `generated_at` − 6 h |
| `no_sleep` | `snapshot_fresh` with `day` ← `day_no_sleep.json`, `sleep` ← `sleep_no_sleep.json` | paired |
| `calibrating` | `snapshot_fresh` with `day` ← `day_calibrating.json` | paired |
| `new_user` | `snapshot_fresh` with `day` ← `day_new_user.json`, `status` ← `status_new_user.json` | paired |
| `offline` | `snapshot_fresh` | paired, fetched_at = `generated_at` − 2 days, every fetch fails with a transport error |
| `unpaired` | none | unpaired |

In fixture mode the network is never used (except `offline`, which simulates failure), "now" is the snapshot's `generated_at` (plus the offsets above for `fetched_at`), and nothing is written to the real cache.

The `GHealthUITests` tour launches each set and captures `XCTAttachment` screenshots named `<set>-<screen>.png` (`lifetime = .keepAlways`) for: Today, Recovery, Strain, the first workout, Sleep, Trends (30 days), Health, Settings; for `unpaired` only the Pairing screen.

Widgets: launch argument `-GHealthWidgetPreview <set>` opens `WidgetPreviewHost` (DEBUG only), which renders the `Shared/WidgetViews` entry views from that fixture set at fixed sizes on a dark background: small 170×170 pt, medium 364×170, circular 76×76, rectangular 172×76, inline 257×26 (lock-screen views rendered in vibrant white). The tour captures one screenshot per set for `fresh`, `stale` and `unpaired`, named `widgets-<set>.png`.
