package v2report

import "time"

type BriefTarget struct {
	Status   string  `json:"status"`
	Reason   *string `json:"reason"`
	Intent   string  `json:"intent"`
	Position *string `json:"position"`
	*BriefTargetValues
}
type BriefTargetValues struct {
	Low  *float64 `json:"low"`
	High *float64 `json:"high"`
}
type BriefPlan struct {
	Status     string  `json:"status"`
	Reason     *string `json:"reason"`
	WakeSource string  `json:"wake_source"`
	*BriefPlanValues
}
type BriefPlanValues struct {
	Need    int        `json:"need_minutes"`
	Bedtime *time.Time `json:"bedtime"`
}

// BriefHRVTrend is day.vitals.hrv_trend for agents (contract §5.13); values only with --include-values.
type BriefHRVTrend struct {
	Position *string `json:"position"`
	Nights   int     `json:"nights"`
	Baseline *int    `json:"baseline_values"`
	*BriefHRVTrendValues
}
type BriefHRVTrendValues struct {
	Value *float64 `json:"value"`
	Low   *float64 `json:"range_low"`
	High  *float64 `json:"range_high"`
}
type BriefReview struct {
	Workouts int      `json:"workouts"`
	Detected int      `json:"detected_efforts"`
	Flags    []string `json:"new_flags"`
	*BriefReviewValues
}
type BriefReviewValues struct {
	Zones13 *int `json:"zones_1_3_minutes"`
	Zones45 *int `json:"zones_4_5_minutes"`
}

func (b *Builder) Brief(date string, values bool, part string) Brief {
	d := b.Day(date)
	f := d.Freshness
	out := Brief{
		Envelope: b.envelope("brief"), Disclosure: "status_only", Part: part, Date: date,
		Freshness: BriefFreshness{f.Collected, f.CollectorStale, f.DeviceStale},
		Recovery:  BriefRecovery{Status: d.Recovery.Status, Reason: d.Recovery.Reason, Band: d.Recovery.Band, Calibrating: d.Recovery.Calibrating},
		Strain:    BriefStrain{Status: d.Strain.Status, Reason: d.Strain.Reason, Band: d.Strain.Band, Confidence: d.Strain.Confidence},
		Target:    BriefTarget{Status: d.StrainTarget.Status, Reason: d.StrainTarget.Reason, Intent: d.StrainTarget.Intent, Position: d.StrainTarget.Position},
		Sleep:     BriefSleep{Status: d.Sleep.Performance.Status, Reason: d.Sleep.Performance.Reason, Band: d.Sleep.Performance.Band},
		Adverse:   d.Vitals.Adverse, Workouts: []BriefWorkout{}, Flags: []string{},
		HRVTrend: BriefHRVTrend{Position: d.Vitals.HRVTrend.Position, Nights: d.Vitals.HRVTrend.Nights, Baseline: d.Vitals.HRVTrend.N},
		Note:     "ghoops estimates from documented formulas; not medical advice. Strain uses Banister's published heart-rate formula on a scale ghoops set from public examples; it is not WHOOP's Strain.",
	}
	if values {
		out.Disclosure = "values"
		out.Recovery.BriefRecoveryValues = &BriefRecoveryValues{d.Recovery.Value}
		out.Strain.BriefStrainValues = &BriefStrainValues{d.Strain.Value, d.Strain.Coverage}
		out.Target.BriefTargetValues = &BriefTargetValues{d.StrainTarget.Low, d.StrainTarget.High}
		out.Sleep.BriefSleepValues = &BriefSleepValues{d.Sleep.Performance.Value, d.Sleep.Asleep, d.Sleep.Need.Total}
		out.HRVTrend.BriefHRVTrendValues = &BriefHRVTrendValues{d.Vitals.HRVTrend.Value, d.Vitals.HRVTrend.Low, d.Vitals.HRVTrend.High}
	}
	if plan := d.SleepPlan; plan != nil {
		out.Plan = &BriefPlan{Status: plan.Status, Reason: plan.Reason, WakeSource: plan.WakeSource}
		if values {
			out.Plan.BriefPlanValues = &BriefPlanValues{Need: plan.Need}
			for _, goal := range plan.Goals {
				if goal.Percent == 100 {
					out.Plan.Bedtime = ptr(goal.Bedtime)
				}
			}
		}
	}
	rows := make([]DayRow, 0, TrendLongDays)
	end := b.engine.Date(date)
	for at := end.AddDate(0, 0, 1-TrendLongDays); !at.After(end); at = at.AddDate(0, 0, 1) {
		rows = append(rows, b.row(at.Format("2006-01-02")))
	}
	out.Trend = briefTrends(rows, values)
	for _, w := range d.Workouts {
		entry := BriefWorkout{Kind: w.Kind, Category: w.Category, Type: w.Type}
		if w.Suggested != nil {
			entry.Suggested = ptr(w.Suggested.Type)
		}
		if values {
			entry.BriefWorkoutValues = &BriefWorkoutValues{w.Elapsed, w.Strain}
		}
		out.Workouts = append(out.Workouts, entry)
	}
	for _, flag := range d.Flags {
		out.Flags = append(out.Flags, flag.Code)
	}
	if part == "evening" {
		out.Review = b.briefReview(d, values)
	}
	if part == "week" {
		out.Week = briefWeek(b.Week(date), values)
	}
	return out
}

func (b *Builder) briefReview(d Day, values bool) *BriefReview {
	out := &BriefReview{Flags: []string{}}
	for _, w := range d.Workouts {
		if w.Kind == "recorded" || w.Kind == "goop" {
			out.Workouts++
		}
		if w.Kind == "detected" {
			out.Detected++
		}
	}
	previous := b.engine.Date(d.Date).AddDate(0, 0, -1).Format("2006-01-02")
	seen := map[string]bool{}
	for _, flag := range b.engine.Flags(previous, b.engine.Vitals(previous)) {
		seen[flag.Code] = true
	}
	for _, flag := range d.Flags {
		if !seen[flag.Code] {
			out.Flags = append(out.Flags, flag.Code)
		}
	}
	if values {
		out.BriefReviewValues = &BriefReviewValues{}
		if zones := d.Strain.Zones; zones != nil {
			out.Zones13, out.Zones45 = ptr(zones.Z1+zones.Z2+zones.Z3), ptr(zones.Z4+zones.Z5)
		}
	}
	return out
}
