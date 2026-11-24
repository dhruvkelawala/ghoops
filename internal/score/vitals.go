package score

import (
	"encoding/json"
	"fmt"
	"math"
	"slices"
)

type VitalInput struct {
	Value    *float64
	Status   string
	Baseline []float64
}
type NightInput struct {
	HRV, RHR, RR, SpO2 VitalInput
	Temp               *TemperatureInput
	TempStatus         string
}

func (e *Engine) Vitals(date string) Vitals {
	before := make([]Vitals, 0, VitalAttentionNights-1)
	for k := 1; k < VitalAttentionNights; k++ {
		before = append(before, night(e.nightInput(e.add(date, -k))))
	}
	v := withAttention(night(e.nightInput(date)), before)
	week := []float64{}
	for k := 0; k < HRVTrendDays; k++ {
		if value, status := e.metric(e.add(date, -k), "daily-heart-rate-variability"); status == "available" {
			week = append(week, *value)
		}
	}
	v.HRVTrend = hrvTrend(week, e.baseline(e.add(date, -(HRVTrendDays-1)), "daily-heart-rate-variability"))
	return v
}

// hrvTrend is scores.md §5.3. week holds the available HRV values in D-6 … D; baseline is the
// §1.3 HRV baseline taken as of D-6, so it ends before the week starts.
func hrvTrend(week, baseline []float64) HRVTrend {
	out := HRVTrend{Vital: Vital{Unit: "ms", Status: "missing", N: ptr(len(baseline))}, Nights: len(week)}
	base := stats(baseline, SDFloorLnRMSSD, true)
	ranged := base.n >= HRVTrendMinBaseline
	low, high := base.mean-HRVTrendBandSD*base.sd, base.mean+HRVTrendBandSD*base.sd
	if ranged {
		out.Low, out.High = ptr(round(math.Exp(low), 1)), ptr(round(math.Exp(high), 1))
	}
	if len(week) < HRVTrendMinNights {
		return out
	}
	mean := stats(week, 0, true).mean
	out.Value, out.Status, out.Position = ptr(round(math.Exp(mean), 1)), "available", ptr("no_baseline")
	if ranged {
		out.Position = position(mean, low, high)
	}
	return out
}

func (e *Engine) nightInput(date string) NightInput {
	metric := func(id string) VitalInput {
		value, status := e.metric(date, id)
		return VitalInput{value, status, e.baseline(date, id)}
	}
	status := e.MissingStatus(date, "daily-sleep-temperature-derivations", "list")
	if len(e.points["daily-sleep-temperature-derivations"][date]) > 1 {
		status = "conflict"
	}
	return NightInput{
		HRV: metric("daily-heart-rate-variability"), RHR: metric("daily-resting-heart-rate"),
		RR: metric("daily-respiratory-rate"), SpO2: metric("daily-oxygen-saturation"),
		Temp: e.temperature(date), TempStatus: status,
	}
}

