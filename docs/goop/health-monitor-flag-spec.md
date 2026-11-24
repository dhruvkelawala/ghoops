# ghoops: Health Monitor attention rule (issue #26)

Status: draft, for lead review and the owner's approval of the mockup. Written 2026-11-18 against `main` at `8d5cfa8`; `internal/score` and `internal/v2report` are the same as at `installed-mac`. The mockup is [mockups/health-monitor-flag.html](mockups/health-monitor-flag.html), rendered per phone in `mockups/screens/health-flag-<key>.png`. No product code, golden, fixture or `score_version` changes with this document.

## 0. The rule in plain words

Each overnight vital still has a typical range. The range gets a little wider. It becomes your usual value plus or minus 1.25 of your usual spread, instead of 1. A vital outside its range on one night shows the grey triangle. The Health Monitor turns amber, and Home shows a banner, only when **the same two or more vitals are outside their range in the less favourable direction on two nights in a row**. Skin temperature counts as less favourable only when it runs warmer than usual.

Counted read-only on the owner's store (§4), the amber state drops from 20 of 35 days to 2 of 35, and the banner drops from 9 days to 2. On modelled data the banner fires on about 1 to 3 ordinary days in 100. It catches most clear illness-like changes within three nights (§5).

## 1. Decisions

This spec extends [scores.md](../v2/scores.md) §0, §5, §6, §9 and §11 and [contract.md](../v2/contract.md) §5.1.1 and §5.6. It overrides the colour rules in [spec.md](spec.md) §5.8 (Monitor card), §5.23 (vital tile and range chip) and §14.4 (Health status sentences), and in [parity1-spec.md](parity1-spec.md) §2.7 (small HRV widget) and §8.6 (`WidgetData.hrvAdverse`). In each of those, "key in `adverse`" becomes "key in `persistent` and `monitor_state` is `attention`". Where any of them disagrees with this spec, this spec wins. The build updates each document in the step that changes the behaviour it describes (§12).

