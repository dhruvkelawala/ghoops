# ghoops: implementation spec

Status: approved design, ready to build. Written 2026-11-12 for the iOS builder, who implements it as written. The build order and acceptance checks are in [plan.md](plan.md).

This spec defines the ghoops iPhone app and its widgets, together with additive fields in the Go API. The approved mockup is [mockups/goop.html](mockups/goop.html) (open in a browser; `?screen=<name>` shows one screen). Its renders are [mockups/goop3-a.jpg](mockups/goop3-a.jpg) (Home, Recovery, Strain, Sleep), [mockups/goop3-b.jpg](mockups/goop3-b.jpg) (Workout, Trend view, Health tab, Widgets), [mockups/sleepE.jpg](mockups/sleepE.jpg) (left phone: the E1 sleep chart), and one PNG per screen in [mockups/screens/](mockups/screens/) at 3× (390 pt wide). Every value in the mockup is a placeholder; real values come from the bindings below.

## 0. How to read this spec

### 0.1 Precedence

[rename-ghoops.md](rename-ghoops.md) supersedes the original branding and wordmark instructions. Original mockup files and historical evidence retain their old names.

1. This spec wins over `docs/v2/app.md` for everything visual, for navigation, for copy, and for widget appearance. The app.md sections it replaces are listed in §0.3.
2. `docs/v2/contract.md`, `scores.md` and `data.md` still define the data. §13 of this spec adds fields to the contract. The builder copies §13 into those files in plan step B1, so after that step the contract files are again the single source for data.
3. Where this spec and the mockup disagree, this spec wins. Every deliberate deviation from the mockup is marked **Deviation** and listed in §17.
4. Where this spec is silent about a pixel, match the mockup HTML at 390 pt (read the CSS in `goop.html`; class names are quoted below as `.name`).

### 0.2 What does not change

- Bundle IDs, App Group, Keychain group, URL scheme `ghealth`, background task ID, widget kinds `ScoresWidget` and `LockScoresWidget`, deployment target, signing and orientation (app.md §2.1). Only the display name changes (§1).
- The cache, network client, refresh strategy, fixture mode and the honest-data rules: app.md §5, §6, §7 (reason texts), §8 (three separate ages), §11 (fixture sets). §10 of this spec restyles their states; it does not change when they occur.
- The app never computes a score. It may compute presentation aggregates that this spec defines exactly (window means for the trend view, sums of zone minutes, differences between two shown numbers). Each one is named where it is used.
- Missing stays missing: a null value renders `—` and never `0`. A null day is a gap in every chart.

### 0.3 app.md sections superseded

| app.md | Replaced by |
| --- | --- |
| §1 paragraph 2 (no WHOOP-like look) | The owner approved a WHOOP-inspired look on 2026-11-12. The rule still holds for brand assets: no WHOOP name, logo or font files. |
| §2.1 row "display name" | §1 |
| §3 Navigation | §6 |
| §4 Screens | §8 |
| §8 "Shown as" column | §10.2 (ages and rules unchanged) |
| §9 Visual design | §2 to §5 |
| §10 entry-view rules 4 to 5 (appearance) | §11 (data, timeline and staleness rules unchanged) |
| §11 screenshot list | plan.md (step S1 onward) |

Plan step S0 adds a note at the top of app.md pointing here.

### 0.4 Units in this spec

All sizes are SwiftUI points on a 390 pt wide layout, the mockup's width. The test device is iPhone 17 Pro (402 pt wide). Horizontal sizes marked "fixed" stay fixed; everything else stretches with the screen (side margins stay as specified, inner widths grow). Vertical sizes are fixed unless marked "min", in which case they are minimum heights that grow with Dynamic Type (§12.2).

`em` tracking converts to points as `em × font size` (0.10 em at 12.5 pt is 1.25 pt of `tracking`).

## 1. Identity

| Item | Value |
| --- | --- |
| App display name | `ghoops` (`CFBundleDisplayName` in `ios/GHealth/Info.plist`) |
| Widget extension display name | `ghoops` (`ios/GHealthWidgets/Info.plist`) |
| Product name in copy | `ghoops`. The Mac CLI is `ghoops`; its signed target and hidden identifiers stay unchanged under [rename-ghoops.md](rename-ghoops.md). |
| Bundle IDs, App Group, URL scheme, widget kinds, BG task ID | unchanged (§0.2) |
| App icon | `docs/goop/assets/logo/goop-app-icon-ios-1024.png` (1024×1024, no alpha) copied to `ios/GHealth/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`; `Contents.json` keeps its single-size entry. Delete `ios/scripts/make_icon.swift`. |
| Wordmark | §2.2 |

## 2. Assets

### 2.1 Fonts

Both fonts are SIL OFL 1.1; the licences ship next to the files.

| Family | Source in this repo | Copy to | PostScript name of the default instance | Axes (tag, decimal tag for Core Text, min/default/max) |
| --- | --- | --- | --- | --- |
| Sofia Sans Condensed | `docs/goop/assets/fonts/SofiaSansCondensed-Variable.ttf` | `ios/Shared/Fonts/SofiaSansCondensed-Variable.ttf` | `SofiaSansCondensed-Regular` | `wght` 2003265652: 1 / 400 / 1000 |
| Nunito Sans | `docs/goop/assets/fonts/NunitoSans-Variable.ttf` | `ios/Shared/Fonts/NunitoSans-Variable.ttf` | `NunitoSans-12ptExtraLight` | `wght` 2003265652: 200 / 200 / 1000; `wdth` 2003072104: 75 / 100 / 125; `opsz` 1869640570: 6 / 12 / 12; `YTLC` 1498696771: 440 / 500 / 540 |

Also copy `OFL-SofiaSansCondensed.txt` and `OFL-NunitoSans.txt` to `ios/Shared/Fonts/`, add an "Open-source fonts" row to More → About (§8.10) and keep the files out of the app bundle's resources (they are text; exclude `*.txt` in `project.yml`).

Registration: add `UIAppFonts` = `["SofiaSansCondensed-Variable.ttf", "NunitoSans-Variable.ttf"]` to both `ios/GHealth/Info.plist` and `ios/GHealthWidgets/Info.plist`. In `project.yml`, both targets already compile `Shared`; make sure the two `.ttf` files land in each target's Copy Bundle Resources phase (XcodeGen does this for `.ttf` by default; check the generated project).

Font construction (new file `ios/Shared/Goop/GoopFont.swift`):

- Build every font as a Core Text font from a descriptor with the PostScript name above and `kCTFontVariationAttribute` set to the axis values, then wrap it with `Font(ctFont)`. Do not use `Font.custom(_:size:).weight(_:)`: it cannot set weight 750 or 650 exactly.
- Sofia Sans Condensed: `wght` = 750 for every use.
- Nunito Sans: `wght` per style (§3.3), `wdth` 100, `opsz` 12, `YTLC` 500, at every size.
- Numerals: Sofia Sans Condensed's default figures (proportional). Do not apply `monospacedDigit()` anywhere.
- A unit test in `GHealthCore`'s app-side tests is not possible (fonts live in the app bundle), so plan step F1 adds a DEBUG-only check: on launch in fixture mode, `CTFontCopyVariation` of one Sofia font and one Nunito font must report `wght` 750 and 650; the result is shown as `font-check` text in the widget preview host (§11.6) and asserted by the UI test.

### 2.2 Logo

| File in `docs/goop/assets/logo/` | Use |
| --- | --- |
| `goop-wordmark.svg`, `-white.svg`, `-muted.svg` | Historical wordmark geometry for the original GOOP mockups. Not bundled. |
| `goop-mark.svg`, `goop-mark-white.svg` | Reference geometry for the mark (Pairing screen, empty states). |
| `goop-app-icon-ios.svg`, `goop-app-icon-ios-1024.png` | App icon (§1). |

The shared `GoopWordmark(size:color:)` view draws the approved [ghoops wordmark](mockups/ghoops-wordmark.html), also rendered in [the reference PNG](mockups/screens/ghoops-wordmark.png). Text is Nunito Sans weight 750 with tracking −0.01 em. The two o shapes have diameter 0.50 F, the first a ring with stroke 0.17 D and the second a solid disc. Their gap is 0.035 F, side spacing 0.015 F, and optical downward shift 0.03 F.

Font size F is 26 on Home, 24 in detail/activity dials, 14 in widgets and the Live Activity, and 40 on launch/pairing. Existing wordmark layout boxes and surrounding spacing stay fixed. Colours remain Home `#E9ECEE`, detail dials and small widget `#8D9499`, and medium widget `#C4C8CB`. The old wordmark SVGs remain as historical references for the original mockups.

**Mark** (`GoopMark`): a ring (circle centre (108.5, 128) radius 70, stroke 22) with the area inside circle centre (166.5, 128) radius 76 cut out of the ring, plus a filled circle centre (166.5, 128) radius 62. Draw the ring with an even-odd mask or `.subtracting` (iOS 17 shape operations).

### 2.3 Icons

SF Symbols only, rendered with `Image(systemName:)`, `.symbolRenderingMode(.monochrome)`, weight `.light` unless the table says otherwise, sized by `.font(.system(size: S, weight: …))` where S is the point size in the table. "Height" in the mockup (`sf(name, h)`) is the rendered glyph height; the sizes below are point sizes that give those heights within ±1 pt. No emoji, no custom-drawn icons. Data marks (triangles, dots, legend swatches, dashes) are chart marks, specified in §5.

