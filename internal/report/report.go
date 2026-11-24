package report

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
)

type Metric struct {
	Status           string               `json:"status"`
	Value            *float64             `json:"value"`
	Unit             string               `json:"unit"`
	Records          int                  `json:"observed_records"`
	LastSync         *time.Time           `json:"last_successful_sync"`
	LastObservedDate *string              `json:"last_observed_date"`
	Stale            bool                 `json:"stale"`
	Sources          []*health.DataSource `json:"raw_source_candidates"`
	Stream           string               `json:"stream"`
	Warnings         []string             `json:"warnings"`
}

type Sleep struct {
	Duration Metric            `json:"asleep_minutes"`
	Stages   map[string]Metric `json:"stage_minutes"`
	Sessions int               `json:"sessions"`
}
type HeartRate struct {
	Mean Metric `json:"sample_mean_bpm"`
	Min  Metric `json:"min_bpm"`
	Max  Metric `json:"max_bpm"`
}
type Workout struct {
	Types           []string             `json:"exercise_types"`
	Start           time.Time            `json:"start"`
	End             time.Time            `json:"end"`
	DurationMinutes float64              `json:"elapsed_minutes"`
	ActiveMinutes   *float64             `json:"active_minutes"`
	Lifting         bool                 `json:"lifting"`
	Wearable        *bool                `json:"recorded_by_wearable"`
	Sources         []*health.DataSource `json:"sources"`
	MergedRecords   int                  `json:"merged_records"`
	activeConflict  bool
}
type Exercise struct {
	Coverage Metric    `json:"coverage"`
	Workouts []Workout `json:"workouts"`
}
type Daily struct {
	Date       string    `json:"date"`
	Sleep      Sleep     `json:"sleep"`
	HRV        Metric    `json:"hrv_rmssd_ms"`
	SampleHRV  Metric    `json:"hrv_sample_rmssd_mean_ms"`
	SampleSDNN Metric    `json:"hrv_sample_sdnn_mean_ms"`
	RHR        Metric    `json:"resting_heart_rate_bpm"`
	Steps      Metric    `json:"steps"`
	HR         HeartRate `json:"heart_rate"`
	Exercise   Exercise  `json:"exercise"`
}
type Trend struct {
	Unit           string   `json:"unit"`
	Mean           *float64 `json:"mean"`
	FirstHalfMean  *float64 `json:"first_half_mean"`
	SecondHalfMean *float64 `json:"second_half_mean"`
	Change         *float64 `json:"change"`
	AvailableDays  int      `json:"available_days"`
	RequestedDays  int      `json:"requested_days"`
	StaleDays      int      `json:"stale_days"`
}
type Summary struct {
	Version              int              `json:"schema_version"`
	Source               string           `json:"source"`
	GeneratedAt          time.Time        `json:"generated_at"`
	Timezone             string           `json:"timezone"`
	DailyMetricsTimezone string           `json:"daily_metrics_timezone"`
	From                 string           `json:"from"`
	Until                string           `json:"until_exclusive"`
	Days                 []Daily          `json:"days"`
	Trends               map[string]Trend `json:"trends"`
	Synthetic            bool             `json:"synthetic_fixture,omitempty"`
}

func points(state cache.State, date, id, stream string) []health.Point {
	out := []health.Point{}
	for _, r := range state.Records {
		if r.Date == date && r.Type == id && r.Stream == stream {
			p, err := health.Decode(r)
			if err == nil {
				out = append(out, p)
			}
		}
	}
	return out
}

