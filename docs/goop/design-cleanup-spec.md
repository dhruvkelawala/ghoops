# ghoops: design cleanup

Status: build-ready spec, written 2026-11-12 against commit `8b06816`. The build plan is [design-cleanup-plan.md](design-cleanup-plan.md).

This cleanup brings the iOS app into line with its own [DESIGN.md](../../DESIGN.md). It removes the 14 drift items that DESIGN.md records and builds the extensions that DESIGN.md proposes, because the next feature (activity editing, [edit-spec.md](edit-spec.md), written in parallel) depends on them. It adds no feature and no screen. Apart from the changes listed in §6, every screen stays pixel-identical.

## 0. Precedence, owner decisions and scope

- This spec extends DESIGN.md. Where they disagree, this spec wins for the work described here, and the last plan step updates DESIGN.md to match.
- **Owner decisions (2026-11-12, already in DESIGN.md):**
  1. Every sheet closes with an `xmark` on the right. ActivityPicker's × therefore moves to the right.
  2. A task sheet commits with one `strain` button pinned at the bottom.
  3. Every destructive confirmation is a centred system `.alert` with an orange (`zone5`) destructive button. Unpair and Replace pairing therefore switch from `.confirmationDialog` to `.alert`, and the UNPAIR button becomes a `zone5` outline.
- **In scope:** the 14 drift items (§5), the new tokens (§2), the new type cases (§3), the components in §4, the gallery entries (§8), a lint guard (§9) and a screenshot diff tool (§10).
- **Out of scope:** any editing UI, any change to copy except the two new alert messages (§4.2), any change to Go code, fixtures or GHealthCore. The edit mockups are used only to check that the component APIs are enough (§11).
- **Line numbers** in this spec refer to commit `8b06816`. Steps move lines, so find each site by its content as well as its number.
- **Nothing in this spec is left to the builder's taste.** If a site does not behave as written, stop and report it. Do not pick another value.

## 1. Rules this cleanup follows

1. **Pixel identity.** A swap from a literal to a token, or from an ad-hoc style to a type case, keeps every value. The screenshot tours before and after a step must match except for the changes §6 lists for that step.
2. **Type mapping.** An ad-hoc `GoopTextStyle(size:…)` call or a raw `Font(GoopFont…)` call maps onto an existing `Goop.TextStyle` case only when family, size, weight, tracking and line height all match. Otherwise it gets a new named case (§3.1) with those exact values. The size is never rounded to a nearby case.
3. **Dynamic Type caps.** A new label case uses cap 1.5, a body or caption case cap 1.6, and a Sofia value case cap 1.35, which is the rule DESIGN.md states for each role. The exception is a case that replaces a raw `Font(GoopFont…)` call. Raw fonts never scaled, so those cases use cap 1 and stay fixed. Where the cap differs from the call it replaces, §6 lists the change; it shows only at Dynamic Type sizes above xxxLarge.
4. **Fixed numerals stay fixed.** Numbers that sit inside fixed frames (the 98×41 activity value block, the live screen, the Live Activity, widgets) keep a fixed size. Letting them scale is a layout change, not a cleanup; see §13.
5. **Selectors stay.** Every existing accessibility identifier and label stays, so the XCUITests and verify-ios recipes keep working. New identifiers are listed with their components.

## 2. Tokens

All tokens live in `ios/Shared/Goop/GoopTokens.swift`, which both the app and the widget extension compile. Every new colour is also appended to `Goop.Color.all`, in the order listed here.

### 2.1 New colours (`Goop.Color`)

| Token | Value | Replaces |
| --- | --- | --- |
| `strainLight` | `#4FB6F5` | `ActivityPicker.swift:53`, `WorkoutScreen.swift:18`, `GoopLiveActivityView.swift:57`, `:70` |
| `strainPale` | `#7FD0FF` | `GoopLiveRow.swift:20` |
| `strainDeep` | `#0B3550` | `GoopLiveRow.swift:25` |
| `liveActivityFill` | `#101418` | `GoopLiveActivityView.swift:17`, `ActivityWidget.swift:9`, `:11`, `LiveActivityPreview.swift:25` |
| `sheetTop` | `#252C32` | `ActivityPicker.swift:42` |
| `sheetMid` | `#1A1F23` | `ActivityPicker.swift:42` |
| `sheetBottom` | `#151A1D` | `ActivityPicker.swift:40`, `:42` |
| `backgroundHomeTop` | `#293339` | `GoopTokens.swift:342` |
| `backgroundHomeUpper` | `#1A222B` | `GoopTokens.swift:342` |
| `backgroundHomeLower` | `#13171C` | `GoopTokens.swift:342` |
| `backgroundHomeBase` | `#0E1313` | `GoopTokens.swift:342`, `GoopControls.swift:109`, `:110` |
| `backgroundDetailTop` | `#273238` | `GoopTokens.swift:342` |
| `backgroundDetailUpper` | `#1D252B` | `GoopTokens.swift:342` |
| `backgroundDetailLower` | `#14191D` | `GoopTokens.swift:342` |
| `backgroundDetailBase` | `#111619` | `GoopTokens.swift:342` |
| `barFadeStart` | `#2B3238` | `GoopTokens.swift:317`, `:318` |
| `wallpaperTop` | `#3D4A57` | `GoopTokens.swift:321` |
| `wallpaperMid` | `#1E262D` | `GoopTokens.swift:321` |
| `wallpaperBottom` | `#2A2230` | `GoopTokens.swift:321` |
| `dotHole` | `#13181C` | `GoopCharts.swift:145`, `GoopTrendComponents.swift:150`, `SleepScreen.swift:142` |
| `wordmarkDial` | `#8D9499` | `GoopCards.swift:55`, `HomeScoresView.swift:73` |
| `vitalTitle` | `#E5E7E9` | `GoopHealth.swift:27` |
| `typicalKeyEdge` | `#CCCCCC` | `GoopSleepComponents.swift:41` |
| `stageRing` | `#D0D3D6` | `GoopSleepComponents.swift:82` |

Two literals equal existing tokens and switch to them: `HomeScoresView.swift:40` `#C4C8CB` becomes `textSoft`, and `Pairing.swift:12` `#E9ECEE` becomes `bodyText`. `WorkoutScreen.swift:19` `#D6E6F2` has no token; the banner rebuild (§4.3) replaces it with `textSoft`.

`backgroundDetailLower` has the same value as `sheetFill`. They stay separate tokens because they have different roles.

### 2.2 Gradients (`Goop.Gradient`)

- **New** `sheet = LinearGradient(colors: [Color.sheetTop, Color.sheetMid, Color.sheetBottom], startPoint: .top, endPoint: .bottom)`. It is the task sheet's background.
- `hoursBar` and `baselineNeedBar` use `Color.barFadeStart` in place of the literal.
- `widgetWallpaper` keeps its stops and points and uses `wallpaperTop`, `wallpaperMid` and `wallpaperBottom`.
- `GoopBackground` keeps its positions. Its colour arrays become `[SwiftUI.Color]`: home `[backgroundHomeTop, backgroundHomeUpper, backgroundHomeLower, backgroundHomeBase]`, detail `[backgroundDetailTop, backgroundDetailUpper, backgroundDetailLower, backgroundDetailBase]`. The stop is `.init(color: $1, location: …)`.
- `LiveActivityScreen.swift:65` uses `Goop.Gradient.card` in place of its copy built from literals (drift 2).

### 2.3 Radii (`Goop.Metric`)

The existing 17 metrics stay. These are new:

| Token | Value | Role |
| --- | --- | --- |
| `radiusHairline` | 1 | the 2 pt edge bar in activity rows, level segments, legend swatches |
| `radiusMark` | 2 | the zone meter's segments, hypnogram awake segments, the nap and restorative swatches |
| `radiusSegment` | 4 | hypnogram stage segments, the calibration bar |
| `radiusHighlight` | 5 | the current-day highlight column in Canvas charts |
| `radiusBanner` | 10 | the neutral banner |
| `radiusBannerTinted` | 12 | the tinted banner |
| `radiusChoice` | 12 | a selected choice row |
| `radiusLiveActivity` | 24 | the Live Activity shell |
| `radiusSheet` | 26 | the task sheet's `presentationCornerRadius` |