Among the approved renders, the amber HRV sample in `mockups/screens/parity1-hrv-widget.png` now stands for an attention day. On a single night outside its range, the same widget shows the grey triangle. `health.png` and `home.png` show WITHIN RANGE and stay valid.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | The typical range becomes mean ± `VitalRangeSD` × `sd_eff`, with `VitalRangeSD = 1.25` (was 1). For HRV the range is still built in ln space. For skin temperature it is ± `VitalRangeSD` × max(Google's 30-day SD, 0.10). | A ±1 SD band leaves about a third of ordinary nights outside it for every vital. At 1.25 a vital sits outside on about one ordinary night in five, and the two-night rule (D3) stays sensitive (§5). |
| D2 | Skin temperature is less favourable only when it is **above** its range. Below its range it is outside, shown with a grey triangle, and never counts towards amber or the banner. | Illness raises skin temperature (Mason 2022; Oura's Symptom Radar notes). A cooler night is usually the room or the fit of the band. The owner's replay gives the same counts either way (§4), so this changes no count today and removes a source of noise later. |
| D3 | **Attention** means the same two or more vitals (`VitalAttentionMinVitals = 2`) are outside their range in the less favourable direction on each of the last two nights (`VitalAttentionNights = 2`): night D and night D−1. The `vitals_outside_range` flag fires on attention only, with a new message (§6.2). | Persistence costs a few points of sensitivity when nights are normal and holds up best when they are heavy-tailed, as the owner's may be (§4, §5). It matches NightSignal's "deviations in successive nights", Mishra's two-tier alarm and Apple's "two or more metrics" (§3). |
| D4 | The Mac classifies the card and the app reads the class. New `vitals.monitor_state` is `building`, `within`, `outside` or `attention`. New `vitals.persistent` lists the vitals in the two-night pattern. | engine-numbers D3: where the Mac classifies, the app never works it out again. The phone can't see last night's position from today's body. |
| D5 | On screen, amber means attention and nothing else. The card is amber only when `monitor_state` is `attention`, and a tile chip is amber only for a vital in `persistent` on such a day. One night outside shows grey, in either direction. Card words do not change. | Amber is the signal the owner must not learn to ignore (issue #26). The grey triangle and grey OUTSIDE RANGE already exist for favourable moves. |
| D6 | `score_constants` gains `vitals: {range_sd, attention_nights, attention_min_vitals}`. The app keeps no copy of these numbers. | AGENTS.md hard rule; engine-numbers D1. The VoiceOver phrase uses `attention_nights` (§9). |
| D7 | `score_version` becomes **`2.2.0`**. | Ranges, `adverse` (skin temperature), the flag condition and the flag message all change. scores.md §0 calls for a minor bump. Recovery, Strain and Sleep do not change. |
| D8 | Unchanged: `spo2_below_usual` (single night, 2 SD below), the irregular-rhythm flag and every other flag; the position classes `above`, `below`, `within` and `no_baseline`; the baseline rules of §1.3; the 7-value minimum for a range. | Out of scope. §13 asks whether the SpO2 flag should follow later. |

Rejected:
- **A wider single-night range, 1.5 or 2 SD, with today's "two or more" banner.** Even at 2 SD, two vitals were beyond their range on the same night on 3 of 35 days, against about 1 expected (§4). Modelled at an equal false-alarm rate, the single-night rule catches the fewest illness patterns once nights are heavy-tailed (§5.2).
- **A combined score across vitals** (sum of how far each vital sits on its less favourable side). It is the best rule when nights are perfectly normal, and the worst for a change in only two vitals, such as fever with fast breathing (§5.2). It is also the hardest to explain on screen, because the banner could fire while every tile shows a tick.
- **The two-night rule at 1 SD.** It catches the most, but fires on about 3 to 6 ordinary days in 100 modelled, above the target (§2).
- **The two-night rule at 1.5 SD.** It fires on about 1 ordinary day in 100 or fewer, but misses about half of the moderate illness patterns in their first three nights.
- **A separate "attention range" that differs from the range on the tile.** The banner would then say "outside your usual range" while the tiles showed ticks.
- **A third tile colour for "near the edge".** It needs a new token and a new rule for the owner to learn, for no gain in the flag.

## 2. Target

I set this target after the first replay counts were on screen, and before the fixed-constant model runs (§5.1) that chose 1.25.

- **Attention and the banner:** at most about 1 ordinary day in 50 (2%) on the model's typical settings (§5).
- **Sensitivity:** catch most illness-like patterns in which four vitals move by about 1.5 of their usual spreads, within the first three nights.
- **The card:** WITHIN RANGE on more ordinary mornings than today.

The 35 replay days cannot test a 2% rate, because one day either way is 3%. The replay checks that the rule is not wildly off on real data. The model sets the constant.

## 3. Research case

All sources were retrieved on 2026-11-18. Numbers below come from pages read in this session. Quer 2021 (DETECT, *Nat Med*) could not be retrieved on two tries, so no number here comes from it.

### 3.1 How other wearables decide

| Product | What it does | Source |
| --- | --- | --- |
| WHOOP Health Monitor | Green "within normal range", orange "slight deviation from baseline", red "significant deviation; review trends over time". "Alert thresholds are based on your historical data and adjust dynamically." The feature article says a green check means "within or near the typical range". An orange or red metric is one "you may want to keep an eye on … over the next few days". | [V1], [V2] |
| Apple Vitals (watchOS) | Needs 7 nights to set a typical range. "By default, you receive notifications when at least two of your overnight metrics are outside of your typical range." | [V3] |
| Garmin Health Status | Five overnight metrics; 3 to 4 weeks of sleep data to set typical ranges; each is "within range or out of range". | [V4] |
| Oura Symptom Radar | Three levels: no signs, minor signs, major signs. It needs 7 nights in the last 14. It "looks at how several metrics change over time rather than checking whether any single reading is abnormal". | [V5] |
| Oura readiness contributors | Judged against personal averages, which take up to two weeks to learn. The resting HR contributor "may decline if you have an RHR that's 3-5 BPM higher … than your usual average". HRV balance compares the last 14 days, weighted to recent days, with the 3-month average, to show "prolonged stressors (such as overtraining or illness)". | [V6] |
| Google Health readiness (the owner's platform) | "A sustained rise in RHR over a few days is generally associated with your body working harder to recover or fight illness." | [V7] |

They share one pattern. Each metric has a personal range, and one metric outside it is a calm state. An alert needs **more than one signal**: two or more metrics (Apple), a change held over several nights (WHOOP, Oura, Google), or both.

### 3.2 What the studies found

| Study | Device and signals | Rule | Result that matters here |
| --- | --- | --- | --- |
| Alavi 2022 [S1] (NightSignal) | Fitbit and Apple Watch, overnight resting HR | Baseline is the running median of nightly resting HR. +3 and ≥ +4 bpm are steps in a state machine; "Deviations in successive nights … trigger an alert". | Red alerts for 80% of COVID-19 cases at or before symptoms. Red alerts also fell on 12.3% of non-COVID days (specificity 87.7%). Non-COVID alert periods lasted 1.9 days on average, against 4.3 for COVID-19. |
| Mishra 2020 [S2] | Fitbit, resting HR | CuSum on standardised residuals against a 28-day baseline. A yellow warning on the first excursion, red "if it remains elevated over 24 hours". | Median resting HR rise of 7 bpm at onset. The online rule alarmed at or before symptoms in 16 of 24 cases. Before COVID-19 the alarms averaged 0.25 per 30 days. |
| Natarajan 2020 [S3] | Fitbit: breathing rate, resting HR, RMSSD | z-scores against a rolling mean and SD, over the day and the 4 days before | Breathing rate shows the largest change and the slowest return. At 99% specificity (false positives on 0.85% of days) sensitivity is 26%; at 95% it is 44%. |
| Esmaeilpour 2024 [S4] | Fitbit Sense and Versa 3: resting HR, breathing rate, HRV during sleep | z-scored metrics over the last 5 nights; alerts paused for 5 days after a positive | Prospective. False positives on 2% of prediction days; 28 of 31 PCR-confirmed COVID-19 cases had an alert in the 8 days before the test. False alerts came from stress, poor sleep, intense exercise and alcohol. |
| Miller 2020 [S5] | WHOOP: breathing rate | Features include the mean of tonight and last night against a baseline lagged 7 to 21 nights | Within-person nightly SD: breathing rate 0.51 rpm, resting HR 4.83 bpm, HRV 17.74 ms. 20% of cases flagged before symptoms, 80% by day 3. |
| Mason 2022 [S6] (TemPredict) | Oura: temperature, HR, HRV, breathing rate | Classifier on 3-day windows | Sensitivity 82%, specificity 63%. Temperature added 4.9% to the ROC AUC. When dating illness onset, the authors found that "shorter-duration (i.e., overnight, etc.) fluctuations … did not necessarily reflect infection-related disruptions" and emphasised trend-like rises, "e.g., a clear rise in the respiratory rate over three consecutive days". |
| Plews 2012 [S7] | Daily HRV, two elite triathletes | 7-day rolling mean of ln RMSSD | The rolling mean fell steadily towards non-functional overreaching in one athlete and stayed flat in the other. |
| Schneider 2019 [S8] | HR and ln RMSSD, overload microcycles | Single days against 2 to 4-day rolling means | Overload moved resting HR and ln RMSSD by small effects. Rolling 2 to 4-day means estimated changes more precisely than single days. Within one person, HR and ln RMSSD correlated at r −0.61 to −0.67 (supine). |

### 3.3 What that means for ghoops

1. **One night is weak evidence.** Short swings happen often and have many causes (S1, S4, S6). Every system that alerts requires either several metrics or several nights.
2. **Two nights in a row is the published minimum.** NightSignal's red alert and Mishra's red status both need the change to persist past one night. Non-COVID alert periods are short (1.9 days on average), so a two-night requirement removes many of them.
3. **More than one vital.** Illness moves breathing rate, resting HR, HRV and temperature together (S3, S6; Oura's notes). Two vitals together are much less likely by chance than one.
4. **Slow overreaching is a trend, not a night.** Plews and Schneider show small, steady shifts best seen in a rolling mean over days. No nightly range rule can catch them without many false alarms (§5.1). That belongs to a trend signal (§13, question 6), not to this flag.
5. **About 1 to 2% of days is a false-alarm rate published systems report as workable.** S3's strictest operating point gave 0.85% of days, and S4 ran at 2% in a prospective study. NightSignal's 12% shows what a looser rule costs.
6. **SpO2 has the thinnest evidence.** None of the studies above used nightly average SpO2 from a consumer wearable as an early illness sign. The one Fitbit SpO2 study the search found (Yamagami 2021 [S9]) used overnight oxygen dips in 23 people already ill with COVID-19. SpO2 counts in the two-vital rule like the other vitals because it counts today. §13, question 3, asks whether it should.

## 4. Replay on the owner's store (counts only)

**Method.** One script kept outside the repo ran the installed `~/.local/bin/ghealth days --days 90 --json`, plus `day --date <d> --json` for each day with a vital. It held the output in memory and printed counts, rates and booleans only. Nothing was written to the store, no dev binary touched it, and nothing called Google. `internal/score` and `internal/v2report` are unchanged between `installed-mac` and `main`. The script recomputed each baseline as scores.md §1.3 describes and classified every candidate rule from those z-scores. The script was debugged on synthetic fixtures before it read real data.

**Gate.** The script reproduces the issue's counts exactly: 37 days with any vital, 20 with one or more less favourable vitals, 9 with two or more. Its own ±1 SD positions agree with the engine's on 138 of 138 ranged vitals, and its baseline counts agree on 148 of 148. Ranges backed out of the engine's ±1 SD edges and ranges recomputed from the baseline disagree on 1 of 106 positions at 1.5 SD and 0 of 106 at 2 SD. No vital falls in the first 42 days of the window, so every baseline was complete inside the read.

**Denominators.** 37 days with any vital; 35 with at least one ranged vital; 34 of those also have a ranged night before. 11 of the 35 have a young baseline (some ranged vital with 7 to 13 values) and 24 a full one.

| Rule (temperature "both" means above or below counts as less favourable; "up" means above only) | Days of 35 | Separate runs | Young / full baseline |
| --- | --- | --- | --- |
| **2.1.0 today:** amber card, ≥ 1 vital less favourable beyond 1 SD (both) | 20 | 11 | 6 / 14 |
| **2.1.0 today:** banner, ≥ 2 less favourable beyond 1 SD (both) | 9 | 6 | 3 / 6 |
| Card at 1 SD, temperature up only | 15 | 9 | 6 / 9 |
| ≥ 1 less favourable beyond 1.5 SD (both / up) | 12 / 11 | 9 / 8 | 4 / 8, 4 / 7 |
| ≥ 2 less favourable beyond 1.5 SD | 4 | 4 | 1 / 3 |
| ≥ 1 less favourable beyond 2 SD | 8 | 6 | 2 / 6 |
| ≥ 2 less favourable beyond 2 SD | 3 | 3 | 0 / 3 |
| ≥ 2 less favourable beyond 1 SD on both nights (any vitals) | 3 | 2 | 0 / 3 |
| ≥ 1 less favourable beyond 1 SD on both nights (any vitals) | 6 | 4 | 2 / 4 |
| ≥ 2 less favourable beyond 1.5 SD on both nights | 0 | 0 | 0 / 0 |
| Combined score (sum of less favourable z, each capped at 3) ≥ 4 / ≥ 5 | 6 / 4 | 5 / 4 | 2 / 4, 1 / 3 |
| Combined score ≥ 3 on both nights | 3 | 3 | 1 / 2 |
| Two-night mean of the combined score ≥ 3 / ≥ 4 | 9 / 7 | 5 / 4 | 3 / 6, 1 / 6 |
| Two-night mean z beyond 1 SD on ≥ 2 vitals / beyond 1.5 SD | 8 / 3 | 5 / 2 | 2 / 6, 0 / 3 |
| Resting HR alone beyond 1 SD on both nights / beyond 1.5 SD | 1 / 0 | 1 / 0 | 0 / 1, 0 / 0 |
| **Same ≥ 2 vitals less favourable on both nights, 1 SD** | 3 | 2 | 0 / 3 |
| **Same ≥ 2 vitals less favourable on both nights, 1.25 SD (chosen)** | **2** | **2** | **0 / 2** |
| Same ≥ 2 vitals less favourable on both nights, 1.5 SD / 2 SD | 0 / 0 | 0 / 0 | 0 / 0 |
| Any vital outside its range either way: 1 SD / 1.25 / 1.5 / 2 | 24 / 20 / 13 / 9 | 8 / 9 / 9 / 6 | 8 / 16, 8 / 12, 4 / 9, 2 / 7 |

For the chosen rule, temperature "up" and "both" give identical counts. The 2 attention days are both among today's 9 banner days. On neither of them were two vitals beyond 2 SD. Of the 3 days with two vitals beyond 2 SD on one night, 2 had at least one vital beyond 1 SD the night before. The engine's `spo2_below_usual` flag showed on 2 of 37 days.

**On screen under the new rule:** WITHIN RANGE on 15 of 35 days (today 11), grey OUTSIDE RANGE on 18, amber on 2. The banner shows on 2 days, in 2 separate runs (today 9 days in 6 runs). The card's headline still reads OUTSIDE RANGE, grey or amber, on 20 of 35 mornings (§13, question 8).

**What 35 days can and cannot show.** They cannot tell a 1% rule from a 5% one, and they hold no record of illness, so they cannot measure sensitivity. They hint at heavy tails. One vital beyond 2 SD in the less favourable direction appeared on 8 of 35 days, against about 5 expected from the model (13 to 14%, §5.1). Two at once appeared on 3 days, against about 1. The first gap is about 1.5 standard errors, and those days cluster in runs, so a real episode could explain it as well as heavy tails. The choice does not depend on it. The two-night rule gives up a few points against the other rules when nights are normal and leads clearly when they are heavy-tailed (§5.2). Whether those nights were real events is §13, question 5.

## 5. Model (synthetic data only)

**Set-up.** The model generates five nightly vitals, each pointed so that "higher" is the less favourable direction. Correlations: resting HR with low HRV 0.6, from Schneider's within-person r of −0.61 to −0.67 [S8]; other pairs 0.15; SpO2 independent (both assumptions). Night-to-night carry-over is 0.3. Tails are either normal or Student t with 5 degrees of freedom ("heavy"). Each night is judged against the previous 28 nights with the sample SD, as in §1.3. The model has no SD floors, so it errs towards more alarms. An "illness" adds a shift, in units of the vital's usual spread, for 5 nights after a 40-night run-in. For scale, Mishra's median rise of 7 bpm [S2] against Miller's within-person SD of 4.83 bpm [S5] is about 1.4 spreads. The anchor is rough. Mishra's rise is Fitbit resting HR, while Miller's SD is WHOOP's heart rate in the last minutes of deep sleep. "Caught early" means the rule fired on night 1, 2 or 3 of the episode; "caught" means on any night of it. These are modelled rates, not measured ones.

### 5.1 The chosen rule and its neighbours

False alarms are the share of ordinary days the banner fires. Catch rates are early / any, in %.

| Setting | Rule | False alarms | Illness, 4 vitals, 1.0 spread | 1.5 spreads | 2.0 spreads | Fever and breathing only, 1.5 | Heart only (HRV, resting HR), 1.5 | Overreaching, HRV and resting HR, 0.75, 7 nights |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Normal | 2.1.0 banner | 27.3% | 94 / 98 | 99 / 100 | 100 / 100 | 91 / 98 | 96 / 99 | 83 / 98 |
| Heavy tails | 2.1.0 banner | 23.1% | 95 / 99 | 99 / 100 | 100 / 100 | 91 / 97 | 95 / 98 | 80 / 96 |
| Normal | **chosen, 1.25** | **1.3%** | 38 / 53 | 62 / 79 | 85 / 95 | 32 / 42 | 39 / 54 | 14 / 26 |
| Heavy tails | **chosen, 1.25** | **1.2%** | 38 / 49 | 68 / 84 | 89 / 97 | 34 / 46 | 42 / 59 | 14 / 24 |
| Heavy tails, carry-over 0.5 | **chosen, 1.25** | **2.7%** | 45 / 57 | 71 / 85 | 89 / 96 | 43 / 54 | 48 / 63 | 19 / 34 |
| Normal / heavy / carry-over 0.5 | same rule at 1.0 | 3.6% / 2.9% / 5.7% | 52 / 52 / 60 early | 79 / 81 / 85 early | | | | |
| Normal / heavy / carry-over 0.5 | same rule at 1.5 | 0.5% / 0.5% / 1.2% | 24 / 22 / 29 early | 43 / 48 / 56 early | | | | |

The 2.1.0 card is amber on 66.1% (normal) and 57.2% (heavy) of ordinary days. The replay shows 20 of 35, so the heavy model matches the owner's data well. With a young baseline of 10 values, the chosen rule fires on 1.7%, 1.5% and 3.3% of ordinary days in the three settings. All five vitals sit inside their range on 28.2%, 39.9% and 35.1% of ordinary days at 1.25, against 14.1%, 24.2% and 20.0% at 1.

Overreaching modelled as a small, steady shift is caught early only 14 to 19% of the time. §3.3 point 4 explains why that is expected.

### 5.2 Rule families at the same false-alarm rate

Each family's threshold was tuned so it fires on 2% of ordinary days. Catch rates are early / any, in %.

| Family (heavy tails) | Threshold | Illness 1.0 | Illness 1.5 | Fever and breathing only | Heart only |
| --- | --- | --- | --- | --- | --- |
| ≥ 2 vitals beyond k tonight | k 2.23 | 28 / 38 | 56 / 66 | 22 / 30 | 34 / 43 |
| **Same ≥ 2 vitals beyond k on both nights** | k 1.11 | **47 / 64** | **77 / 90** | **45 / 60** | **50 / 69** |
| ≥ 2 vitals with two-night mean beyond k | k 1.75 | 33 / 45 | 67 / 78 | 30 / 41 | 39 / 50 |
| Two-night mean of the combined score | 5.65 | 43 / 58 | 80 / 89 | 27 / 37 | 28 / 38 |
| ≥ 3 vitals with two-night mean beyond k | k 1.18 | 42 / 58 | 76 / 88 | 19 / 29 | 23 / 35 |

With normal tails the families are close (illness 1.5 caught early by 72 to 84%), and the combined score leads. With heavy tails the same-vitals two-night family leads on every pattern, and it is the only one that stays strong when just two vitals move. At 1% false alarms with heavy tails it still catches 65 / 79 of the 1.5 pattern, where the single-night family falls to 33 / 40. The constant 1.25 is a round value close to that family's 1 to 2% thresholds across the three settings.

## 6. The rule (scores.md §5 and §6, as they will read)

### 6.1 §5 Overnight vitals panel: what changes

- **Ranges.** Replace `mean ± sd_eff` with `mean ± VitalRangeSD × sd_eff`. HRV becomes `[exp(mean_ln − VitalRangeSD × sd_eff_ln), exp(mean_ln + VitalRangeSD × sd_eff_ln)]`. Skin temperature becomes `[−VitalRangeSD × max(stddev_30d, 0.10), +VitalRangeSD × max(stddev_30d, 0.10)]`. Rounding, the 7-value minimum, the position classes and "compare unrounded numbers" do not change.
- **Less favourable direction.** In the table, skin temperature's "above or below" becomes "above". Add the sentence: "Below its range, skin temperature is outside but not less favourable."
- **New §5.1 Persistent vitals.** "`persistent` lists, in the order `hrv_rmssd`, `resting_hr`, `respiratory_rate`, `spo2`, `skin_temp_deviation`, each key that is in `adverse` on night D and in `adverse` on each of the `VitalAttentionNights − 1` London dates before D, each night judged against its own baseline. A night with no value, no range or a conflict for that key breaks the run. Nothing is carried over a missing night."
- **New §5.2 Monitor state.** "`monitor_state` is `building` when `metrics_with_range` is 0. Otherwise it is `attention` when `persistent` has at least `VitalAttentionMinVitals` keys; `outside` when `outside_range` is not empty; else `within`."

### 6.2 §6 Health flags: what changes

- `vitals_outside_range`: the condition becomes `len(persistent) ≥ VitalAttentionMinVitals`. The message becomes `"<N> overnight vitals have been outside your usual range for <VitalAttentionNights> nights in a row, in the less favourable direction."`, where N is `len(persistent)`. Severity stays `attention`, and its place in the order does not change.
- `spo2_below_usual`: the `2` in the condition becomes the named constant `SpO2FlagSD = 2.0`. Its value and behaviour do not change.

### 6.3 §0 Constants: rows to add

| Name | Value | Used in |
| --- | --- | --- |
| `VitalRangeSD` | 1.25 | §5; reported in `score_constants` |
| `VitalAttentionNights` | 2 | §5.1, §6; reported in `score_constants` |
| `VitalAttentionMinVitals` | 2 | §5.2, §6; reported in `score_constants` |
| `SpO2FlagSD` | 2.0 | §6 |

The header's `score_version` becomes `2.2.0`, and so does the §9 envelope example.

### 6.4 §11 Sources: entries to add

S1 to S8 from §14 below. Vendor pages stay in this spec, not in scores.md.

### 6.5 Worked example (synthetic; becomes golden case `two_nights_same_two`)

Both nights use these baselines, most recent first, 14 values each:
- resting HR `[55, 56, 54, 57, 55, 56, 54, 55, 56, 55, 54, 57, 55, 56]`: mean 55.357, sample SD 1.008, so `sd_eff` is the floor 2.0 and the range is 52.857 to 57.857, reported as `[52.9, 57.9]`;
- breathing rate `[15.0, 15.2, 14.8, 15.1, 14.9, 15.3, 15.0, 14.8, 15.2, 15.1, 14.9, 15.0, 15.1, 14.9]`: mean 15.021, `sd_eff` is the floor 0.4, range `[14.5, 15.5]` (14.521 to 15.521);
- HRV ms `[52.0, 48.5, 55.1, 50.2, 47.9, 53.4, 51.0, 49.6, 54.2, 50.8, 52.7, 48.1, 51.5, 53.0]`: ln mean 3.9365, `sd_eff_ln` is the floor 0.10, range `[45.2, 58.1]`;
- SpO2 `[96.0, 96.4, 95.8, 96.2, 96.6, 95.9, 96.1, 96.3, 95.7, 96.0, 96.2, 96.5, 95.9, 96.1]`: `sd_eff` is the floor 0.5, range `[95.5, 96.7]`;
- skin temperature: `stddev_30d_c` 0.08, so the range is ±0.125, reported as `[-0.13, 0.13]`.

Last night: resting HR 58, breathing rate 15.6, HRV 47, SpO2 96.0, skin temperature +0.05. Tonight: resting HR 59, breathing rate 15.8, HRV 50, SpO2 96.1, skin temperature +0.10.

Expected for tonight: `adverse` `["resting_hr", "respiratory_rate"]` and `persistent` the same; `monitor_state` `attention`; flags `["vitals_outside_range"]` with message `"2 overnight vitals have been outside your usual range for 2 nights in a row, in the less favourable direction."` Under 2.1.0, last night alone would already have raised the banner. Under 2.2.0, last night is `outside` with no flag.

## 7. Contract

- **§5.1.1 `score_constants`** gains `"vitals": { "range_sd": 1.25, "attention_nights": 2, "attention_min_vitals": 2 }` after `workouts`. Row: "`vitals` | `{range_sd: num, attention_nights: int, attention_min_vitals: int}` | scores.md §5 and §6. Added on <date of step H1>." Extend the existing note: a Mac built before that date omits `vitals`, and a client treats it as unknown.
- **§5.6 `vitals`**:
  - `adverse` rule: "keys outside in their less favourable direction (scores.md §5; skin temperature: above only)".
  - New row after `adverse`: "`persistent` | string[] | scores.md §5.1. Added on <date>."
  - New row after `values_needed`: "`monitor_state` | string | `building`, `within`, `outside` or `attention` (scores.md §5.2). Added on <date>."
  - Add under VitalMetric: "`range_low` and `range_high` are mean ± `VitalRangeSD` × `sd_eff` (scores.md §5)."
- **Days rows and brief** keep their fields. `vitals_adverse` stays `len(adverse)` (days) or the `adverse` list (brief), so a cool skin-temperature night no longer counts there. Agents see attention through the flag code `vitals_outside_range`, as today.
- Consumers ignore unknown keys (§1.2), so `schema_version` stays 2.

## 8. Engine numbers in the app

| Number | Where the app gets it | Used for |
| --- | --- | --- |
| `VitalRangeSD` | already applied in `range_low` and `range_high`; also `score_constants.vitals.range_sd` | the chip shows the Mac's edges; the app never multiplies |
| `VitalAttentionNights` | `score_constants.vitals.attention_nights` | the VoiceOver phrase (§9). The banner text comes whole from the Mac |
| `VitalAttentionMinVitals` | `score_constants.vitals.attention_min_vitals` | not used by the app today; reported so a later info sheet has it |
| the attention class | `vitals.monitor_state`, `vitals.persistent` | card colour, chip colour, HRV widget colour |

The app never works out attention from `adverse`, and it holds no copy of 1.25 or 2. Against a Mac without these fields (D5 of engine-numbers):
- no `monitor_state`: the card is `building`, `within` or `outside` exactly as today's code would place it, but never amber, and no tile is amber;
- no `score_constants.vitals`: the VoiceOver phrase drops the night count.

Installing the Mac and the phone in the same session means the owner sees neither case (§12, H4).

## 9. The app

The visible change is in the mockup and needs the owner's approval before any build. Every value in it is synthetic.

| Surface | Today | New |
| --- | --- | --- |
| Home Health Monitor card | Amber heart and OUTSIDE RANGE when any vital is less favourable tonight | Amber only when `monitor_state` is `attention`. Otherwise grey heart and OUTSIDE RANGE when any vital is outside, mint tick and WITHIN RANGE when none are. Words and subline (`3/5 Metrics`) unchanged |
| Health status card | Same colours as Home | Same rule as Home. The sentence stays `<within>/<total> overnight metrics in your typical range` |
| Vital tile chip | Amber triangle when outside in the less favourable direction | Amber triangle only for a vital in `persistent` on an attention day. Every other outside vital gets the grey triangle (neutral fill at 15%, `textSoft`), as favourable moves do today |
| Tile range numbers | ±1 SD | ±1.25 SD, from the Mac; slightly wider |
| Banner (Home, Health) | The old message on one night | The new message, on attention days only (§6.2) |
| HRV small widget | Amber when HRV is less favourable tonight | Amber only when HRV is in `persistent` on an attention day |
| VoiceOver, tile | `<title>, <value>, above typical range <low> to <high>` | On an attention vital, append `, outside your typical range for <attention_nights> nights in a row`, or `, outside your typical range on recent nights` without the constant |
| VoiceOver, Home card and Health status card | `Health monitor, outside range, 3 of 5 metrics` for a grey card and an amber one alike, so the state is colour only | On attention, append the same phrase as the tile. The status card gets an explicit label, `<title>, <sentence>`, plus the phrase on attention |
| Trends chart | Shades tonight's typical range as a band behind the line | Same code. The band is wider because the Mac's range is wider |
| Trends sentence | Compares a 7-day mean with tonight's range | Same code. It now compares with the wider range. Audit fix 9 owns that sentence |

The mockup has four sections. Section 1 shows one night outside, now and new, on Home and Health. Section 2 shows the second night, new, on Home and Health. Section 3 is a colour key with the banner text before and after, and says how often the grey OUTSIDE RANGE will still show. Section 4 is the approval question.

**DESIGN.md rule.** The lead records it when the build lands, under Colors, Named Rules.

> **The Amber Is A Pattern Rule.** On the Health Monitor card, the vital tiles and the HRV widget, amber appears only when the Mac reports `monitor_state: attention`, and only on the vitals it lists in `persistent`. A vital outside its range on one night shows the grey triangle, whichever way it moved. The phone never decides amber from `adverse`.

## 10. Golden vectors

New file `fixtures/v2/scores/vitals.json`, in the §9 envelope (`kind: score_vectors`, `score_version: 2.2.0`, `synthetic_fixture: true`). Add a row to scores.md §9:

| File | Function under test | `input` fields | `expected` fields |
| --- | --- | --- | --- |
| `vitals.json` | ranges, positions, `adverse`, `persistent`, `monitor_state` and the two vitals flags (§5, §6) | `tonight` and `last_night` (null for none), each `{hrv_ms, hrv_baseline_ms[], rhr_bpm, rhr_baseline_bpm[], rr_bpm, rr_baseline_bpm[], spo2_pct, spo2_baseline_pct[], skin_temp {nightly_c, baseline_c, stddev_30d_c} or null}`; any value can be null; baselines already selected, most recent first | `ranges {key: [low, high] or null}`, `positions {key: position or null}`, `outside_range`, `adverse`, `persistent`, `metrics_with_range`, `monitor_state`, `flags [{code, message}]` |

Cases (synthetic numbers; reuse §6.5's baselines unless a case says otherwise):

| Case | Proves |
| --- | --- |
| `within_all` | all five within; `within`; no flag |
| `one_night_two_adverse` | §6.5's last night as tonight, with a within night before it: `outside`, no flag. This is the 2.1.0 banner case |
| `two_nights_same_two` | §6.5: `attention`, `persistent` resting HR and breathing rate, the flag and its exact message |
| `two_nights_three` | three vitals persistent: message says 3 |
| `two_nights_different_vitals` | tonight resting HR and breathing rate, last night HRV and skin temperature above: `persistent` empty, `outside`, no flag |
| `one_vital_two_nights` | breathing rate above both nights, nothing else: `persistent` has one key, `outside`, no flag |
| `gap_last_night` | `last_night` null: no persistence, no flag |
| `last_night_no_baseline` | last night's baselines have 6 values: last night has no range, no flag |
| `exact_edge` | breathing-rate baseline of seven values of 15.0, so SD 0, floor 0.4 and edges exactly 14.5 and 15.5. Tonight's value 15.5 is `within` |
| `just_past_edge` | the same baseline with tonight's value 15.6: `above` |
| `sd_floor_active` | covered by §6.5: every range comes from a floor |
| `hrv_log_range` | HRV low both nights with resting HR high both nights: `attention`; the HRV range is asymmetric in ms |
| `favourable_both_nights` | HRV above and resting HR below on both nights: `outside`, `adverse` empty, no flag |
| `skin_cool_both_nights` | skin temperature below its range both nights, plus breathing rate above both: temperature `outside` but not in `adverse`; one persistent key; no flag |
| `skin_warm_both_nights` | skin temperature above both nights, plus resting HR above both: `attention` |
| `spo2_and_attention` | SpO2 more than 2 `sd_eff` below tonight, also low last night, with breathing rate high both nights: `vitals_outside_range` then `spo2_below_usual`, in §6 order |
| `building` | every baseline has fewer than 7 values: `building`, `metrics_with_range` 0, no flag |

Compare integers exactly and decimals within one unit of the last place, as §9 says.

Whole-response goldens: regenerating changes `score_version` to 2.2.0, range edges, and possibly positions, `outside_range`, `adverse`, `vitals_adverse` and day-row counts. It adds `persistent`, `monitor_state` and `score_constants.vitals`. No golden today carries `vitals_outside_range`. Any other difference is a stop-and-tell-the-lead (§12, H1).

## 11. `score_version`

`2.1.0` becomes **`2.2.0`** in `internal/score/constants.go` `Version`, the scores.md header and §9 example, every regenerated golden and `vitals.json`. The three preview bodies keep the `score_version` they carry today, as in earlier bumps. Their generator does not touch it (acceptance notes for P6).

## 12. Build plan

Each step is one commit that keeps `make check` green and is pushed to `main` under the trunk rules. H1 changes what an installed Mac sends, but nothing is installed until H4, and the lead installs the Mac and the phone together.

**H1 Engine (Go) and documents.**
1. `constants.go`: add `VitalRangeSD = 1.25`, `VitalAttentionNights = 2`, `VitalAttentionMinVitals = 2` and `SpO2FlagSD = 2.0`; set `Version = "2.2.0"`.
2. `vitals.go`: split today's body into a pure `night(in NightInput) Vitals`, where `NightInput` has a `VitalInput{Value *float64, Status string, Baseline []float64}` per metric plus `Temp *TemperatureInput` and its status. `Engine.Vitals(date)` builds the input for D and for each of the `VitalAttentionNights − 1` dates before it, with the existing `metric`, `baseline`, `temperature` and `MissingStatus` calls. Apply `VitalRangeSD` to every range and make skin temperature less favourable only when above. A pure `withAttention(tonight Vitals, before []Vitals) Vitals` sets `Persistent` and `State`.
3. `types.go`: `Vitals` gains `Persistent []string `json:"persistent"`` after `Adverse`, and `State string `json:"monitor_state"`` after `Needed`. Use `[]string{}`, never nil.
4. `Flags`: the new condition and message (§6.2). The SpO2 check uses `SpO2FlagSD`. Move the two vitals flags into a pure `vitalFlags(v Vitals, spo2 *float64, spo2Baseline []float64) []Flag`, which `Flags` calls first so the order holds.
5. `report_constants.go`: `Constants` gains `Vitals VitalConstants `json:"vitals"`` after `Workouts`, with `RangeSD float64 `json:"range_sd"``, `AttentionNights int `json:"attention_nights"`` and `AttentionMinVitals int `json:"attention_min_vitals"``, filled from the constants.
6. `fixtures/v2/scores/vitals.json` with §10's cases, and `TestVitalVectors` in `internal/score`, which runs `night`, `withAttention` and `vitalFlags` on each case. Extend `TestReportedConstantsReproduceTheEngine`: `withAttention` on a case built at exactly `attention_min_vitals` keys and `attention_nights` nights gives `attention`, and one fewer gives `outside`.
7. `scripts/v2_shape.py`: add `"monitor_state"` to `ENUM_FIELDS`.
8. `$GO test ./internal/v2report -update-goldens`, then a throwaway check (not committed) that every changed path is in §10's allowed list. If anything else differs, stop and tell the lead.
9. Documents: scores.md §0, §5, §6, §9 and §11 (§6 of this spec); contract.md §5.1.1 and §5.6 (§7); `fixtures/v2/README.md` lists `vitals.json`.

Check: `make GO=/opt/homebrew/opt/go@1.27/bin/go check`. The `verify-ghealth` skill on a temp state dir with fixtures shows `monitor_state` and `score_constants.vitals` in `day --json`.

**H2 App models (no visible change).**
1. `Vitals.swift`: `@DefaultEmpty public var persistent: [String]`, `public var monitorState: String?`, and `public func inAttention(_ key: String) -> Bool { monitorState == "attention" && persistent.contains(key) }`.
2. `ScoreConstants.swift`: `public var vitals: VitalConstants?` with `rangeSd: Double`, `attentionNights: Int` and `attentionMinVitals: Int`.
3. `HealthText.attentionSpoken(_ c: ScoreConstants?) -> String`: `outside your typical range for <n> nights in a row`, or `outside your typical range on recent nights`.
4. `fixtures/v2/engine/odd_constants.json` gains `"vitals": {"range_sd": 1.5, "attention_nights": 3, "attention_min_vitals": 3}`. `EngineNumberTests.sentencesUseTheMacsNumbers` checks `attentionSpoken` for default, odd and nil, and `defaultsNeverLeakIntoOddOutput` adds `2 nights`.
5. `scripts/goop_preview_fixtures.py` `add_engine_fields`: a dict with `metrics_with_range` and no `monitor_state` gains `persistent: []` after `adverse`, and `monitor_state` after `values_needed`. The value is `building` when `metrics_with_range` is 0, `outside` when `outside_range` is non-empty, else `within`. Any `score_constants` without `vitals` gains `day_full.json`'s. The preview ranges are not recomputed. Update its test.
6. `olderMacBodiesDecode` also removes `persistent`, `monitor_state` and `score_constants.vitals`.

Check: `make ios-core-test` and `make check`.

**H3 App behaviour and UI (the visible change, in one commit).**
1. `HealthState`: `Kind` is `building`, `within`, `outside`, `attention`. With `monitorState` present, `kind` follows it; an unknown string reads as `outside`. Without it, today's derivation minus the amber case (§8). `color` maps `attention` to caution, `within` to healthOK and anything else to neutral. Title, subline and sentence keep their text.
2. `GoopVitalTile`: rename `adverse` to `attention`. `GoopHealthScreen` passes `day.vitals.inAttention(key)`. The accessibility label appends `HealthText.attentionSpoken(day.scoreConstants)` when `attention` is true.
3. `GoopCards.GoopMonitorCard` keeps its icon logic (tick for `within`, heart otherwise). Its accessibility label appends `HealthText.attentionSpoken(day.scoreConstants)` on attention. `GoopHealthStatusCard` gets `.accessibilityElement(children: .ignore)` and the label `<title>, <sentence>`, plus the phrase on attention.
4. Rename `WidgetData.hrvAdverse` to `hrvAttention`, set from `inAttention("hrv_rmssd")`, and update `HRVSmallView`.
5. `ComponentGallery`: the amber sample sets `monitorState: "attention"` and `persistent`; add a grey one-night sample.
6. Fixture sets `health_one_night` and `health_attention`, both from `snapshot_fresh`. `health_one_night` has resting HR and breathing rate in `adverse` and `outside_range`, `persistent` empty, state `outside`, no flag. `health_attention` has the same plus `persistent` with both, state `attention`, and the `vitals_outside_range` flag with the §6.2 message.
7. Tests: update `GoopPresentationTests.healthStateFirstMatchAndSentences` for the four states and the nil fallback. UI test `testHealthAttention` runs both sets. `health_attention`: the banner text exists on Home and Health, and the resting-HR tile label and the `monitor-health-link` label both end with the attention phrase. `health_one_night`: no `vitals_outside_range` banner. Capture `health-attention-home`, `health-attention`, `health-one-night`.
8. DESIGN.md: the §9 rule.

Check: `make ios-test` on a Simulator created for the run (§ Build and test), then the `verify-ios` skill. At most two delegates build iOS at once.

**H4 (lead) Install and owner check.** Install the Mac and the phone from the same green SHA in one session, Mac first, and tag both. For the owner check, on the next morning with a single night outside, the card is grey and there is no banner. Record counts only in `acceptance.md`.

## 13. Open questions for the lead

1. **The constant.** Approve `VitalRangeSD = 1.25` with the two-night, two-vital rule? The alternatives are 1.0 (catches more, about 3 to 6 false days in 100 modelled) and 1.5 (about 1 or fewer, but misses about half of moderate patterns early).
2. **Skin temperature direction (D2).** Approve "warmer only" as less favourable? It also changes `vitals_adverse` for agents and the days rows.
3. **SpO2.** The `spo2_below_usual` flag stays single-night at 2 SD. It showed on 2 of 37 days on the owner's store. SpO2 also counts towards attention, with the thinnest evidence of the five vitals (§3.3, point 6). Keep both as they are, give the SpO2 flag the two-night rule, or leave SpO2 out of attention? I recommend keeping both, then reviewing after a month on the new rule.
4. **Young baselines.** Attention is not held back until a baseline has 14 values. The modelled rise is small (from 1.2% to 1.5% of days with heavy tails), and the replay found no attention day on a young baseline. Agree?
5. **Ground truth.** Could the lead ask the owner whether they were ill, or trained unusually hard, in the last five weeks? A yes or no is enough, with no dates. The replay found 2 attention days in 2 separate runs, and 3 nights with two vitals beyond 2 SD. A remembered illness would show whether the rule caught something real.
6. **Overreaching follow-up.** A slow, steady HRV decline is a trend job (Plews [S7]). File an issue for a weekly HRV signal, a 7-day rolling ln RMSSD against the baseline, perhaps through `brief` trends (scores.md §11b)?
7. **Install order.** H1 changes what an installed Mac sends. Confirm that the lead installs the Mac and phone together (H4), so the old app never sees the new banner text next to single-night amber.
8. **The grey headline.** Under the new rule the card still says OUTSIDE RANGE on 20 of 35 mornings on the owner's store: 18 grey, 2 amber. Modelled, it says so on 60 to 72% of ordinary mornings. The grey state is honest, since a vital is outside its range that night, and WHOOP's own feature describes metrics as "within or outside of their typical range" [V2]. Keep the words, with colour carrying the signal (recommended), or open a follow-up to reword the grey state, for example with the count alone? The mockup tells the owner how often grey will show.

For the owner, one question, with the mockup: "Do these screens look right?" Recommended answer: approve as shown.

## 14. Sources

Retrieved 2026-11-18.

- **[V1]** WHOOP Support. "WHOOP Health Monitor & Report." Last published 2025-07-22. https://support.whoop.com/s/article/WHOOP-Health-Monitor-Report
- **[V2]** WHOOP. "WHOOP Feature: The Health Monitor." 2021-09-11. https://www.whoop.com/us/en/thelocker/health-monitor-feature/
- **[V3]** Apple Support. "Track your vitals on Apple Watch" (watchOS guide) and "Track your overnight and daytime vitals with Apple Watch" (article 120142, published 2026-09-14). https://support.apple.com/guide/watch/apd15aa7ed96/watchos and https://support.apple.com/120142
- **[V4]** Garmin Support. "What Is the Health Status Feature in Garmin Connect?" https://support.garmin.com/en-US/?faq=hCW4HgpoXc06XQol8EiYC6
- **[V5]** Oura Member Care. "Symptom Radar" (updated 2026-10-14), https://support.ouraring.com/hc/en-us/articles/35593651188115-Symptom-Radar; Oura. "How Oura Can Help Monitor Signs of Illness" (updated 2026-10-27), https://ouraring.com/blog/symptom-radar/
- **[V6]** Oura Member Care. "Readiness Contributors" (updated 2026-08-14). https://support.ouraring.com/hc/lv/articles/360057791533-Readiness-Contributors (English text)
- **[V7]** Google Health Help. "Understanding your readiness score in the Google Health app." https://support.google.com/googlehealth/answer/14236710
- **[S1]** Alavi A, et al. Real-time alerting system for COVID-19 using wearable data (title as retrieved from PMC). *Nature Medicine*. doi:10.1038/s41591-021-01593-2 (full text, PMC8799466).
- **[S2]** Mishra T, et al. Early detection of COVID-19 using a smartwatch (title as retrieved from PMC). *Nature Biomedical Engineering* 2020;4:1208–1220. doi:10.1038/s41551-020-00640-6 (full text, PMC9020268).
- **[S3]** Natarajan A, Su H-W, Heneghan C. Assessment of physiological signs associated with COVID-19 measured using wearable devices. *npj Digital Medicine* 2020;3:156. doi:10.1038/s41746-020-00363-7 (full text, PMC7705652).
- **[S4]** Esmaeilpour Z, et al. Detection of common respiratory infections, including COVID-19, using consumer wearable devices in health care workers: prospective model validation study. *JMIR* 2024. JMIR Publications, 2024. doi:10.2196/53716 (full text, PMC11292157).
- **[S5]** Miller DJ, et al. Analyzing changes in respiratory rate to predict the risk of COVID-19 infection. *PLoS ONE* 2020;15(12):e0243693 (full text, PMC7728254).
- **[S6]** Mason AE, et al. Detection of COVID-19 using multimodal data from a wearable device: results from the first TemPredict Study. *Scientific Reports* 2022;12:3463 (full text, PMC8891385).
- **[S7]** Plews DJ, Laursen PB, Kilding AE, Buchheit M. Heart rate variability in elite triathletes, is variation in variability the key to effective training? A case comparison. *European Journal of Applied Physiology* 2012;112(11). doi:10.1007/s00421-012-2354-4. Abstract only.
- **[S8]** Schneider C, et al. Heart rate variability monitoring during strength and high-intensity interval training overload microcycles. *Frontiers in Physiology* 2019;10:582. doi:10.3389/fphys.2019.00582 (full text, PMC6538885).
- **[S9]** Yamagami K, et al. Early detection of symptom exacerbation in patients with SARS-CoV-2 infection using the Fitbit Charge 3 (DEXTERITY): pilot evaluation. JMIR Publications, 2021. doi:10.2196/30819. Abstract only.

ghoops sources: `internal/score/vitals.go`, `constants.go`, `report_constants.go`, `types.go`; `docs/v2/scores.md` §0, §1.3, §5, §6, §9; `docs/v2/contract.md` §5.1.1, §5.6; [engine-numbers-spec.md](engine-numbers-spec.md); [data-honesty-audit.md](data-honesty-audit.md), Health and fix 3; `ios/GHealthCore/Sources/GHealthCore/Presentation/Levels.swift` (`HealthState`), `ios/GHealth/Components/Goop/GoopHealth.swift`, `GoopCards.swift`, `ios/GHealth/Screens/GoopHealthScreen.swift`, `HomeScreen.swift`, `ios/Shared/WidgetViews/WidgetData.swift`, `HRVSmallView.swift`; DESIGN.md.

## 15. Lead review and owner approval (2026-11-18)

The owner was shown the six renders (Home and Health: today, one night, two nights) and approved them as shown.

Lead answers to §13:

1. **The constant.** Approved: `VitalRangeSD = 1.25`, two nights, two vitals.
2. **Skin temperature.** Approved: it is less favourable only when warmer (D2). The change to `vitals_adverse` for agents and the days rows is accepted.
3. **SpO2.** Both stay as they are: the single-night `spo2_below_usual` flag at 2 SD, and SpO2 counting towards attention. The lead reviews this after a month on the new rule.
4. **Young baselines.** Agreed. Attention isn't held back until 14 values.
5. **Ground truth.** Not asked. The model sets the constant, so the answer wouldn't change the rule, and an illness answer is health information that stays out of the repo.
6. **Overreaching.** Filed as a separate issue: a weekly HRV trend signal.
7. **Install order.** Confirmed. The Mac and the phone install together from one green SHA, Mac first (H4).
8. **The grey headline.** Keep OUTSIDE RANGE, and let colour carry the signal, as approved in the mockup.

The spec is final. The implementer builds H1 to H3. The lead does H4 with the owner and adds the DESIGN.md rule when H3 lands.