func base(state cache.State, date, id, stream, unit string, now time.Time) Metric {
	m := Metric{Status: "not_synced", Unit: unit, Stale: true, Sources: []*health.DataSource{}, Stream: stream, Warnings: []string{}}
	for _, c := range state.Coverage {
		if c.Date == date && c.Type == id && c.Stream == stream {
			m.LastSync = c.SuccessAt
			m.Status = c.Status
			if c.Status == "ok" {
				m.Status = "missing"
			}
			m.Stale = c.SuccessAt == nil || now.Sub(*c.SuccessAt) > 24*time.Hour || c.Status != "ok"
			if c.Error != "" {
				m.Warnings = append(m.Warnings, c.Error)
			}
		}
	}
	seen := map[string]bool{}
	for _, r := range state.Records {
		if r.Type != id {
			continue
		}
		if r.Date == date && r.Stream == stream {
			if _, err := health.Decode(r); err != nil {
				m.Status = "invalid_data"
				m.Warnings = append(m.Warnings, "invalid cached health record excluded")
				continue
			}
		}
		if r.Stream == stream && (m.LastObservedDate == nil || r.Date > *m.LastObservedDate) {
			d := r.Date
			m.LastObservedDate = &d
		}
		if r.Date == date && r.Stream == "raw" {
			p, err := health.Decode(r)
			if err == nil && p.DataSource != nil {
				b, _ := json.Marshal(p.DataSource)
				if !seen[string(b)] {
					m.Sources = append(m.Sources, p.DataSource)
					seen[string(b)] = true
				}
			}
		}
	}
	return m
}

func available(m Metric, v float64, n int) Metric {
	if m.Status == "invalid_data" {
		m.Value = nil
		m.Records = n
		return m
	}
	if math.IsNaN(v) || math.IsInf(v, 0) || v < 0 {
		m.Status = "invalid_data"
		m.Value = nil
		return m
	}
	m.Value = &v
	m.Records = n
	if m.Status == "missing" || m.Status == "not_synced" {
		m.Status = "available"
	}
	return m
}

func mean(values []float64) *float64 {
	if len(values) == 0 {
		return nil
	}
	total := 0.0
	for _, v := range values {
		total += v
	}
	v := total / float64(len(values))
	return &v
}

func scalar(m Metric, values []float64, average bool) Metric {
	if len(values) == 0 {
		return m
	}
	if average {
		return available(m, *mean(values), len(values))
	}
	for _, v := range values {
		if v != values[0] {
			if m.Status != "invalid_data" {
				m.Status = "conflict"
			}
			m.Records = len(values)
			m.Warnings = append(m.Warnings, "multiple distinct daily values; no value selected")
			return m
		}
	}
	return available(m, values[0], len(values))
}