| Role | Symbol | Weight | Point size | Colour | Where |
| --- | --- | --- | --- | --- | --- |
| Home tab | `house` | light | 22 | active `#FFFFFF`, inactive `#75777B` | tab bar |
| Health tab | `heart` | light | 21 | same | tab bar |
| Trends tab | `chart.xyaxis.line` | light | 21 | same | tab bar |
| More tab | `line.3.horizontal` | light | 17 | same | tab bar |
| Back | `chevron.left` | light | 21 | `#FFFFFF` | detail headers |
| Info | `info.circle` | light | 25 (19 inside cards) | `#9AA0A5` | detail headers, Hours vs. Needed card |
| Disclosure | `chevron.right` | light | 11 (dial captions), 12 (cards) | `#8A9096` (dial captions), `#C4C8CB` (cards) | §5 |
| Date back / forward | `chevron.left`, `chevron.right` | semibold | 11 (date control), 13 (trend range) | enabled `#FFFFFF`, disabled `#6C737A` (date control) or `#4A5056` (trend range) | §5.3, §5.21 |
| Dropdown | `chevron.down` | semibold | 11 | `#FFFFFF` | metric picker |
| Avatar | `person.crop.circle.fill` | light | 28 | `#6B757D` | Home header (from the approved mockup) |
| Battery | `battery.0percent`, `battery.25percent`, `battery.50percent`, `battery.75percent`, `battery.100percent` (by level, §5.2) | light | 15 | `#CFD3D6` | Home header |
| Expand | `arrow.down.left.and.arrow.up.right` | light | 16 | `#9AA0A5` | Today's Activities header |
| Insight action | `arrow.right` | light | 13 | `#7489F0` | insight card (from the approved mockup) |
| Positive status | `checkmark` | semibold | 12 | `#14E09E` | monitor badge, vital chips |
| Dismiss | `xmark` | light | 13 | `#9AA0A5` | banners, sheets |
| HRV | `waveform.path.ecg` | light | 17 | `#9AA0A5` | rows, tiles, vital tile, picker |
| Resting heart rate | `heart` | light | 16 | `#9AA0A5` | rows, tiles, vital tile |
| Respiratory rate | `lungs` | light | 16 | `#9AA0A5` | rows, vital tile |
| Blood oxygen | `drop` | light | 15 | `#9AA0A5` | vital tile |
| Skin temperature | `thermometer.medium` | light | 15 | `#9AA0A5` | vital tile |
| Sleep metric | `moon` | light | 17 | `#9AA0A5` | rows, tiles |
| Sleep activity | `moon.fill` | light | 22 (rows), 20 (tiles) | `#FFFFFF` | activity rows |
| Sleep consistency | `clock` | light | 17 | `#9AA0A5` | sleep contributor row |
| Sleep efficiency | `chart.bar` | light | 16 | `#9AA0A5` | sleep contributor row |
| HR zones | `heart` | light | 16 | `#9AA0A5` | strain rows |
| Strength time | `dumbbell` | light | 14 | `#9AA0A5` | strain row |
| Steps | `shoe.2` | light | 13 | `#9AA0A5` | strain row, tile |
| Combat workout | `figure.boxing` | light | 22 (row), 30 (workout header) | `#FFFFFF` | |
| Strength workout | `figure.strengthtraining.traditional` | light | same | `#FFFFFF` | |
| Walking workout | `figure.walk` | light | same | `#FFFFFF` | |
| Running and other cardio | `figure.run` | light | same | `#FFFFFF` | |
| Cycling (`BIKING`, `OUTDOOR_BIKE`, `STATIONARY_BIKE`, `SPINNING`) | `figure.outdoor.cycle` | light | same | `#FFFFFF` | |
| Swimming (`SWIMMING`, `SWIMMING_POOL`) | `figure.pool.swim` | light | same | `#FFFFFF` | |
| Yoga (`YOGA`) | `figure.yoga` | light | same | `#FFFFFF` | |
| Category `other` | `clock` | light | same | `#FFFFFF` | |
| Detected effort | `heart` | light | same | `#FFFFFF` | |
| Up / down comparison | `arrowtriangle.up.fill` / `arrowtriangle.down.fill` | regular | 8 | per §4.5 | rows, tiles, chips (renders as the mockup's 9×7 triangle) |
| No change | `circle.fill` | regular | 6 | per §4.5 | rows, tiles |
| Stale / old copy | `clock` | light | 15 | `#FFA722` | banners, widgets |
| Mac or band sync | `arrow.clockwise` | light | 15 | `#FFA722` | banners |
| Health flag (attention) | `heart` | light | 15 | `#FFA722` | banners, Health tab flags |
| Health flag (info) | `info.circle` | light | 15 | `#9AA0A5` | Health tab flags |

Symbol selection for a workout: `category` first (`combat`, `strength`, `walking`, `detected`, `other`); for `cardio`, `exercise_type` decides cycling, swimming, else `figure.run`; for `other`, `YOGA` gives `figure.yoga`, else `clock`.

## 3. Tokens

All tokens live in `ios/Shared/Goop/GoopTokens.swift` as `enum Goop` with nested `Color`, `Gradient`, `Metric` and `TextStyle` namespaces. The old `ios/Shared/Theme.swift` and `ios/Shared/Dial.swift` are deleted when the last screen moves over (plan step W2).

### 3.1 Colours

Hex values are sRGB, opacity 1 unless a percentage is given.

| Token | Value | Use |
| --- | --- | --- |
| `sleep` | `#7BA1BB` | sleep ring, sleep activity block |
| `recoveryHigh` | `#19EC06` | recovery band high |
| `recoveryMedium` | `#FFDF00` | recovery band medium |
| `recoveryLow` | `#FC0028` | recovery band low |
| `strain` | `#0294E7` | strain ring, bars, workout blocks, Activity Strain label |
| `ringTrack` | `#343C42` | every ring's empty track |
| `positive` | `#00F19F` | favourable comparison, Optimal level, trend chip up-good |
| `caution` | `#FFA722` | unfavourable comparison, Poor level, stale and warning glyphs |
| `neutral` | `#848586` | comparison with no good/bad direction, Sufficient legend dash |
| `sufficient` | `#D6D9DB` | active Sufficient segment, Sleep Debt swatch |
| `healthOK` | `#14E09E` | Within Range text and check |
| `dayHR` | `#67AEE6` | Day Heart Rate badge |
| `text1` | `#FFFFFF` | primary text and values |
| `text2` | `#A4A8AB` | comparison numbers, secondary text, times |
| `text3` | `#75777B` | inactive tab, tertiary text |
| `textSoft` | `#C4C8CB` | card chevrons, BPM ranges, secondary labels inside cards |
| `iconMuted` | `#9AA0A5` | metric icons, axis labels, "vs. prior 30 days" |
| `monitorSub` | `#D5D8DA` | monitor card sublines, status sublines |
| `legendText` | `#D8DADC` | legend strip and need-legend text |
| `bodyText` | `#E9ECEE` | trend summary sentence |
| `laneLabel` | `#B4B9BD` | hypnogram lane labels |
| `tickLabel` | `#8E959A` | hypnogram hour ticks |
| `chevronDial` | `#8A9096` | chevron after dial captions |
| `avatar` | `#6B757D` | avatar symbol |
| `battery` | `#CFD3D6` | battery symbol |
| `disabledChevron` | `#6C737A` | date control disabled chevron |
| `disabledChevronDark` | `#4A5056` | trend range disabled chevron |
| `segmentOff` | `#3A3F44` | inactive contributor segment |
| `dialSegmentOff` | `#4A5056` | inactive sleep-dial segment, Baseline Need swatch end |
| `divider` | `#2C3034` | contributor row dividers |
| `cardDivider` | `#353B40` | dividers inside the sleep card |
| `chartGrid` | `#3A4045` | weekly bar chart grid |
| `plotGrid` | `#2C3237` | workout and trend chart grid |
| `hrLine` | `#9BBBD2` | overnight HR line |
| `hrFill` | `#8FB0C8` | overnight HR area, hours-of-sleep bar end |
| `trendLine` | `#7FB0E0` | trend line, points, labels |
| `workoutLine` | `#1AA3F5` | workout HR line |
| `insightAction` | `#7489F0` | insight action text and arrow |
| `stageAwake` | `#C9C6CA` | Awake |
| `stageLight` | `#A6A1F2` | Light |
| `stageDeep` | `#FB94FB` | SWS (Deep) |
| `stageREM` | `#AC58EF` | REM |
| `zone0`…`zone5` | `#FDFBFC`, `#AEC2CF`, `#4699C4`, `#59B797`, `#FBAD5F`, `#FD7138` | heart-rate zones 0 (below) to 5 |
| `hatchLight` / `hatchDark` | `#36383E` / `#202326` | hatched tracks |
| `typicalEdge` | `#E8E8E8` | typical-range dashed edges |
| `typicalFill` | `#FFFFFF` at 11 % | typical-range box fill |
| `trendBand` | `#FFFFFF` at 8 % | trend typical-range band, typical-range key swatch |
| `highlightColumn` | `#FFFFFF` at 7 % (weekly card), 5 % (trend chart) | latest-day column |
| `contributorFillTop` / `Bottom` | `#252B30` / `#1B2024` | notched card |
| `contributorBorder` | `#262B2F` | notched card border |
| `notchBorder` | `#2A2F33` | notch edges |
| `legendFill` | `#090C0D` | legend strip, need legend, banners |
| `insightFillTop` / `Bottom` | `#192024` / `#171C1F` | insight card |
| `insightBorderStart` / `End` | `#4D3D8C` / `#32738C` | insight border, left to right |
| `cardTop` / `cardBottom` | `#2A3035` / `#22272B` | standard detail card |
| `tileTop` / `tileBottom` | `#30353A` / `#2A2E33` | dashboard tiles, vital tiles |
| `monitorTop` / `monitorBottom` | `#303439` / `#2A2E33` | monitor cards, Health status card |
| `activitiesFill` | `#292D30` | Today's Activities parent |
| `activityRow` | `#3D4144` | nested activity row |
| `zoneRowFill` | `#2A2D33` | workout zone rows |
| `controlFill` | `#2A2E33` | metric picker, More rows |
| `rangeTrack` | `#0D1012` | W/M/6M container |
| `rangeSelected` | `#2F363C` | selected segment |
| `rangeText` | `#C9CDD0` | unselected segment text |
| `chipFill` / `chipText` | `#2A3036` / `#CFD3D6` | comparison chips |
| `vitalChipFill` | `#00F19F` at 12 % | in-range chip |
| `outlineBorder` | `#3B4247` | outline buttons |
| `dateOuter` / `dateInner` | `#2F3740` / `#434B53` | date control |
| `tabTop` / `tabBottom` | `#14181D` / `#0B0D11` | tab bar |
| `widgetFill` | `#14181C` | widget container background |
| `sheetFill` | `#14191D` | sheets |
| `naCredit` | `#777777` | nap-credit dashed swatch and overlay |

Badge tints are the badge colour at 15 % opacity (`healthOK`, `dayHR`, `caution`, `neutral`).

### 3.2 Gradients

| Token | Definition |
| --- | --- |
| `homeBackground` | Vertical, measured in points from the top of the screen (top of the status bar): `#293339` at 0, `#1A222B` at 224, `#13171C` at 459, `#0E1313` at 740 and below. |
| `detailBackground` | Same, with `#273238` at 0, `#1D252B` at 200, `#14191D` at 420, `#111619` at 760 and below. |
| Card fills | Every "Top / Bottom" pair in §3.1 is a top-to-bottom linear gradient over the element's own height. |
| `insightBorder` | Left-to-right linear gradient `insightBorderStart` → `insightBorderEnd` over the card width. |
| `hoursBar` | Left-to-right `#2B3238` → `hrFill`. |
| `baselineNeedBar` | Left-to-right `#2B3238` → `dialSegmentOff`. |
| `hrArea` | Top-to-bottom `hrFill` at 28 % → `hrFill` at 0 % over the HR band height. |
| `workoutArea` | Top-to-bottom `strain` at 35 % → 0 % over the plot height. |
| `restorativeSwatch` | A 15×15 square, radius 2, split along the top-left to bottom-right diagonal: `stageDeep` above-left, `stageREM` below-right (CSS `linear-gradient(135deg, deep 50%, rem 50%)`). |
| `widgetWallpaper` | Preview host only: 160° linear `#3D4A57` → `#1E262D` at 60 % → `#2A2230`. |

**Background placement (decision).** Screen backgrounds are fixed to the screen, not to the scroll content: a `homeBackground` or `detailBackground` view behind the `ScrollView`, ignoring all safe areas. Content scrolls over it. Rubber-band overscroll shows the same gradient, so no seam appears.

### 3.3 Type styles

`S` = Sofia Sans Condensed 750. `N<w>` = Nunito Sans at weight `w`. Tracking in em. "Upper" = the string is uppercased in code (`.textCase(.uppercase)` is not enough for VoiceOver; pass uppercase strings and set the accessibility label in normal case, §12.1). Line height is given when it matters; apply it with `lineSpacing` = line height − font line height.

| Style | Font | Size | Tracking | Case | Line height | Dynamic Type (§12.2) |
| --- | --- | --- | --- | --- | --- | --- |
| `scoreHome` | S | 30 (percent sign 18.6) | 0 | — | 1.0 | fixed |
| `scoreDetail` | S | 76 (percent sign 47.1) | 0 | — | 1.0 | fixed |
| `scoreWidgetSmall` | S | 30 (18.6) | 0 | — | 1.0 | fixed |
| `scoreWidgetMedium` | S | 24 (14.9) | 0 | — | 1.0 | fixed |
| `valueWidgetList` | S | 15 | 0 | — | — | fixed |
| `valueLock` | S | 16 | 0 | — | — | fixed |
| `valueRow` | S | 23 | 0 | — | — | values |
| `valueStat` | S | 34 | 0 | — | — | values |
| `valueAverage` | S | 38 | 0 | — | — | values |
| `valueVital` | S | 31 | 0 | — | — | values |
| `valueHours` | S | 28 | 0 | — | — | values |
| `valueZone` | S | 20 | 0 | — | — | values |
| `valueStage` | S | 18 | 0 | — | — | values |
| `valueMid` | S | 17 | 0 | — | — | values |
| `valueSmall` | S | 14 | 0 | — | — | values |
| `valueTiny` | S | 13 | 0 | — | — | values |
| `valueChart` | S | 14 | 0 | — | — | fixed (inside charts) |
| `axis` | S | 11 | 0 | — | — | fixed |
| `axisTime` | S | 12 | 0 | — | — | fixed (mockup used DIN Alternate; ghoops uses Sofia, §17) |
| `compareRow` | S | 11.5 | 0 | — | — | values |
| `compareTile` | S | 11 | 0 | — | — | values |
| `labelNav` | N700 | 13 | 0.14 | upper | — | labels |
| `labelDialInner` | N750 | 13.5 | 0.14 | upper | 18.2 | fixed |
| `labelDial` | N750 | 11.5 | 0.10 | upper | — | labels |
| `labelCard` | N750 | 12.5 | 0.10 | upper | — | labels |
| `labelMonitor` | N750 | 12 | 0.10 | upper | 16.2 | labels |
| `labelStatus` | N750 | 11.5 | 0.10 | upper | 14.4 | labels |
| `labelSmall` | N750 | 12 | 0.10 | upper | — | labels |
| `labelStage` | N750 | 13 | 0.10 | upper | — | labels |
| `labelLane` | N750 | 10.5 | 0.09 | upper | — | fixed |
| `labelActivity` | N700 | 13.5 | 0.12 | upper | — | labels |
| `labelAction` | N700 | 12.5 | 0.12 | upper | — | labels |
| `labelDate` | N700 | 12 | 0.12 | upper | — | labels |
| `labelSegment` | N700 | 12.5 | 0 | upper | — | labels |
| `labelWorkoutTitle` | N750 | 15 | 0.12 | upper | — | labels |
| `labelWidget` | N750 | 10.5 | 0.10 | upper | — | fixed |
| `labelWidgetSmall` | N750 | 10 | 0.10 | upper | — | fixed |
| `labelLock` | N700 | 8 | 0.08 | upper | — | fixed |
| `heading` | N650 | 22 | −0.01 | as written | — | text |
| `body` | N550 | 15 | 0 | as written | 21.3 | text |
| `bodyMid` | N550 | 13.5 | 0 | as written | 18.9 | text |
| `bodySmall` | N550 | 12.5 | 0 | as written | 18.1 | text |
| `legend` | N550 | 14 | 0 | as written | — | text |
| `time` | N550 | 11.5 | 0 | — | 18.4 | text |
| `tab` | N550 | 10.5 | 0 | as written | — | fixed |
| `axisDay` | N500 | 12 (latest day N700, `text1`) | 0 | as written | — | fixed |
| `axisDayNumber` | N500 | 10.5 | 0 | — | — | fixed |
| `battery` | N550 | 13 | 0 | — | — | labels |
| `unit` | N500 | 13 (vital tiles), 16 (trend average) | 0 | as written | — | values |

Default text colour is `text1` unless a component says otherwise.

### 3.4 Spacing and radii

| Token | Value |
| --- | --- |
| `screenMargin` | 16 (Home content, detail cards) |
| `homeTitleInset` | 4 (My Day and My Dashboard headings sit at 16 + 4 = 20) |
| `radiusMonitor` | 13 |
| `radiusActivities` | 13 (parent and rows) |
| `radiusActivityBlock` | 8 |
| `radiusTile` | 12 |
| `radiusCard` | 14 |
| `radiusInsight` | 12 |
| `radiusLegend` | 8 |
| `radiusZoneRow` | 12 |
| `radiusBar` | 3 |
| `radiusBadge` | 5 |
| `radiusPicker` | 10 |
| `radiusRange` | 10 (container), 8 (segment) |
| `radiusChip` | 6 |
| `radiusWidget` | system (`containerBackground`) |
| `radiusButton` | 12 |

## 4. Formatting

All formatting lives in `GHealthCore/Sources/GHealthCore/Presentation/GoopFormat.swift` (pure functions, unit-tested in `make ios-core-test`). Times and dates use `TimeZone(identifier: "Europe/London")`, never `.current` (this fixes the existing `Format.time`, which uses the device zone). Locale for numbers is `en_GB`; month abbreviations use `en_US_POSIX` so September is `Sep`.

### 4.1 Values

| Value | Display precision | Example | Null |
| --- | --- | --- | --- |
| Recovery, sleep performance, consistency, efficiency (%) | integer + `%` | `73%` | `—` |
| Strain | 1 decimal | `12.8` | `—` |
| HRV (ms) | integer | `56` | `—` |
| Resting HR, average HR, peak HR (bpm) | integer | `56` | `—` |
| Respiratory rate (rpm) | 1 decimal | `15.2` | `—` |
| Blood oxygen (%) | integer | `96` | `—` |
| Skin temperature deviation (°C) | 1 decimal with sign, `+0.0` for zero | `+0.2`, `−0.1` (U+2212) | `—` |
| Steps | integer with grouping | `6,904` | `—` |
| Minutes as duration (asleep, in bed, stages, zones, need, strength, workout duration) | `h:mm` | `6:55`, `0:07` | `—` |
| Need adjustments | signed `h:mm` | `+0:06`, `−0:28` (nap credit always `−`) | n/a (always present) |
| Clock time | `HH:mm`, 24 h, Europe/London | `23:12` | `—` |
| Comparison number under a value | same precision as the value | `52`, `7:11` | hidden |
| Percent change in trend chips | integer `%` of the prior mean | `4%` | hidden |

Integer rounding is half away from zero (match the Go side). Means given by the API are rounded to the display precision of their metric before they are compared or shown.

### 4.2 Dates

| Use | Format | Example |
| --- | --- | --- |
| Date control, selected date is `snapshot.default_date` | literal | `TODAY` |
| Date control, other dates | `EEE d MMM`, uppercased | `MON 9 MAR` |
| Detail header title | same as the date control | `TODAY` |
| Weekly chart day labels | weekday `EEE` (`Thu`) and day number `d` (`6`) on two lines | |
| Trend range label | `MMM d - MMM d, yy`, uppercased, hyphen with spaces | `MAR 4 - MAR 10, 26` |
| Trend M x labels | `MMM d` at window indices 0, 7, 14, 21, 28 | `Feb 9` |
| Trend 6M x labels | `MMM` at each calendar month's centre | `Oct` |

### 4.3 Durations from minutes

`h:mm` = `minutes / 60` then `minutes % 60` padded to two digits. A mean in minutes is rounded to the nearest minute first.

### 4.4 Comparison direction

A **comparison** compares today's value `v` with a mean `m` (both rounded to display precision first).

- `v > m`: up; `v < m`: down; equal: no change. Either null: no indicator and no comparison number.
- The indicator is the up/down triangle symbol or the no-change dot (§2.3), placed right after the value with 8 pt spacing on rows and 6 pt on tiles.

### 4.5 Direction colours

| Metric | Up | Down | No change |
| --- | --- | --- | --- |
| HRV, sleep performance, hours of sleep, restorative sleep, sleep efficiency, sleep consistency, recovery, blood oxygen, steps, zones 1–3, zones 4–5, strength activity time, day strain, workout strain, workout average HR | `positive` | `caution` | `neutral` |
| Resting heart rate | `caution` | `positive` | `neutral` |
| Respiratory rate, skin temperature | `neutral` | `neutral` | `neutral` |

These are display conventions, not medical judgments; the info sheets (§8.11) say so.

## 5. Components

Each component is a SwiftUI view in `ios/GHealth/Components/Goop/` (app only) or `ios/Shared/Goop/` (also used by widgets: rings, score text, logo, tokens, fonts, formatting glue). Geometry is at 390 pt; see §0.4.

### 5.1 ScoreRing

| Variant | Diameter | Stroke | Use |
| --- | --- | --- | --- |
| `home` | 92 fixed | 6.5 | Home dials |
| `detail` | 262 fixed | 16 | detail dials |
| `widgetSmall` | 100 | 6.5 | small widget |
| `widgetMedium` | 76 | 5.5 | medium widget |
| `widgetList` | 30 | 3.5 | small list widget |
| `lock` | 54/62 of the accessory's shorter side | 4/54 of the ring diameter | Lock Screen circular |

- Track: full 360° circle, `ringTrack` (lock: white 25 %), radius `(diameter − stroke) / 2` so the stroke stays inside the frame.
- Progress: starts at 12 o'clock and runs clockwise. Fraction = value / 100 (recovery, sleep) or value / 21 (strain), clamped 0…1. Caps `.butt` (the approved mockup's flat ends). No glow, no shadow.
- Colour: recovery by band (`recoveryHigh`, `recoveryMedium`, `recoveryLow`); strain `strain`; sleep `sleep`. Recovery with a value but null band uses `text2`.
- Null value: track only.
- Animation: on first appearance only, progress animates 0 → fraction with `.easeOut(duration: 0.6)`. No animation with Reduce Motion, in widgets, or in fixture mode (screenshots must be deterministic).

### 5.2 Home header

Row 30 tall, top padding 6 below the safe area, side padding 20. Three items, vertically centred:

1. Left: avatar button (`person.crop.circle.fill`, 28 pt frame, `avatar` colour). Tap → More tab (§6). Accessibility label "More and settings".
2. Centre: date control (§5.3).
3. Right: battery group, only when `status.device.status == "ok"` and `status.device.battery_level` is non-null: text `NN%` in `battery` style `text2`, 7 pt gap, battery symbol (`battery.0percent` below 13, `25percent` below 38, `50percent` below 63, `75percent` below 88, else `100percent`). Accessibility label "Band battery NN percent". Otherwise an empty 28 pt frame so the date control stays centred.