func night(in NightInput) Vitals {
	out := Vitals{Needed: BaselineMinValues, Metrics: map[string]Vital{}, Outside: []string{}, Adverse: []string{}, Persistent: []string{}}
	for _, m := range []struct {
		key, unit string
		input     VitalInput
		floor     float64
		places    int
		log       bool
	}{
		{"hrv_rmssd", "ms", in.HRV, SDFloorLnRMSSD, 1, true},
		{"resting_hr", "bpm", in.RHR, SDFloorRestingHR, 0, false},
		{"respiratory_rate", "breaths_per_minute", in.RR, SDFloorRespRate, 1, false},
		{"spo2", "percent", in.SpO2, SDFloorSpO2, 1, false},
	} {
		value, status := m.input.Value, m.input.Status
		sample := stats(m.input.Baseline, m.floor, m.log)
		v := Vital{Value: rounded(value, m.places), Unit: m.unit, Status: status, N: ptr(sample.n)}
		if value != nil {
			v.Position = ptr("no_baseline")
		}
		if sample.n >= BaselineMinValues {
			low, high := sample.mean-VitalRangeSD*sample.sd, sample.mean+VitalRangeSD*sample.sd
			if m.log {
				low, high = math.Exp(low), math.Exp(high)
			}
			v.Low, v.High = ptr(round(low, 1)), ptr(round(high, 1))
			if value != nil {
				v.Position = position(*value, low, high)
			}
		}
		out.Metrics[m.key] = v
	}
	t := in.Temp
	v := Vital{Unit: "celsius_deviation", Status: in.TempStatus}
	if t != nil && t.Nightly != nil {
		v.Status = "available"
		v.Position = ptr("no_baseline")
		if t.Baseline != nil {
			value := *t.Nightly - *t.Baseline
			v.Value = ptr(round(value, 2))
			if t.SD != nil {
				sd := VitalRangeSD * math.Max(*t.SD, SDFloorSkinTemp)
				v.Low, v.High = ptr(round(-sd, 2)), ptr(round(sd, 2))
				v.Position = position(value, -sd, sd)
			}
		}
	}
	out.Metrics["skin_temp_deviation"] = v
	for _, key := range []string{"hrv_rmssd", "resting_hr", "respiratory_rate", "spo2", "skin_temp_deviation"} {
		v := out.Metrics[key]
		if v.Position == nil {
			continue
		}
		if *v.Position == "above" || *v.Position == "below" {
			out.Outside = append(out.Outside, key)
			if (key == "hrv_rmssd" || key == "spo2") && *v.Position == "below" || (key == "resting_hr" || key == "respiratory_rate" || key == "skin_temp_deviation") && *v.Position == "above" {
				out.Adverse = append(out.Adverse, key)
			}
		}
		if *v.Position != "no_baseline" {
			out.WithRange++
		}
	}
	return out
}

func withAttention(tonight Vitals, before []Vitals) Vitals {
	tonight.Persistent = []string{}
	if len(before) >= VitalAttentionNights-1 {
		for _, key := range tonight.Adverse {
			persistent := true
			for _, v := range before[:VitalAttentionNights-1] {
				persistent = persistent && slices.Contains(v.Adverse, key)
			}
			if persistent {
				tonight.Persistent = append(tonight.Persistent, key)
			}
		}
	}
	switch {
	case tonight.WithRange == 0:
		tonight.State = "building"
	case len(tonight.Persistent) >= VitalAttentionMinVitals:
		tonight.State = "attention"
	case len(tonight.Outside) > 0:
		tonight.State = "outside"
	default:
		tonight.State = "within"
	}
	return tonight
}

func position(value, low, high float64) *string {
	if value < low {
		return ptr("below")
	}
	if value > high {
		return ptr("above")
	}
	return ptr("within")
}