func Days(state cache.State, from, until, now time.Time) Summary {
	s := Summary{Version: 1, Source: health.Source, GeneratedAt: now.UTC(), Timezone: from.Location().String(), DailyMetricsTimezone: "provider_civil_date", From: from.Format("2006-01-02"), Until: until.Format("2006-01-02"), Days: []Daily{}, Trends: map[string]Trend{}}
	for _, record := range state.Records {
		if record.Synthetic && record.Date >= s.From && record.Date < s.Until {
			s.Synthetic = true
		}
	}
	for d := from; d.Before(until); d = d.AddDate(0, 0, 1) {
		date := d.Format("2006-01-02")
		day := Daily{Date: date}
		day.Sleep = sleep(state, date, now)
		day.HRV = base(state, date, "daily-heart-rate-variability", "raw", "ms", now)
		var values []float64
		for _, p := range points(state, date, "daily-heart-rate-variability", "raw") {
			if p.DailyHRV != nil && p.DailyHRV.RMSSD != nil {
				values = append(values, float64(*p.DailyHRV.RMSSD))
			}
		}
		day.HRV = scalar(day.HRV, values, false)
		day.RHR = base(state, date, "daily-resting-heart-rate", "raw", "bpm", now)
		values = nil
		for _, p := range points(state, date, "daily-resting-heart-rate", "raw") {
			if p.RHR != nil && p.RHR.BPM != nil {
				values = append(values, float64(*p.RHR.BPM))
			}
		}
		day.RHR = scalar(day.RHR, values, false)
		day.SampleHRV = base(state, date, "heart-rate-variability", "raw", "ms", now)
		day.SampleSDNN = day.SampleHRV
		values = nil
		var sdnn []float64
		for _, p := range points(state, date, "heart-rate-variability", "raw") {
			if p.HRV != nil {
				if p.HRV.RMSSD != nil {
					values = append(values, float64(*p.HRV.RMSSD))
				}
				if p.HRV.SDNN != nil {
					sdnn = append(sdnn, float64(*p.HRV.SDNN))
				}
			}
		}
		day.SampleHRV = scalar(day.SampleHRV, values, true)
		day.SampleSDNN = scalar(day.SampleSDNN, sdnn, true)
		day.Steps = base(state, date, "steps", "reconciled", "steps", now)
		total, n := 0.0, 0
		for _, p := range points(state, date, "steps", "reconciled") {
			if p.Steps != nil {
				// Returned intervals with omitted count are true zeros, not missing data.
				// https://developers.google.com/health/data-types/steps#handle_true_zeros
				if p.Steps.Count != nil {
					total += float64(*p.Steps.Count)
				}
				n++
				if p.Steps.Interval.End.Add(-time.Nanosecond).In(from.Location()).Format("2006-01-02") != date {
					if day.Steps.Status != "invalid_data" {
						day.Steps.Status = "conflict"
					}
					day.Steps.Warnings = append(day.Steps.Warnings, "step interval crosses a reporting day; count not allocated")
				}
			}
		}
		if n > 0 && day.Steps.Status != "conflict" {
			day.Steps = available(day.Steps, total, n)
		}
		m := base(state, date, "heart-rate", "reconciled", "bpm", now)
		values = nil
		for _, p := range points(state, date, "heart-rate", "reconciled") {
			if p.HR != nil && p.HR.BPM != nil {
				values = append(values, float64(*p.HR.BPM))
			}
		}
		day.HR = HeartRate{Mean: scalar(m, values, true), Min: m, Max: m}
		if len(values) > 0 {
			sort.Float64s(values)
			day.HR.Min = available(m, values[0], len(values))
			day.HR.Max = available(m, values[len(values)-1], len(values))
		}
		day.Exercise = exercises(state, date, now)
		s.Days = append(s.Days, day)
	}
	for _, key := range []string{"sleep_minutes", "hrv_rmssd_ms", "resting_heart_rate_bpm", "steps"} {
		var all, first, second []float64
		stale := 0
		unit := ""
		for i, d := range s.Days {
			var m Metric
			switch key {
			case "sleep_minutes":
				m = d.Sleep.Duration
			case "hrv_rmssd_ms":
				m = d.HRV
			case "resting_heart_rate_bpm":
				m = d.RHR
			case "steps":
				m = d.Steps
			}
			unit = m.Unit
			if m.Value != nil && m.Status == "available" {
				all = append(all, *m.Value)
				if m.Stale {
					stale++
				}
				if i < len(s.Days)/2 {
					first = append(first, *m.Value)
				} else {
					second = append(second, *m.Value)
				}
			}
		}
		t := Trend{Unit: unit, Mean: mean(all), FirstHalfMean: mean(first), SecondHalfMean: mean(second), AvailableDays: len(all), RequestedDays: len(s.Days), StaleDays: stale}
		if t.FirstHalfMean != nil && t.SecondHalfMean != nil {
			v := *t.SecondHalfMean - *t.FirstHalfMean
			t.Change = &v
		}
		s.Trends[key] = t
	}
	return s
}

