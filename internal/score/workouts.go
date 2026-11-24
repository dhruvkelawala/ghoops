package score

import (
	"encoding/json"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/health"
)

type recordedWorkout struct {
	Workout
	types          []string
	activeConflict bool
}

func (e *Engine) Workouts(date string, series bool) []Workout {
	entries := e.effectiveWorkouts()
	out := []Workout{}
	for _, w := range entries {
		if !w.hidden && w.CycleDate == date {
			out = append(out, e.workoutScore(w, series))
		}
	}
	rest, _, maximum, _ := e.rates(date)
	cycle := e.Cycle(date)
	if rest != nil && maximum != nil && *maximum > *rest && cycle.Status != "not_started" {
		end := e.Now
		if cycle.End != nil {
			end = *cycle.End
		}
		minutes, _ := e.window(cycle.Start, end)
		hot := []time.Time{}
		finish := func() {
			if len(hot) < EffortMinMinutes {
				hot = nil
				return
			}
			start, end := hot[0], hot[len(hot)-1].Add(time.Minute)
			overlap := 0.0
			for _, w := range entries {
				a, b := w.Start, w.End
				if a.Before(start) {
					a = start
				}
				if b.After(end) {
					b = end
				}
				if b.After(a) {
					overlap += b.Sub(a).Seconds()
				}
			}
			if overlap < EffortOverlap*end.Sub(start).Seconds() {
				w := Workout{Kind: "detected", ID: "effort-" + start.Format(time.RFC3339), Name: ptr("Detected effort"), Category: "detected", CycleDate: date, Start: start, End: end, Elapsed: round(end.Sub(start).Minutes(), 1), Merged: []WorkoutOriginal{}, Pauses: []activities.Pause{}}
				w.Suggested = e.suggest(w, entries)
				out = append(out, e.workoutScore(w, series))
			}
			hot = nil
		}
		for _, m := range minutes {
			if (m.Avg-*rest)/(*maximum-*rest) < EffortHRR {
				continue
			}
			at := time.Unix(m.Start, 0).UTC()
			if len(hot) > 0 && at.Sub(hot[len(hot)-1]) > time.Duration(EffortMaxGap+1)*time.Minute {
				finish()
			}
			hot = append(hot, at)
		}
		finish()
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Start.Before(out[j].Start) })
	return out
}

func (e *Engine) workoutScore(w Workout, series bool) Workout {
	minutes, expected := e.window(w.Start.Truncate(time.Minute), w.End)
	if len(w.Pauses) > 0 {
		paused := map[int64]bool{}
		for at := w.Start.Truncate(time.Minute); at.Before(w.End); at = at.Add(time.Minute) {
			for _, p := range w.Pauses {
				if at.Before(p.End) && at.Add(time.Minute).After(p.Start) {
					paused[at.Unix()] = true
				}
			}
		}
		w.Paused = len(paused)
		expected -= w.Paused
		kept := minutes[:0]
		for _, m := range minutes {
			if !paused[m.Start] {
				kept = append(kept, m)
			}
		}
		minutes = kept
	}
	if series {
		points := []HRPoint{}
		for _, m := range minutes {
			points = append(points, HRPoint{time.Unix(m.Start, 0).UTC(), int(math.Round(m.Avg))})
		}
		w.HR = &points
	}
	if expected > 0 {
		w.Coverage = ptr(round(float64(len(minutes))/float64(expected), 2))
	}
	rest, _, maximum, _ := e.rates(w.CycleDate)
	if len(minutes) == 0 || rest == nil || maximum == nil || *maximum <= *rest {
		w.Avg, w.Peak = minuteStats(minutes)
		return w
	}
	score, avg, peak := e.scoreWindow(minutes, expected, *rest, *maximum)
	w.Strain, w.Trimp, w.Avg, w.Peak, w.Zones = score.Strain, ptr(score.Trimp), avg, peak, &score.Zones
	if expected > 0 {
		w.Confidence = confidence(float64(len(minutes)) / float64(expected))
	}
	return w
}

// recorded decodes and merges the stored workouts once per engine. Only the cycle
// date, which a sleep edit can move, is worked out on each call.
func (e *Engine) recorded() []recordedWorkout {
	if e.workouts == nil {
		e.workouts = e.decodeRecorded()
	}
	out := append([]recordedWorkout{}, e.workouts...)
	for i := range out {
		out[i].CycleDate = e.workoutDate(out[i].Start)
	}
	return out
}