### 2.4 Opacity (`Goop.Opacity`, new enum)

- `stale: Double = 0.55`. It replaces all 32 stale-dimming literals (§5, drift 13).
- `disabled: Double = 0.4`. It is used by `Pairing.swift:18` and the task sheet's disabled commit button.

## 3. Type scale

### 3.1 New `Goop.TextStyle` cases

Append these to the enum after `unit`, in this order, each with the `GoopTextStyle` values shown. N is Nunito Sans (`sofia: false`), S is Sofia Sans Condensed (`sofia: true`, weight 750). Tracking is in em, as in the existing cases. Line height is `nil` for all of them.

| Case | Font | Size | Weight | Tracking | Cap | Used for |
| --- | --- | --- | --- | --- | --- | --- |
| `labelTiny` | N | 11 | 750 | 0.10 | 1.5 | vital tile title, live HR chip, Live Activity zone label |
| `labelMicro` | N | 10 | 750 | 0.10 | 1.5 | `WAITING FOR MAC`, Live Activity stat labels |
| `labelStat` | N | 10.5 | 750 | 0.10 | 1.5 | live row `LIVE ·`, live screen stat labels |
| `labelPicker` | N | 13.5 | 750 | 0.10 | 1.5 | the metric picker label |
| `labelRing` | N | 12.5 | 750 | 0.14 | 1.5 | the label inside the live Strain ring |
| `labelCommit` | N | 14 | 750 | 0.14 | 1.5 | the task sheet commit button |
| `labelTimerPill` | N | 8 | 750 | 0.10 | 1.5 | `PAUSED` in the Live Activity timer pill |
| `labelLockRow` | N | 11 | 750 | 0.08 | 1 | rectangular Lock Screen widget row labels |
| `captionDial` | N | 10.5 | 550 | 0 | 1.6 | the caption under a Home dial |
| `captionWidget` | N | 10 | 550 | 0 | 1 | the stale age line in Home widgets |
| `rowNote` | N | 12 | 550 | 0 | 1.6 | a choice row's trailing note (`Last: Sat`) |
| `chip` | N | 11.5 | 550 | 0 | 1.6 | `GoopChip` text |
| `unitLarge` | N | 16 | 500 | 0 | 1.35 | the unit beside a trend average |
| `unitSmall` | N | 10 | 550 | 0 | 1.6 | `BPM` under the live row value |
| `valueChip` | S | 11.5 | 750 | 0 | 1 | the vital tile's range chip |
| `valueBlock` | S | 21 | 750 | 0 | 1 | the value in an activity row's value block |
| `valueLiveRow` | S | 20 | 750 | 0 | 1 | the bpm in the live row |
| `valueTimer` | S | 44 | 750 | 0.02 | 1 | the live screen timer |
| `scoreLive` | S | 68 | 750 | 0 | 1 | the live Strain inside the live ring |
| `valueLiveHR` | S | 46 | 750 | 0 | 1 | the live screen bpm |
| `valueZoneRange` | S | 13 | 750 | 0 | 1 | the live screen zone bpm range |
| `valueLiveStat` | S | 22 | 750 | 0 | 1 | live screen stats, the Live Activity timer |
| `valueLiveActivityHR` | S | 40 | 750 | 0 | 1 | the Live Activity bpm |
| `valueIsland` | S | 18 | 750 | 0 | 1 | the Dynamic Island compact bpm |

`valueTimer`'s tracking of 0.02 em reproduces today's `.tracking(0.88)` at 44 pt.

### 3.2 Every ad-hoc and raw call, mapped

`GoopTextStyle(size: n)` with no other arguments means N, weight 550, tracking 0, cap 1.6, no line height. Every value below was read from the code at `8b06816`.

| Site | Today | Becomes | Identical? |
| --- | --- | --- | --- |
| `GoopCards.swift:34` | N 10.5/550, cap 1.6 | `.captionDial` | yes |
| `GoopCards.swift:86`, `:88`, `:90` | raw S 14 | `.valueChart` (S 14, cap 1) | yes |
| `GoopActivities.swift:66` | raw S 21 | `.valueBlock` | yes |
| `GoopActivities.swift:71` | N 10/750/0.10, cap 1.6 | `.labelMicro` | cap 1.6 → 1.5 |
| `GoopHealth.swift:27` | N 11/750/0.10, cap 1.5 | `.labelTiny` | yes |
| `GoopHealth.swift:37` | raw S 11.5 | `.valueChip` | yes |
| `GoopHealth.swift:59` | N 13/750/0.10, cap 1.5 | `.labelStage` | yes |
| `GoopTrendComponents.swift:18` | N 13.5/750/0.10, cap 1.5 | `.labelPicker` | yes |
| `GoopTrendComponents.swift:63` | N 11.5/550, cap 1.6 | `.chip` | yes |
| `GoopTrendComponents.swift:79` | N 16/500, cap 1.35 | `.unitLarge` | yes |
| `GoopSleepComponents.swift:42` | N 11.5 or 12/750/0.10, cap 1.5 | `trend ? .labelDial : .labelSmall` | yes |
| `GoopDetailSupport.swift:82` | S 17, cap 1.6 | `.valueMid` (S 17, cap 1.35) | cap 1.6 → 1.35 |
| `GoopLiveRow.swift:12` | raw S 21 | `.valueBlock` | yes |
| `GoopLiveRow.swift:18` | N 10.5/750/0.10, cap 1.6 | `.labelStat` | cap 1.6 → 1.5 |
| `GoopLiveRow.swift:19` | raw S 12 | `.axisTime` (S 12, cap 1) | yes |
| `GoopLiveRow.swift:23` value | raw S 20 | `.valueLiveRow` | yes |
| `GoopLiveRow.swift:23` `BPM` | N 10/550, cap 1.6 | `.unitSmall` | yes |
| `LiveActivityScreen.swift:12` | raw S 44 + `.tracking(0.88)` | `Text(…).monospacedDigit().goop(.valueTimer)`; remove `.tracking(0.88)` | yes |
| `LiveActivityScreen.swift:17` | raw S 68 | `.scoreLive` | yes |
| `LiveActivityScreen.swift:18` | N 12.5/750/0.14, cap 1.6 | `.labelRing` | cap 1.6 → 1.5 |
| `LiveActivityScreen.swift:39` | N 11/750/0.10, cap 1.6 | `.labelTiny` | cap 1.6 → 1.5 |
| `LiveActivityScreen.swift:48` | raw S 46 | `.valueLiveHR` | yes |
| `LiveActivityScreen.swift:49` | N 14/550, cap 1.6 | `.legend` | yes |
| `LiveActivityScreen.swift:53` | raw S 13 | `.valueZoneRange` | yes |
| `LiveActivityScreen.swift:68` value | raw S 22 | `.valueLiveStat` | yes |
| `LiveActivityScreen.swift:68` label | N 10.5/750/0.10, cap 1.6 | `.labelStat` | cap 1.6 → 1.5 |
| `LiveActivityScreen.swift:88` | raw S 11 on the HStack | `.goop(.axis)` on the same HStack | yes |
| `LiveActivityScreen.swift:104` | N 13/750/0.10, cap 1.6 | `.labelStage` | cap 1.6 → 1.5 |
| `ActivityPicker.swift:39` | N 14/750/0.14, cap 1.6 | `.labelCommit`, inside `GoopTaskSheet` (§4.4) | cap 1.6 → 1.5 |
| `ActivityPicker.swift:47` | N 11.5/750/0.10, cap 1.6 | `GoopSectionLabel` (`.labelCard`), §4.4 | **no**: V19 |
| `ActivityPicker.swift:54` | N 13/750/0.10, cap 1.6 | `.labelStage`, inside `GoopChoiceRow` | cap 1.6 → 1.5 |
| `ActivityPicker.swift:56` | N 12/550, cap 1.6 | `.rowNote`, inside `GoopChoiceRow` | yes |
| `HeartRateBanner.swift:12` | N 11.5/750/0.10, cap 1.6 | banner title `.labelStatus` (§4.3) | cap 1.6 → 1.5 |
| `HeartRateBanner.swift:13` | N 12.5/550, line 16.25, cap 1.6 | banner text `.bodySmall` (line 18.1) | **no**: V17 |
| `WorkoutScreen.swift:19` | N 13/550, line 17.55, cap 1.6 | banner text `.bodySmall` | **no**: V16 |
| `GoopLiveActivityView.swift:52` | raw S 40 | `.valueLiveActivityHR` | yes |
| `GoopLiveActivityView.swift:53` | N 14/550, cap 1.6 | `.legend` | yes |
| `GoopLiveActivityView.swift:58` | raw S 22 on `GoopActivityTimer` | `.goop(.valueLiveStat)` on the same view | yes |
| `GoopLiveActivityView.swift:60` | N 8/750/0.10, cap 1.6 | `.labelTimerPill` | cap 1.6 → 1.5 |
| `GoopLiveActivityView.swift:66` | N 11/750/0.10, cap 1.6 | `.labelTiny` | cap 1.6 → 1.5 |
| `GoopLiveActivityView.swift:83` | raw S 24 | `.scoreWidgetMedium` (S 24, cap 1) | yes |
| `GoopLiveActivityView.swift:84` | N 10/750/0.10, cap 1.6 | `.labelMicro` | cap 1.6 → 1.5 |
| `ActivityWidget.swift:22` | raw S 18 | `.valueIsland` | yes |
| `ActivityWidget.swift:25` | raw S 16 on `GoopActivityTimer` | `.goop(.valueLock)` (S 16, cap 1) | yes |
| `LiveActivityPreview.swift:34` | raw S 18 | `.valueIsland` | yes |
| `LiveActivityPreview.swift:36` | raw S 16 | `.goop(.valueLock)` | yes |
| `HomeScoresView.swift:45` | raw N 10.5/550 on the HStack | `.goop(.tab)` (N 10.5/550, cap 1) on the same HStack | yes |
| `HomeScoresView.swift:66` | raw N 10/550 on the HStack | `.goop(.captionWidget)` on the same HStack | yes |
| `LockScoresView.swift:29` | raw N 11/750 + `.tracking(0.88)` | `.goop(.labelLockRow)`; remove `.tracking(0.88)` | yes |
| `LockScoresView.swift:31` | raw S 15 | `.goop(.valueWidgetList)` (S 15, cap 1) | yes |

