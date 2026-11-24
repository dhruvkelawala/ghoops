package score_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

func TestGOOPWorkoutsScorePausesAndHideDuplicates(t *testing.T) {
	var vectors struct {
		Cases []struct {
			Name     string
			Input    score.MinuteInput
			Expected score.MinuteScore
		}
	}
	vectorFile(t, "strain", &vectors)
	var boxing score.MinuteInput
	var expected score.MinuteScore
	for _, c := range vectors.Cases {
		if c.Name == "boxing_hour" {
			boxing = c.Input
			expected = c.Expected
		}
	}
	state := fixtureState(t, "full")
	start := time.Date(2026, 3, 10, 12, 0, 0, 0, time.UTC)
	windows := []store2.Minute{}
	for i, bpm := range boxing.Averages {
		windows = append(windows, store2.Minute{Start: start.Add(time.Duration(i) * time.Minute).Unix(), Min: bpm, Avg: bpm, Max: bpm})
	}
	state.HRMinutes = []store2.MinuteDay{{Date: "2026-03-10", Windows: windows}}
	cfg := config.Defaults()
	maxHR := 187
	cfg.MaxHR = &maxHR
	e := engine(t, state, "2026-03-10T14:30:00Z", cfg)
	before, _ := json.Marshal(e.Strain("2026-03-10"))
	a := activities.Record{Upload: activities.Upload{ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING", DisplayName: "Boxing", Start: start, End: start.Add(time.Hour)}}
	e.Activities = []activities.Record{a}
	rows := e.Workouts("2026-03-10", true)
	if len(rows) != 1 || rows[0].Kind != "goop" {
		t.Fatalf("recorded/detected duplicates: count=%d", len(rows))
	}
	w := rows[0]
	if w.Strain == nil || *w.Strain != *expected.Strain || *w.Trimp != expected.Trimp || *w.Zones != expected.Zones {
		t.Fatalf("boxing_hour golden mismatch: %+v", w)
	}
	after, _ := json.Marshal(e.Strain("2026-03-10"))
	if string(before) != string(after) {
		t.Fatal("activity changed Day Strain")
	}
	e.Activities[0].Pauses = []activities.Pause{{Start: start.Add(10*time.Minute + 5*time.Second), End: start.Add(20 * time.Minute)}}
	w = e.Workouts("2026-03-10", true)[0]
	if w.Paused != 10 || len(*w.HR) != 50 || *w.Coverage != 1 || *w.Trimp >= expected.Trimp {
		t.Fatalf("paused slots not excluded: %+v", w)
	}
	removeDate(&state, "exercise", "2026-03-10")
	e = engine(t, state, "2026-03-10T14:30:00Z", cfg)
	if rows = e.Workouts("2026-03-10", false); len(rows) != 1 || rows[0].Kind != "detected" {
		t.Fatal("fixture must detect effort without activity")
	}
	e.Activities = []activities.Record{a}
	if rows = e.Workouts("2026-03-10", false); len(rows) != 1 || rows[0].Kind != "goop" {
		t.Fatal("detected effort not hidden")
	}
}