func sleep(state cache.State, date string, now time.Time) Sleep {
	b := base(state, date, "sleep", "reconciled", "minutes", now)
	out := Sleep{Duration: b, Stages: map[string]Metric{}}
	for _, key := range []string{"AWAKE", "ASLEEP", "RESTLESS", "LIGHT", "DEEP", "REM"} {
		out.Stages[key] = b
	}
	total, n := 0.0, 0
	stageTotals := map[string]float64{}
	stageCounts := map[string]int{}
	stagePartial := map[string]bool{}
	var intervals []health.Interval
	for _, p := range points(state, date, "sleep", "reconciled") {
		if p.Sleep == nil {
			continue
		}
		sl := p.Sleep
		out.Sessions++
		for _, prior := range intervals {
			if sl.Interval.Start.Before(prior.End) && prior.Start.Before(sl.Interval.End) {
				if out.Duration.Status != "invalid_data" {
					out.Duration.Status = "conflict"
				}
				out.Duration.Warnings = append(out.Duration.Warnings, "overlapping reconciled sleep sessions; duration not summed")
			}
		}
		intervals = append(intervals, sl.Interval)
		if sl.Metadata.Processed != nil && !*sl.Metadata.Processed {
			out.Duration.Warnings = append(out.Duration.Warnings, "sleep processing incomplete")
		}
		if sl.Metadata.StagesStatus != "" && sl.Metadata.StagesStatus != "SUCCEEDED" {
			out.Duration.Warnings = append(out.Duration.Warnings, "stages_status="+sl.Metadata.StagesStatus)
		}
		for _, short := range sl.ShortAwakenings {
			if short.Type != "AWAKE" {
				out.Duration.Warnings = append(out.Duration.Warnings, "non-AWAKE short-awakening segments preclude sleep timeline interpretation")
				break
			}
		}
		stages, complete := sleepStageMinutes(sl)
		for key, v := range stages {
			stageTotals[key] += v
			stageCounts[key]++
			stagePartial[key] = stagePartial[key] || !complete
		}
		if sl.Summary.MinutesAsleep != nil {
			total += float64(*sl.Summary.MinutesAsleep)
			n++
		} else if complete {
			total += stages["ASLEEP"] + stages["LIGHT"] + stages["DEEP"] + stages["REM"]
			n++
		}
	}
	if n == out.Sessions && n > 0 && out.Duration.Status != "conflict" && out.Duration.Status != "invalid_data" {
		out.Duration = available(out.Duration, total, n)
	} else if out.Sessions > n {
		out.Duration.Warnings = append(out.Duration.Warnings, "asleep duration unavailable for one or more sessions; time in bed is not sleep duration")
	}
	for key, v := range stageTotals {
		if _, ok := out.Stages[key]; ok {
			m := b
			if out.Duration.Status == "conflict" {
				m.Status = "conflict"
				m.Warnings = append(m.Warnings, "overlapping sessions; stage total not summed")
			} else {
				m = available(b, v, stageCounts[key])
				if (stageCounts[key] < out.Sessions || stagePartial[key]) && m.Status == "available" {
					m.Status = "partial"
					m.Warnings = append(m.Warnings, "stages do not cover every sleep session completely")
				}
			}
			out.Stages[key] = m
		}
	}
	return out
}