"Identical" means identical at the default size and at every larger size. `GoopTextStyle` also applies its scale when it is below 1, so text that used a raw font now shrinks at Dynamic Type sizes smaller than Large, like every other Goop style (V3). Widgets and the Live Activity preview hosts force `.dynamicTypeSize(.large)`, so they never change.

**Order matters at one site.** Keep `.monospacedDigit()` on the `Text`, before `.goop(.valueTimer)`, so the digits stay fixed-width. The plan checks this on the frozen `activity-paused` capture.

**Exceptions that keep a raw font**, with a lint allow marker (§9): `GoopCharts.swift:6` (`GoopPlot.text` draws Canvas text at chart sizes), `ScoreRing.swift:66` and `:67` (ring numerals sized by the ring variant), `GoopLogo.swift:15` (the wordmark), and the simulated iOS Lock Screen clock in the Debug hosts (`LiveActivityPreview.swift:21`, `:22`, `WidgetPreviewHost.swift:21`).

## 4. Components

New components go in `ios/GHealth/Components/Goop/` (the app target), apart from tokens and type. Each one is added to `ComponentGallery` (§8).

### 4.1 `GoopButton(role:)`

```swift
enum GoopButtonRole { case outline, primary, destructive }

struct GoopButton: View {
    var title: String
    var role: GoopButtonRole = .outline
    var busy = false
    var identifier: String? = nil
    var action: () -> Void
}
```

- Layout, unchanged from today: `HStack(spacing: 8) { Text(title).goop(.labelCard); if busy { ProgressView().tint(ink) } }`, then `.frame(maxWidth: .infinity).frame(minHeight: 50).foregroundStyle(ink)`, then background, overlay and `.buttonStyle(.plain)`. When `identifier` is set, apply it with `.accessibilityIdentifier` to the `Button`.
- `.outline`: ink `text1`, transparent, `strokeBorder(Goop.Color.outlineBorder, lineWidth: 1.5)` on `RoundedRectangle(cornerRadius: Goop.Metric.radiusButton)`.
- `.primary`: ink `backgroundHomeBase`, fill `text1` in the same shape, no stroke.
- `.destructive`: ink `zone5`, transparent, `strokeBorder(Goop.Color.zone5, lineWidth: 1.5)`.
- The `primary: Bool` parameter is removed. `Pairing.swift:18` becomes `GoopButton(title: "PAIR", role: .primary, busy: busy, action: pair)`, and the gallery's PAIR button changes the same way.
- **DELETE ACTIVITY** (`WorkoutScreen.swift:37`) becomes `GoopButton(title: "DELETE ACTIVITY", role: .destructive, identifier: "activity-delete") { deleting = true }.padding(16)`. It is 50 tall instead of 48, the stroke is 1.5 instead of 1, and the text is `labelCard` instead of `labelAction` (V10).
- **UNPAIR** (`GoopMoreScreen.swift:26`) becomes `GoopButton(title: "UNPAIR", role: .destructive) { confirmUnpair = true }`, which turns the stroke and label `zone5` (V11). **Owner decision (2026-11-12): it moves to the end of More**, after ABOUT and before the Debug-only DEVELOPER section, as a full-width destructive button with nothing after it in Release. Remove it from the MAC section.

### 4.2 Destructive confirmation: `goopDestructiveAlert`

Add to `GoopControls.swift`:

```swift
extension View {
    func goopDestructiveAlert(_ title: String, isPresented: Binding<Bool>, verb: String, message: String, perform: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            Button(verb, role: .destructive, action: perform)
            Button("Cancel", role: .cancel) {}
        } message: { Text(message) }
    }
}
```

The three destructive confirmations all use it:

| Action | Site | Title | Verb | Message |
| --- | --- | --- | --- | --- |
| Delete activity | `WorkoutScreen.swift:50-63` | `Delete this activity?` | `Delete` | `This removes it from ghoops on your phone and your Mac.` (unchanged) |
| Unpair | `GoopMoreScreen.swift:69-71` | `Unpair from your Mac?` | `Unpair` | `This iPhone stops reading from your Mac until you pair again. Nothing is deleted on your Mac.` |
| Replace pairing | `GHealthApp.swift:41-46` | `Replace the current pairing?` | `Replace pairing` | `This iPhone switches to the Mac in the new link. Nothing is deleted on your Mac.` |

- The Delete `perform` closure is today's `Delete` button body, moved unchanged.
- Unpair: `perform` is `{ Task { await model.unpair() } }`.
- Replace pairing: `isPresented` is today's binding (`model.pendingURL != nil`, setting `nil` on false). `perform` is today's button body: pair with `pendingURL` if set, then set `pendingURL = nil`. Cancel closes the alert through the binding, which clears `pendingURL`.
- The two messages are new copy (V12, V13). Both are true of the code: `PairingRepository.unpair()` deletes only the phone's token and server URL, and `AppModel.pair` replaces the phone's credentials and drops its cached snapshot. Neither touches the Mac.
- `.confirmationDialog` no longer appears anywhere in the app. The lint guard enforces this (§9).

**The orange verb.** The owner decision asks for an orange destructive verb inside the alert. A system alert draws `role: .destructive` in the system's own red, and SwiftUI has no documented way to recolour one alert action. The plan therefore treats orange as a probe (plan step D8) with exactly one attempt: add `.tint(Goop.Color.zone5)` to the destructive `Button` inside `goopDestructiveAlert`. It passes only if the verb renders orange and Cancel does not. If it fails, the probe is reverted, the verb stays the system colour, and the owner chooses from the options in §13. The builder tries nothing else.

### 4.3 `GoopBanner(tone:)`

`GoopBanner` absorbs `HeartRateBanner`'s drawing and the inline workout banner, gains a tone, an optional title, an optional trailing text action and an optional accessory area.