### 5.3 Date control

Capsule `dateOuter`, height 30, corner 16, horizontal padding 6, item gap 4: back chevron (11 pt semibold), centre pill (`dateInner`, 84 wide fixed, 24 tall, corner 12, text `labelDate`), forward chevron.

- Text: §4.2.
- Back enabled while `selectedDate > status.store.oldest_date`; disabled (colour `disabledChevron`, not tappable) when equal or when `oldest_date` is null.
- Forward enabled while `selectedDate < snapshot.default_date`; disabled at `default_date`.
- Tapping the centre pill when not on `default_date` returns to `default_date`.
- Hit targets: each chevron 44×44 (invisible padding), pill 84×44.
- Identifiers: `date-prev`, `date-label`, `date-next`. Accessibility: "Previous day", "Next day", label "Showing today" or "Showing Monday 9 March".

### 5.4 Wordmark block (Home)

`GoopWordmark(size: 26, color: #E9ECEE)` centred, 30 above, 22 below. Accessibility label `ghoops`; the screen's accessibility header is "ghoops" on the Home screen container.

### 5.5 Home dial

Column 92 wide fixed: ScoreRing `home` with centred ScoreText, then 12 pt gap, then caption row: `labelDial` text + 4 pt + `chevron.right` 11 pt `chevronDial`. Optional status caption under it (4 pt gap): `bodySmall` at 10.5 pt, `text2`, centred, width 110 fixed, at most 2 lines.

ScoreText: value in `scoreHome`; for percentages, a `%` in S at 62 % of the value size, baseline-aligned, 1 pt leading gap. Null value: `—` in `scoreHome` colour `text2`, no `%`.

Row of three dials: horizontal padding 29, `.spaceBetween`. Order Sleep, Recovery, Strain.

### 5.6 Detail dial

ScoreRing `detail` (262), content stacked and centred inside: `GoopWordmark(size: 24, color: #8D9499)`, 10 pt gap, ScoreText in `scoreDetail`, 12 pt gap, inner label in `labelDialInner` (centred, up to 2 lines), optional extra (sleep level segments, §5.11). Top margin 16 below the nav header.

### 5.7 Detail nav header

Height 50, side padding 18: back button (`chevron.left` 21 pt, 44×44 hit target, identifier `back-button`, label "Back"), centred title (`labelNav`), right slot: info button (`info.circle` 25 pt, `iconMuted`, 44×44, identifier `info-button`, label "How this works") or an empty 28 pt frame.

Implementation: the system navigation bar is hidden on ghoops screens (`.toolbarVisibility(.hidden, for: .navigationBar)`). The header is the first row inside the screen's `ScrollView`, directly below the top safe area, so it scrolls away with the content as in the mockup. Swipe-back must keep working: add `InteractivePopEnabler` (a `UIViewControllerRepresentable` that, on `didMove(toParent:)`, sets `navigationController?.interactivePopGestureRecognizer?.isEnabled = true` and its `delegate = nil`). UI test checks an edge swipe returns to Home (§15).

### 5.8 Monitor card

Two cards in a 2-column grid, gap 13, top margin 22 below the dial captions. Card: min height 121, corner 13, `monitorTop → monitorBottom`, padding 15 top, 16 sides, 16 bottom.

- Title top-left in `labelMonitor`, two lines as written in §14 (`HEALTH\nMONITOR`, `DAY HEART\nRATE`).
- `chevron.right` 12 pt `textSoft` at top 16, right 14.
- Bottom-left group (10 pt gap): badge (28×28, corner 5; the Day Heart Rate badge is 34 wide) + two-line text: status in `labelStatus` (badge colour) and subline in `bodySmall` `monitorSub`, line height 1.25.
- Whole card is one button. Health Monitor → Health tab (switches tab, does not push). Day Heart Rate → Strain detail (push). Identifiers `monitor-health-link`, `monitor-dayhr-link`.

Health Monitor content (from `day.vitals`): let `n = metrics_with_range`, `out = outside_range.count`, `within = n − out`.

| Condition (first match) | Badge | Status text | Subline |
| --- | --- | --- | --- |
| `monitor_state` is `building` | `neutral` tint, symbol none, text `—` in `neutral` S 14 | `BUILDING\nBASELINE` (`neutral`) | `No ranges yet` |
| `monitor_state` is `attention` | `caution` tint, `heart` 12 pt `caution` | `OUTSIDE\nRANGE` (`caution`) | `{within}/{n} Metrics` |
| `monitor_state` is `outside` | `neutral` tint, `heart` 12 pt `neutral` | `OUTSIDE\nRANGE` (`neutral`) | `{within}/{n} Metrics` |
| `monitor_state` is `within` | `healthOK` tint, `checkmark` semibold 12 `healthOK` | `WITHIN\nRANGE` (`healthOK`) | `{within}/{n} Metrics` |

With no `monitor_state`, use building when `n == 0`, outside when `out > 0`, else within. An unknown state is outside. The app never decides attention from `adverse`. The Home and Health status labels, and the tiles in the attention pattern, append the phrase in health-monitor-flag-spec.md §9 using `score_constants.vitals.attention_nights`, or its count-free fallback.

Day Heart Rate content (from `day.strain`): badge `dayHR` tint, 34×28, number `avg_hr_bpm` in S 14 `dayHR` (or `—`); status `AVG BPM` in `dayHR`; subline `Peak {peak_hr_bpm}` or `No heart rate yet` when `avg_hr_bpm` is null.

### 5.9 Activity rows

**Parent card** (`TODAY'S ACTIVITIES`): `activitiesFill`, corner 13, padding 16 top, 13 sides, 13 bottom. Header row (inset 4 left/right): `labelCard` text + expand symbol (button, identifier `activities-expand`, label "Show all activities"). Rows follow with 12 pt top margin each.

**Row**: `activityRow`, corner 13, min height 58, horizontal padding 9. Left to right:

1. Value block 98×41 fixed, corner 8, content centred with 10 pt gap: symbol (22 pt, white) + value in S 21 white.
2. Name in `labelActivity`, 17 pt left margin, flexible, single line, truncates tail.
3. Times, right-aligned, `time` style `text2`, two lines (start, end), 8 pt right margin.
4. Interval marker: 2×26, corner 1, block colour.

| Row kind | Block fill | Symbol | Value | Name | Tap |
| --- | --- | --- | --- | --- | --- |
| Main sleep (`day.sleep.bedtime` non-null) | `sleep` | `moon.fill` | `time_in_bed_minutes` as `h:mm` | `SLEEP` | Sleep detail |
| Nap (`day.sleep.naps[]`) | `sleep` at 60 % | `moon.fill` | `end − start` in minutes as `h:mm` | `NAP` | none |
| Recorded workout | `strain` | §2.3 | `strain` (1 dp) or `—` | `display_name` uppercased, else `WORKOUT` | Workout detail |
| Detected effort | clear, 1.5 pt dashed (`[4, 3]`) `strain` border | `heart` | `strain` or `—` | `DETECTED EFFORT` | Workout detail |

Order: the main-sleep row first, then naps and workouts together by `start` descending. Home shows at most 3 rows; the expand button opens the full list (§8.9). Identifiers: `sleep-activity-link`, `workout-link-<id>`, `nap-row-<index>`.

### 5.10 Dashboard tile

Min height 62, corner 12, `tileTop → tileBottom`, horizontal padding 16, gap 12, 10 pt top margin. Icon (§2.3, `iconMuted`) + label (`labelCard`, flexible, up to 2 lines) + right column: value in `valueRow` with indicator (§4.4) and the comparison number below in `compareTile` `text2`, right-aligned with a 14 pt right inset (so it sits under the number, not the triangle). Whole tile is a button → Trend view for its metric. Identifier `tile-<metric key>` (keys in §7.4).

### 5.11 Notched contributor card

Margins 26 top, 16 sides. Corner 14, fill `contributorFillTop → contributorFillBottom`, 1 pt `contributorBorder` stroke, padding 4 top, 14 sides, 14 bottom.

**Notch:** an upward triangle centred on the card's top edge: base 18 wide at the top edge, apex 9 above it. Fill `contributorFillTop`; its two slanted edges stroked 1 pt `notchBorder`; the card's top border has no line under the notch base. Build card + notch as one `Shape` path so fill and stroke are continuous.