func (e *Engine) Activity(date string) map[string]Metric {
	out := map[string]Metric{}
	for _, spec := range []struct {
		key, id, unit, field string
		paths                []string
		scale                float64
		places               int
	}{
		{"steps", "steps", "steps", "steps", []string{"countSum"}, 1, 0},
		{"active_zone_minutes", "active-zone-minutes", "minutes", "activeZoneMinutes", []string{"sumInFatBurnHeartZone", "sumInCardioHeartZone", "sumInPeakHeartZone"}, 1, 0},
		{"calories_kcal", "total-calories", "kcal", "totalCalories", []string{"kcalSum"}, 1, 0},
		{"distance_km", "distance", "km", "distance", []string{"millimetersSum"}, 1e6, 2},
	} {
		metric := Metric{Unit: spec.unit, Status: e.MissingStatus(date, spec.id, "dailyRollUp")}
		for _, row := range e.State.DailyRollups {
			if row.Date != date || row.Type != spec.id {
				continue
			}
			var fields map[string]map[string]json.RawMessage
			if json.Unmarshal(row.Value, &fields) != nil {
				continue
			}
			sum, present := 0.0, false
			for _, key := range spec.paths {
				raw := fields[spec.field][key]
				if len(raw) == 0 || string(raw) == "null" {
					continue
				}
				var value json.Number
				if json.Unmarshal(raw, &value) != nil {
					continue
				}
				v, err := value.Float64()
				if err == nil {
					sum += v
					present = true
				}
			}
			if present {
				v := round(sum/spec.scale, spec.places)
				if metric.Value != nil && *metric.Value != v {
					metric.Value = nil
					metric.Status = "conflict"
					break
				}
				metric.Value = &v
				metric.Status = "available"
			}
		}
		out[spec.key] = metric
	}
	return out
}
func (e *Engine) VO2(date string) VO2Max {
	out := VO2Max{Unit: "ml_per_kg_min", Status: "missing", Reason: ptr("no_data")}
	for k := 0; k <= 30; k++ {
		day := e.add(date, -k)
		for _, p := range e.points["daily-vo2-max"][day] {
			v := p.point.VO2
			if v != nil && v.VO2 != nil {
				return VO2Max{Value: rounded(number(v.VO2), 1), Unit: out.Unit, Date: &day, Level: text(v.Level), Estimated: v.Estimated, Status: "available"}
			}
		}
	}
	return out
}
func (e *Engine) ProviderTimezone() *string {
	var settings struct {
		Zone string `json:"timeZone"`
	}
	if e.State.User["settings"].Status != "ok" || json.Unmarshal(e.State.User["settings"].Body, &settings) != nil {
		return nil
	}
	return text(settings.Zone)
}
func (e *Engine) Flags(date string, v Vitals) []Flag {
	spo2, _ := e.metric(date, "daily-oxygen-saturation")
	out := vitalFlags(v, spo2, e.baseline(date, "daily-oxygen-saturation"))
	add := func(code, severity, message string) { out = append(out, Flag{code, severity, message}) }
	alert := false
	for day, rows := range e.points["irregular-rhythm-notification"] {
		if day >= e.add(date, -29) && day <= date && len(rows) > 0 {
			alert = true
		}
	}
	if alert {
		add("irn_alert_recorded", "attention", "Your Fitbit recorded an irregular rhythm notification. Check the Fitbit app and speak to a clinician if you are concerned.")
	}
	d := e.device
	if d.Battery != nil && *d.Battery < 20 || d.BatteryStatus != nil && (*d.BatteryStatus == "Low" || *d.BatteryStatus == "Empty") {
		add("device_battery_low", "info", "Tracker battery is low.")
	}
	if e.freshness.CollectorStale {
		add("collector_stale", "attention", "The Mac has not collected new data recently.")
	}
	if e.freshness.DeviceStale != nil && *e.freshness.DeviceStale {
		add("device_sync_stale", "info", "The tracker has not synced to the Fitbit app recently.")
	}
	if zone := e.ProviderTimezone(); zone != nil && *zone != "Europe/London" {
		add("provider_timezone_mismatch", "attention", "Your Google Health timezone is not Europe/London, so daily dates may not align.")
	}
	return out
}

func vitalFlags(v Vitals, spo2 *float64, spo2Baseline []float64) []Flag {
	out := []Flag{}
	if len(v.Persistent) >= VitalAttentionMinVitals {
		out = append(out, Flag{"vitals_outside_range", "attention", fmt.Sprintf("%d overnight vitals have been outside your usual range for %d nights in a row, in the less favourable direction.", len(v.Persistent), VitalAttentionNights)})
	}
	sample := stats(spo2Baseline, SDFloorSpO2, false)
	if spo2 != nil && sample.n >= BaselineMinValues && *spo2 < sample.mean-SpO2FlagSD*sample.sd {
		out = append(out, Flag{"spo2_below_usual", "attention", "Overnight SpO2 is well below your usual range."})
	}
	return out
}