```swift
enum GoopBannerTone { case neutral, strain, positive, caution, muted }

struct GoopBannerAction {
    var title: String        // uppercase, e.g. "UNDO"
    var identifier: String
    var perform: () -> Void
}

struct GoopBanner<Accessory: View>: View {
    var text: String
    var title: String? = nil
    var symbol: String = "clock"
    var tone: GoopBannerTone = .neutral
    var symbolColor: Color = Goop.Color.caution   // used by .neutral only
    var action: GoopBannerAction? = nil
    var dismiss: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory
}

extension GoopBanner where Accessory == EmptyView {
    init(text: String, title: String? = nil, symbol: String = "clock", tone: GoopBannerTone = .neutral,
         symbolColor: Color = Goop.Color.caution, action: GoopBannerAction? = nil, dismiss: (() -> Void)? = nil)
}
```

**Structure, shared by every tone:**

```
VStack(alignment: .leading, spacing: 7) {
    HStack(spacing: S) {
        GoopSymbol(symbol)
        VStack(alignment: .leading, spacing: 3) {
            if let title { Text(title).goop(.labelStatus).foregroundStyle(ink) }
            Text(text).goop(textStyle).foregroundStyle(textColor).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if let action { Button(action: action.perform) { Text(action.title).goop(.labelCard).foregroundStyle(Goop.Color.text1).frame(minHeight: 44).contentShape(Rectangle().inset(by: -8)) }.accessibilityIdentifier(action.identifier) }
        if let dismiss { Button(action: dismiss) { GoopSymbol(name: "xmark", size: 13).frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -8)) }.accessibilityLabel("Dismiss: \(text)") }
    }
    accessory()
}
.padding(.vertical, PV).padding(.horizontal, PH).frame(maxWidth: .infinity, alignment: .leading)
.background(…).overlay(…).buttonStyle(.plain)
```

An `EmptyView` accessory takes no space and adds no spacing.

**Per tone:**

| | `.neutral` | `.strain` | `.positive` | `.caution` | `.muted` |
| --- | --- | --- | --- | --- | --- |
| Base colour | n/a | `strain` | `positive` | `caution` | `text2` |
| Ink (symbol, title) | `symbolColor` | `strainLight` | `positive` | `caution` | `text2` |
| Symbol | 15 pt, `.light` | 18 pt, `.semibold` | same | same | same |
| HStack spacing S | 10 | 11 | 11 | 11 | 11 |
| Text style, colour | `bodyMid`, `legendText` | `bodySmall`, `textSoft` | same | same | same |
| Padding PV, PH | 12, 14 | 11, 13 | 11, 13 | 11, 13 | 11, 13 |
| Background | `legendFill` in `RoundedRectangle(radiusBanner)` | base at 12 % in `RoundedRectangle(radiusBannerTinted)` | same | same | same |
| Overlay | none | 1 pt `strokeBorder` of base at 25 %, same shape | same | same | same |

With no title, action or accessory, `.neutral` draws exactly today's `GoopBanner`. The `color:` parameter is renamed `symbolColor:`.

**Call sites.** Every call names `dismiss:` explicitly, because a trailing closure would now bind to `accessory`:

- `HomeScreen.swift:14`, `:15`, `:126`: unchanged arguments.
- `HomeScreen.swift:150`: `GoopBanner(text: text, symbol: symbol, dismiss: { dismissed.insert(id) })`.
- `GoopHealthScreen.swift:21`: `color:` becomes `symbolColor:`.
- `ComponentGallery.swift:196`: unchanged.

**`HeartRateBanner`** keeps its file, its `state` and `select` inputs, its title, message and symbol mapping, and the identifier `heart-rate-banner`. Its body becomes:

```swift
GoopBanner(text: message, title: title, symbol: symbol, tone: tone) {
    if case .denied = state { Link("Settings", destination: URL(string: UIApplication.openSettingsURLString)!).goop(.bodyMid).foregroundStyle(ink) }
    if case .choosing(let devices) = state { ForEach(devices) { device in Button(device.name) { select(device.id) }.goop(.bodyMid).foregroundStyle(ink) } }
}.accessibilityIdentifier("heart-rate-banner")
```

- `tone` replaces `color`: `.connected` → `.positive`; `.searching` and `.choosing` → `.muted`; every other state → `.caution`. `ink` is that tone's ink colour.
- The `Image(systemName:)` at `HeartRateBanner.swift:10` goes away (drift 14), because `GoopBanner` draws its symbol with `GoopSymbol`.

**Workout pending banner** (`WorkoutScreen.swift:17-20`) becomes:

```swift
GoopBanner(text: message, symbol: "arrow.triangle.2.circlepath", tone: .strain)
    .padding(.horizontal, 16).padding(.top, 12).accessibilityIdentifier("activity-save-banner")
```

Its fill goes from 8.6 % to 12 %, its stroke from 27 % to 25 %, its symbol from light to semibold, and its text from 13 pt `#D6E6F2` to `bodySmall` `textSoft` (V16).

### 4.4 `GoopTaskSheet` and the pieces of a task

Extract these from `ActivityPicker.swift` into a new file `ios/GHealth/Components/Goop/GoopTaskSheet.swift`.

```swift
struct GoopCommit {
    var title: String          // uppercase, names the result: "START BOXING"
    var symbol: String         // SF Symbol, e.g. "stopwatch", "checkmark"
    var identifier: String
    var enabled = true
    var action: () -> Void
}

struct GoopTaskSheet<Content: View>: View {
    var title: String
    var back: (() -> Void)? = nil
    var closeIdentifier = "sheet-close"
    var commit: GoopCommit
    @ViewBuilder var content: () -> Content
}
```

**Appearance:**

- **Header** (fixed, outside the scroll view): a `ZStack` of height 50 with no extra top padding.
  - Centre: `Text(title).goop(.labelNav)`.
  - Left, only when `back` is set: `GoopSymbol(name: "chevron.left", size: 21, color: Goop.Color.text1)` in a 44×44 frame, identifier `sheet-back`, label `Back`.
  - Right, always: `GoopSymbol(name: "xmark", size: 13)` (light, `iconMuted`) in a 44×44 frame, identifier `closeIdentifier`, label `Close`. It calls the environment's `dismiss()`.
  - The `HStack` holding the two buttons has no horizontal padding, as in `GoopSheet`.
- **Body:** `ScrollView { content().padding(.horizontal, 16).padding(.bottom, 16) }.scrollDismissesKeyboard(.interactively)`.
- **Commit**, in `.safeAreaInset(edge: .bottom)`:
  - `HStack(spacing: 10) { GoopSymbol(name: commit.symbol, size: 18, color: Goop.Color.text1); Text(commit.title).goop(.labelCommit) }`, then `.frame(maxWidth: .infinity).frame(height: 54).background(Goop.Color.strain, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusButton))`.
  - It is a `Button(action: commit.action)` with `.accessibilityIdentifier(commit.identifier)`. When `enabled` is false, it gets `.disabled(true)` and `.opacity(Goop.Opacity.disabled)`.
  - Around it: `.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8).background(Goop.Color.sheetBottom)`.
- **Sheet:** `.foregroundStyle(Goop.Color.text1).buttonStyle(.plain).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(Goop.Metric.radiusSheet).presentationBackground(Goop.Gradient.sheet)`.
- **A sub-step** (such as picking a sport inside a bigger task) is the same `GoopTaskSheet` with a different `title`, `back` and `commit` and different content. The caller swaps them from its own state. A sub-step never presents a second sheet.

**Pieces used inside a task**, in the same file:

```swift
struct GoopSectionLabel: View { var title: String }   // called as GoopSectionLabel(title: "RECENT")
struct GoopSearchField: View { var prompt: String; @Binding var text: String; var identifier: String }
struct GoopChoiceRow: View {
    var symbol: String
    var title: String          // passed already uppercased
    var note: String? = nil
    var selected: Bool
    var identifier: String
    var action: () -> Void
}
```

- `GoopSectionLabel`: `Text(title).goop(.labelCard).foregroundStyle(Goop.Color.iconMuted).frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)`. The caller adds padding.
- `GoopSearchField`: today's search field (`ActivityPicker.swift:24-27`) with `cornerRadius: Goop.Metric.radiusPicker` and no outer top padding.
- `GoopChoiceRow`: today's row (`ActivityPicker.swift:51-62`) with these substitutions:
  - the selected symbol colour is `strainLight`;
  - the name uses `.goop(.labelStage)`;
  - the note uses `.goop(.rowNote)` in `chevronDial`;
  - the radius is `Goop.Metric.radiusChoice`.

  It keeps the `.isSelected` trait.

