package score

import (
	"math"

	"github.com/dhruvkelawala/ghoops/internal/activities"
)

const (
	SuggestWindowDays            = 56
	SuggestStartToleranceMinutes = 90
	SuggestMinRatio              = 0.5
	SuggestMaxRatio              = 2.0
	SuggestMinMatches            = 3
	SuggestMinShare              = 0.6
)

type WorkoutSuggestion struct {
	Type       string `json:"exercise_type"`
	Name       string `json:"display_name"`
	Matches    int    `json:"matches"`
	WindowDays int    `json:"window_days"`
}

func (e *Engine) suggest(effort Workout, entries []Workout) *WorkoutSuggestion {
	counts := map[string]int{}
	first := e.add(effort.CycleDate, -SuggestWindowDays)
	start := effort.Start.In(e.loc)
	total := 0
	for _, w := range entries {
		if w.hidden || (w.Kind != "recorded" && w.Kind != "goop") || w.Type == nil || *w.Type == "OTHER" || activities.Sports[*w.Type] == "" || w.CycleDate < first || w.CycleDate >= effort.CycleDate {
			continue
		}
		at := w.Start.In(e.loc)
		if at.Weekday() != start.Weekday() || math.Abs(localMinutes(at, e.loc)-localMinutes(start, e.loc)) > SuggestStartToleranceMinutes || w.Elapsed < SuggestMinRatio*effort.Elapsed || w.Elapsed > SuggestMaxRatio*effort.Elapsed {
			continue
		}
		counts[*w.Type]++
		total++
	}
	for sport, count := range counts {
		if count >= SuggestMinMatches && float64(count) >= SuggestMinShare*float64(total) {
			return &WorkoutSuggestion{sport, activities.Sports[sport], count, SuggestWindowDays}
		}
	}
	return nil
}