func (e *Engine) decodeRecorded() []recordedWorkout {
	rows := []observation{}
	for _, points := range e.points["exercise"] {
		rows = append(rows, points...)
	}
	sort.SliceStable(rows, func(i, j int) bool {
		a, b := rows[i].point.Exercise, rows[j].point.Exercise
		if a.Interval.Start.Equal(b.Interval.Start) {
			return rows[i].point.Name < rows[j].point.Name
		}
		return a.Interval.Start.Before(b.Interval.Start)
	})
	out := []recordedWorkout{}
	for _, row := range rows {
		x := row.point.Exercise
		if x == nil {
			continue
		}
		var extra struct {
			Exercise struct {
				Name    string `json:"displayName"`
				Metrics struct {
					Avg      *health.Number `json:"averageHeartRateBeatsPerMinute"`
					Calories *health.Number `json:"caloriesKcal"`
					AZM      *health.Number `json:"activeZoneMinutes"`
				} `json:"metricsSummary"`
				Metadata struct {
					GPS bool `json:"hasGps"`
				} `json:"exerciseMetadata"`
			} `json:"exercise"`
		}
		_ = json.Unmarshal(row.raw, &extra)
		provider := &WorkoutProvider{rounded(number(extra.Exercise.Metrics.Avg), 0), number(extra.Exercise.Metrics.Calories), rounded(number(extra.Exercise.Metrics.AZM), 0)}
		var source *WorkoutSource
		if s := row.point.DataSource; s != nil {
			source = &WorkoutSource{text(s.Method), text(s.Platform), text(s.Device.FormFactor)}
		}
		w := Workout{Kind: "recorded", ID: lastSegment(row.point.Name), Type: text(x.Type), Name: workoutName(x.Type, extra.Exercise.Name), Category: category(x.Type), Start: x.Interval.Start, End: x.Interval.End, Elapsed: round(x.Interval.End.Sub(x.Interval.Start).Minutes(), 1), Provider: provider, Source: source, GPS: extra.Exercise.Metadata.GPS}
		if duration, err := time.ParseDuration(x.ActiveDuration); err == nil && duration >= 0 && duration <= w.End.Sub(w.Start) {
			w.Active = ptr(round(duration.Minutes(), 1))
		}
		index := -1
		for i, old := range out {
			compatible := true
			for _, kind := range old.types {
				if kind != x.Type && kind != "WORKOUT" && kind != "OTHER" && x.Type != "WORKOUT" && x.Type != "OTHER" {
					compatible = false
				}
			}
			if compatible && old.Start.Equal(w.Start) && old.End.Equal(w.End) {
				index = i
				break
			}
		}
		if index < 0 {
			out = append(out, recordedWorkout{Workout: w, types: []string{x.Type}})
			continue
		}
		old := &out[index]
		old.types = append(old.types, x.Type)
		active := old.Active
		conflict := old.activeConflict
		if active != nil && w.Active != nil && *active != *w.Active {
			conflict = true
		}
		if conflict {
			active = nil
		} else if active == nil {
			active = w.Active
		}
		if categoryRank(w.Category) > categoryRank(old.Category) {
			old.Workout = w
		}
		old.Active, old.activeConflict = active, conflict
	}
	return out
}

func workoutName(kind, name string) *string {
	if sport, ok := activities.Sports[kind]; ok {
		return ptr(sport)
	}
	return text(name)
}

func lastSegment(s string) string { parts := strings.Split(s, "/"); return parts[len(parts)-1] }
func category(kind string) string {
	switch kind {
	case "BOXING", "KICKBOXING", "MARTIAL_ARTS", "MUAY_THAI", "KARATE", "TAEKWONDO", "WRESTLING", "JIU_JITSU", "FENCING":
		return "combat"
	case "FREE_WEIGHTS", "FUNCTIONAL_STRENGTH_TRAINING", "POWERLIFTING", "STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHT_MACHINES", "WEIGHTS":
		return "strength"
	case "WALKING", "POWER_WALKING", "TREADMILL_WALK", "HIKING", "NORDIC_WALKING":
		return "walking"
	case "RUNNING", "TREADMILL", "TRAIL_RUN", "BIKING", "OUTDOOR_BIKE", "STATIONARY_BIKE", "SPINNING", "ROWING_MACHINE", "ELLIPTICAL", "HIIT", "SWIMMING", "SWIMMING_POOL", "JUMPING_ROPE", "INTERVAL_WORKOUT", "CIRCUIT_TRAINING", "CARDIO_WORKOUT":
		return "cardio"
	}
	return "other"
}
func categoryRank(category string) int {
	switch category {
	case "combat":
		return 4
	case "strength":
		return 3
	case "walking", "cardio":
		return 2
	}
	return 1
}

func goopHidesRecorded(a, b Workout) bool {
	start, end := a.Start, a.End
	if b.Start.After(start) {
		start = b.Start
	}
	if b.End.Before(end) {
		end = b.End
	}
	return end.After(start) && end.Sub(start).Seconds() >= RecordedHiddenOverlap*math.Min(a.End.Sub(a.Start).Seconds(), b.End.Sub(b.Start).Seconds())
}