**ActivityPicker** becomes:

```swift
GoopTaskSheet(title: "START ACTIVITY", closeIdentifier: "activity-picker-close",
              commit: GoopCommit(title: "START \(selection.name.uppercased())", symbol: "stopwatch", identifier: "activity-start") { Task { await model.activity.start(sport: selection) } }) {
    HeartRateBanner(state: model.activity.connection, select: model.activity.connect).padding(.top, 12)
    GoopSearchField(prompt: "Search activities", text: $query, identifier: "activity-search").padding(.top, 14)
    if !recent.isEmpty {
        GoopSectionLabel(title: "RECENT").padding(.horizontal, 2).padding(.top, 18).padding(.bottom, 6)
        ForEach(recent, id: \.id) { … GoopChoiceRow(…, note: "Last: …") … }
    }
    GoopSectionLabel(title: "ALL ACTIVITIES").padding(.horizontal, 2).padding(.top, recent.isEmpty ? 18 : 16).padding(.bottom, 6)
    ForEach(…) { … GoopChoiceRow(…) … }
}
.accessibilityElement(children: .contain).accessibilityIdentifier("activity-picker")
.onAppear { … unchanged … }
```

- The content is wrapped in a `VStack(spacing: 0)`, as today.
- The search filter (`query.isEmpty || name contains query`) stays in `ActivityPicker`.
- The row identifiers stay `activity-sport-<id>`.
- Visible results: the × moves to the right and becomes 13 pt light `iconMuted` instead of 15 pt semibold white; the title moves up 5 pt (V18); and RECENT and ALL ACTIVITIES go from N 11.5 to `labelCard` 12.5 (V19). The picker keeps its gradient, its radius of 26 and its commit button. The commit radius becomes 12 in step D5 (V7).

### 4.5 `GoopRow` and `GoopTimeRow`

Promote the More screen's private `line()` (`GoopMoreScreen.swift:82-88`) to a new file, `ios/GHealth/Components/Goop/GoopRow.swift`.

```swift
enum GoopRowDisclosure { case none, push, menu }

struct GoopRow<Trailing: View>: View {
    var label: String
    var disclosure: GoopRowDisclosure = .none
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder var trailing: () -> Trailing
    init(_ label: String, disclosure: GoopRowDisclosure = .none, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder trailing: @escaping () -> Trailing)
}

struct GoopRowValue: View { var text: String }   // Text(text).goop(.bodySmall).foregroundStyle(Goop.Color.textSoft)

extension GoopRow where Trailing == GoopRowValue {
    init(_ label: String, value: String, disclosure: GoopRowDisclosure = .none)
}

struct GoopTimeRow: View {
    var label: String
    @Binding var time: Date
    var range: ClosedRange<Date>
    var identifier: String
    init(_ label: String, time: Binding<Date>, range: ClosedRange<Date>, identifier: String)
}
```

**`GoopRow` body:**

```swift
HStack(alignment: alignment, spacing: 16) {
    Text(label).goop(.labelCard).layoutPriority(1)
    Spacer(minLength: 0)
    HStack(alignment: alignment, spacing: 8) {
        trailing().multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        switch disclosure {
        case .none: EmptyView()
        case .push: GoopSymbol(name: "chevron.right", size: 12, color: Goop.Color.textSoft)
        case .menu: GoopSymbol(name: "chevron.down", size: 12, color: Goop.Color.textSoft)
        }
    }
}
.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 48)
.background(Goop.Color.controlFill, in: RoundedRectangle(cornerRadius: Goop.Metric.radiusPicker))
```

With `.none`, it draws exactly what `line()` draws today.

**How rows are used:**

- A row whose tap pushes or opens a choice is wrapped by the caller in a `Button` and uses `.push`.
- A row whose tap opens a short fixed list is the label of a `Menu` and uses `.menu`.
- A row never contains a second button.

**`GoopTimeRow` body:**

```swift
GoopRow(label, alignment: .center) {
    DatePicker(label, selection: $time, in: range, displayedComponents: .hourAndMinute)
        .datePickerStyle(.compact).labelsHidden().tint(Goop.Color.strain)
        .environment(\.timeZone, GoopFormat.london).accessibilityIdentifier(identifier)
}
```

The row may grow taller than 48 when the system's compact picker needs it. No screen uses `GoopTimeRow` in this cleanup; it exists for the edit feature and the gallery.

**More screen:**

- `row(label, value)` becomes `GoopRow(label, value: value)`.
- `line("TEST CONNECTION") { … }` becomes `GoopRow("TEST CONNECTION") { … }`.
- The FIXTURE MODE `Menu` label becomes `GoopRow("FIXTURE MODE") { Text(…).goop(.bodySmall).foregroundStyle(Goop.Color.textSoft) }` with no disclosure. It is a Debug row, and adding a chevron would change it.
- The `line` and `row` helpers are deleted.
- `section()` uses `GoopSectionLabel(title: title).padding(.top, 26).padding(.bottom, 10)` in place of its `Text`.
- `warning()` uses `Goop.Metric.radiusPicker`.
- `.textSelection(.enabled)` stays on the ADDRESS row.

The More screen stays pixel-identical in this step; UNPAIR's colour changes in D7, not here.

### 4.6 Header trailing slot

```swift
struct GoopHeaderButton {
    var symbol: String
    var size: CGFloat
    var label: String
    var identifier: String
    var action: () -> Void
    static func info(_ action: @escaping () -> Void) -> Self { .init(symbol: "info.circle", size: 25, label: "How this works", identifier: "info-button", action: action) }
    static func edit(_ action: @escaping () -> Void) -> Self { .init(symbol: "pencil", size: 21, label: "Edit activity", identifier: "edit-button", action: action) }
}
```

- The button is drawn as `Button(action: action) { GoopSymbol(name: symbol, size: size).frame(width: 44, height: 44) }.accessibilityIdentifier(identifier).accessibilityLabel(label)`, which is light `iconMuted`, exactly as the info button is today.
- `GoopDetailHeader(title:back:info:)` becomes `GoopDetailHeader(title: String, back: (() -> Void)? = nil, trailing: GoopHeaderButton? = nil)`. The right slot draws `trailing` when it is set. `GoopDetailPage` passes `trailing: info.map { .info($0) }`. The other call sites (`GoopTrendScreen.swift:23`, `WorkoutScreen.swift:41`, `GoopMoreScreen.swift:12`, `GoopHealthScreen.swift:10`) pass no trailing button.
- **New `GoopWorkoutHeader`**, extracted from `WorkoutScreen.header(_:)` (`:71-81`):

  ```swift
  struct GoopWorkoutHeader: View {
      var symbol: String
      var title: String
      var subtitle: String
      var back: () -> Void
      var trailing: GoopHeaderButton? = nil
  }
  ```

  Its body is today's `HStack(spacing: 16)` with `GoopSymbol` for the symbol, `labelWorkoutTitle` for the title, `bodySmall` `textSoft` for the subtitle and `Spacer(minLength: 0)`. After the spacer, it draws the trailing button when one is set. `WorkoutScreen` passes today's symbol, title and subtitle and no trailing button, so the screen is unchanged.
- The edit feature will pass `.edit { … }` to either header. No screen shows a pencil in this cleanup.

### 4.7 Global tint

`GHealthApp.swift:15`: `.tint(Goop.Color.recoveryHigh)` becomes `.tint(Goop.Color.strain)` (V9).

## 5. Drift list resolution

Each item gives the site, the replacement and the visible change. "None" means pixel-identical.

1. **Hard-coded hex outside tokens.** Every site in §2.1 switches to its token.
   - Also: `GoopTokens.swift:317-318`, `:321` and `:342-343` switch to named tokens (§2.2).
   - Two Debug lines that DESIGN.md does not list are handled too:
     - `LiveActivityPreview.swift:25` switches to `liveActivityFill`.
     - `LiveActivityPreview.swift:41` keeps its simulated Lock Screen wallpaper behind an allow marker.

   Visible change: none.
