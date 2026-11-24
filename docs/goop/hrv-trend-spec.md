# ghoops: weekly HRV trend (issue #30)

Status: draft, for lead review and the owner's approval of the mockup. Written 2026-11-22 against `main` at `b99a4e9` (`score_version` 2.3.0). The mockup is [mockups/hrv-trend.html](mockups/hrv-trend.html), rendered in `mockups/screens/hrv-trend-<key>.png`. No product code, golden, fixture or `score_version` changes with this document. The build plan is [hrv-trend-plan.md](hrv-trend-plan.md).

## 0. The rule in plain words

Each morning the Mac averages your HRV over the last 7 nights. It compares that average with your usual range for a 7-day average. That range comes from up to 28 nights before the week, as your usual value plus or minus one usual spread. The Health screen gets one new tile, **HRV 7-day average**, in the empty slot beside skin temperature. It shows the average and the range. A mint tick means the average is inside the range. A grey triangle means it is above or below. The tile never turns amber and never raises a banner. On the Trends screen's HRV week view, the sentence under the average says the same thing as the tile.

The nightly Health Monitor (#26) catches a sudden change across several vitals. A slow HRV drift over one to three weeks stays inside each night's range, so the nightly rule misses it (health-monitor-flag-spec.md §5.1). A 7-day average against a range built before the week is the method HRV-guided training studies use for that drift (§3).

The tile describes a shift. It never names a cause. Published studies disagree on which way HRV moves when training load builds up too far, so the tile cannot tell you that you are overreaching (§3.2).

Counted read-only on the owner's store (§4), the rule had a range on 20 days. It showed the average below the range on 6 of them, in 2 separate runs of at most 3 days, and above it on none. Modelled on synthetic data, the average sits inside the range on about 9 ordinary days in 10. The model also catches most declines of 1.5 usual spreads built up over three weeks within those three weeks (§5).

## 1. Decisions

This spec extends [scores.md](../v2/scores.md) §0, §5, §9 and §11 and [contract.md](../v2/contract.md) §5.1.1, §5.6 and §5.13. It does not change any existing field, flag, colour rule or score.

| # | Decision | Reason |
| --- | --- | --- |
| D1 | **Signal.** The mean of ln RMSSD over the nights D−6 … D that have an HRV value. It needs at least `HRVTrendMinNights = 4` of the `HRVTrendDays = 7` nights. The value reported is `exp(mean)`, in ms. | Plews and colleagues used a 7-day rolling average of ln RMSSD rather than single days [S1][S2]. Buchheit's review found links with performance only for averages of at least 3 to 4 days [S4]. At least 3 valid days per week are needed for a valid weekly mean [S3]. ghoops already asks for 4 of 7 in `brief` trends (scores.md §11b). |
| D2 | **Baseline.** The scores.md §1.3 HRV baseline taken as of date D−6. It walks D−7 … D−48, keeps up to 28 available nights, and transforms them to ln. It needs at least `HRVTrendMinBaseline = 14` values. `sd_eff = max(sd, SDFloorLnRMSSD)`. | The baseline must end before the week starts, or the week pulls its own reference towards it. Reusing §1.3 adds no new walking rule. Oura and Garmin both learn a personal range for about two to three weeks before they judge [V2][V3]. 14 is the value ghoops already treats as a calibrated baseline (scores.md §2.5). |
| D3 | **Range.** `[exp(mean_b − HRVTrendBandSD × sd_eff), exp(mean_b + HRVTrendBandSD × sd_eff)]` with `HRVTrendBandSD = 1.0`. The position is `below`, `above` or `within`, comparing unrounded ln numbers. | Studies that guide training by HRV set the smallest worthwhile change as a fraction of the person's own day-to-day variation. Le Meur used 0.5 and Plews used 1 times the coefficient of variation [S4]. Modelled, 0.5 leaves the weekly mean outside the range on about 38% of ordinary days, against about 9% at 1.0 (§5.1). A status that is grey on more than a third of ordinary mornings tells the owner nothing. |
| D4 | **Both directions shown, neither called good.** Below and above both get the grey triangle. | A raised weekly mean followed functional overreaching in one controlled study [S5], and Garmin says the same of "abnormally high HRV" [V3]. A lowered one preceded non-functional overreaching in a case study [S1]. A meta-analysis found resting HRV "largely unaffected by overreaching" [S6]. |
| D5 | **No amber, no flag, no banner, no Home change.** | Amber means the Health Monitor's two-night pattern and nothing else (DESIGN.md, The Amber Is A Pattern Rule). The evidence linking a weekly HRV shift to overreaching is a case study and a mixed meta-analysis (D4). Garmin and Oura show the same kind of state as a label and send no alert [V2][V3]. §4 and §5 give the counts a banner would have had. |
| D6 | **Output.** `day.vitals.hrv_trend`, shaped like a VitalMetric plus `nights`. It is never part of `metrics`, `outside_range`, `adverse`, `metrics_with_range` or `monitor_state`. | The app draws it with the existing vital tile (§8). The Health Monitor's counts stay as #26 defined them. |
| D7 | **Brief.** `brief` gains `hrv_trend {position, nights, baseline_values}`, plus `value`, `range_low` and `range_high` with `--include-values`. `trend.hrv_rmssd_ms` (scores.md §11b) is unchanged. | Agents can repeat the tile's statement. §11b stays a display-only comparison of two arithmetic means and keeps its meaning. |
| D8 | **Constants.** `score_constants` gains `hrv_trend {days, min_nights, band_sd, min_baseline}`. The app reads `days` for the tile title and the Trends sentence. It keeps no copy of any of the four. | AGENTS.md hard rule; engine-numbers-spec.md D1. |
| D9 | **`score_version`** goes up one minor version on top of whatever `main` carries when the engine step lands. Today that is 2.3.0 → **2.4.0**. | New engine output (scores.md §0). Recovery, Strain, Sleep and the Health Monitor do not change. |

Rejected:
- **The smallest worthwhile change at 0.5.** It is the commonest published value [S4][S7][S8], but it was chosen to switch a day's training, where a false call costs one easy session. As a status it is outside on about 38% of ordinary days modelled, and was below on 14 of the owner's 20 ranged days (§4, §5).
- **A baseline that overlaps the week** (§1.3 as of D). The week is then compared partly with itself. Modelled at the same constant it catches about half as many slow declines (§5.2).
- **A 60-day baseline**, nearer Oura's three months [V2]. Modelled, it is no better than 28 values at the same false rate (§5.2). The owner's store has about 6 weeks of HRV, so it would not be ready for weeks.
- **The coefficient of variation of the weekly mean** [S1][S4]. Plews saw it fall towards non-functional overreaching. It is a second number to explain, its direction is ambiguous on its own, and no published threshold exists for it. It can follow later if the mean proves useful.
- **A health flag after N days below.** See D5. §13 asks the lead.

## 2. Target

I set this target after the first model run was on screen. The constant in D3 also stands on its own published value: 1 × the person's coefficient of variation, as Plews used [S4].

- **Ordinary weeks:** the 7-day average sits inside its range on at least 9 ordinary days in 10, on the model's typical settings.
- **Sensitivity:** a decline of 1.5 usual spreads built up over 21 days shows below at least once within those 21 days in at least 85% of modelled runs.

The owner's 20 ranged days cannot test either rate. They check that the rule is not wildly off on real data.

## 3. Research case

All sources were retrieved on 2026-11-22. Numbers below come from pages read in this session. Several sources are abstracts only, and §14 says which.

### 3.1 How other wearables show it

| Product | What it does | Source |
| --- | --- | --- |
| Garmin HRV Status | Compares "your 7-day average HRV" with "your personal baseline range". Balanced is inside the range. Unbalanced is outside it, "either higher or slightly lower". Low is "significantly below". It needs "around three weeks" of nightly wear. Garmin adds that "abnormally high HRV values relative to your personal baseline" can go with functional overreach. | [V3] |
| Oura | The readiness contributor HRV Balance "compares your average HRV from the past 14 days against your three-month average", weighted to recent days. It "can highlight the negative effects of prolonged stressors (such as overtraining or illness)". The HRV rating in Trends reflects "your average HRV over the past seven days as compared to your long-term average". | [V2] |
| WHOOP | Shows HRV each morning against the person's own history. Its 2026 podcast on HRV-CV discusses day-to-day variation as a separate signal. Neither page gives a weekly rule. | [V4] |

They share one pattern. A weekly average is judged against a personal range learned over weeks. The result is a label in a trend view. None of them sends an alert for it.

### 3.2 What the studies found

| Study | Signal | Rule | Result that matters here |
| --- | --- | --- | --- |
| Plews 2012 [S1] | Morning ln RMSSD, two elite triathletes, 77 days | 7-day rolling average and its CV | The rolling average "declined towards the day of triathlon event" in the athlete later diagnosed as non-functionally overreached, and stayed stable in the other. One case. |
| Plews 2013 [S2] | Morning ln RMSSD, elite rowers | Weekly and 7-day rolling averages plotted against the athlete's smallest worthwhile change | A weekly change counted as clear only when its 90% confidence interval cleared that band (figure captions). |
| Plews 2014 [S3] | ln RMSSD | Days per week needed | "A minimum of 3 (randomly selected) valid data points per week." |
| Buchheit 2014 [S4] | Review of HR measures | Smallest worthwhile change | "SWC = 0.5 Le Meur et al., 2013b or 1 Plews et al., 2012, 2013b × CV". Also: "there is currently no evidence that changes greater than any fraction of the CV would actually be meaningful in practice", and the size of change for negative adaptation "has still to be investigated". |
| Le Meur 2013 [S5] | Daily HRV, 21 triathletes, 3-week overload | Weekly means | Overload led to functional overreaching, and the weekly mean of ln RMSSD **rose**. Single weekly readings missed it. |
| Bellenger 2016 [S6] | Meta-analysis, 24 studies | Resting and post-exercise HRV | Training that lowered performance gave "a small increase in resting RMSSD". "Resting HRV is largely unaffected by overreaching." |
| Vesterinen 2016 [S7] | Morning HRV, 40 recreational runners | Hard sessions only when HRV was "within an individually determined smallest worthwhile change" | The HRV-guided group improved 3000 m time with fewer hard sessions. |
| Javaloyes 2019 [S8] | ln RMSSD, cyclists | 7-day rolling average against a 4-week baseline ± 0.5 SD | HRV-guided training improved performance. |

### 3.3 What that means for ghoops

1. **A week, not a night.** Every source that tracks slow change averages several days [S1][S2][S5]. Single readings missed what weekly means showed [S4][S5].
2. **The baseline ends before the week.** Studies fix a baseline period first, then judge later weeks against it [S7][S8].
3. **The direction is not a verdict.** HRV went down before one athlete's overreaching [S1] and up in another study's overreaching [S5]. A meta-analysis found little change on average [S6]. ghoops shows the shift both ways and says nothing about its cause.
4. **The size of change that matters is unsettled** [S4]. The constant is a choice among published values, and the model shows what each costs (§5).
5. **Nightly wrist HRV is not morning chest-strap HRV.** Every study above used short morning recordings. Google's daily HRV comes from sleep. The method carries over in shape. Its thresholds may not carry over in size, which is one more reason the tile stays grey.

## 4. Replay on the owner's store (counts only)

**Method.** Two scripts kept outside the repo, in a temporary folder, ran the installed `~/.local/bin/ghealth --json days --days 90`. The gate script also ran `day --date <d>` for each date with HRV. They held the output in memory and printed counts and booleans only. Nothing was written to the store, no dev binary touched it, and nothing called Google. Both scripts were debugged on a synthetic 90-day body before they read real data.

**Gate.** The replay rebuilds each night's §1.3 HRV baseline from the day rows. Its baseline counts agree with the engine's `baseline_values` on 38 of 38 nights with HRV. Its nightly positions at ±1.25 SD agree with the engine's on 31 of 31 ranged nights.

**Denominators.** 38 nights with HRV in the 90-day read. 35 seven-day windows end on or after the 7th day of data. Each had at least 5 nights with HRV (3 windows had 5, 15 had 6, 17 had 7), so the 4-night minimum never blocked one. 20 days had a ranged trend with the 14-value baseline, and 13 with a 21-value one. The SD floor was active on 0 of the 20.

| Rule (7-day window, 4-night minimum) | Ranged days | Within | Below (separate runs, longest run) | Above | Weeks below, of 3 ranged |
| --- | --- | --- | --- | --- | --- |
| 14-value baseline, band 0.5 | 20 | 6 | 14 (4 runs, longest 9) | 0 | 2 |
| 14-value baseline, band 0.75 | 20 | 12 | 8 (2 runs, longest 7) | 0 | 2 |
| **14-value baseline, band 1.0 (chosen)** | **20** | **14** | **6 (2 runs, longest 3)** | **0** | **1** |
| 14-value baseline, band 1.25 | 20 | 19 | 1 (1 run) | 0 | 0 |
| 21-value baseline, band 0.5 / 0.75 / 1.0 | 13 | 3 / 6 / 7 | 10 / 7 / 6 | 0 | n/a |

The 4- and 5-night minimums give identical counts. "Weeks" are non-overlapping 7-day windows counted back from the last date, each judged on its last day.

**On screen under the chosen rule:** the tile would have shown the mint tick on 14 of the 20 ranged days and the grey down triangle on 6. On the days before that, it showed "Building baseline".

**What 20 days can and cannot show.** 6 of 20 is above the modelled ordinary rate of about 5 to 8% (§5.1). The 6 days fall in 2 runs, so they are 2 episodes, not 6 events. Two episodes cannot tell a real shift from chance, and the store holds no record of training load or illness. The baseline on those days was also the first 2 to 4 weeks of wearing the band, which may not be typical. The constant does not depend on this replay.

## 5. Model (synthetic data only)

**Set-up.** Nightly ln RMSSD is a constant plus AR(1) noise with a usual spread σ of 0.20. That is above the 0.10 floor, which the owner's store never triggered (§4). Carry-over from one night to the next is 0.3 or 0.5, and tails are normal or Student t with 5 degrees of freedom ("heavy"). 10% of nights are missing at random. Each day is judged by the rule in §6. "Ordinary" means days with no shift and a full 28-value baseline. An episode starts on night 0. A ramp lowers the mean steadily to its full size by the stated night and holds it. A step lowers it at once. 600 runs per cell. These are modelled rates, not measured ones.

### 5.1 Ordinary days

| Setting | Band | Below | Above | 21-day spans with any below day |
| --- | --- | --- | --- | --- |
| Normal, carry 0.3 | 0.5 / 0.75 / **1.0** / 1.25 | 19.2 / 9.9 / **4.5** / 1.9% | 19.6 / 9.8 / **4.6** / 2.0% | 76 / 54 / **32** / 16% |
| Heavy, carry 0.3 | 0.5 / 0.75 / **1.0** / 1.25 | 18.6 / 9.8 / **4.7** / 2.2% | 19.1 / 10.1 / **5.0** / 2.3% | 74 / 51 / **31** / 16% |
| Heavy, carry 0.5 | 0.5 / 0.75 / **1.0** / 1.25 | 23.5 / 14.1 / **8.0** / 4.4% | 23.1 / 13.9 / **7.7** / 4.2% | 80 / 62 / **43** / 28% |

At 1.0 the average is inside its range on 91%, 90% and 84% of ordinary days in the three settings. With a young baseline of 14 values the below rate at 1.0 rises to 6.4%, 6.9% and 10.7%. About a third of ordinary three-week spans hold at least one grey below day. The tile is information, not an alarm, and §9 says so on screen.

### 5.2 Slow declines

Catch rates are below on night 7 / 14 / 21 after onset, then below on any night 1 to 21, in %. The table uses heavy tails and carry-over 0.3. Normal tails give results within a few points. Carry-over 0.5 catches up to about 10 points more, and false-flags more (§5.1).

| Episode | Band 0.5 | 0.75 | **1.0** | 1.25 | 1.0, baseline overlaps the week | 1.0, 60-day baseline |
| --- | --- | --- | --- | --- | --- | --- |
| Ramp to 0.5 σ over 14 nights | 26/43/47, any 93 | 14/30/29, any 81 | **8/17/15, any 60** | 4/10/9, any 41 | 3/7/6, any 36 | 6/16/16, any 54 |
| Ramp to 1.0 σ over 14 nights | 39/67/68, any 99 | 25/49/48, any 94 | **12/34/30, any 81** | 6/22/19, any 60 | 4/15/13, any 56 | 11/35/38, any 82 |
| Ramp to 1.0 σ over 21 nights | 30/52/64, any 96 | 15/32/48, any 87 | **8/19/32, any 69** | 4/12/18, any 50 | 2/8/12, any 42 | 6/18/34, any 67 |
| Ramp to 1.5 σ over 21 nights | 35/70/82, any 99 | 23/51/70, any 96 | **13/33/52, any 88** | 6/20/36, any 70 | 6/16/25, any 64 | 11/33/61, any 87 |
| Step of 1.0 σ, held | 78/66/48, any 100 | 64/48/32, any 98 | **48/30/18, any 92** | 31/17/9, any 76 | 25/10/5, any 69 | 50/35/28, any 90 |
| Step of 0.75 σ for 7 nights | any in 1–7: 77 | 62 | **43** | 30 | 24 | 41 |

The last row is the overreaching pattern of health-monitor-flag-spec.md §5.1, which the nightly rule caught early in 14 to 19% of runs. That figure needed HRV and resting HR together, so the two rows are not exactly alike. The weekly rule sees the HRV half of it on some night of the week in 43%.

A step held for weeks fades after about three weeks, because the baseline absorbs the new level. That is expected: the range follows the person, as Garmin's does [V3]. The tile reports a recent shift, not a permanent one.

At 1.0, "any below in nights 1 to 21" is 81–88% for the larger ramps and 60–69% for the smaller, against 31% for an ordinary three-week span. The rule tells larger slow declines from noise reasonably well, and smaller ones only weakly.

## 6. The rule (scores.md §5.3, as it will read)

### 6.1 New §5.3 Weekly HRV trend

> For date D:
>
> 1. `nights` is the number of London dates D−6 … D on which daily HRV is `available` (§1.3, step 2).
> 2. When `nights ≥ HRVTrendMinNights`, `mean_w` is the mean of `ln(rmssd_ms)` over those nights, `value = exp(mean_w)` rounded to 1 dp, and `status` is `available`. Otherwise `value`, `range_low`, `range_high` and `position` are null and `status` is `missing`.
> 3. The baseline is the §1.3 HRV baseline for date D−(`HRVTrendDays` − 1): dates D−7 … D−48, at most 28 values, ln-transformed. `baseline_values` is its `n`. `sd_eff = max(sd, SDFloorLnRMSSD)`.
> 4. When `n ≥ HRVTrendMinBaseline`, `range_low = exp(mean_b − HRVTrendBandSD × sd_eff)` and `range_high = exp(mean_b + HRVTrendBandSD × sd_eff)`, each rounded to 1 dp. Otherwise both are null.
> 5. `position` is null when `value` is null; `no_baseline` when `n < HRVTrendMinBaseline`; otherwise `below` when `mean_w < mean_b − HRVTrendBandSD × sd_eff`, `above` when `mean_w > mean_b + HRVTrendBandSD × sd_eff`, else `within`. Compare unrounded numbers.
> 6. `unit` is `ms`.
>
> `hrv_trend` is display only. It never enters `metrics`, `outside_range`, `adverse`, `persistent`, `metrics_with_range`, `monitor_state`, any health flag or any score.
>
> Sources: 7-day rolling ln RMSSD after Plews et al. 2012 and 2013; the 1 × CV band after Plews as reported by Buchheit 2014; at least 3 nights a week after Plews et al. 2014. The 4-night minimum, the lag and the 14-value minimum are ghoops choices.

### 6.2 §0 Constants: rows to add

| Name | Value | Used in |
| --- | --- | --- |
| `HRVTrendDays` | 7 | §5.3; reported in `score_constants` |
| `HRVTrendMinNights` | 4 | §5.3; reported in `score_constants` |
| `HRVTrendBandSD` | 1.0 | §5.3; reported in `score_constants` |
| `HRVTrendMinBaseline` | 14 | §5.3; reported in `score_constants` |

The header's `score_version` and the §9 envelope example take the new version (D9).

### 6.3 §11 Sources: entries to add

S3, S5, S6, S7 and S8 from §14. §11 already lists S1 (as its [S7]), S2 and S4. Vendor pages stay in this spec.

### 6.4 Worked example (synthetic; becomes golden case `below`)

Baseline, most recent first, 14 values: `[60.2, 47.6, 64.3, 52.0, 45.8, 66.5, 55.1, 50.4, 61.7, 48.3, 58.8, 63.1, 46.9, 57.4]`. Its ln mean is 4.0102 and its sample SD 0.1284, above the 0.10 floor. The range is 48.511 to 62.714, reported as `[48.5, 62.7]`.

Week, D first: `[44.1, 47.8, 43.6, 49.2, null, 45.9, 46.3]`. `nights` is 6. The ln mean is 3.8310, so `value` is 46.1 and `position` is `below`.

With the week `[55.0, 52.3, 57.9, null, 53.6, 56.2, 54.8]` instead, `value` is 54.9 and `position` is `within` (golden case `within`).

## 7. Contract

- **§5.1.1 `score_constants`** gains `"hrv_trend": {"days": 7, "min_nights": 4, "band_sd": 1.0, "min_baseline": 14}` after `vitals`. Row: "`hrv_trend` | `{days: int, min_nights: int, band_sd: num, min_baseline: int}` | scores.md §5.3. Added on <date of step T1>." A Mac built before that date omits it, and a client treats it as unknown.
- **§5.6 `vitals`** gains a row after `monitor_state`: "`hrv_trend` | object | a VitalMetric plus `nights: int` (scores.md §5.3). `baseline_values` counts the baseline before the week. Display only. Added on <date>."
- **§5.13 `brief`** gains a row after `vitals_adverse`: "`hrv_trend` | `{position, nights, baseline_values}` | `value`, `range_low`, `range_high`". Add one sentence: "`hrv_trend` and `trend.hrv_rmssd_ms` differ. The first compares a 7-day ln mean with a range built before the week (scores.md §5.3). The second compares two arithmetic means (§11b)."
- Consumers ignore unknown keys (§1.2), so `schema_version` stays 2. `scripts/v2_shape.py` treats `hrv_trend.position` like the other positions.

## 8. Engine numbers in the app

| Number | Where the app gets it | Used for |
| --- | --- | --- |
| `HRVTrendDays` | `score_constants.hrv_trend.days` | the tile title ("HRV 7-day average"), the "<nights> of 7 nights" chip, and whether the Trends week view's sentence uses the trend (§9) |
| `HRVTrendBandSD`, `HRVTrendMinBaseline`, `HRVTrendMinNights` | already applied by the Mac; reported in `score_constants.hrv_trend` | not used by the app today; reported for a later info sheet |
| the range and position | `vitals.hrv_trend.range_low`, `range_high`, `position` | the chip numbers and the tick or triangle |

The app never averages HRV for this tile and keeps no copy of 7, 4, 1.0 or 14. Against a Mac without `vitals.hrv_trend` or without `score_constants.hrv_trend`, the tile is absent, the slot stays empty as today, and the Trends sentence keeps today's wording.

## 9. The app

The visible change is in the mockup and needs the owner's approval before the UI step. Every value in it is synthetic. The UI ships dark behind `GoopFeature.hrvTrend`, on in Debug and off in Release, until the lead turns it on.

| Surface | Today | New |
| --- | --- | --- |
| Health screen, Overnight Vitals grid | 5 tiles; the slot beside skin temperature is empty | A sixth tile, `vital-hrv_trend`, in that slot: HRV symbol, title "HRV <days>-day average", the value in ms, and a chip with the range. Mint tick inside, grey triangle above or below, "Building baseline" for `no_baseline`, "<nights> of <days> nights" with a `—` value for `missing`. Tapping it opens the HRV trend view, as the HRV tile does. At accessibility sizes it is the last row of the one-column grid |
| Tile VoiceOver | n/a | The vital tile's own format: "HRV 7-day average, 46.1 milliseconds, below typical range 48.5 to 62.7" |
| Trends, HRV, week view ending on the default date | "Your average HRV over these 7 days was within its typical range (<tonight's range>)." This compares a 7-day mean with a one-night range, which it nearly always sits inside (data-honesty-audit fix 9) | When `hrv_trend.position` is `within`, `below` or `above` and the view's length equals `hrv_trend.days`: "Your <days>-day HRV average is <within / below / above> your usual range." The "<n> of <days> days have data." suffix stays. Other windows, other metrics and past end dates keep today's sentence |
| Health Monitor card, flags, banners, Home, widgets | | Unchanged |
| Footnote | "ghoops shows estimates and your own ranges. It does not diagnose…" | Unchanged. It already covers the tile |

The new sentence carries no numbers. The view's big AVERAGE is an arithmetic mean of the shown days, and the Mac's is a geometric one, so a number in the sentence could disagree with it by a few tenths near the edge.

The mockup has four sections. Section 1 shows the Health screen in four states: within, below, building and too few nights (`health-within`, `health-below`, `health-building`, `health-few`). Section 2 shows the HRV week view, today and new (`trend-now`, `trend-below`). Section 3 describes Garmin's and Oura's weekly HRV displays in words, with links, and gives the counts of how often each state would show. Section 4 is the approval question. Each key renders to `mockups/screens/hrv-trend-<key>.png` at 390 × 844 @3x.

**DESIGN.md rule.** Recorded in the UI step, under Colors, Named Rules:

> **The Weekly Tile Is Never Amber Rule.** The HRV 7-day average tile shows the mint tick inside its range and the grey triangle above or below it. It never uses amber and never raises a banner. A weekly shift is information. Amber stays the Health Monitor's two-night pattern.

## 10. Golden vectors

New file `fixtures/v2/scores/hrv_trend.json`, in the scores.md §9 envelope (`kind: score_vectors`, the new `score_version`, `synthetic_fixture: true`). Add a row to scores.md §9:

| File | Function under test | `input` fields | `expected` fields |
| --- | --- | --- | --- |
| `hrv_trend.json` | weekly HRV trend (§5.3) | `week_hrv_ms[7]` (D first; null for no value), `baseline_hrv_ms[]` (already selected, most recent first, at most 28) | `value`, `status`, `nights`, `range_low`, `range_high`, `baseline_values`, `position` |

Cases (synthetic; reuse §6.4's baseline unless a case says otherwise):

| Case | Proves |
| --- | --- |
| `within` | §6.4's second week: `within`, range `[48.5, 62.7]` |
| `below` | §6.4: `below`, value 46.1, nights 6 |
| `above` | a high week: `above` |
| `four_nights` | exactly 4 nights: `available` and ranged |
| `three_nights` | 3 nights: value null, `missing`, position null, range still reported, nights 3 |
| `no_nights` | 7 nulls: nights 0, `missing` |
| `baseline_13` | the first 13 baseline values: value present, `no_baseline`, range null, `baseline_values` 13 |
| `baseline_14` | all 14: ranged |
| `sd_floor` | a stable baseline whose sample SD is below 0.10: the range uses 0.10 |
| `just_inside` / `just_outside` | weeks whose ln mean sits 0.001 inside and outside the low edge |
| `range_asymmetric` | the reported range is asymmetric in ms around `exp(mean_b)` |

Compare integers exactly and decimals within one unit of the last place.

The lag (the baseline ends before the week) is a selection rule, so the whole-day goldens and one engine test prove it (plan T1).

Whole-response goldens: regenerating changes `score_version` and adds `vitals.hrv_trend`, `score_constants.hrv_trend` and, in `brief`, `hrv_trend`. Any other difference is a stop-and-tell-the-lead.

## 11. `score_version`

One minor bump on top of `main` when T1 lands (D9): `internal/score/constants.go` `Version`, the scores.md header and §9 example, every regenerated golden and `hrv_trend.json`. The three preview bodies keep the `score_version` they carry, as in earlier bumps.

## 12. Build

Steps T1 to T5 are in [hrv-trend-plan.md](hrv-trend-plan.md). T1 to T3 change no screen and may land before the owner approves the mockup. T4 waits for that approval. T5, turning the flag on in Release, waits for the lead.

## 13. Open questions for the lead

1. **The band.** Approve `HRVTrendBandSD = 1.0`? The alternatives are 0.5, the commonest published value (grey on about 38% of ordinary days modelled, 14 of the owner's 20), and 1.25 (inside on about 96%, but it catches a 1.5-spread decline over three weeks in about 70% of runs, against 88%).
2. **No alert.** Agree that the trend never raises a flag or banner (D5)? If the lead wants one later, the counts are these. A banner on every below day would have shown on 6 of the owner's 20 days and on about 5 to 8% of ordinary days modelled. A banner from the third below day in a row would have shown on 2 of the 20.
3. **Both directions.** Show above as well as below, both grey (D4)? The alternative is to treat above as within. Garmin and Le Meur both treat a high week as a change worth seeing [V3][S5].
4. **Trends sentence.** Change it only for the HRV week view ending on the default date (§9), and leave fix 9 to handle the other windows and metrics?
5. **Baseline minimum.** 14 values, or Garmin's three weeks (21)? At 21 the owner's store would have had 13 ranged days instead of 20.
6. **Brief.** Add `hrv_trend` and keep §11b's `trend.hrv_rmssd_ms` unchanged (D7)?
7. **Install.** T1 changes what an installed Mac sends, but no installed app reads the new fields, and the UI is dark in Release. Can the lead install the Mac alone after T1, or should it wait for the phone?

For the owner, one question, with the mockup: "Do these screens look right?" Recommended answer: approve as shown.

## 15. Lead review (2026-11-22)

The lead approved this spec at `32cf1c5` with the recommended answer to each question in §13: band 1.0; no flag or banner; both directions grey; the Trends sentence only on the HRV week view ending on the default date; a 14-value baseline; `brief` gains `hrv_trend` and §11b is unchanged. Install timing (question 7) stays the lead's call. The lead asked for the acceptance doc to say whether the 6 flagged days of 20 were one run: they were 2 runs, the longer 3 days.

T1 to T3 are built on 2026-11-22. T4 waits for the owner's approval of the mockup and is not built tonight.

## 14. Sources

Retrieved 2026-11-22.

- **[V2]** Oura Member Care. "Readiness Contributors" (HRV Balance; the HRV rating in Trends). https://support.ouraring.com/hc/en-us/articles/360057791533-Readiness-Contributors
- **[V3]** Garmin. "HRV Status." Garmin Technology, Health Science. https://www.garmin.com/en-US/garmin-technology/health-science/hrv-status/ ; and "Understanding the HRV Status on Your Garmin Smartwatch." https://www.garmin.com/en-US/blog/fitness/understanding-the-hrv-status-on-your-garmin-smartwatch/
- **[V4]** WHOOP. "Heart Rate Variability Explained: Benefits, Trends, and Insights." https://www.whoop.com/us/en/thelocker/heart-rate-variability-hrv/ ; "HRV-CV Explained" (podcast, 2026-02-25). https://www.whoop.com/us/en/thelocker/episode364-hrv-cv-explained/ (search excerpts only)
- **[S1]** Plews DJ, Laursen PB, Kilding AE, Buchheit M. Heart rate variability in elite triathletes, is variation in variability the key to effective training? A case comparison. *European Journal of Applied Physiology* 2012;112(11):3729–3741. doi:10.1007/s00421-012-2354-4. Abstract only (PubMed 22367011).
- **[S2]** Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring. *Sports Medicine* 2013;43(9):773–781. Figure captions only.
- **[S3]** Plews DJ, et al. Monitoring training with heart-rate variability: how much compliance is needed for valid assessment? *International Journal of Sports Physiology and Performance* 2014;9(5):783. Abstract only (PubMed 24334285).
- **[S4]** Buchheit M. Monitoring training status with HR measures: do all roads lead to Rome? *Frontiers in Physiology* 2014;5:73. doi:10.3389/fphys.2014.00073. Full text.
- **[S5]** Le Meur Y, et al. Evidence of parasympathetic hyperactivity in functionally overreached athletes. *Medicine and Science in Sports and Exercise* 2013;45(11):2061–2071. Abstract only (PubMed 24136138).
- **[S6]** Bellenger CR, et al. Monitoring athletic training status through autonomic heart rate regulation: a systematic review and meta-analysis. *Sports Medicine*, published online 2016-02-18. Abstract only (PubMed 26888648).
- **[S7]** Vesterinen V, et al. Individual endurance training prescription with heart rate variability. *Medicine and Science in Sports and Exercise* 2016;48(7):1347–1354. doi:10.1249/MSS.0000000000000910. Abstract only (PubMed 26909534).
- **[S8]** Javaloyes A, Sarabia JM, Lamberts RP, Moya-Ramón M. Training prescription guided by heart-rate variability in cycling. *International Journal of Sports Physiology and Performance* 2019;14(1):23–32. doi:10.1123/ijspp.2018-0122. Search excerpts only; the 4-week baseline and ± 0.5 SD come from those excerpts, not the paper.

ghoops sources: `internal/score/vitals.go`, `constants.go`, `report_constants.go`; `internal/v2report/trend.go`; `docs/v2/scores.md` §0, §1.3, §5, §9, §11b; `docs/v2/contract.md` §5.1.1, §5.6, §5.13; [health-monitor-flag-spec.md](health-monitor-flag-spec.md) §3.3 and §5.1; [engine-numbers-spec.md](engine-numbers-spec.md); [data-honesty-audit.md](data-honesty-audit.md) fix 9; `ios/GHealth/Screens/GoopHealthScreen.swift`, `GoopTrendScreen.swift`, `ios/GHealth/Components/Goop/GoopHealth.swift`, `ios/GHealthCore/Sources/GHealthCore/Presentation/Insights.swift`; DESIGN.md.