func sleepStageMinutes(sl *health.Sleep) (map[string]float64, bool) {
	values := map[string]float64{}
	known := func(kind string) bool {
		switch kind {
		case "AWAKE", "ASLEEP", "RESTLESS", "LIGHT", "DEEP", "REM":
			return true
		}
		return false
	}
	if len(sl.Summary.Stages) > 0 {
		total := int64(0)
		complete := true
		for _, stage := range sl.Summary.Stages {
			if !known(stage.Type) {
				return nil, false
			}
			if stage.Minutes == nil {
				complete = false
				continue
			}
			values[stage.Type] += float64(*stage.Minutes)
			total += int64(*stage.Minutes)
		}
		elapsed := sl.Interval.End.Sub(sl.Interval.Start)
		return values, complete && elapsed%time.Minute == 0 && total == int64(elapsed/time.Minute)
	}
	for _, awake := range sl.ShortAwakenings {
		if awake.Type != "AWAKE" || !awake.End.After(awake.Start) {
			return nil, false
		}
	}
	stages := append([]health.Stage{}, sl.Stages...)
	sort.Slice(stages, func(i, j int) bool { return stages[i].Start.Before(stages[j].Start) })
	awakenings := append([]health.Stage{}, sl.ShortAwakenings...)
	sort.Slice(awakenings, func(i, j int) bool { return awakenings[i].Start.Before(awakenings[j].Start) })
	cursor := sl.Interval.Start
	complete := len(stages) > 0
	for _, stage := range stages {
		if !known(stage.Type) || stage.Start.Before(cursor) || stage.End.After(sl.Interval.End) || !stage.End.After(stage.Start) {
			return nil, false
		}
		if !stage.Start.Equal(cursor) {
			complete = false
		}
		cursor = stage.End
		minutes := stage.End.Sub(stage.Start).Minutes()
		if stage.Type == "LIGHT" || stage.Type == "DEEP" || stage.Type == "REM" || stage.Type == "ASLEEP" {
			awakeCursor := stage.Start
			for _, awake := range awakenings {
				start, end := awake.Start, awake.End
				if start.Before(awakeCursor) {
					start = awakeCursor
				}
				if end.After(stage.End) {
					end = stage.End
				}
				if end.After(start) {
					v := end.Sub(start).Minutes()
					minutes -= v
					values["AWAKE"] += v
					awakeCursor = end
				}
			}
		}
		values[stage.Type] += minutes
	}
	return values, complete && cursor.Equal(sl.Interval.End)
}

func lifting(kind string) bool {
	switch kind {
	case "FREE_WEIGHTS", "FUNCTIONAL_STRENGTH_TRAINING", "POWERLIFTING", "STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHT_MACHINES", "WEIGHTS":
		return true
	}
	return false
}

func exercises(state cache.State, date string, now time.Time) Exercise {
	out := Exercise{Coverage: base(state, date, "exercise", "raw", "sessions", now), Workouts: []Workout{}}
	for _, p := range points(state, date, "exercise", "raw") {
		if p.Exercise == nil {
			continue
		}
		ex := p.Exercise
		var existing *Workout
		for i := range out.Workouts {
			w := &out.Workouts[i]
			compatible := true
			for _, kind := range w.Types {
				if kind != ex.Type && kind != "WORKOUT" && kind != "OTHER" && ex.Type != "WORKOUT" && ex.Type != "OTHER" {
					compatible = false
				}
			}
			if compatible && ex.Interval.Start.Equal(w.Start) && ex.Interval.End.Equal(w.End) {
				existing = w
				break
			}
		}
		if existing == nil {
			out.Workouts = append(out.Workouts, Workout{Types: []string{}, Start: ex.Interval.Start, End: ex.Interval.End, DurationMinutes: ex.Interval.End.Sub(ex.Interval.Start).Minutes(), Sources: []*health.DataSource{}})
			existing = &out.Workouts[len(out.Workouts)-1]
		}
		w := existing
		w.MergedRecords++
		found := false
		for _, kind := range w.Types {
			if kind == ex.Type {
				found = true
			}
		}
		if !found {
			w.Types = append(w.Types, ex.Type)
			sort.Strings(w.Types)
		}
		w.Lifting = w.Lifting || lifting(ex.Type)
		if ex.ActiveDuration != "" && !w.activeConflict {
			if d, err := time.ParseDuration(ex.ActiveDuration); err == nil && d >= 0 && d <= ex.Interval.End.Sub(ex.Interval.Start) {
				v := d.Minutes()
				if w.ActiveMinutes == nil {
					w.ActiveMinutes = &v
				} else if *w.ActiveMinutes != v {
					w.ActiveMinutes = nil
					w.activeConflict = true
					out.Coverage.Warnings = append(out.Coverage.Warnings, "duplicate workouts disagree on active duration")
				}
			}
		}
		if p.DataSource != nil {
			b, _ := json.Marshal(p.DataSource)
			seen := false
			for _, s := range w.Sources {
				prior, _ := json.Marshal(s)
				if string(prior) == string(b) {
					seen = true
				}
			}
			if !seen {
				w.Sources = append(w.Sources, p.DataSource)
			}
			factor := p.DataSource.Device.FormFactor
			if factor == "WATCH" || factor == "FITNESS_BAND" || factor == "RING" || factor == "CHEST_STRAP" {
				v := true
				w.Wearable = &v
			} else if w.Wearable == nil && p.DataSource.Method == "MANUAL" {
				v := false
				w.Wearable = &v
			}
		}
	}
	sort.Slice(out.Workouts, func(i, j int) bool { return out.Workouts[i].Start.Before(out.Workouts[j].Start) })
	if len(out.Workouts) > 0 {
		out.Coverage = available(out.Coverage, float64(len(out.Workouts)), len(out.Workouts))
	}
	return out
}