2. **Duplicated gradient.** `LiveActivityScreen.swift:65` uses `Goop.Gradient.card`. Visible change: none.
3. **Ad-hoc text styles.** §3.2. Visible change: none in the tours. V1 and V2 apply at sizes above xxxLarge, and the banner and picker-label changes belong to items 9 and 10.
4. **Raw `Font(GoopFont…)`.** §3.2.
   - Sites that DESIGN.md does not list are handled the same way: `ActivityWidget.swift:22`, `:25`, `LiveActivityScreen.swift:88`, `LiveActivityPreview.swift:34`, `:36`, and the allow-marked exceptions in §3.2.
   - Visible change: V3 only, below Large.
5. **Button radii.** Every button uses `Goop.Metric.radiusButton` (12):
   - START ACTIVITY and END ‹SPORT› (`GoopActivities.swift:110`, `:111`): 10 → 12 (V4);
   - pause (`LiveActivityScreen.swift:23`): 14 → 12 (V5);
   - HOLD TO END (`:102`, `:105`, `:106`): 14 → 12 (V6);
   - the picker commit (`ActivityPicker.swift:39`): 14 → 12 (V7);
   - `GoopButton` and DELETE ACTIVITY: already 12.
6. **`Goop.Metric` unused.** Every `cornerRadius:` literal in the app, the shared code and the widgets reads a `Goop.Metric` token. The full map is below. The only literal left is the Debug widget-preview corner (`WidgetPreviewHost.swift:34`, 22, a simulated system widget), which has an allow marker. Visible change: only V4–V8.

   | Sites | Token |
   | --- | --- |
   | `GoopActivities.swift:67`, `:68`; `GoopLiveRow.swift:13` | `radiusActivityBlock` |
   | `GoopActivities.swift:75`; `GoopCards.swift:188`, `:236` | `radiusHairline` |
   | `GoopActivities.swift:76`, `:114`; `GoopLiveRow.swift:25`, `:26` | `radiusActivities` |
   | `GoopActivities.swift:110`, `:111`; `GoopControls.swift:111`, `:112`; `LiveActivityScreen.swift:23`, `:102`, `:105`, `:106`; `ActivityPicker.swift:39` | `radiusButton` |
   | `GoopCards.swift:85`; `GoopHealth.swift:54` | `radiusBadge` |
   | `GoopCards.swift:98`; `GoopHealth.swift:62` | `radiusMonitor` |
   | `GoopCards.swift:158`; `GoopHealth.swift:39`; `GoopHealthScreen.swift:64` | `radiusTile` |
   | `GoopCards.swift:243`; `GoopSleepComponents.swift:156` | `radiusLegend` |
   | `GoopCards.swift:256`, `:257` | `radiusInsight` |
   | `GoopCards.swift:265`; `LiveActivityScreen.swift:65` | `radiusCard` |
   | `GoopCharts.swift:54`; `GoopTrendComponents.swift:127` | `radiusHighlight` |
   | `GoopCharts.swift:111`; `RecoveryScreen.swift:52`, `:53` | `radiusSegment` |
   | `GoopCharts.swift:114`; `GoopSleepComponents.swift:164` (×2); `GoopLiveActivityView.swift:10`; `GoopTokens.swift:353` | `radiusMark` |
   | `GoopControls.swift:127` | `radiusBanner` |
   | `GoopHealth.swift:38`; `GoopTrendComponents.swift:64` | `radiusChip` |
   | `GoopSleepComponents.swift:20`, `:31`, `:132`, `:148` | `radiusBar` |
   | `GoopSleepComponents.swift:191` | `radiusZoneRow` |
   | `GoopTrendComponents.swift:20`; `ActivityPicker.swift:27`; `GoopMoreScreen.swift:87`, `:89`; `Pairing.swift:17` | `radiusPicker` |
   | `GoopTrendComponents.swift:31` | `radiusRangeSegment` |
   | `GoopTrendComponents.swift:34` | `radiusRange` |
   | `ActivityPicker.swift:59`, `:60` | `radiusChoice` |
   | `ActivityPicker.swift:42` `presentationCornerRadius(26)` | `radiusSheet` |
   | `ActivityWidget.swift:10`; `LiveActivityPreview.swift:25`, `:26`, `:39` | `radiusLiveActivity` |
   | `HeartRateBanner.swift:21`, `:22`; `WorkoutScreen.swift:20` | replaced by `GoopBanner` (`radiusBannerTinted`) |
   | `WorkoutScreen.swift:37` | replaced by `GoopButton` |

7. **Destructive actions disagree.** §4.1 and §4.2. Visible change: V10–V14, and V15 if the probe passes.
8. **Two sheet anatomies.** `ActivityPicker` is rebuilt on `GoopTaskSheet` (§4.4): close on the right, header 50, tokenised gradient. Info sheets (`GoopSheet`) are unchanged. Visible change: V18.
9. **Three banner implementations.** One `GoopBanner` with tones (§4.3). Visible change: V16, V17.
10. **Three section-label treatments.** Two roles remain, each with one treatment:
    - A label above a group of rows or controls is `GoopSectionLabel` (`labelCard`, `iconMuted`). Used by More and the picker.
    - A heading above prose in an info sheet is `GoopSheetSection`'s title (`labelCard`, white), which is unchanged. It belongs to the approved info sheets.

    The 11.5 ad-hoc treatment is gone. Visible change: V19. Owner override: §13.
11. **Input radius.** The Pairing link field uses `radiusPicker` (10). Visible change: V8.
12. **Global tint is recovery green.** §4.7. Visible change: V9.
13. **The 55 % stale opacity is a literal.**
    - There are **32** stale sites, not 34. DESIGN.md's count included two lines that are not staleness: `GoopCharts.swift:105` (a sleep connector's alpha) and `ComponentGallery.swift:130` (a bar fraction). Those two stay as they are.
    - Every `cond ? 0.55 : 1` becomes `cond ? Goop.Opacity.stale : 1`, including `AppModel.swift:296`, `LockScoresView.swift:22`, `:31`, `:39` and `HomeScoresView.swift:31`, `:77`.

    Visible change: none.
14. **`Image(systemName:)` in app code.** `HeartRateBanner.swift:10` goes away (§4.3).
    - `LiveActivityPreview.swift:33` and `:38` (Debug) mirror widget-target code that cannot use `GoopSymbol`, and they keep an allow marker.
    - The uses in `Shared/` and `GHealthWidgets/` stay, because `GoopSymbol` lives in the app target.

    Visible change: none.

## 6. Intended visible changes

These are the only allowed differences in the before and after screenshot tours. The plan step that makes each change is in brackets. "Captures" names the tour screenshots expected to show it.

