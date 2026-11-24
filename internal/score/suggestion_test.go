package score_test

import (
	"fmt"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

const parityEffort = "effort-2026-03-09T19:40:00Z"

func TestSuggestParityAndDayStrainUnchanged(t *testing.T) {
	full := engine(t, fixtureState(t, "full"), "2026-03-10T14:30:00Z", config.Defaults())
	parity := engine(t, fixtureState(t, "parity"), "2026-03-10T14:30:00Z", config.Defaults())
	w := workoutByID(t, parity.Workouts("2026-03-09", false), parityEffort)
	want := &score.WorkoutSuggestion{Type: "BOXING", Name: "Boxing", Matches: 3, WindowDays: 56}
	if !reflect.DeepEqual(w.Suggested, want) {
		t.Fatalf("suggestion = %+v, want %+v", w.Suggested, want)
	}
	if workoutByID(t, full.Workouts("2026-03-09", false), parityEffort).Suggested != nil {
		t.Fatal("full store unexpectedly suggests a sport")
	}
	for _, day := range []string{"2026-03-09", "2026-03-10"} {
		if !reflect.DeepEqual(full.Strain(day), parity.Strain(day)) {
			t.Fatal("Day Strain changed with suggestion history")
		}
	}
	for _, day := range []string{"2026-02-16", "2026-03-10"} {
		for _, row := range parity.Workouts(day, false) {
			if row.Kind != "detected" && row.Suggested != nil {
				t.Fatal("recorded workout has a suggestion")
			}
		}
	}
}

func TestSuggestMatchingRulesAndEffectiveHistory(t *testing.T) {
	type candidate struct {
		start    string
		duration time.Duration
		sport    string
	}
	base := []candidate{{"2026-02-16T19:30:00Z", time.Hour, "BOXING"}, {"2026-02-23T19:30:00Z", time.Hour, "BOXING"}, {"2026-03-02T19:30:00Z", time.Hour, "BOXING"}}
	for _, tc := range []struct {
		name   string
		change func([]candidate) []candidate
		apply  func(*score.Engine)
		want   bool
	}{
		{name: "different_weekday", change: func(c []candidate) []candidate { c[0].start = "2026-02-17T19:30:00Z"; return c }},
		{name: "91_minutes", change: func(c []candidate) []candidate { c[0].start = "2026-02-16T18:09:00Z"; return c }},
		{name: "90_minutes_inclusive", change: func(c []candidate) []candidate { c[0].start = "2026-02-16T18:10:00Z"; return c }, want: true},
		{name: "duration_049", change: func(c []candidate) []candidate { c[0].duration = 22*time.Minute + 3*time.Second; return c }},
		{name: "duration_201", change: func(c []candidate) []candidate { c[0].duration = 90*time.Minute + 27*time.Second; return c }},
		{name: "duration_edges_inclusive", change: func(c []candidate) []candidate {
			c[0].duration = 22*time.Minute + 30*time.Second
			c[1].duration = 90 * time.Minute
			return c
		}, want: true},
		{name: "two_matches", change: func(c []candidate) []candidate { return c[:2] }},
		{name: "three_of_five_inclusive", change: func(c []candidate) []candidate {
			for _, row := range append([]candidate{}, c[:2]...) {
				row.sport = "WALKING"
				c = append(c, row)
			}
			return c
		}, want: true},
		{name: "three_of_six", change: func(c []candidate) []candidate {
			for _, row := range append([]candidate{}, c...) {
				row.sport = "WALKING"
				c = append(c, row)
			}
			return c
		}},
		{name: "other_ignored", change: func(c []candidate) []candidate {
			for _, row := range append([]candidate{}, c...) {
				row.sport = "OTHER"
				c = append(c, row)
			}
			return c
		}, want: true},
		{name: "unsupported_ignored", change: func(c []candidate) []candidate {
			for _, row := range append([]candidate{}, c...) {
				row.sport = "FENCING"
				c = append(c, row)
			}
			return c
		}, want: true},
		{name: "own_cycle_date", change: func(c []candidate) []candidate {
			c[0].start = "2026-03-09T18:10:00Z"
			c[0].duration = 22*time.Minute + 30*time.Second
			return c
		}},
		{name: "57_days_back", change: func(c []candidate) []candidate { c[0].start = "2026-01-11T19:30:00Z"; return c }},
		{name: "63_days_back_same_weekday", change: func(c []candidate) []candidate { c[0].start = "2026-01-05T19:30:00Z"; return c }},
		{name: "56_days_inclusive", change: func(c []candidate) []candidate { c[0].start = "2026-01-12T19:30:00Z"; return c }, want: true},
		{name: "hidden", apply: func(e *score.Engine) { e.Edits = []activities.Edit{{ID: "synthetic-history-0", Hidden: true}} }},
		{name: "effective_sport", apply: func(e *score.Engine) {
			e.Edits = []activities.Edit{{ID: "synthetic-history-0", ExerciseType: editText("WALKING")}}
		}},
		{name: "effective_window", apply: func(e *score.Engine) {
			e.Edits = []activities.Edit{{ID: "synthetic-history-0", Start: editTime("2026-02-16T16:00:00Z"), End: editTime("2026-02-16T17:00:00Z")}}
		}},
		{name: "named_effort_counts", change: func(c []candidate) []candidate { return c[:2] }, apply: func(e *score.Engine) {
			e.Activities = []activities.Record{{Upload: activities.Upload{ID: "synthetic-added", ExerciseType: "BOXING", DisplayName: "Boxing", Start: *editTime("2026-03-02T19:30:00Z"), End: *editTime("2026-03-02T20:30:00Z"), Origin: "added"}}}
		}, want: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			state := fixtureState(t, "full")
			rows := append([]candidate{}, base...)
			if tc.change != nil {
				rows = tc.change(rows)
			}
			for i, c := range rows {
				start := *editTime(c.start)
				raw := fmt.Sprintf(`{"name":"users/synthetic/dataTypes/exercise/dataPoints/synthetic-history-%d","exercise":{"exerciseType":%q,"displayName":%q,"interval":{"startTime":%q,"endTime":%q}}}`, i, c.sport, c.sport, c.start, start.Add(c.duration).Format(time.RFC3339))
				state.Records = append(state.Records, testutil.Record(t, "exercise", "raw", start.Format("2006-01-02"), raw))
			}
			e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
			if tc.apply != nil {
				tc.apply(e)
			}
			w := workoutByID(t, e.Workouts("2026-03-09", false), parityEffort)
			if (w.Suggested != nil) != tc.want {
				t.Fatalf("suggestion = %+v, want present %v", w.Suggested, tc.want)
			}
			if w.Suggested != nil && (w.Suggested.Type != "BOXING" || w.Suggested.Matches != 3) {
				t.Fatalf("wrong suggestion: %+v", w.Suggested)
			}
			for _, a := range e.Workouts("2026-03-02", false) {
				if a.Kind == "goop" && a.Suggested != nil {
					t.Fatal("added activity has suggestion")
				}
			}
		})
	}
}
