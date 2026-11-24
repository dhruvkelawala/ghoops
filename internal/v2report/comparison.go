package v2report

import (
	"github.com/dhruvkelawala/ghoops/internal/score"
	"math"
)

type ComparisonValue struct {
	Mean *float64 `json:"mean"`
	Days int      `json:"available_days"`
}
type Comparison struct {
	Window  int               `json:"window_days"`
	From    string            `json:"from"`
	To      string            `json:"to"`
	Min     int               `json:"min_days"`
	Metrics ComparisonMetrics `json:"metrics"`
}
type ComparisonMetrics struct {
	Recovery    ComparisonValue `json:"recovery"`
	Strain      ComparisonValue `json:"strain"`
	Performance ComparisonValue `json:"sleep_performance"`
	Asleep      ComparisonValue `json:"asleep_minutes"`
	Efficiency  ComparisonValue `json:"efficiency_pct"`
	Restorative ComparisonValue `json:"restorative_minutes"`
	HRV         ComparisonValue `json:"hrv_rmssd_ms"`
	RHR         ComparisonValue `json:"resting_hr_bpm"`
	RR          ComparisonValue `json:"respiratory_rate_bpm"`
	SpO2        ComparisonValue `json:"spo2_pct"`
	Temperature ComparisonValue `json:"skin_temp_deviation_c"`
	Steps       ComparisonValue `json:"steps"`
	Zones13     ComparisonValue `json:"zones_1_3_minutes"`
	Zones45     ComparisonValue `json:"zones_4_5_minutes"`
	Strength    ComparisonValue `json:"strength_minutes"`
	// PerformanceComposite is present only in composite mode (composite-sleep-spec D9).
	PerformanceComposite *ComparisonValue `json:"sleep_performance_composite,omitempty"`
}

func (b *Builder) comparison(date string) Comparison {
	end := b.engine.Date(date)
	out := Comparison{Window: score.ComparisonDays, From: end.AddDate(0, 0, -score.ComparisonDays).Format("2006-01-02"), To: end.AddDate(0, 0, -1).Format("2006-01-02"), Min: score.ComparisonMinDays}
	if b.engine.Config.CompositeSleep() {
		out.Metrics.PerformanceComposite = &ComparisonValue{}
	}
	for k := score.ComparisonDays; k >= 1; k-- {
		row := b.row(end.AddDate(0, 0, -k).Format("2006-01-02"))
		out.Metrics.Recovery.add(row.Recovery)
		out.Metrics.Strain.add(row.Strain)
		out.Metrics.Performance.add(row.Performance)
		out.Metrics.Asleep.add(floatValue(row.Asleep))
		out.Metrics.Efficiency.add(floatValue(row.Efficiency))
		out.Metrics.Restorative.add(floatValue(row.Restorative))
		out.Metrics.HRV.add(row.HRV)
		out.Metrics.RHR.add(row.RHR)
		out.Metrics.RR.add(row.RR)
		out.Metrics.SpO2.add(row.SpO2)
		out.Metrics.Temperature.add(row.Temperature)
		out.Metrics.Steps.add(row.Steps)
		out.Metrics.Zones13.add(floatValue(row.Zones13))
		out.Metrics.Zones45.add(floatValue(row.Zones45))
		out.Metrics.Strength.add(floatValue(row.Strength))
		if out.Metrics.PerformanceComposite != nil && row.PerformanceComposite != nil {
			out.Metrics.PerformanceComposite.add(*row.PerformanceComposite)
		}
	}
	out.Metrics.Recovery.finish(1)
	out.Metrics.Strain.finish(1)
	out.Metrics.Performance.finish(1)
	out.Metrics.Asleep.finish(1)
	out.Metrics.Efficiency.finish(1)
	out.Metrics.Restorative.finish(1)
	out.Metrics.HRV.finish(1)
	out.Metrics.RHR.finish(1)
	out.Metrics.RR.finish(1)
	out.Metrics.SpO2.finish(1)
	out.Metrics.Temperature.finish(2)
	out.Metrics.Steps.finish(0)
	out.Metrics.Zones13.finish(1)
	out.Metrics.Zones45.finish(1)
	out.Metrics.Strength.finish(1)
	if out.Metrics.PerformanceComposite != nil {
		out.Metrics.PerformanceComposite.finish(1)
	}
	return out
}
func (v *ComparisonValue) add(value *float64) {
	if value == nil {
		return
	}
	if v.Mean == nil {
		v.Mean = ptr(0.0)
	}
	*v.Mean += *value
	v.Days++
}
func (v *ComparisonValue) finish(places int) {
	if v.Days < score.ComparisonMinDays {
		v.Mean = nil
		return
	}
	scale := math.Pow10(places)
	*v.Mean = math.Round(*v.Mean/float64(v.Days)*scale) / scale
}
func floatValue(value *int) *float64 {
	if value == nil {
		return nil
	}
	return ptr(float64(*value))
}
func intValue(value *float64) *int {
	if value == nil {
		return nil
	}
	return ptr(int(math.Round(*value)))
}
func (b *Builder) strength(date string, workouts []score.Workout) *int {
	sum, count := 0.0, 0
	for _, workout := range workouts {
		if (workout.Kind == "recorded" || workout.Kind == "goop") && workout.Category == "strength" {
			sum += workout.Elapsed
			count++
		}
	}
	if count == 0 && b.engine.MissingStatus(date, "exercise", "list") != "missing" {
		return nil
	}
	return ptr(int(math.Round(sum)))
}