| ID | Change | Captures |
| --- | --- | --- |
| V1 | [D3] At sizes above xxxLarge, these labels cap at 1.5× instead of 1.6×: WAITING FOR MAC, live row `LIVE ·`, live stat labels, the live ring label, the live HR chip, HOLD TO END, the picker's sport names and START ‹SPORT›, and the Live Activity's PAUSED, zone and stat labels. | none in the tours (none of these appears in the AX5 tour) |
| V2 | [D3] At sizes above xxxLarge, info-sheet row values (`GoopSheetRow`) cap at 1.35× instead of 1.6×. | none |
| V3 | [D3] Text that used a raw font now shrinks at sizes smaller than Large. It is unchanged at Large and above. | none |
| V4 | [D5] START ACTIVITY and END ‹SPORT› corners 10 → 12 (fill, and the END stroke). | every capture that shows the activities card's bottom button: expected `activity-a`, `activity-e-2`, Home captures that reach the activities card (`fresh-home-2`, `fresh-home-ax5-2`, state `-home` captures where visible) |
| V5 | [D5] Pause square corners 14 → 12. | `activity-c`, `activity-no_hr`, `activity-paused` |
| V6 | [D5] HOLD TO END corners 14 → 12 (fill, progress clip and highlight stroke). | `activity-c`, `activity-no_hr`, `activity-paused` |
| V7 | [D5] START ‹SPORT› commit corners 14 → 12. | `activity-b` |
| V8 | [D5] Pairing link field corners 12 → 10. | `unpaired-pairing` |
| V9 | [D6] System controls use `strain` instead of `recoveryHigh`: text cursor and selection handles, alert buttons that take the tint, untinted spinners (TEST CONNECTION while busy), menu accents. | none in the tours. The D7 alert captures show the tint as it is from then on. |
| V10 | [D7] DELETE ACTIVITY: 50 tall (was 48), 1.5 pt stroke (was 1), `labelCard` (was `labelAction`). Colour unchanged. | `activity-ended_pending`, `activity-f`, `activity-flow-pending` where the button is on screen |
| V11 | [D7] UNPAIR: `zone5` stroke and label (was `outlineBorder` and white), moved from the MAC section to the end of More. | `fresh-more` |
| V12 | [D7] Unpair confirmation: a centred alert with title, message, Unpair and Cancel, in place of an action sheet. | new `alert-unpair` |
| V13 | [D7] Replace pairing confirmation: a centred alert with title, message, Replace pairing and Cancel. | new `alert-replace` |
| V14 | [D7] New captures of the three alerts. | new `alert-delete`, `alert-unpair`, `alert-replace` |
| V15 | [D8, only if the probe passes] The destructive verb in all three alerts is `zone5`. | `alert-delete`, `alert-unpair`, `alert-replace` |
| V16 | [D9] Workout pending banner: fill 12 % (was 8.6 %), stroke 25 % (was 27 %), symbol semibold (was light), text `bodySmall` `textSoft` (was 13 pt `#D6E6F2`, line 17.55). | `activity-flow-pending`, `activity-ended_pending`, `activity-f` |
| V17 | [D9] Heart-rate banner: the message's line height is 18.1 (was 16.25), so a message on two or more lines gains about 1 pt per line gap. Single-line messages are unchanged. | `activity-b` only if its message wraps |
| V18 | [D10] Picker header: × on the right, 13 pt light `iconMuted` (was left, 15 pt semibold white); title 5 pt higher; header block still 50 tall. | `activity-b` |
| V19 | [D10] Picker section labels RECENT and ALL ACTIVITIES: `labelCard` 12.5 (was N 11.5), same colour. The rows below move down by the difference in line height. | `activity-b` |
| V20 | [D10] Picker section labels gain the header trait. VoiceOver only. | none |
| V21 | [D7, D9, D10, D11] New gallery sections appended after "Full-screen and loading states". Every earlier gallery capture is unchanged; the capture that shows the old last section and every capture after it may change, and new `gallery-NN` files may appear. | `gallery-NN` from the first capture that shows a new heading |

## 7. Screens that must stay pixel-identical

Every tour capture not named in §6 must be identical to the previous step's capture, apart from the noise regions recorded in plan step D1. That covers:

- Home, Recovery, Strain, Sleep, Workout (fresh), Trend, the Trends tab, Health and More except UNPAIR;
- the info sheets and the activities sheet;
- every state capture;
- every widget capture;
- the Live Activity and Dynamic Island previews (`activity-d`, `activity-island`);
- `activity-too-short`;
- the AX5 tour.

## 8. Component gallery additions

Append these sections to `ComponentGallery.states`, after "Full-screen and loading states" and before `gallery-end`, in this order and in the step that builds each component.

- Each section shows its variants at the default size, then a `GoopSectionLabel(title: "ACCESSIBILITY 5")`, then the same variants inside a `VStack(alignment: .leading, spacing: 16) { … }.dynamicTypeSize(.accessibility5)`.
- Sample copy is fixed and generic; samples carry no health values beyond the fixture's.
- A sample action is an empty closure. A sample binding is a gallery `@State`.

| Section heading | Step | Variants (default and AX5) |
| --- | --- | --- |
| `GoopButton roles` | D7 | `VIEW TRENDS` outline; `PAIR` primary; `PAIR` primary busy; `DELETE ACTIVITY` destructive |
| `GoopBanner tones` | D9 | neutral `Too short to save.`; neutral with dismiss; neutral `Boxing deleted.` with symbol `trash`, `symbolColor: iconMuted` and action `UNDO` (identifier `gallery-banner-undo`); strain `Saved on your phone. It will be sent to your Mac when it can be reached.` with symbol `arrow.triangle.2.circlepath`; positive with title `FITBIT AIR CONNECTED`; caution with title `NO LIVE HEART RATE`; muted with title `CHOOSE YOUR BAND` and an accessory of two `bodyMid` buttons `Band 1` and `Band 2` |
| `GoopTaskSheet` | D10 | a `GoopTaskSheet(title: "SAMPLE TASK", closeIdentifier: "gallery-task-close", commit: GoopCommit(title: "SAVE SAMPLE", symbol: "checkmark", identifier: "gallery-task-commit") {})` holding `GoopSectionLabel(title: "RECENT")` and two `GoopChoiceRow`s (one selected, with note `Last: Sat`); the same sheet as a sub-step titled `SPORT` with `back:` set and commit `USE SAMPLE`, symbol `figure.boxing`; and a third with `enabled: false`. Each is framed `.frame(height: 420).background(Goop.Gradient.sheet).clipShape(RoundedRectangle(cornerRadius: Goop.Metric.radiusSheet))`. Below them: `GoopSearchField` (empty, prompt `Search activities`, identifier `gallery-search`) |
| `GoopRow` | D11 | `GoopRow("PAIRED MAC", value: "Fixture Mac")`; `GoopRow("SPORT", value: "Boxing", disclosure: .push)`; `GoopRow("EFFORT", value: "18:04 to 19:04", disclosure: .menu)`; a row whose value has two lines; `GoopTimeRow("START", time: $galleryTime, range: <fixture day 00:00…23:59>, identifier: "gallery-time-start")`, where `galleryTime` starts at the fixture's `generatedAt` |
| `Headers` | D11 | `GoopDetailHeader(title: "TODAY", back: {}, trailing: .info {})`; `GoopDetailHeader(title: "TODAY", back: {}, trailing: .edit {})`; `GoopWorkoutHeader(symbol: "figure.boxing", title: "BOXING", subtitle: "17:56 to 19:12", back: {})`; the same with `trailing: .edit {}` |

The edit button's identifier in the gallery is `edit-button`, as defined. That is safe because the gallery is a separate launch.

## 9. Lint guard (`goop-lint`)

`scripts/goop_lint.py` is plain Python 3 (stdlib only, run with `python3 -I`). It scans every `*.swift` file under `ios/GHealth`, `ios/Shared` and `ios/GHealthWidgets`, except `ios/GHealth/Debug/Reference/`. It counts every match of each rule below, one finding per match.

| Rule | Pattern | Exempt |
| --- | --- | --- |
| `hex` | `goopHex:` | In `ios/Shared/Goop/GoopTokens.swift`, two kinds of line: a line matching `^\s*static let \w+ = SwiftUI\.Color\(goopHex: 0x[0-9A-F]{6}\)(\.opacity\([0-9.]+\))?$`, and the `init(goopHex:` line |
| `textstyle` | `GoopTextStyle\(` | `GoopFont.swift`, `GoopTokens.swift` |
| `rawfont` | `GoopFont\.(sofia|nunito)\(` | `GoopFont.swift` |
| `radius` | `cornerRadius: [0-9]` or `CornerRadius\([0-9]` | none |
| `stale` | `\?\s*0\.55\s*:` | none |
| `symbol` | `Image\(systemName:` | files outside `ios/GHealth/`; `ios/GHealth/Components/Goop/GoopControls.swift` (the `GoopSymbol` definition) |
| `dialog` | `\.confirmationDialog\(` | none |

**Allow marker.** A line that ends with `// goop-lint: allow <rule>: <reason>` is exempt from that one rule. A marker on a line with no finding for its rule is an error ("unused allow marker"), so markers cannot outlive their reason. The complete list of allowed lines after the cleanup, and the only ones:

| File and line (at `8b06816`) | Rule | Reason text |
| --- | --- | --- |
| `GoopCharts.swift:6` | `rawfont` | `Canvas chart text has fixed chart sizes` |
| `ScoreRing.swift:66`, `:67` | `rawfont` | `ring numerals are sized by the ring variant` |
| `GoopLogo.swift:15` | `rawfont` | `wordmark is drawn at its own size` |
| `LiveActivityPreview.swift:21`, `:22` | `rawfont` | `simulated Lock Screen clock` |
| `WidgetPreviewHost.swift:21` | `rawfont` | `simulated Lock Screen clock` |
| `LiveActivityPreview.swift:41` | `hex` | `simulated Lock Screen wallpaper` |
| `LiveActivityPreview.swift:33`, `:38` | `symbol` | `mirrors widget-target Dynamic Island code` |
| `WidgetPreviewHost.swift:34` | `radius` | `simulated system widget corner` |