func value(m Metric) string {
	if m.Value == nil {
		s := m.Status
		if m.LastObservedDate != nil {
			s += " (last observed " + *m.LastObservedDate + ")"
		}
		return s
	}
	s := fmt.Sprintf("%.1f %s", *m.Value, m.Unit)
	if m.Stale {
		s += " (stale)"
	}
	if m.Status != "available" {
		s += " (" + m.Status + ")"
	}
	return s
}

func Text(w io.Writer, s Summary, withTrends bool) {
	fmt.Fprintf(w, "Google Health v4 · %s\n", s.Timezone)
	for _, d := range s.Days {
		fmt.Fprintf(w, "%s  sleep %s; HRV %s; resting HR %s; steps %s; HR %s; exercise %s\n", d.Date, value(d.Sleep.Duration), value(d.HRV), value(d.RHR), value(d.Steps), value(d.HR.Mean), value(d.Exercise.Coverage))
		stageValues := []string{}
		for _, stage := range []string{"LIGHT", "DEEP", "REM", "ASLEEP", "AWAKE", "RESTLESS"} {
			m := d.Sleep.Stages[stage]
			if m.Value != nil {
				stageValues = append(stageValues, strings.ToLower(stage)+" "+value(m))
			}
		}
		if len(stageValues) > 0 {
			fmt.Fprintln(w, "  sleep stages:", strings.Join(stageValues, "; "))
		}
		for _, entry := range []struct {
			name string
			m    Metric
		}{{"sleep", d.Sleep.Duration}, {"HRV", d.HRV}, {"resting HR", d.RHR}, {"steps", d.Steps}, {"exercise", d.Exercise.Coverage}} {
			if len(entry.m.Warnings) > 0 {
				fmt.Fprintf(w, "  %s: %s\n", entry.name, strings.Join(entry.m.Warnings, "; "))
			}
		}
		for _, ex := range d.Exercise.Workouts {
			label := "recorded activity"
			if ex.Lifting {
				label = "lifting"
			}
			fmt.Fprintf(w, "  %s: %s, %.1f min, wearable=%v\n", label, strings.Join(ex.Types, "/"), ex.DurationMinutes, wearableText(ex.Wearable))
		}
	}
	if withTrends {
		keys := []string{"sleep_minutes", "hrv_rmssd_ms", "resting_heart_rate_bpm", "steps"}
		for _, key := range keys {
			t := s.Trends[key]
			if t.Mean == nil {
				fmt.Fprintf(w, "%s trend: missing (%d/%d days)\n", key, t.AvailableDays, t.RequestedDays)
			} else {
				change := "change unavailable"
				if t.Change != nil {
					change = fmt.Sprintf("change %+.1f %s", *t.Change, t.Unit)
				}
				fmt.Fprintf(w, "%s mean: %.1f %s (%d/%d days; %d stale; %s)\n", key, *t.Mean, t.Unit, t.AvailableDays, t.RequestedDays, t.StaleDays, change)
			}
		}
	}
}

func wearableText(v *bool) string {
	if v == nil {
		return "unknown"
	}
	if *v {
		return "true"
	}
	return "false"
}