**Rows:** min height 57, 11 pt gap between icon, label and right block; 1 pt `divider` line above every row except the first (the line spans the card's inner width). Label `labelCard`, flexible, up to 2 lines. Right block, right-aligned:

- Value in `valueRow` + indicator (§4.4), 8 pt gap; comparison number below in `compareRow` `text2` with a 17 pt right inset. No comparison → value only, vertically centred.
- Sleep rows: level segments (below) 14 pt left of the value, value without indicator.

**Level segments** (Sleep): three 17×4 bars, corner 1, 3 pt gap. Off = `segmentOff`. Active index: Poor 0 (`caution`), Sufficient 1 (`sufficient`), Optimal 2 (`positive`). No level (null value) → all off.

**Sleep dial segments** (inside the Sleep detail dial, 14 pt below the label): three 16×3 bars, corner 1, 4 pt gap, off `dialSegmentOff`, active as above using the Hours vs. Needed level.

Rows are buttons → Trend view for their metric (§7.4). Identifier `contributor-<metric key>`.

**Legend strip** (last child, 8 pt top margin): `legendFill`, corner 8, height 40, horizontal padding 14, gap 18, text `legend` `legendText`.

- Recovery and Strain: up triangle `positive` + down triangle `caution` (2 pt gap) then `Today` + 4 pt + `vs. prior 30 days` in `iconMuted`. (The triangles group sits 10 pt closer to the text than the gap, as in the mockup.)
- Sleep: three items, each a 12×4 dash (corner 1) + 8 pt + label: `Poor` (`caution`), `Sufficient` (`neutral`), `Optimal` (`positive`).

### 5.12 Insight card

Margins 12 top, 16 sides. Corner 12, padding 15 vertical, 16 horizontal. Fill `insightFillTop → insightFillBottom`; 1.5 pt border stroked with `insightBorder` (draw with `strokeBorder` of a `LinearGradient`). Text `body`. Action row 9 pt below: `labelAction` `insightAction` + 8 pt + `arrow.right` 13 pt. The action row is a button (identifier `insight-action`) that opens the score's info sheet (§8.11). Copy rules: §9.

### 5.13 Section heading

`heading` style. Detail screens: margins 30 top, 16 sides, 14 bottom. Home: `My Day` 37 top, inset 4; `My Dashboard` 34 top, inset 4, 4 bottom.

### 5.14 Weekly trend card

Detail card (corner 14, `cardTop → cardBottom`, padding 16, margins 0 × 16). Title row: `labelCard` title + `chevron.right` 12 pt `textSoft`; the whole card is a button → Trend view (identifier `weekly-trend-<metric key>`).

Chart (14 pt below the title), drawn with `Canvas` or Swift Charts, plot height 246 (bars area 200 + labels 46), full card inner width `W`:

- 7 slots, `step = W / 7`; slot `i` centre `cx = i·step + step/2`. Days: the 7 dates ending at the selected date (§7.1), oldest left.
- Highlight column behind the last slot: 34 wide, from y 0 to 244, corner 5, `highlightColumn` 7 %.
- Grid: 4 horizontal 1 pt `chartGrid` lines at y = 10 + k·(190/3), k = 0…3.
- Bars: width 22, bottom y 200, height = value / max · 170 (max 100 for recovery, 21 for strain). Colour: recovery by that row's `recovery_band`; strain `strain`.
- Value label: `valueChart` in the bar colour, centred, baseline at bar top − 7. Recovery `NN%`, strain 1 dp.
- Null day: no bar, no value label.
- Day labels: weekday baseline y 220 (`axisDay`, `iconMuted`; last slot `text1` N700); day number baseline y 236 (`axisDayNumber`, same colours).

### 5.15 Hatched bar and typical-range box

**Hatched track:** rounded rect (corner 3), fill `hatchDark`, overlaid with 2 pt wide `hatchLight` lines in the `/` direction (from bottom-left up to top-right at 45°), lines 6 pt apart measured perpendicular to the lines (8.485 pt apart horizontally), clipped to the track. Heights: 16 (stage bars), 18 (zone bars).

**Fill:** from x 0, width = fraction · track width, corner 3, the stage or zone colour, drawn over the track.

**Typical-range box:** drawn over the fill, full track height, from `low` to `high` on the same scale: fill `typicalFill`, left and right edges 1.3 pt `typicalEdge` dashed `[3, 2]`, no top or bottom edge. Hidden when the range is null.

**Typical Range key:** 13×13 square: hatched as above, with a 1 pt dashed `#CCCCCC` border; then 8 pt + `TYPICAL RANGE` in `labelSmall` `textSoft`.

### 5.16 Stage row

Vertical padding 10. Top row, 12 pt gaps: selection circle (26×26, 1.8 pt stroke `#D0D3D6`), stage name (`labelStage`), percentage (`valueTiny` in the stage colour; Awake uses `textSoft`), spacer, duration (`valueStage`). Bar 9 pt below (§5.15, height 16).

Selection: tapping a row selects it (circle fills with the stage colour and shows a `checkmark` semibold 12 pt in `#14181C`); the hypnogram draws other stages' blocks at 25 % opacity. Tapping again clears. Only one stage at a time. Identifier `stage-<awake|light|deep|rem>`; accessibility trait `.isSelected` when selected.

### 5.17 Restorative row

Top border 1 pt `cardDivider`, padding 16 top, 10 bottom, 12 pt gaps: `restorativeSwatch`, `RESTORATIVE SLEEP` (`labelStage`, flexible), right block: value `valueStage` + indicator (7 pt gap) and comparison number in `compareRow` `iconMuted` with a 16 pt right inset.

### 5.18 Sleep chart (E1: stage lanes plus heart-rate band)

The approved variant E1 (left phone in `mockups/sleepE.jpg`). Inside the "Last Night's Sleep" card (padding 14 top, 14 sides, 6 bottom). Layout: label column 50 wide fixed, 10 pt gap, plot `W` = card inner width − 60 (270 at 390 pt).

Vertical bands (y measured from the plot top): stage lanes 0–136 (4 lanes × 34), gap 136–160, HR band 160–220, axis 220–246. Total height 246.

Time scale: `x(t) = (t − hypnogram.start) / (hypnogram.end − hypnogram.start) · W`.

**Lanes.** Order top to bottom: Awake, REM, Light, Deep. Lane centre `y = lane·34 + 17`. A 1 pt line at each lane centre across `W`, white 4.3 %.

**Blocks.** For each `hypnogram.segments[]`: rect from `x(start)`, width `max(x(end) − x(start), 3)`, height 15, centred on its lane, corner 4, stage colour. Stage to lane: `awake` and `restless` → Awake; `rem` → REM; `light` and `asleep` → Light; `deep` → Deep. Draw all connectors first, then all blocks.

**Unstaged.** Each `hypnogram.unstaged` span is one `stageUnstaged` block from y 43.5 (top of REM) to y 126.5 (bottom of Deep), radius 4, behind the stage blocks, with no connectors. At widths of at least 64pt, centre `UNSTAGED` in `labelLane`, `laneLabel`. Selecting its row dims the other stages to 25%; selecting another stage dims this block to 25%.

**Connectors.** Between consecutive segments `a` and `b` (sorted by start) when `b.start − a.end ≤ 60 s` and their lanes differ: a vertical 1.5 pt line at `x(a.end)` from `a`'s lane centre to `b`'s, stroked with a vertical linear gradient from `a`'s colour to `b`'s, opacity 0.55. A larger gap gets no connector; uncovered time uses the unstaged block.

**Short awakenings.** Each `hypnogram.short_awakenings[]`: a block in the Awake lane, width `max(x(end) − x(start), 2)`, height 15, corner 2, `stageAwake` at 70 %; no connectors.

**Classic sessions** (`session.type == "CLASSIC"`): same drawing with the stage mapping above; add `Classic sleep (no stages)` in `bodySmall` `text2` under the axis, and the stage rows and Restorative row are hidden (light, deep and REM minutes are null).

**Label column.** Each lane label centred on its lane centre: 6 pt dot in the stage colour + 5 pt + lane name in `labelLane` `laneLabel` (`AWAKE`, `REM`, `LIGHT`, `DEEP`). HR label block with its top at y 176: `HR` in `labelLane` `laneLabel`, then `{min}–{max}` (rounded min and max bpm of the series, en dash) in S 12 `hrLine`, line height 1.25. Hidden when the series is empty.

**HR band** (`sleep.overnight_hr`, 5-minute buckets):

- Point `x = x(t + 150 s)` (bucket centre), `y = 160 + 60 − (bpm − lo) / (hi − lo) · 60` with `lo = min(bpm) − 4`, `hi = max(bpm) + 4`.
- Split into runs where consecutive points are ≤ 300 s apart; each run is drawn separately (a gap stays empty).
- Curve: Catmull-Rom through the run's points converted to cubic Béziers with tension 1/6 (control points `p1 + (p2 − p0)/6` and `p2 − (p3 − p1)/6`, end points duplicated), as `smooth()` in `goop.html`.
- Area: the curve closed down to y 220, filled with `hrArea`.
- Line: 1.6 pt `hrLine`, round caps and joins.
- Baseline: 1 pt line at y 220 across `W`, white 6.3 %.
- Minimum marker: circle radius 3, fill `#13181C`, 1.6 pt `hrLine` stroke, at the first point with the minimum bpm.
- Fewer than 2 points: no band, no marker, no HR label.

**Axis.**

- Dashed verticals at x 0.75 and W − 0.75 from y −2 to 224, 1 pt white 22 %, dash `[2.5, 3]`; white dots radius 2.2 at (1.6, 225) and (W − 1.6, 225).
- Start and end labels: `HH:mm` of `hypnogram.start` and `.end` in `axisTime` white, baseline y 243, left-aligned at x 0 and right-aligned at W.
- Hour ticks: every whole London hour `h` with `h` odd (01:00, 03:00, …, 23:00) that lies at least 40 minutes after the start and 40 minutes before the end. Each: a 4 pt line (y 221–225, white 25 %) and the label `HH:00` in S 11 `tickLabel`, centred, baseline y 243. Drop a tick label whose frame would overlap the start or end label (keep the tick line).

**Accessibility:** `accessibilityChartDescriptor` listing each stage interval (category = "Light 23:40 to 00:15", value = minutes) each unstaged span (category = "Unstaged 06:29 to 07:41", value = minutes), and an HR series (time, bpm). Identifier `hypnogram`.

### 5.19 Need card (Hours vs. Needed)

Detail card, 12 pt below the sleep card.

1. Title row: `HOURS VS. NEEDED` (`labelCard`) + `info.circle` 19 pt → Sleep info sheet.
2. Value (6 pt below): sleep performance in `valueHours` + indicator (comparison `sleep_performance`); comparison number below in S 12 `iconMuted`.
3. `HOURS OF SLEEP` row (16 pt top, 10 pt inset each side, 8 pt below): label `labelSmall` `textSoft`, value `asleep_minutes` in `valueMid`.
4. Hours bar: inset 10, height 16, corner 3, `hoursBar`, width = `asleep / S` of the inset width.
5. Need bar (9 pt below): inset 10, height 16, corner 3, clipped; segments left to right with 2 pt gaps: `baseline_minutes` (`baselineNeedBar`), `strain_extra_minutes` (`strain`), `debt_extra_minutes` (`sufficient`); zero-width segments and their gaps are omitted. When `nap_credit_minutes > 0`, overlay the rightmost `nap_credit / S` of the drawn bar with a box filled `legendFill` at 70 % and a 1 pt `naCredit` dashed `[3, 2]` border.
6. `SLEEP NEEDED` row (8 pt below): label + `need.total_minutes` in `valueMid`.
7. Need legend (12 pt below): `legendFill`, corner 8, padding 6 vertical, 14 horizontal; four rows (padding 5 vertical, 10 pt gap): 13×13 swatch (corner 2) + label (`legend`) + value (`valueSmall`, right). Rows: Baseline Need (`dialSegmentOff`, `h:mm`), Recent Strain (`strain`, `+h:mm`), Sleep Debt (`sufficient`, `+h:mm`), Nap Credit (clear swatch with 1 pt dashed `naCredit` border, `−h:mm`).

`S = max(asleep_minutes ?? 0, baseline + strain_extra + debt_extra)`. No main sleep: title becomes `TONIGHT'S NEED SO FAR`, items 2 to 4 are hidden, the rest stays.

### 5.20 Zone row (workout)

Card `zoneRowFill`, corner 12, padding 13 vertical, 14 horizontal, 8 pt top margin. Top row (9 pt gaps, first-baseline aligned): `ZONE n` (`labelStage`), `{range} BPM` (`valueTiny` `textSoft`), percentage (`valueTiny` in the zone colour), spacer, duration (`valueZone`). Bar 9 pt below: hatched, height 18, fill in the zone colour.

- Rows run Zone 5 down to Zone 0. Zone 0 is `zones_minutes.below`.
- Percentage = zone minutes / sum of all six × 100, rounded; sum 0 → all rows show `0%` and no bars.
- Fill fraction = zone share × `k`, `k = min(2.2, 0.95 / largest share)`.
- Zero-minute rows: opacity 0.5, padding 12 vertical, no bar.
- BPM ranges from the cycle's `resting_hr_bpm` (R) and `max_hr_bpm` (M): edge `e` → `ceil(R + (M − R)·e)`. Zone 0 `<{e(0.30)}`; Zone 1 `{e(0.30)}-{e(0.50) − 1}`; Zone 2 `{e(0.50)}-{e(0.60) − 1}`; Zone 3 `{e(0.60)}-{e(0.70) − 1}`; Zone 4 `{e(0.70)}-{e(0.85) − 1}`; Zone 5 `{e(0.85)}+`. Either null → ranges hidden.

### 5.21 Trend controls

**Metric picker:** height 54, corner 10, `controlFill`, padding 18, gap 14: metric icon, metric name (`labelCard` at 13.5 pt), `chevron.down`. Tapping opens a SwiftUI `Menu` with sections Recovery, Strain, Sleep, Health (§7.4). Identifier `metric-picker`; menu items `metric-<key>`.

**Range selector:** container `rangeTrack`, corner 10, padding 3, gap 2; three segments 52×32 fixed, corner 8, `labelSegment` `rangeText`; selected segment `rangeSelected` fill and `text1`. Labels `W`, `M`, `6M`. Identifiers `range-W`, `range-M`, `range-6M`; selected has `.isSelected`.

**Range navigation:** 20 pt below the selector, right-aligned, 14 pt gaps: `chevron.left` 13 pt semibold, label (`labelCard` §4.2), `chevron.right`. Disabled colour `disabledChevronDark`. Identifiers `range-prev`, `range-label`, `range-next`.

**Average block (left):** `AVERAGE` (`labelSmall` `iconMuted`), then (4 pt) value in `valueAverage` + 6 pt + unit in `unit` 16 `textSoft` baseline-aligned; then (8 pt) a chip: `chipFill`, corner 6, padding 3 × 8, 5 pt gap, indicator + text in N550 11.5 `chipText`.

### 5.22 Trend chart

Plot area: card-less, side padding 10, height 250 plus 44 for labels, y-axis label gutter 30 on the left.

- **Y scale:** for percent scores (recovery, sleep performance, efficiency, consistency) fixed 0–100 with 6 gridlines every 20. Strain fixed 0–21 with gridlines at 0, 4, 8, 12, 16, 20 (top at 21). Otherwise: `lo..hi` from the window's non-null values together with the typical range when shown; `span = max(max − min, 1)`; pick the first step in [1, 2, 4, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000] where `floor((min − 0.15·span)/step)·step + 5·step ≥ max + 0.15·span`; gridlines at the 6 values from that floor in `step` increments.
- Gridlines: 1 pt `plotGrid`; labels in `axis` `iconMuted` right-aligned in the gutter, vertically centred on their line.
- **Typical band** (vital metrics only, §7.5): rect from `range_low` to `range_high` across the plot, `trendBand`. Key above the chart, right-aligned: 12×12 `trendBand` square + 8 pt + `TYPICAL RANGE` (`labelSmall` at 11.5 pt).
- **Highlight:** the newest slot's column, inset 3 each side, from y −6 to plot bottom + 38, corner 5, `highlightColumn` 5 %.
- **W, line metrics:** polyline 1.6 pt `trendLine` through non-null points (split at nulls); points radius 5, fill `#13181C`, 1.8 pt `trendLine` stroke; value label `valueChart` `trendLine` centred 11 pt above the point.
- **W, bar metrics:** bars width = slot × 0.4, value labels as §5.14, colour per §7.4.
- **M:** line metrics as W but points radius 3 and no value labels; bars width slot × 0.6 and no value labels. X labels §4.2.
- **6M:** daily marks at 30 % opacity (bars width slot × 0.6, or a 1 pt line without points); per calendar month in the window with ≥ 1 value, a 2 pt horizontal segment at that month's mean spanning the month's x range, in the metric colour, with the mean as a `valueChart` label 8 pt above its centre. X labels §4.2.
- Day labels for W: as §5.14 (weekday and day number, newest in `text1`).
- Accessibility: `accessibilityChartDescriptor` with one point per day in the window (null days omitted).

### 5.23 Vital tile and range chip (Health tab)

Grid of 2 columns, gap 11, 12 pt below the heading. Tile: min height 122, corner 12, `tileTop → tileBottom`, padding 13 top/sides, 12 bottom.

- Label row: icon + 7 pt + name (`labelSmall` at 11 pt, colour `#E5E7E9`), up to 2 lines.
- Value 12 pt below: `valueVital` + 4 pt + unit (`unit` 13 `text2`).
- Chip pinned bottom-left: corner 6, padding 3 × 8, 6 pt gap, symbol + text in S 11.5:

| Vital state | Chip fill / text colour | Symbol | Text |
| --- | --- | --- | --- |
| `position == "within"` | `vitalChipFill` / `positive` | `checkmark` | `{low} – {high}` |
| `above` or `below`, key in `persistent` and `monitor_state` is `attention` | `caution` 12 % / `caution` | `arrowtriangle.up.fill` or `.down.fill` | `{low} – {high}` |
| `above` or `below`, not in the attention pattern | `neutral` 15 % / `textSoft` | same | `{low} – {high}` |
| `no_baseline` | `neutral` 15 % / `textSoft` | none | `Building baseline` |
| status not `available` | `neutral` 15 % / `textSoft` | none | MetricStatus text (app.md §7.2) |

Range numbers use the metric's display precision (§4.1), joined by ` – ` (spaces, en dash). Tile is a button → Trend view (identifier `vital-<key>`).

### 5.24 Status card (Health tab)

Monitor-card fill, corner 13, padding 16, 14 pt gap, top margin 22: badge 40×40 (same colours and symbols as the Health Monitor card, §5.8) + text: status (`labelStatus` at 13 pt, one line, e.g. `WITHIN RANGE`) and 3 pt below the sentence in `bodyMid` `monitorSub` (§14.4).

### 5.25 Outline button

Height 50, corner 12, 1.5 pt `outlineBorder`, label `labelCard` centred. Used for `VIEW TRENDS`, `TRY AGAIN`, `UNPAIR`. Primary button (Pairing): same size, fill `#FFFFFF`, label `labelCard` in `#0E1313`.

### 5.26 Banner

`legendFill`, corner 10, padding 12 × 14, 10 pt gap: symbol (§2.3, 15 pt), text `bodyMid` `legendText` (flexible, wraps), `xmark` button (label "Dismiss: {text}") when dismissible. Stacked with 8 pt gaps.

### 5.27 Tab bar

Custom bar (the system `TabView` bar is hidden: `.toolbarVisibility(.hidden, for: .tabBar)` on every tab root). Background `tabTop → tabBottom` extended through the bottom safe area. Content: top padding 12, four equal items (each 70 wide fixed, `.spaceAround`), icon in a 24 pt tall frame, 4 pt gap, label in `tab`; bottom padding 8 above the safe area. Active item `text1`, others `text3`. Items: Home (`house`), Health (`heart`), Trends (`chart.xyaxis.line`), More (`line.3.horizontal`). Identifiers `tab-home`, `tab-health`, `tab-trends`, `tab-more`; accessibility traits `.isButton` plus `.isSelected` on the active tab; labels "Home", "Health", "Trends", "More".

The bar shows only when the current tab's navigation path is empty (tab roots). Pushed screens have no tab bar, as in the mockup. Root scroll views reserve the bar's height at the bottom (`contentMargins(.bottom, barHeight + 22, for: .scrollContent)`).

### 5.28 Sheet

Info sheets (§8.11) and the full activities list use `.sheet` with `.presentationDetents([.large])`, `.presentationDragIndicator(.visible)`, background `sheetFill`. Header row 50 tall: centred title `labelNav`, `xmark` button at the right (identifier `sheet-close`, label "Close"). Content padding 16; section titles `labelCard` with 24 pt above and 10 below; body `bodyMid` `legendText`; key–value rows 44 min height, label `bodyMid`, value S 17 right-aligned.

### 5.29 Empty and loading states

**Full-screen state** (no cache, offline past day): centred column, `GoopMark` 56 pt white at 40 %, 20 pt, title `heading`, 8 pt, text `bodyMid` `text2` centred (max width 300), 20 pt, optional outline button (240 wide).

**Card placeholder** (a card's data is missing): the card keeps its frame; content replaced by one `bodyMid` `text2` line from §14.

**Loading:** `ProgressView()` tinted `text2` with `Loading from your Mac` below in `bodySmall` `text2`, centred in the area that is loading.

## 6. Navigation

### 6.1 Root

```
AppRoot
├─ not paired or invalid pairing → PairingScreen (full screen, no tab bar)
├─ paired, no cache → NoDataState (full screen, tab bar visible)
└─ paired with cache → GoopTabs
     ├─ Home   NavigationStack(path: homePath)    root: HomeScreen
     ├─ Health NavigationStack(path: healthPath)  root: HealthScreen
     ├─ Trends NavigationStack(path: trendsPath)  root: TrendScreen(mode: .tabRoot)
     └─ More   NavigationStack(path: morePath)    root: MoreScreen
```

`AppModel` owns `tab: GoopTab` (`home`, `health`, `trends`, `more`) and the four paths. `ghealth://today` selects Home, clears `homePath` and sets `selectedDate = default_date`.

### 6.2 Routes

```swift
enum Route: Hashable {
    case recovery, strain, sleep
    case workout(id: String, date: String)
    case trend(metric: TrendMetricKey, end: String)
    case activities(date: String)
}
```

| From | Trigger | Destination |
| --- | --- | --- |
| Home | Sleep / Recovery / Strain dial | push `.sleep` / `.recovery` / `.strain` |
| Home | Health Monitor card | switch to Health tab |
| Home | Day Heart Rate card | push `.strain` |
| Home | Activity row (sleep) | push `.sleep` |
| Home | Activity row (workout) | push `.workout` |
| Home | Expand | sheet: Activities list |
| Home | Dashboard tile | push `.trend(metric, end: selectedDate)` |
| Home | Avatar | switch to More tab |
| Recovery / Strain / Sleep | contributor row, weekly trend card | push `.trend` |
| Recovery / Strain / Sleep | info button, insight action | sheet: that score's info |
| Strain | activity row | push `.workout` |
| Sleep | Hours vs. Needed info | sheet: Sleep info |
| Health | vital tile | push `.trend` (that vital) |
| Health | View Trends | push `.trend(.hrv, end: selectedDate)` |
| Trend (pushed) | back | pop |
| Any pushed screen | back button or edge swipe | pop |

Routes push within the current tab's stack. Pushed screens read the bundle for `selectedDate` (§7.1).

## 7. App data layer additions

### 7.1 Selected date and day bundles

`AppModel.selectedDate: String` starts at `snapshot.default_date` and resets to it whenever a new snapshot with a different `default_date` arrives, and on `ghealth://today`.

`DayBundle = (day: Day, sleep: Sleep, workouts: [Workout])` (workouts with `hr_series`).

- For `default_date`: built from the snapshot (`snapshot.day`, `snapshot.sleep`, `snapshot.workouts.workouts` filtered to `cycle_date == default_date`). Always available offline.
- For another date: fetched with three concurrent requests: `GET /v2/day?date=D`, `GET /v2/sleep?date=D`, `GET /v2/workouts?from=D&to=D`. Kept in an in-memory dictionary for the session (cleared on unpair and when a new snapshot arrives). Not written to disk.
- States per date: `loading`, `loaded(DayBundle)`, `failed(ClientError)`. A 401 sets `invalidPairing` as today.
- Fixture mode: other dates fail immediately with `ClientError.offline` (no network), so screens show the offline day state (§10).

Add to `APIClient`: `day(date:)`, `sleep(date:)`, `workouts(from:to:)`, `days(from:to:)`. Each decodes with the existing schema and synthetic checks.

### 7.2 Trend history

`TrendStore` (actor in GHealthCore, `Presentation/TrendStore.swift`, unit-tested with a stub client):

- Holds `rows: [String: DayRow]`. Seeded from `snapshot.days.days` on every snapshot; fetched rows never overwrite snapshot rows.
- `rows(from:to:) async throws -> [DayRow]` returns one row per date (a missing date that the API returned with nulls is a row of nulls; a date not yet fetched triggers a fetch).
- Fetching: compute the missing dates in `[from, to]`, group into contiguous runs, split each run into chunks of at most 90 days (newest chunk first), request `GET /v2/days?from=&to=` for each chunk sequentially, merge. Never request a range over 90 days (the API rejects it). Never request a date after `default_date`.
- On failure: throw; rows already fetched stay cached.

### 7.3 Trend windows

| Range | Window length `L` | Prior window | Step for ‹ › |
| --- | --- | --- | --- |
| W | 7 days ending `E` | the 7 days before | 7 days |
| M | 30 days ending `E` | the 30 days before | 30 days |
| 6M | 180 days ending `E` | the 180 days before | 180 days |

- `E` starts at the route's `end` (Trends tab: `default_date`).
- Previous is disabled when `E − L < status.store.oldest_date` (or `oldest_date` is null); next is disabled when `E == default_date`; next never moves past `default_date` (it clamps).
- Load the current window first, then the prior window. The chart renders when the current window is loaded; the comparison chip appears when the prior window is loaded and has at least 1 value. Prior-window failure hides the chip silently.
- 6M needs up to 360 days, so up to 4 requests (store retention is 400 days).
- Window mean = arithmetic mean of non-null values in the window, then rounded to display precision. Available days = count of non-null values.

### 7.4 Trend metrics

| Key | Name (picker, title) | Group | Source: `DayRow` field | Chart | Colour | Unit text | Icon |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `recovery` | Recovery | Recovery | `recovery` | bars | by `recovery_band` | `%` | `heart` |
| `hrv` | Heart Rate Variability | Recovery | `hrv_rmssd_ms` | line | `trendLine` | `ms` | `waveform.path.ecg` |
| `resting_hr` | Resting Heart Rate | Recovery | `resting_hr_bpm` | line | `trendLine` | `bpm` | `heart` |
| `respiratory_rate` | Respiratory Rate | Recovery | `respiratory_rate_bpm` | line | `trendLine` | `rpm` | `lungs` |
| `strain` | Day Strain | Strain | `strain` | bars | `strain` | none | `heart` |
| `zones_1_3` | Heart Rate Zones 1-3 | Strain | `zones_1_3_minutes` | bars | `zone2` | `h:mm` values | `heart` |
| `zones_4_5` | Heart Rate Zones 4-5 | Strain | `zones_4_5_minutes` | bars | `zone4` | `h:mm` values | `heart` |
| `strength` | Strength Activity Time | Strain | `strength_minutes` | bars | `strain` | `h:mm` values | `dumbbell` |
| `steps` | Steps | Strain | `steps` | bars | `strain` | none | `shoe.2` |
| `sleep_performance` | Sleep Performance | Sleep | `sleep_performance` | bars | `sleep` | `%` | `moon` |
| `hours` | Hours of Sleep | Sleep | `asleep_minutes` | bars | `sleep` | `h:mm` values | `moon` |
| `restorative` | Restorative Sleep | Sleep | `restorative_minutes` | bars | `stageREM` | `h:mm` values | `moon` |
| `consistency` | Sleep Consistency | Sleep | `sleep_consistency` | line | `trendLine` | `%` | `clock` |
| `efficiency` | Sleep Efficiency | Sleep | `efficiency_pct` | line | `trendLine` | `%` | `chart.bar` |
| `spo2` | Blood Oxygen | Health | `spo2_pct` | line | `trendLine` | `%` | `drop` |
| `skin_temp` | Skin Temp | Health | `skin_temp_deviation_c` | line | `trendLine` | `°C` | `thermometer.medium` |

Duration metrics show values and the average as `h:mm` with no unit text. The `%` unit for percent metrics is attached to the number (`73%`), not shown as a separate unit.

Where rows link to trends: Recovery rows → `hrv`, `resting_hr`, `respiratory_rate`, `sleep_performance`; Recovery weekly card → `recovery`; Strain rows → `zones_1_3`, `zones_4_5`, `strength`, `steps`; Strain weekly card → `strain`; Sleep rows → `sleep_performance`, `consistency`, `efficiency`; Home tiles → `hrv`, `sleep_performance`, `hours`, `resting_hr`, `steps`; vital tiles → `respiratory_rate`, `spo2`, `resting_hr`, `hrv`, `skin_temp`.

Trends tab default metric: `recovery`.

### 7.5 Typical range in the trend view

Shown only for `hrv`, `resting_hr`, `respiratory_rate`, `spo2`, `skin_temp`, and only when the window ends on `default_date`: the band is `snapshot.day.vitals.metrics[k].range_low … range_high` (k = `hrv_rmssd`, `resting_hr`, `respiratory_rate`, `spo2`, `skin_temp_deviation`). Both bounds null → no band. For other windows and metrics there is no band and no key. (That range is the personal range ending today; drawing it behind past windows would misstate it.)

### 7.6 Comparisons

Today-versus-prior comparisons use `day.comparison.metrics` (§13.2): `recovery`, `strain`, `sleep_performance`, `asleep_minutes`, `efficiency_pct`, `restorative_minutes`, `hrv_rmssd_ms`, `resting_hr_bpm`, `respiratory_rate_bpm`, `spo2_pct`, `skin_temp_deviation_c`, `steps`, `zones_1_3_minutes`, `zones_4_5_minutes`, `strength_minutes`. A missing `comparison` object (older server) or a null mean hides the indicator and the number.

Workout chips (§8.5) compare against other workouts, computed in the app from the loaded workouts list as stated there.

## 8. Screens

Bindings use: `S` = cached snapshot, `B` = the `DayBundle` for `selectedDate`, `D` = `B.day`, `L` = `B.sleep`, `C` = `D.comparison.metrics`. All values are dimmed to 55 % opacity when the phone copy is older than 6 h (app.md §8, unchanged): apply to rings, values and charts, not to labels, banners or controls.

### 8.1 Home (`today-screen`)

Background `homeBackground`. Scroll view, pull to refresh (app.md §6.3; light haptic on completion). Top to bottom:

1. Header (§5.2).
2. Banners (§10.2), 12 pt below the header, 16 pt side margins. Hidden when none.
3. Wordmark (§5.4).
4. Dials (§5.5):

| Dial | Value | Ring colour | Caption | Status caption (first match) | Link id |
| --- | --- | --- | --- | --- | --- |
| Sleep | `D.sleep.performance.value` (%) | `sleep` | `SLEEP` | null → reason text (app.md §7.1) | `sleep-link` |
| Recovery | `D.recovery.value` (%) | by `D.recovery.band` | `RECOVERY` | null → reason text with N = `min(hrv_values, resting_hr_values)`; `calibrating` → `Calibrating`; `confidence == low` → `Low data` | `recovery-link` |
| Strain | `D.strain.value` (/21) | `strain` | `STRAIN` | null → reason text; `confidence == low` → `Low data` | `strain-link` |

5. Monitor cards (§5.8), side margins 16.
6. `My Day` heading (§5.13).
7. Today's Activities (§5.9), 18 pt below the heading. No rows at all → the parent card shows `No activities yet` (`bodyMid` `text2`, 12 pt below the header) and the expand button is hidden.
8. `My Dashboard` heading. No CUSTOMIZE control.
9. Tiles in this fixed order:

| Label | Icon | Value | Comparison mean | Trend key |
| --- | --- | --- | --- | --- |
| HEART RATE VARIABILITY | `waveform.path.ecg` | `D.vitals.metrics.hrv_rmssd.value` | `C.hrv_rmssd_ms` | `hrv` |
| SLEEP PERFORMANCE | `moon` 18 pt | `D.sleep.performance.value` % | `C.sleep_performance` | `sleep_performance` |
| HOURS OF SLEEP | `moon` | `D.sleep.asleep_minutes` `h:mm` | `C.asleep_minutes` | `hours` |
| RESTING HEART RATE | `heart` | `D.vitals.metrics.resting_hr.value` | `C.resting_hr_bpm` | `resting_hr` |
| STEPS | `shoe.2` | `D.activity.steps.value` | `C.steps` | `steps` |

A vital or activity value whose `status` is not `available` shows `—`; tapping the tile still opens the trend. (The old "tap shows the status in words" alert moves into the tile's accessibility hint: §12.1.)

10. Bottom content margin for the tab bar.

Not on Home: Daily Outlook, coach, floating +, Plan, Community, Stress Monitor, strain target, CUSTOMIZE.

Loading another date: dials show tracks only with `—`, monitor cards and tiles show `—`, activities show the loading state (§5.29). Failed: everything below the header is replaced by the full-screen offline-day state (§10.3) inside the scroll view; the date control stays usable.

### 8.2 Recovery detail (`recovery-screen`)

`detailBackground`. Header title: date label (§4.2); info button → Recovery sheet.

1. Detail dial: `D.recovery.value` (%), ring colour by band, label `RECOVERY`. Calibrating: a second label line `CALIBRATING` in `labelDialInner` `text2`.
2. Notched card rows:

| Row | Icon | Value | Comparison | Trend key |
| --- | --- | --- | --- | --- |
| HEART RATE VARIABILITY | `waveform.path.ecg` | `D.recovery.inputs.hrv_rmssd_ms` | `C.hrv_rmssd_ms` | `hrv` |
| RESTING HEART RATE | `heart` | `D.recovery.inputs.resting_hr_bpm` | `C.resting_hr_bpm` | `resting_hr` |
| RESPIRATORY RATE | `lungs` | `D.recovery.inputs.respiratory_rate_bpm` | `C.respiratory_rate_bpm` | `respiratory_rate` |
| SLEEP PERFORMANCE | `moon` | `D.recovery.inputs.sleep_performance` % | `C.sleep_performance` | `sleep_performance` |

   Legend strip: Today vs. prior 30 days.
3. Insight card (§9.1), action `BREAK DOWN MY RECOVERY`.
4. Calibration card, only when `D.recovery.calibrating` or `reason == insufficient_baseline`: detail card 12 pt below the insight. `CALIBRATING` (`labelCard`), 10 pt, text `Calibrating: N of 7 nights` (`bodyMid`), 10 pt, an 8 pt tall progress track (corner 4, `ringTrack`) filled `positive` to `min(N, 14)/14` with a 2 pt white tick at 50 %, 8 pt, `7 nights to start · 14 for full confidence` (`bodySmall` `text2`).
5. `Weekly Trends` heading; weekly card `RECOVERY` (bars, band colours) for the 7 days ending `selectedDate`. Rows come from `TrendStore` (in the snapshot for the default date; fetched otherwise; failure → card placeholder `Needs a connection to your Mac`).
6. 30 pt bottom spacer.

### 8.3 Strain detail (`strain-screen`)

1. Detail dial: `D.strain.value` (/21), label `DAY STRAIN`; when `status == in_progress` a second label line `SO FAR` in `labelDialInner` `text2` (**Deviation**, §17).
2. Notched card rows:

| Row | Icon | Value | Comparison | Trend key |
| --- | --- | --- | --- | --- |
| HEART RATE ZONES 1-3 | `heart` | `z1 + z2 + z3` of `D.strain.zones_minutes`, `h:mm` (null object → `—`) | `C.zones_1_3_minutes` | `zones_1_3` |
| HEART RATE ZONES 4-5 | `heart` | `z4 + z5`, `h:mm` | `C.zones_4_5_minutes` | `zones_4_5` |
| STRENGTH ACTIVITY TIME | `dumbbell` | `D.strength_minutes`, `h:mm` | `C.strength_minutes` | `strength` |
| STEPS | `shoe.2` | `D.activity.steps.value` | `C.steps` | `steps` |

   Legend strip: Today vs. prior 30 days.
3. Insight card (§9.2), action `EXPLORE MY STRAIN`.
4. Today's Activities card (§5.9) with margins 30 top, 16 sides; workouts and detected efforts only (no sleep or nap rows), all of them (no 3-row limit, no expand). None → `No workouts yet`.
5. `Weekly Trends`; weekly card `STRAIN` (blue bars).
6. 30 pt spacer.

### 8.4 Sleep detail (`sleep-screen`)

1. Detail dial: `D.sleep.performance.value` (%), ring `sleep`, label `SLEEP\nPERFORMANCE`, level segments (Hours vs. Needed level).
2. Notched card rows (levels §9.4):

| Row | Icon | Value | Level from | Trend key |
| --- | --- | --- | --- | --- |
| HOURS VS. NEEDED | `moon` | `L.performance.value` % | same | `sleep_performance` |
| SLEEP CONSISTENCY | `clock` | `L.consistency.value` % | same | `consistency` |
| SLEEP EFFICIENCY | `chart.bar` | `L.efficiency_pct` % | same | `efficiency` |

   Legend strip: Poor, Sufficient, Optimal.
3. Insight card (§9.3), action `DIVE INTO MY SLEEP`.
4. `Last Night's Sleep` heading, then the sleep card (detail card, padding 14/14/6):
   1. Sleep chart E1 (§5.18) from `L.hypnogram`, `L.overnight_hr`.
   2. Divider 1 pt `cardDivider` (12 pt above, 4 below).
   3. Key row (padding 8 vertical): Typical Range key (§5.15) left; right `DURATION` (`labelSmall` `textSoft`) + 4 pt + `L.time_in_bed_minutes` (`valueSmall` white).
   4. Stage rows (§5.16) in order Awake, Light, SWS (Deep), REM, then Unstaged when `stages.unstaged.minutes > 0`:

| Row | Name | Percentage | Duration | Bar colour | Typical range |
| --- | --- | --- | --- | --- | --- |
| Awake | `AWAKE` | `round(100 × awake.minutes / time_in_bed_minutes)`% (**decision**, §17) | `L.stages.awake.minutes` | `stageAwake` | `L.stage_typical.awake` |
| Light | `LIGHT` | `round(light.pct_of_asleep)`% | `light.minutes` | `stageLight` | `.light` |
| SWS (Deep) | `SWS (DEEP)` | `round(deep.pct_of_asleep)`% | `deep.minutes` | `stageDeep` | `.deep` |
| REM | `REM` | `round(rem.pct_of_asleep)`% | `rem.minutes` | `stageREM` | `.rem` |
| Unstaged | `UNSTAGED` | `round(unstaged.pct_of_asleep)`% in `textSoft` | `unstaged.minutes` | `stageUnstaged` | none |

      Bar scale: `scale = max(all shown stage minutes, all four non-null typical highs) / 0.87`; fill fraction = minutes / scale; typical box from low / scale to high / scale.
      The unstaged row has id `stage-unstaged`, no typical box, and reads "Unstaged, 15 percent, 1 hour 12 minutes" for the fixture's 14.8% and 72 minutes. The Night info section adds `Includes <h:mm> without stages` under Hours of sleep when unstaged minutes are positive. How this works reads `score_constants.sleep.unstaged_counts_as`: `asleep` gives "Time in a night with no sleep stages counts as sleep. It shows as unstaged."; `awake` gives "Time in a night with no sleep stages counts as awake."; missing or unknown omits the sentence. Dials, Home, widgets and Trends carry no unstaged marker.
   5. Restorative row (§5.17): `deep.minutes + rem.minutes` (null if either is null), comparison `C.restorative_minutes`.
5. A full-width outline `EDIT SLEEP` button (`sleep-edit-open`) sits 12 pt below the sleep card and opens the editor for the selected night. It appears when the Mac supplies `session.edit_range` and no pending sleep change locks that night.
   - Outside the Mac's horizon, show `Only nights from the last <n> days can be edited.` (`sleep-edit-horizon`). Use `Only last night's sleep can be edited.` for one day.
   - For a night with no stages, show `This night has no sleep stages from your band, so ghoops can't edit it.` (`sleep-edit-no-stages`). Older Macs without sleep editing show neither eligibility note.
   - For an applied ghoops edit, show `Edited in ghoops. Google Health has <start> to <end>.` (`sleep-edited-footnote`), 12 pt below the button when present. Read the times from `session.google`. All three footnotes use `bodySmall` and `iconMuted`.
   - [Sleep editing spec §4](sleep-edit-spec.md#4-editing-a-night) defines the editor, save states, and restore action.
6. Need card (§5.19), 12 pt below.
7. When the open cycle has `day.sleep_plan`, the Tonight card appears 12pt below the need card (or below the last placeholder card when sleep is missing), followed by the 30pt spacer. Layout, unavailable state and accessibility: [parity1-spec §2.4](parity1-spec.md#24-sleep-detail-tonights-sleep-sleep-plan).

### 8.5 Workout detail (`workout-screen`)

Pushed with a workout ID and its date; reads the workout (with `hr_series`) from that date's bundle. Header: back button, 16 pt, workout symbol 30 pt, 16 pt, a column: name (`labelWorkoutTitle`, `display_name` uppercased, or `DETECTED EFFORT`) and `{start} to {end}` (`bodySmall` `textSoft`, 2 pt below). Height 50.

1. Stats grid (2 equal columns, padding 18 top, 16 sides, 4 bottom):
   - `ACTIVITY STRAIN` (`labelSmall` in `strain`), 6 pt, value `strain` in `valueStat` `strain` + 8 pt + chip.
   - `AVERAGE HR` (`labelSmall` `text1`), value `avg_hr_bpm` in `valueStat` `text1` + chip.
   - Chip (§5.21 style): difference from the mean of the other workouts in the loaded list (`S.workouts.workouts` plus any fetched bundle workouts) with the same `category` and a non-null value, excluding this workout; text = absolute difference at display precision; indicator per §4.4/§4.5. No other workouts → no chip.
2. HR chart (padding 14 top, 16 sides), height 190 + 26: grid 4 lines `plotGrid` at 0, h/3, 2h/3, h; y domain `lo = floor(min/10)·10 − 10`, `hi = ceil(max/10)·10 + 10`; labels (S 11 `textSoft`) for the three upper grid values, drawn 4 pt above their line at x 4. Line: 2 pt `workoutLine`, round joins, through `hr_series` points (one per covered minute; split where consecutive points are > 60 s apart). Area under each run: `workoutArea`. Start and end markers: dashed white verticals `[3, 3]` at x 1 and W − 1 with white dots radius 2.5 on the baseline; time labels `HH:mm` (`axisTime`) under them. Empty series → `No heart rate recorded for this workout` placeholder.
3. Stats line (padding 14 top, 18 sides, 4 bottom): left `MAX HR` (`labelSmall` `iconMuted`) + `peak_hr_bpm` (`valueSmall` white); right `DURATION` (`labelSmall` `textSoft`) + `elapsed_minutes` as `h:mm`.
4. Zone rows (§5.20) from `zones_minutes`, BPM ranges from `D.strain.resting_hr_bpm` and `max_hr_bpm` of the workout's cycle. Null zones → placeholder `No heart-rate zones for this workout`.
5. Footnote (`bodySmall` `iconMuted`, 14 pt top): `Zones use heart rate reserve (resting {R}, max {M}). Change max HR on the Mac with ghoops config.` (`ghoops config` in `textSoft`). Then, recorded workouts with a `provider`: `Fitbit says: avg {avg} bpm · {kcal} kcal · {azm} active zone minutes.` Then: `Based on {coverage}% heart-rate coverage.` Detected efforts: `Not logged as a workout. ghoops found a stretch of high heart rate.`
6. 30 pt spacer.

### 8.6 Trend view (`trend-view-screen` pushed; `trends-screen` as the Trends tab root)

`detailBackground`. Header: pushed → back + `TREND VIEW` + empty right slot; tab root → no back, title `TRENDS`.

1. Metric picker (§5.21), margins 14 top, 16 sides.
2. Summary row (padding 22 top, 16 sides): average block left (§5.21; chip text `{pct}% vs. prior week|month|6 months`, skin temp uses the absolute difference `+0.1 °C vs. prior week`), range selector and range navigation right.
3. Summary sentence (`body` `bodyText`, padding 24 top, 18 sides), §9.5.
4. Typical Range key row (padding 22 top, 18 sides, 6 bottom), only when the band shows.
5. Chart (§5.22), padding 0 × 10, 30 bottom.

States: current window loading → chart area shows the loading state; failed → chart area shows `Needs a connection to your Mac` (`bodyMid` `caution`) and a `TRY AGAIN` outline button; no values in the window → `No data in this range` and average `—`.

### 8.7 Health tab (`health-screen`)

`homeBackground`. Header: centred `HEALTH MONITOR` (`labelNav`), height 50; date control centred 4 pt below (same control and `selectedDate` as Home).

Content, side margins 16:

1. Status card (§5.24) for `D.vitals`.
2. Health flags (when `D.health_flags` is non-empty): banners (§5.26, not dismissible), 12 pt below the status card, in API order: attention → `heart` `caution`; info → `info.circle` `iconMuted`. Text = flag `message`.
3. `Overnight Vitals` heading (30 top, inset 4) with, on the right, `Synced {HH:mm}` (`bodySmall` 12 pt `iconMuted`) from `S.freshness.device_last_sync_at`, only when `selectedDate == default_date` and the time is non-null.
4. Vital grid (§5.23) in this order: Respiratory Rate (`respiratory_rate`, unit `rpm`), Blood Oxygen (`spo2`, `%`), Resting HR (`resting_hr`, `bpm`), HRV (`hrv_rmssd`, `ms`), Skin Temp (`skin_temp_deviation`, `°C`).
5. `VIEW TRENDS` outline button, 14 pt top (identifier `view-trends`).
6. `More Health Data` heading (30 top, inset 4), then two monitor-style rows (min height 62, corner 12, tile fill, padding 16, label `labelCard` + value right):
   - `CARDIO FITNESS`: `D.vo2_max.value` 1 dp + ` ml/kg/min` (unit `unit` 13), with `estimated` appended in `bodySmall` `text2` when `estimated == true`; null → `Not available from your band yet` (`bodySmall` `text2`).
   - `IRREGULAR RHYTHM`: `S.status.user_resources.irn_profile`: `permission_missing` → `Needs permission`; `enrolled == true` → `Enrolled`; else `Not set up in Fitbit`. If a flag `irn_alert_recorded` exists, its message is already in the flags list.
7. Footer (`bodySmall` `text2`, 20 pt top): `ghoops shows estimates and your own ranges. It does not diagnose. Talk to a clinician about health concerns.`
8. Bottom margin for the tab bar.

### 8.8 More tab (`more-screen`, replaces `settings-screen`)

`homeBackground`. Header: centred `MORE` (`labelNav`), height 50. Sections, side margins 16, section title `labelCard` `iconMuted` with 26 pt above and 10 below, rows `controlFill` min height 48, corner 10, 8 pt apart, padding 14 horizontal, label `labelCard`, value right in `bodySmall` `textSoft` (multi-line allowed):

| Section | Rows |
| --- | --- |
| MAC | `PAIRED MAC` → `credentials.name` (fixture: `Fixture Mac`); `ADDRESS` → URL (text selectable); `LAST FETCH` → relative phone-copy age; `TEST CONNECTION` (button; result shown as the value, identifier `connection-result`); `UNPAIR` outline button (§5.25), confirmation dialog "Unpair from your Mac?" with a destructive `Unpair`. |
| BAND | `S.status.device`: `scope_missing` → one row `Band details need permission: run ghoops auth login on your Mac` (`caution`); otherwise `NAME` → name or `Unavailable`; `BATTERY` → `NN% · {battery_status}` or `—`; `LAST SYNCED` → `Last synced to Fitbit {relative}` or `Band sync time unavailable`. |
| DATA COLLECTION | `LAST COLLECTED` → relative `collected_at` or `never`; `STATUS` → `last_collect_status`; `SCHEDULE` → `Installed` / `Not installed`; `CALIBRATION` → `status.calibration.status` capitalised; missing scopes → `Run ghoops auth login on your Mac to grant: …` (`caution`). |
| SCORES | `SCORE VERSION`, `MAX HR OVERRIDE` (`N bpm` or `Default`), `SLEEP BASE NEED` (`h:mm`), `TRIMP PROFILE`; caption `Change these with ghoops config set on your Mac`. |
| ABOUT | `VERSION` → `CFBundleShortVersionString`; text `Data stays on your Mac and this iPhone. ghoops is not a medical device.`; `OPEN-SOURCE FONTS` → `Sofia Sans Condensed and Nunito Sans, SIL Open Font License 1.1`. |
| DEVELOPER (DEBUG only) | `FIXTURE MODE` menu listing the sets (app.md §11). |

### 8.9 Activities list (sheet)

Title `TODAY'S ACTIVITIES` (or the date label for other dates). All rows of §5.9 for `selectedDate`, same order, same taps (a tap dismisses the sheet, then pushes on the Home stack).

### 8.10 Pairing (`pairing-screen`)

`homeBackground`, no tab bar. Centred column, side margins 24: `GoopMark` 72 pt white, 24 pt, `GoopWordmark(size: 40, color: #E9ECEE)`, 28 pt, `Pair with your Mac` (`heading`), 10 pt, `On the Mac, run ghoops pair, then scan the code with the Camera app, or paste the link below.` (`bodyMid` `text2`, centred), 24 pt, text field (min height 50, corner 12, `controlFill`, padding 14, `bodyMid`, placeholder `ghealth://pair?…` in `text3`, multi-line, accessibility label `Pairing link`), 12 pt, primary `PAIR` button (disabled at 40 % opacity while empty or busy; progress view inside while busy), 12 pt, error text (`bodyMid` `caution`). Pairing flow and messages unchanged (contract §8.4, app.md §4.9).

### 8.11 Info sheets

| Sheet | Opened by | Sections |
| --- | --- | --- |
| Recovery (`RECOVERY`) | Recovery info button, `BREAK DOWN MY RECOVERY` | **Breakdown**: rows for HRV, Resting HR, Sleep performance, Respiratory rate, Skin temperature: input value (or `not available`), `usual {baseline}` where a baseline exists, `z {z}`, component score `{score} of 100` and weight (55 %, 20 %, 25 %), penalty `−{p} points` or `no effect`. **Calibration** (as §8.2 item 4 text). **How this works**: the existing paragraph (app.md §4.2 item 5) with the product name `ghoops`, band ranges `High 67–100 · Medium 34–66 · Low 0–33`, the comparison note (§14.6), `Score version {score_version}`. |
| Strain (`DAY STRAIN`) | Strain info button, `EXPLORE MY STRAIN` | **Coverage**: `Based on {pct}% of the day's heart rate` + `until {HH:mm}` for open cycles, `Low data` when confidence is low; cycle line (`Since you woke at HH:mm` / `Since about HH:mm (no sleep recorded)`). **Zones**: six rows Zone 5…0 minutes. **Heart rate**: `Max HR {M} ({source})`, `Resting {R} ({source})` with app.md §4.3 source words. **How this works**: strain is a 0–21 log scale of TRIMP over the cycle; band ranges; comparison note; score version. |
| Sleep (`SLEEP`) | Sleep info button, Hours vs. Needed info, `DIVE INTO MY SLEEP` | **Need**: `Baseline 7:30 + strain 0:06 + debt 0:16 − naps 0:28 = 7:24 needed`. **Night**: Time in bed, Efficiency, Fell asleep in (`N min`), Disturbances (`total` with `awake_segments awake · short_awakenings short`), Bedtime, Wake time. **Breathing**: full / deep / light / REM rpm (1 dp) when `respiratory_rate` is non-null. **Overnight HRV**: a small line chart (§5.22 line style, height 120) of `overnight_hrv`. **Naps**: `HH:mm–HH:mm · h:mm asleep`. **How this works**: performance = asleep ÷ need (capped at 100); level thresholds (§9.4); `Awake % is a share of time in bed; the other stages are shares of time asleep.`; typical ranges note (§14.6); score version. |

When a sleep plan is present, the Sleep sheet’s Need section uses `SleepPlanText.needLines`: last night, tonight, efficiency, three goal lines and wake source, or the unavailable sentence. The Tonight info button also opens it. With no plan the existing single line remains. Exact copy and ordering: [parity1-spec §2.5 and §4.3](parity1-spec.md#25-sleep-info-sheet-sleep-info).

## 9. Rules and copy

All rule outputs are fixed sentences from these tables; placeholders are filled with §4 formatting. Implement in `GHealthCore/Presentation/Insights.swift` with unit tests for every row.

### 9.1 Recovery insight

When `value` is null: one sentence = the reason text (app.md §7.1) + `.` Example: `Waiting for last night's sleep.` For `insufficient_baseline`: `Recovery is calibrating: {N} of 7 nights so far. It starts once ghoops has 7 nights of your HRV and resting heart rate.`

Otherwise three parts joined by a space:

**Part 1** by HRV direction (`components.hrv_z`: ≥ 0.5 above, ≤ −0.5 below, else near) and resting HR direction (`components.resting_hr_z`: ≥ 0.5 elevated, ≤ −0.5 low, else near):

| HRV \ RHR | elevated | near | low |
| --- | --- | --- | --- |
| above | `Your HRV is above baseline while your resting heart rate is elevated.` | `Your HRV is above baseline and your resting heart rate is near baseline.` | `Your HRV is above baseline and your resting heart rate is lower than usual.` |
| near | `Your HRV is near baseline while your resting heart rate is elevated.` | `Your HRV and resting heart rate are both near baseline.` | `Your HRV is near baseline and your resting heart rate is lower than usual.` |
| below | `Your HRV is below baseline and your resting heart rate is elevated.` | `Your HRV is below baseline while your resting heart rate is near baseline.` | `Your HRV is below baseline while your resting heart rate is lower than usual.` |

**Part 2** (zero, one or two sentences): `respiratory_rate_penalty > 0` → `A raised breathing rate overnight took {p} points off.`; `skin_temp_penalty > 0` → `A raised skin temperature overnight took {p} points off.` (`p` 1 dp).

**Part 3** by band: high `Recovery is high today.`, medium `Recovery is medium today.`, low `Recovery is low today.`; when `calibrating` append ` It is still calibrating.`

### 9.2 Strain insight

Prepend the target sentence and position sentence from [parity1-spec §4.1](parity1-spec.md#41-strain-target-sentence-insights), including the pending or unavailable copy. Pass `target` and `recoveryBand` to `Insights.strain`; nil target keeps the text below. The target sentence comes first even when strain is null.

Null value: reason text + `.`

Otherwise:

1. Band sentence: light `Strain under 10.0 is considered light.`; moderate `Strain between 10.0 and 13.9 is considered moderate.`; strenuous `Strain between 14.0 and 17.9 is considered strenuous.`; all_out `Strain of 18.0 or more is considered all out.`
2. Workout sentence, when the day has a workout with strain ≥ 10.0: take the one with the highest strain; `Your heart worked hardest during {name} this {part}.` with `name` = `display_name` in lower case, or `a detected effort`; `part` from the London start hour: 05–11 `morning`, 12–16 `afternoon`, 17–21 `evening`, else `night`. When `selectedDate` is not `default_date`, replace `this {part}` with `in the {part}`.
3. Coverage sentence, when `hr_coverage < 0.80`: `This is based on {pct}% of the day's heart rate.`
4. In progress: `Strain keeps building until you sleep.`

### 9.3 Sleep insight

No main sleep: reason text + `.` + ` Tonight's need so far is {need}.`

Otherwise, by Hours vs. Needed level:

| Level | Sentence 1 |
| --- | --- |
| Optimal | `Your Sleep Performance is optimal. You got {asleep} of the {need} you needed.` |
| Sufficient | `Your Sleep Performance is sufficient. You were {short} short of the {need} you needed.` |
| Poor | `Your Sleep Performance is poor. You were {short} short of the {need} you needed.` |

`short = need.total_minutes − asleep_minutes` (`h:mm`). Then append, in order and only when > 0: ` Recent short nights added {debt_extra} to your need.` and ` Yesterday's strain added {strain_extra}.`

### 9.4 Sleep levels (ghoops rules)

| Contributor | Poor | Sufficient | Optimal | Source |
| --- | --- | --- | --- | --- |
| Hours vs. Needed | < 70 | 70–84 | ≥ 85 | `performance.value` (same cut-offs as the API band) |
| Sleep Consistency | < 60 | 60–79 | ≥ 80 | `consistency.value` (same as the API band) |
| Sleep Efficiency | < 85 | 85–89 | ≥ 90 | `efficiency_pct` (ghoops rule; 85 % is the common clinical cut-off for adequate efficiency) |

Null value → no level, all segments off.

### 9.5 Trend summary sentence

`N` = window length (7, 30, 180), `A` = available days, `avg` = window mean (display precision, with unit as in the average block), `name` = metric name in lower case except `HRV` and `REM` (so "HRV", "resting heart rate", "day strain").

| Condition | Sentence |
| --- | --- |
| `A == 0` | `No {name} data in these {N} days.` |
| band shown, `lo ≤ avg ≤ hi` | `Your average {name} over these {N} days was within its typical range ({lo} - {hi}).` |
| band shown, `avg > hi` | `Your average {name} over these {N} days was above its typical range ({lo} - {hi}).` |
| band shown, `avg < lo` | `Your average {name} over these {N} days was below its typical range ({lo} - {hi}).` |
| otherwise | `Your average {name} over these {N} days was {avg}.` |

When `0 < A < N` append ` {A} of {N} days have data.`

## 10. States

### 10.1 State matrix

| State (fixture set) | Home | Recovery | Strain | Sleep | Workout | Trend | Health | More | Widgets |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Fresh (`fresh`) | full | full | full, `SO FAR` | full | full | W from snapshot; M prior and 6M fail → chip hidden / offline message | full | full | full |
| Stale (`stale`) | banners: Mac and band (§10.2); phone age 6 h → values dimmed | dimmed | dimmed | dimmed | dimmed | as fresh | dimmed, Synced time shows the old time | ages shown | dimmed + clock + age |
| No sleep (`no_sleep`) | Sleep and Recovery dials `—` with `Waiting for last night's sleep`; no sleep row | dial `—`, rows show what exists, insight = reason | normal | dial `—`, rows `—` with segments off, insight §9.3 no-sleep, sleep card replaced by placeholder `No sleep recorded for this night` (pending: `Waiting for last night's sleep`), need card in "so far" form | n/a | normal | vitals as available | normal | Sleep and Recovery `—` |
| Calibrating (`calibrating`) | Recovery value + `Calibrating` caption | `CALIBRATING` dial line, calibration card | normal | normal | normal | normal | normal | normal | value shown |
| New user (`new_user`) | Recovery `—` `Calibrating: 3 of 7 nights`; no battery; comparisons hidden | calibration card | normal | typical boxes hidden (nulls) | normal | normal | `Building baseline` chips | permission rows | normal |
| Offline (`offline`) | banner `Offline. Showing your saved data.`; phone age 2 days → dimmed | dimmed | dimmed | dimmed | dimmed | fetches fail → offline message | dimmed | `TEST CONNECTION` shows the offline text | dimmed + clock |
| Unpaired (`unpaired`) | Pairing screen only | — | — | — | — | — | — | — | `Open ghoops to pair` |
| Paired, no cache | full-screen `No data yet` (§14.5) with `TRY AGAIN` | — | — | — | — | — | same | normal | `No data yet` |
| Other date failed | full-screen offline-day state | card placeholders | same | same | not reachable | normal | full-screen offline-day state under the header | — | — |

### 10.2 Banners (Home only, order top to bottom)

| Condition | Symbol | Text | Dismissible |
| --- | --- | --- | --- |
| each `D.health_flags` entry with severity `attention` | `heart` `caution` | flag `message` | yes (session) |
| `model.error` non-null (fetch failed) | `arrow.clockwise` `caution` | the error text (fixture `offline`: `Offline. Showing your saved data.`) | yes |
| phone copy older than 2 h | `clock` `caution` | `Updated {relative}` where `{relative}` is the existing `Format.relative(fetched_at, now:)` output (for example `Updated 6 hr ago`) | no |
| `S.freshness.collector_stale` | `arrow.clockwise` `caution` | `Your Mac last collected data {relative}` | yes |
| `device_stale == true` and source ≠ `scope_missing` | `arrow.clockwise` `caution` | `Your band last synced {relative}. Open the Fitbit app to sync.` | yes |

The phone-copy age replaces the old always-visible freshness pill (**decision**, §17): under 2 h nothing shows; over 2 h a banner shows; the exact age is always in More → Mac → Last fetch.

Banners use the snapshot's freshness even when another date is selected.

### 10.3 Full-screen texts

| State | Title | Text | Button |
| --- | --- | --- | --- |
| Paired, no cache | `No data yet` | `Connect to your Mac to fetch your first snapshot.` + error text on a new line when present | `TRY AGAIN` → refresh |
| Other date failed | `Needs a connection to your Mac` | `Days other than today load from your Mac.` | `BACK TO TODAY` → `selectedDate = default_date` |

## 11. Widgets

Kinds and families keep their IDs. Timeline, refresh and cache rules are unchanged (app.md §10 items 1 to 3, 6). Every widget uses fixed type sizes (`.dynamicTypeSize(.large)` on the entry view) and the ghoops fonts.

### 11.1 Shared data rules

- Values from `snapshot.day` only (never another date).
- `stale` = phone copy older than 6 h, `collector_stale`, a band sync the Mac marks stale (`device_stale`, unless its scope is missing), or a missed refresh after a possible wake (below). Stale → rings and values at 55 % opacity and a `clock` glyph.
- The age beside the clock counts from the health data, not the download: the older of the Mac's last collection and the band's last sync.
- **After a possible wake** (issue #32): a refresh is overdue (the phone copy is older than the widget's 30-minute refresh) and the calendar date is past the scores' day. The scores may be the previous day's, so the age badge and the medium header give the scores' day (`Tue 10`). The circular Lock Screen face shows `—`, the rectangular adds the day after its clock, and the inline reads `Scores from Tue 10`. Spoken labels add `from <Tuesday 10 March>`, or `as of <HH:mm>` for other stale readings. A pre-wake download stays current until a refresh is missed.
- Messages: unpaired `Open ghoops to pair`; no cache `No data yet`; shown centred in `bodyMid` `text2`, with `GoopMark` 28 pt above at 40 % (Home Screen widgets only).

### 11.2 `ScoresWidget` small, single metric (`metric` = recovery, strain, sleep or hrv)

Container `widgetFill`. Centred column: ScoreRing `widgetSmall` (100) containing `GoopWordmark(size: 14, color: #8D9499)`, 3 pt, ScoreText `scoreWidgetSmall`; 9 pt; label `labelWidget` (`RECOVERY`, `STRAIN`, `SLEEP`). When stale: `clock` 10 pt `caution` + the data's age (`now`, `12m`, `3h`) or, after a possible wake, the scores' day (`Tue 10`), in N550 10 `text2`, top-right inset 10.

With `metric = hrv`, use `HRVSmallView`: no ring, wordmark, integer ms value, typical-range/status chip, HRV label and the existing stale indicator. Exact layout, chip states and accessibility: [parity1-spec §2.7](parity1-spec.md#27-small-hrv-widget-hrv-widget). Medium ignores the metric as before.

### 11.3 `ScoresWidget` small, all three (`metric` = all) (new intent option)

`ScoreMetric` gains a case `all` (display "Sleep, Recovery, Strain"); default stays `recovery`. Padding 16; three rows spaced evenly, each: ScoreRing `widgetList` (30, no text inside) + 10 pt + label `labelWidgetSmall` (flexible) + value `valueWidgetList` (`88%`, `64%`, `12.8`, or `—`). Order Sleep, Recovery, Strain. Stale: `clock` 10 pt after the Strain value row as a fourth line with the age, right-aligned.

### 11.4 `ScoresWidget` medium

Padding 14 top, 16 sides, 12 bottom. Top row: `GoopWordmark(size: 14, color: #C4C8CB)` left; right text N550 10.5 `iconMuted`: `{HH:mm of the data, or the scores' day after a possible wake} · {battery}%` (battery part omitted when null; stale adds a `clock` glyph before the time). 10 pt below, three columns `.spaceAround`: ScoreRing `widgetMedium` (76) with ScoreText `scoreWidgetMedium`, 7 pt, label `labelWidgetSmall`. Order Sleep, Recovery, Strain.

### 11.5 `LockScoresWidget`

`LockScoresIntent` gains `@Parameter(title: "Score", default: .recovery) var metric: LockScoreMetric`, a new AppEnum with cases `recovery`, `strain`, `sleep`, `hrv` (no `all`). `selectedMetric` maps it to `ScoreMetric`.

- **Circular:** `AccessoryWidgetBackground()`; ScoreRing `lock` in white (`widgetAccentable()`), track white 25 %; centre: value `valueLock` (`88`, `64`, `12.8`; no `%`) and caption `labelLock` at 80 % opacity (`SLEEP`, `REC`, `STRAIN`). Stale: 55 % opacity. After a possible wake: `—` and an empty ring.
- **Rectangular:** three lines, each label N750 11 (tracking 0.08 em, uppercase) + value S 15 right-aligned: `SLEEP 88%`, `RECOVERY 64%`, `STRAIN 12.8`; stale: `clock` 10 pt after the first line, followed after a possible wake by the scores' day in `captionWidget`.
- **Inline:** system font only (iOS ignores custom fonts): `Sleep 88% · Rec 64% · Strain 12.8`, with `clock` symbol prefix when stale. After a possible wake: `Scores from Tue 10`.

Circular HRV shows its integer value and HRV caption without a ring. Rectangular adds `extraLine` (`None`, `HRV`, `Bed by`; default `None`) and retains the installed three-line layout for None. HRV or Bed by adds a fourth equal-height row. BED BY uses the 100% bedtime only while the plan is ok and the entry precedes its wake target; otherwise `—`. The editor shows Score for circular/inline and Extra line for rectangular. Exact layout and accessibility: [parity1-spec §2.6](parity1-spec.md#26-lock-screen-widgets-lock).

Lock Screen views use no custom colours (vibrant rendering).

### 11.6 Widget preview host (DEBUG)

`-GHealthWidgetPreview <set>` renders, on the `widgetWallpaper` gradient, top to bottom: title `Widgets · {set}` (`heading`), a row of two smalls (recovery single, all-three list) each 170×170, the medium 364×170, a large clock `9:41` (N600 64 white 88 %), a row of three circulars (sleep, recovery, strain) each 76×76, the rectangular 172×76, the inline 257×26, then the parity section (small HRV and rectangular Bed by/HRV plus circular HRV), and the `font-check` text (§2.1) in `bodySmall`. The section’s fixtures, identifiers and ordering are in [parity1-spec §10.2](parity1-spec.md#102-debug-launch-arguments). Widget frames use corner 22 and `widgetFill`. Accessibility identifier `widget-preview` on the scroll view.

## 12. Accessibility

### 12.1 VoiceOver

| Element | Label | Value / hint | Traits |
| --- | --- | --- | --- |
| Home dial | `Recovery, 73 percent, high` / `Strain, 12.8 of 21, moderate, so far` / `Sleep, 93 percent` (null: `Recovery, no data`) — the exact format the current UI test asserts | hint: status caption text if any | button |
| Detail dial | same label | — | header-less static |
| Date control pill | `Showing today` / `Showing Monday 9 March` | hint `Double-tap to return to today` when not today | button |
| Monitor card | `Health monitor, within range, 5 of 5 metrics` / `Day heart rate, average 80 beats per minute, peak 174` | — | button |
| Activity row | `Sleep, 7 hours 17 minutes in bed, 23:12 to 06:29` / `Kickboxing, strain 12.8, 12:00 to 13:00` / `Detected effort, strain 10.4, …` / `Nap, 30 minutes, 15:10 to 15:40` | — | button (not for naps) |
| Tile / contributor row | `{Name}, {value spoken}, {up|down|same} versus prior 30 days average {mean}` (omit the comparison when hidden; sleep rows: `, {level}`) | hint: MetricStatus text when not available | button |
| Comparison triangles and dots | hidden (folded into the row label) | | |
| Insight card | the full sentence; action `Break down my recovery` etc. | | static + button |
| Stage row | `Light, 52 percent, 3 hours 34 minutes, typical 3:16 to 3:52` | | button, selected |
| Weekly / trend / sleep / workout charts | chart title | `accessibilityChartDescriptor` | |
| Vital tile | `Respiratory rate, 15.2 breaths per minute, above typical range 14.2 to 15.0` | | button |
| Tab item | `Home` etc. | | button, selected |
| Decorative logo, swatches, hatch, dividers | hidden | | |

Uppercase strings are displayed; labels are spoken in normal case (pass `accessibilityLabel` in sentence case).

### 12.2 Dynamic Type

- Implementation: a `GoopTextStyle` view modifier reads `@Environment(\.dynamicTypeSize)`, gets the scale `UIFontMetrics(forTextStyle: .body).scaledValue(for: 1, compatibleWith: UITraitCollection(preferredContentSizeCategory: …))` and builds the font at `size × min(scale, cap)`; tracking scales with the size.
- Caps by the style's Dynamic Type column in §3.3: `labels` 1.5, `text` 1.6, `values` 1.35, `fixed` 1.0 (scores inside rings, chart text, tab labels, widgets).
- Rows and tiles have minimum heights and grow. Labels wrap to 2 lines (then truncate tail).
- At accessibility sizes (`dynamicTypeSize.isAccessibilitySize`): monitor cards stack in one column; the vital grid becomes one column; contributor rows and tiles put the value block under the label (left-aligned); activity rows hide the times column (times stay in the label); the trend summary row stacks (average block, then selector, then navigation).
- UI test `testAccessibilityTour` (largest size) must show no truncated score and no overlapping text on Home, Sleep and Trend screenshots (checked by eye in plan step T1).

### 12.3 Other

- Hit targets ≥ 44×44 for every button (pad invisible areas).
- Colour is never the only signal: levels have segment positions and info-sheet text, recovery bands are spoken, chips carry symbols.
- Reduce Motion: no ring animation, no chart animation.
- Contrast: `text2` on the darkest backgrounds is ≥ 4.5:1; `text3` is only used for inactive tab labels and placeholders.

## 13. Backend change (contract additions, schema 2, additive)

All additions are new keys; consumers ignore unknown keys (contract §1.2), so `schema_version` stays 2 and `score_version` stays `2.0.0` (no score changes). The Swift models decode every new key as optional so the app also works against an older server (it then hides comparisons and typical ranges).

### 13.1 `stage_typical` in the sleep summary

Added to the sleep summary object, so it appears in `day.sleep` and at the top level of the `sleep` body (contract §5.5). Always present.

```json
"stage_typical": {
  "window_nights": 30,
  "nights_used": 27,
  "light":       { "low_minutes": 196, "high_minutes": 232, "nights_used": 27 },
  "deep":        { "low_minutes": 74,  "high_minutes": 96,  "nights_used": 27 },
  "rem":         { "low_minutes": 92,  "high_minutes": 121, "nights_used": 27 },
  "awake":       { "low_minutes": 18,  "high_minutes": 34,  "nights_used": 27 },
  "restorative": { "low_minutes": 170, "high_minutes": 214, "nights_used": 27 }
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `window_nights` | int | `StageTypicalNights` (30) |
| `nights_used` | int | number of London dates `D−30 … D−1` (D excluded) whose main sleep (scores.md §4.1) exists and has session `type == "STAGES"` |
| `<stage>.nights_used` | int | of those nights, how many have a non-null `stages.<stage>.minutes` (restorative: both `deep` and `rem` non-null; value = their sum) |
| `<stage>.low_minutes`, `.high_minutes` | `int?` | the 25th and 75th percentiles of those values, rounded half away from zero; null when `<stage>.nights_used < StageTypicalMinNights` (7) |

Percentile (same as numpy `linear`, R type 7): sort ascending `v[0…n−1]`; `pos = q·(n−1)`; `i = floor(pos)`; `f = pos − i`; result `v[i] + f·(v[i+1] − v[i])` (when `i + 1 = n`, `v[i]`). Compute at full precision, round once.

Classic sessions and nights without a main sleep are excluded. Values are computed from the store at request time, like every score.

### 13.2 `comparison` in `day`

New key in the `day` body (and therefore `snapshot.day`), after `health_flags`. Always present.

```json
"comparison": {
  "window_days": 30,
  "from": "2026-02-08",
  "to": "2026-03-09",
  "min_days": 7,
  "metrics": {
    "recovery": { "mean": 61.4, "available_days": 27 },
    "...": {}
  }
}
```

| Field | Type | Rule |
| --- | --- | --- |
| `window_days` | int | `ComparisonDays` (30) |
| `from`, `to` | Date | `D − 30`, `D − 1` |
| `min_days` | int | `ComparisonMinDays` (7) |
| `metrics.<key>` | object | `{mean: num?, available_days: int}` for each key below, in this order: `recovery`, `strain`, `sleep_performance`, `asleep_minutes`, `efficiency_pct`, `restorative_minutes`, `hrv_rmssd_ms`, `resting_hr_bpm`, `respiratory_rate_bpm`, `spo2_pct`, `skin_temp_deviation_c`, `steps`, `zones_1_3_minutes`, `zones_4_5_minutes`, `strength_minutes` |
| `mean` | `num?` | arithmetic mean of the non-null `days`-row values of that key for `from … to` (§13.3 defines the new row keys), 1 decimal (`steps`: 0 decimals; `skin_temp_deviation_c`: 2 decimals); null when `available_days < min_days` |
| `available_days` | int | count of non-null row values in the window |

Use a Go struct (not a map) so key order is stable.

### 13.3 New `days` row fields

Added to every row of the `days` body (contract §5.10). `summary` is unchanged.

| Field | Type | Rule |
| --- | --- | --- |
| `zones_1_3_minutes` | `int?` | `z1 + z2 + z3` of that date's `strain.zones_minutes`; null when `zones_minutes` is null |
| `zones_4_5_minutes` | `int?` | `z4 + z5`; null likewise |
| `strength_minutes` | `int?` | §13.4 |
| `restorative_minutes` | `int?` | `stages.deep.minutes + stages.rem.minutes` of that date's sleep summary; null when `stages` is null or either is null |
| `sleep_consistency` | `int?` | that date's `sleep.consistency.value` |

### 13.4 `strength_minutes` in `day`

New key in `day` after `workouts`: `int?`, and the same value in the `days` row.

- Sum of `elapsed_minutes` of the **recorded** workouts of cycle D with `category == "strength"`, rounded half away from zero to an integer.
- When there are none: `0` if `MissingStatus(D, "exercise", "list") == "missing"` (the exercise stream was collected successfully for D and had nothing), otherwise null (not collected, permission missing or unavailable).
- Detected efforts never count (they have no category). This is a duration; it is not a measure of muscular load.

### 13.5 Go implementation notes

- Constants in `internal/score/constants.go`: `StageTypicalNights = 30`, `StageTypicalMinNights = 7`, `StageTypicalLowQuantile = 0.25`, `StageTypicalHighQuantile = 0.75`, `ComparisonDays = 30`, `ComparisonMinDays = 7`.
- `score.SleepSummary` gets `StageTypical StageTypical \`json:"stage_typical"\``; computed in `Engine.Sleep` (it needs the main sleep of each window night; reuse `e.main` and `strings.ToLower` stage keys as the stages block does).
- `v2report`: split row building out of `Builder.Days` into `func (b *Builder) row(date string) DayRow` that builds the row from the engine without computing `comparison`. `Builder.Day` computes `comparison` from `b.row` for the 30 window dates. `Builder.Days` uses `b.row`. This avoids `Day → comparison → Days → Day` recursion.
- Cost: a snapshot builds 30 rows for `days` and 30 more for `day.comparison`. Add a test that `Build("snapshot")` on `store_full` finishes in under 2 s on the CI machine.
- `brief` is unchanged (no new keys).

### 13.6 Docs

Plan step B1 copies §13.1 to §13.4 into `docs/v2/contract.md` (§5.4 for `strength_minutes`, §5.5 for `stage_typical`, a new §5.2.1 for `comparison`, §5.10 for the row fields) and adds `docs/v2/scores.md` §4.10 "Typical stage ranges (display only)" and §11a "Comparison windows (display only)", stating that these constants do not change `score_version` because no score uses them.

### 13.7 Fixtures

1. **Goldens** (`fixtures/v2/day_*.json`, `sleep_*.json`, `days_full.json`; also `brief_*` must be unchanged): add a `-update-goldens` flag to `TestGoldenResponses` in `internal/v2report/report_test.go` that writes the built body with `json.MarshalIndent(v, "", "  ")` plus a trailing newline (the current file format). Run it once, then check with `git diff --stat` and `git diff` that only new keys appear. Commit the regenerated files.
2. **Preview fixtures** (`fixtures/v2/preview/snapshot_fresh.json`, `snapshot_stale.json`, `days_30.json`): they come from an uncommitted store, so a new committed script `scripts/goop_preview_fixtures.py` (stdlib only, run with `python3 -I`, idempotent: running twice changes nothing) adds the new keys:
   - Rows, for each row at index `i` (0 = oldest) of every `days` body in these files:
     - `zones_1_3_minutes`: null if `strain` is null, else `round(strain × 2.2)`; `zones_4_5_minutes`: null if `strain` is null, else `round(max(0, strain − 6) × 2.4)`.
     - `strength_minutes`: `45` on `2026-02-12` and `2026-02-19`, else `0`.
     - `restorative_minutes`: null if `asleep_minutes` is null, else `round(asleep_minutes × 0.46)`.
     - `sleep_consistency`: null if `sleep_performance` is null, else `70 + (i × 7) % 25`.
     - The `default_date` row (2026-03-10) takes its values from the snapshot's own `day`: zones from `day.strain.zones_minutes` (27 and 33), `strength_minutes` 0, `restorative_minutes` = deep + rem (201), `sleep_consistency` = `day.sleep.consistency.value` (87).
   - `day.strength_minutes` = 0.
   - `day.comparison`: computed by the §13.2 rule from the file's own `days` rows for `2026-02-08 … 2026-03-09` (29 rows exist; the missing 02-08 counts as null).
   - `day.sleep.stage_typical` and `sleep.stage_typical`: exactly the JSON example in §13.1.
   - Keys are inserted in the positions §13 gives; the script writes with `indent=2`, `ensure_ascii=False` and a trailing newline, preserving every existing key and value.
   - Add `scripts/goop_preview_fixtures_test.py` (stdlib `unittest`): running the script on a copy is idempotent, `TestFixtureBodiesPreserveEveryKey` still passes, and the three files decode in `GHealthCore` tests.
3. `fixtures/v2/README.md`: one paragraph naming the script and the new keys.

### 13.8 Go tests

- `internal/score`: percentile function table test (n = 1, 2, 7, 8; values with ties); `stage_typical` with 6 and 7 eligible nights (null vs. values); a CLASSIC night is excluded; D itself is excluded.
- `internal/v2report`: `comparison` window dates for D = 2026-03-10; `min_days` boundary (6 vs. 7 values); `strength_minutes` = null when exercise coverage is missing, 0 when coverage is ok and empty, sum when a `WEIGHTLIFTING` workout exists (synthetic records via `testutil.Record`); row fields equal the day values for the same date; snapshot build time test.
- Goldens as §13.7.

## 14. Copy tables

Parity target, planner, widget and suggestion copy is fixed by [parity1-spec §4](parity1-spec.md#4-copy).

### 14.1 Fixed labels

| Where | Text |
| --- | --- |
| Tabs | `Home`, `Health`, `Trends`, `More` |
| Home dial captions | `SLEEP`, `RECOVERY`, `STRAIN` |
| Monitor titles | `HEALTH` / `MONITOR`; `DAY HEART` / `RATE` |
| Home headings | `My Day`, `My Dashboard` |
| Activities header | `TODAY'S ACTIVITIES` (other dates: `ACTIVITIES`) |
| Detail inner labels | `RECOVERY`; `DAY STRAIN` (+ `SO FAR`); `SLEEP` / `PERFORMANCE` |
| Legend | `Today` `vs. prior 30 days`; `Poor`, `Sufficient`, `Optimal` |
| Insight actions | `BREAK DOWN MY RECOVERY`, `EXPLORE MY STRAIN`, `DIVE INTO MY SLEEP` |
| Detail headings | `Weekly Trends`, `Last Night's Sleep` (other dates: `Sleep`) |
| Sleep card | `TYPICAL RANGE`, `DURATION`, `AWAKE`, `LIGHT`, `SWS (DEEP)`, `REM`, `RESTORATIVE SLEEP` |
| Need card | `HOURS VS. NEEDED`, `HOURS OF SLEEP`, `SLEEP NEEDED`, `Baseline Need`, `Recent Strain`, `Sleep Debt`, `Nap Credit`; no sleep: `TONIGHT'S NEED SO FAR` |
| Workout | `ACTIVITY STRAIN`, `AVERAGE HR`, `MAX HR`, `DURATION`, `ZONE 0` … `ZONE 5`, `BPM` |
| Trend | `TREND VIEW`, `TRENDS`, `AVERAGE`, `W`, `M`, `6M`, `TYPICAL RANGE`, chip suffixes `vs. prior week`, `vs. prior month`, `vs. prior 6 months` |
| Health | `HEALTH MONITOR`, `Overnight Vitals`, `Synced {HH:mm}`, `RESPIRATORY RATE`, `BLOOD OXYGEN`, `RESTING HR`, `HRV`, `SKIN TEMP`, `VIEW TRENDS`, `More Health Data`, `CARDIO FITNESS`, `IRREGULAR RHYTHM` |
| More | §8.8 |

### 14.2 Status texts

App.md §7.1 reason texts and §7.2 MetricStatus texts are unchanged, except that user-facing app copy names the app `ghoops` (`Not logged as a workout. ghoops found a stretch of high heart rate.`, `Open ghoops to pair`, footer and About texts). Texts that name the Mac CLI keep `ghoops`.

### 14.3 Placeholders

| Where | Text |
| --- | --- |
| Activities, none | `No activities yet` |
| Strain activities, none | `No workouts yet` |
| Sleep card, no main sleep | pending: `Waiting for last night's sleep`; otherwise `No sleep recorded for this night` |
| Weekly card or trend chart, fetch failed | `Needs a connection to your Mac` |
| Trend window empty | `No data in this range` |
| Workout HR | `No heart rate recorded for this workout` |
| Workout zones | `No heart-rate zones for this workout` |
| Cardio fitness | `Not available from your band yet` |
| Loading | `Loading from your Mac` |

### 14.4 Health status sentences

| Condition (§5.8 order) | Status | Sentence |
| --- | --- | --- |
| no ranges | `BUILDING BASELINE` | `ghoops needs 7 nights to learn your ranges.` |
| attention | `OUTSIDE RANGE` | `{within}/{n} overnight metrics in your typical range` |
| outside | `OUTSIDE RANGE` | `{within}/{n} overnight metrics in your typical range` |
| all within | `WITHIN RANGE` | `{within}/{n} overnight metrics in your typical range` |

### 14.5 Full-screen states

As §10.3.

### 14.6 Notes in info sheets

- Comparison note: `Arrows compare today with your average over the 30 days before it. Green and orange show the usual direction for that measure; they are not medical advice.`
- Typical ranges note: `Typical ranges are the middle half of your last 30 nights with sleep stages (shown after 7 such nights).`

## 15. Test identifiers and UI tests

Accessibility identifiers (use exactly): `today-screen`, `recovery-screen`, `strain-screen`, `sleep-screen`, `workout-screen`, `trend-view-screen`, `trends-screen`, `health-screen`, `more-screen`, `pairing-screen`, `widget-preview`, `sleep-link`, `recovery-link`, `strain-link`, `monitor-health-link`, `monitor-dayhr-link`, `sleep-activity-link`, `workout-link-<id>`, `activities-expand`, `tile-<key>`, `contributor-<key>`, `weekly-trend-<key>`, `insight-action`, `info-button`, `back-button`, `sheet-close`, `date-prev`, `date-label`, `date-next`, `tab-home`, `tab-health`, `tab-trends`, `tab-more`, `metric-picker`, `metric-<key>`, `range-W`, `range-M`, `range-6M`, `range-prev`, `range-label`, `range-next`, `stage-<stage>`, `hypnogram`, `vital-<key>`, `view-trends`, `connection-result`, `font-check`.

`GHealthUITests` is rewritten in plan step T1 (tours and assertions listed there). The Recovery dial label assertion (`Recovery, 73 percent, high`) stays.

## 16. Out of scope

Daily Outlook, coach, floating + and activity creation, Plan, Community, Journal, Stress Monitor, strain target, dashboard customisation, Live Activities, light mode, landscape, GPS maps, any write to Google or the Mac.

Sleep editing left this list on 2026-11-19: [sleep-edit-spec.md](sleep-edit-spec.md) (issue #31) specifies it. Edits stay on the Mac, so "any write to Google" still holds.

## 17. Decisions made in this spec (not specified by the owner)

| # | Decision | Why |
| --- | --- | --- |
| 1 | Backend adds `day.comparison` (30-day prior means), `day.strength_minutes` and five `days` row fields (zones 1–3, zones 4–5, strength, restorative, consistency), beyond the requested `stage_typical`. | The mocked "vs. prior 30 days" numbers need 30 prior days; the snapshot carries 29, and zones and strength time are not in any history field. Server-side means keep the app from computing over partial data. |
| 2 | `stage_typical` = 25th–75th percentile of the prior 30 nights with stages, shown after 7 nights; also a `restorative` range. | A middle-half range is robust to odd nights; 7 matches the baseline minimum. |
| 3 | Comparison means need ≥ 7 values. | Matches baseline minimum; avoids arrows from one or two days. |
| 4 | Sleep Efficiency levels: Poor < 85, Sufficient 85–89, Optimal ≥ 90. Hours vs. Needed and Consistency reuse the API bands. | Owner asked for explicit thresholds; reusing API bands keeps one meaning per score. |
| 5 | Awake % uses time in bed as denominator; other stages use `pct_of_asleep`. | Contract gives no awake % of asleep; the mock shows one. |
| 6 | The sleep activity row and the sleep card's DURATION show time in bed; Hours of Sleep shows asleep time. | "Duration" of a sleep is its interval; matches the mockup where 23:14–06:52 = 7:38. |
| 7 | Date control navigates real days (fetching `/v2/day`, `/v2/sleep`, `/v2/workouts`), back to `status.store.oldest_date`; Health tab shares the date. | A visible control that does nothing would be a fake; the API already supports dates. |
| 8 | Avatar opens the More tab; battery shows `status.device.battery_level`. | No profile data exists; More holds settings. |
| 9 | Freshness pill replaced by a banner after 2 h; exact age in More. | The mockup header has no pill; staleness is still shown when it matters. |
| 10 | `SO FAR` second line on the Strain dial when in progress (**Deviation** from the mockup). | contract §10 requires "so far" for `in_progress`. |
| 11 | Trend direction uses `arrowtriangle.up.fill` / `.down.fill`, and the no-change dot uses `circle.fill`, instead of the table's `arrow.up` / `arrow.down`. | Matches the approved mockup's triangles while staying SF Symbols (no drawn icons). |
| 12 | Symbols not in the research table but in the approved mockup: `person.crop.circle.fill`, `arrow.right`, `chevron.down`, `battery.*percent`. Added for roles the table lacks: `clock` for category `other`, `heart` for detected efforts and attention flags, `arrow.clockwise` and `clock` for stale banners. | Every icon stays an SF Symbol from the table or the approved mockup. |
| 13 | Health tab keeps flags, cardio fitness and IRN below the mocked content; band details move to More. | These facts existed in v2 and must not disappear; the mocked top of the screen is unchanged. |
| 14 | Trend windows: W = 7, M = 30, 6M = 180 days; comparison chip against the previous equal window; 6M draws monthly means. | Owner named W/M/6M; exact lengths were open. |
| 15 | Trend typical band only for vitals and only for windows ending today. | It is today's personal range; drawing it behind past windows would misstate it. |
| 16 | Workout chips compare with the mean of other loaded workouts of the same category. | No server comparison for workouts exists; this uses only shown data. |
| 17 | Insight sentences are fixed templates from z-scores, bands, levels and need parts (§9). | Owner asked for fixed wording from bands and values. |
| 18 | Ring caps are butt (flat), as in the approved mockup, not WHOOP's rounded-corner caps. | The mockup is the approval. |
| 19 | Display precision follows the mockup: HRV and SpO2 as integers, skin temperature 1 dp. | Matches the approved look; the API keeps full precision. |
| 20 | Backgrounds are fixed behind scrolling content. | Avoids a seam on overscroll. |
| 21 | Chart time labels use Sofia Sans Condensed (the mockup used DIN Alternate as a stand-in). | Only the two approved fonts ship. |
| 22 | Small widget "all three" is a new `metric` option on the existing `ScoresWidget`; Lock Screen circular gains a metric option. | Keeps widget kinds, so installed widgets keep working. |
| 23 | Medium widget top-right shows the fetch time and band battery. | The mockup shows "06:58 · 72%"; fetch time is the honest "as of". |
| 24 | Detail screens and the trend view hide the tab bar; root screens show it. | As in the mockup. |
| 25 | Stage rows are selectable and highlight that stage in the chart. | The mockup shows selection circles; they need a defined behaviour. |
| 26 | Release builds still strip fixtures; fonts ship in both app and widget bundles. | Unchanged privacy rule; widgets need the fonts. |