**Ratchet.** `scripts/goop_lint_baseline.json` maps `"<rule> <repo-relative path>"` to a finding count. For every key:

- more findings than the baseline: fail with `new drift`;
- fewer: fail with `stale baseline: set "<key>" to <n>` (or `remove "<key>"` at 0);
- a key with no findings, a key with a count of 0, or an unknown rule: fail.

The script prints each finding as `path:line: rule: <line, trimmed to 120 characters>`. It ends with `goop-lint ok: <n> findings, all in baseline` and exit 0, or the failures and exit 1. It has no flag that writes the baseline.

The plan lists the baseline after each step. It only ever loses keys or lowers counts, and after D10 it is `{}`.

**Make.** Add a target `goop-lint: python3 -I scripts/goop_lint.py` and append it to the `check` prerequisites. Add `python3 -I scripts/goop_lint_test.py` to `adapter-check`.

**Tests** (`scripts/goop_lint_test.py`, `unittest`, temporary directories, no repo files). Each of these is one test:

- a clean tree passes;
- each rule fires once on a one-line sample;
- a tokens-file definition line passes and a tokens-file gradient literal fails;
- an allow marker exempts only its own rule;
- an unused marker fails;
- over-baseline fails;
- under-baseline fails with the new count;
- `Debug/Reference` is ignored;
- a file outside `ios/GHealth/` may use `Image(systemName:`.

## 10. Screenshot diff tool

`ios/scripts/goop_diff.swift` uses CoreGraphics and ImageIO only, like `goop_compare.swift`. Usage: `swift ios/scripts/goop_diff.swift [--exclude-file <path>] <before-dir> <after-dir> <out-dir>`. `--exclude-file` names a file with one capture basename per line (the plan's `unstable.txt`). Those names are skipped and reported as `EXCLUDED <name>` lines.

1. It reads every `*.png` in either directory. It skips raw xcresult exports, which are the basenames matching `^(?:.*_\d+_)?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.png$`. That covers both the `_<number>_<UUID>.png` form and the bare `<UUID>.png` form this Xcode emits (correction 2026-11-12, after the D1 stop: 99 bare-UUID duplicates in D0a). Only named captures are compared.
2. For each name in the sorted union, it prints one line:
   - `MISSING-BEFORE <name>` or `MISSING-AFTER <name>`;
   - `SIZE <name> <w>x<h> <w>x<h>` when the sizes differ;
   - `SAME <name>`;
   - `DIFF <name> pixels=<n> box=<x>,<y>,<w>,<h>`. The box is the bounding box of the differing pixels in points (pixels ÷ 3, rounded outward).
3. Two pixels differ when any RGBA channel differs at all. Rows above y = 162 px (the 54 pt status bar) are ignored.
4. For each `DIFF`, it writes `<out-dir>/<name minus .png>-diff.png`:
   - three panels: before, after, and after with every differing pixel painted `#FF00FF`;
   - each panel scaled to 402 px wide, with 20 px gaps on `#0F1113`.
5. It writes the printed lines to `<out-dir>/report.txt` as well. It always exits 0; judging the result is the plan's job.

## 11. Fit check against the edit mockups

The PNGs in `docs/goop/mockups/screens/edit-*.png` (from the parallel edit spec) can be drawn with the APIs above:

| Mockup element | API |
| --- | --- |
| `edit-detail`, `edit-effort`: pencil at the top right of the workout header | `GoopWorkoutHeader(…, trailing: .edit { … })` |
| `edit-edit`: EDIT ACTIVITY sheet, × right, SAVE BOXING pinned | `GoopTaskSheet(title:, commit: GoopCommit(title: "SAVE BOXING", symbol: "checkmark", …))` |
| `edit-edit`: SPORT › and MERGE WITH NEXT › | `Button { … } label: { GoopRow("SPORT", value: "Boxing", disclosure: .push) }` |
| `edit-edit`, `edit-add`: START and END with a time | `GoopTimeRow` |
| `edit-add`: EFFORT ⌄ | `Menu { … } label: { GoopRow("EFFORT", value: …, disclosure: .menu) }` |
| `edit-edit`: NOTES label | `GoopSectionLabel` |
| `edit-edit`: RESTORE BAND'S VERSION, DELETE ACTIVITY | `GoopButton` `.outline`, `.destructive` |
| `edit-sport`, `edit-merge`: SPORT and MERGE sub-steps with ‹ and × | `GoopTaskSheet(title:, back:, commit:)` |
| `edit-sport`: search, RECENT, rows with `Last: Sat` / `Band's label` | `GoopSearchField`, `GoopSectionLabel`, `GoopChoiceRow(note:)` |
| `edit-merge`: THIS ACTIVITY / NEXT ACTIVITY with text values | `GoopRow(_, value:)` |
| `edit-undo`: `Boxing deleted.` with UNDO | `GoopBanner(text:, symbol: "trash", symbolColor: Goop.Color.iconMuted, action: GoopBannerAction(title: "UNDO", …))` |
| `edit-delete`: centred alert with Cancel and an orange Delete | `goopDestructiveAlert` (the orange verb depends on the D8 probe) |

These mockup elements are not covered, and the edit spec owns them:

- the stat rows, the selectable chart and the band's-version key;
- the multi-line notes field (DESIGN.md lists free-text notes as outside the system);
- the LIVE / PAST and MON–THU segmented controls in `edit-add`. `GoopRangeSelector` is typed to `TrendWindow.Range`, so it would need a generic version.

## 12. Out of scope

- Editing, adding or merging activities, and any API, store or GHealthCore change.
- `GoopSheet` (info sheets), which already matches DESIGN.md.
- Making fixed numerals scale with Dynamic Type.
- Recolouring a system alert by any means other than the single D8 attempt.
- `.font(.system(…))` uses in `Shared/` and `GHealthWidgets/` (symbol sizes and the inline Lock Screen widget's system font).

## 13. Decisions made in this spec (not specified by the owner)

1. **Banner text sizes.** Tinted banners use `bodySmall` (12.5), not DESIGN.md's `bodyMid` (13.5). This keeps the approved Start Activity sheet as it is. The banner title is `labelStatus`, the same status-label style as the monitor card.
2. **The destructive button** uses `labelCard` and the outline button's metrics (50 tall, 1.5 pt stroke) in `zone5`, so all three `GoopButton` roles share one shape. DESIGN.md's frontmatter is updated to match.
3. **Two section-label roles** (item 10): grey `GoopSectionLabel` above controls; white `GoopSheetSection` headings above prose in info sheets. **Owner may overrule:** (a) keep the two roles (this spec); (b) make every section label grey, which changes the Recovery, Strain and Sleep info sheets; (c) make every section label white, which changes More and the picker.
4. **UNPAIR moves to the end of More** (owner decision 2026-11-12, option b): after ABOUT and before the Debug DEVELOPER section, as a full-width destructive button with nothing after it.
5. **The orange alert verb.** **Owner decision (2026-11-12): (a).** If the D8 probe fails, keep iOS's own destructive colour inside the alert. The options were:
   - (a) accept iOS's own destructive colour inside the system alert, keeping the orange `zone5` outline on the button that opens it;
   - (b) drop `role: .destructive` and tint the alert `zone5`, which makes the verb orange but loses the destructive role, and may tint Cancel too;
   - (c) draw a ghoops alert, which breaks DESIGN.md's "never draw iOS controls".
6. **Fixed numerals** (rule 4). Live and widget numerals keep fixed sizes. The owner could later ask for in-app ones (activity value block, monitor badge, vital chip) to scale at 1.35×, which needs layout work at accessibility sizes.
7. **Type cases are named by role** when they are new, and existing cases are reused when every value matches, even if the existing name comes from another role: `.tab` for the medium widget's fetch line, `.valueChart` for monitor badges, `.labelDial` for the trend typical-range key, `.scoreWidgetMedium` for Live Activity stats. A synonym case would only duplicate values.
8. **New copy:** the Unpair and Replace pairing alert messages in §4.2.
