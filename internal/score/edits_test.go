package score_test

import (
	"encoding/json"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
)

const bandOne = "7300000000000000101"
const bandTwo = "7300000000000000102"

func editTime(value string) *time.Time {
	at, err := time.Parse(time.RFC3339, value)
	if err != nil {
		panic(err)
	}
	return &at
}
func editText(value string) *string { return &value }
func editWindow() activities.Edit {
	return activities.Edit{ID: bandOne, ExerciseType: editText("BOXING"), Start: editTime("2026-03-10T17:56:00Z"), End: editTime("2026-03-10T19:12:00Z"), Notes: editText("Sparring, 6 rounds of 3 minutes."), MergeWith: []string{}}
}
func workoutByID(t *testing.T, rows []score.Workout, id string) score.Workout {
	t.Helper()
	for _, w := range rows {
		if w.ID == id {
			return w
		}
	}
	t.Fatalf("missing fixture workout %s", id)
	return score.Workout{}
}
func hasWorkout(rows []score.Workout, id string) bool {
	for _, w := range rows {
		if w.ID == id {
			return true
		}
	}
	return false
}

func TestEditFixtureDetectedWindowsAndMergeCandidates(t *testing.T) {
	e := engine(t, fixtureState(t, "edit"), "2026-03-12T20:30:00Z", config.Defaults())
	for _, tc := range []struct{ day, start, end string }{{"2026-03-11", "18:04", "19:04"}, {"2026-03-12", "07:10", "07:41"}} {
		found := false
		for _, w := range e.Workouts(tc.day, false) {
			if w.Kind == "detected" && w.Start.Format("15:04") == tc.start && w.End.Format("15:04") == tc.end {
				found = true
			}
		}
		if !found {
			t.Fatalf("detected window %s %s–%s absent", tc.day, tc.start, tc.end)
		}
	}
	target, err := e.EditTarget(bandOne)
	if err != nil || target.Next == nil || target.Next.ID != bandTwo || target.Previous != nil {
		t.Fatal("saved merge candidates", err)
	}
	e.Edits = []activities.Edit{editWindow()}
	target, err = e.EditTarget(bandOne)
	if err != nil || target.Original.Start.Format("15:04") != "18:05" || target.Current.Start.Format("15:04") != "17:56" || target.Next == nil || target.Next.ID != bandTwo {
		t.Fatal("original/current target", err)
	}
	if _, err = e.EditTarget("effort-2026-03-12T07:10:00Z"); !errors.Is(err, activities.ErrNotFound) {
		t.Fatal("detected target accepted")
	}
}

func TestEditRulesKeepDayStrainUnchanged(t *testing.T) {
	for _, tc := range []struct {
		name  string
		apply func(*score.Engine)
		check func(*testing.T, *score.Engine)
	}{
		{"sport-window-notes", func(e *score.Engine) { e.Edits = []activities.Edit{editWindow()} }, func(t *testing.T, e *score.Engine) {
			w := workoutByID(t, e.Workouts("2026-03-10", true), bandOne)
			if *w.Type != "BOXING" || w.Start.Format("15:04") != "17:56" || w.End.Format("15:04") != "19:12" || !w.Edited || w.Active != nil || *w.Notes != "Sparring, 6 rounds of 3 minutes." || *w.Original.Type != "KICKBOXING" {
				t.Fatal("effective fields")
			}
		}},
		{"notes-only", func(e *score.Engine) { e.Edits = []activities.Edit{{ID: bandOne, Notes: editText("Synthetic note")}} }, func(t *testing.T, e *score.Engine) {
			w := workoutByID(t, e.Workouts("2026-03-10", false), bandOne)
			if w.Edited || w.Edit == nil || w.Active == nil {
				t.Fatal("notes became a window edit")
			}
		}},
		{"alias", func(e *score.Engine) { e.Config.SportAliases["KICKBOXING"] = "BOXING" }, func(t *testing.T, e *score.Engine) {
			w := workoutByID(t, e.Workouts("2026-03-10", false), bandOne)
			if *w.Type != "BOXING" || *w.Original.Type != "KICKBOXING" || w.Edited {
				t.Fatal("alias fields")
			}
		}},
		{"edit-over-alias", func(e *score.Engine) {
			e.Config.SportAliases["KICKBOXING"] = "BOXING"
			e.Edits = []activities.Edit{{ID: bandOne, ExerciseType: editText("RUNNING")}}
		}, func(t *testing.T, e *score.Engine) {
			w := workoutByID(t, e.Workouts("2026-03-10", false), bandOne)
			if *w.Type != "RUNNING" || w.Category != "cardio" {
				t.Fatal("alias overrode edit")
			}
		}},
		{"recorded-merge-and-hidden", func(e *score.Engine) {
			x := editWindow()
			x.End = editTime("2026-03-10T19:38:00Z")
			x.MergeWith = []string{bandTwo}
			e.Edits = []activities.Edit{x}
		}, func(t *testing.T, e *score.Engine) {
			rows := e.Workouts("2026-03-10", false)
			w := workoutByID(t, rows, bandOne)
			if hasWorkout(rows, bandTwo) || len(w.Merged) != 1 || w.Merged[0].ID != bandTwo || w.End.Format("15:04") != "19:38" {
				t.Fatal("merge fields")
			}
			e.Edits[0].Hidden = true
			for _, x := range e.Workouts("2026-03-10", false) {
				if x.ID == bandOne || x.ID == bandTwo || x.Kind == "detected" {
					t.Fatal("delete revealed absorbed record or effort")
				}
			}
			e.Edits = nil
			if !hasWorkout(e.Workouts("2026-03-10", false), bandTwo) {
				t.Fatal("restore did not unmerge")
			}
		}},
		{"hidden-recorded-suppresses-effort", func(e *score.Engine) { e.Edits = []activities.Edit{{ID: bandOne, Hidden: true}} }, func(t *testing.T, e *score.Engine) {
			for _, w := range e.Workouts("2026-03-10", false) {
				if w.ID == bandOne || w.Kind == "detected" {
					t.Fatal("deleted record replaced by effort")
				}
			}
		}},
		{"cycle-move", func(e *score.Engine) {
			x := editWindow()
			x.Start = editTime("2026-03-10T06:00:00Z")
			x.End = editTime("2026-03-10T06:20:00Z")
			e.Edits = []activities.Edit{x}
		}, func(t *testing.T, e *score.Engine) {
			if hasWorkout(e.Workouts("2026-03-10", false), bandOne) || workoutByID(t, e.Workouts("2026-03-09", false), bandOne).CycleDate != "2026-03-09" {
				t.Fatal("cycle did not follow effective start")
			}
		}},
		{"extend-over-effort", func(e *score.Engine) {
			e.Activities = []activities.Record{{Upload: activities.Upload{ID: "3f0c0000-0000-4000-8000-0000000000e2", ExerciseType: "BOXING", DisplayName: "Boxing", Start: *editTime("2026-03-11T17:40:00Z"), End: *editTime("2026-03-11T18:00:00Z"), Origin: "added"}}}
			e.Edits = []activities.Edit{{ID: "goop-3f0c0000-0000-4000-8000-0000000000e2", Start: editTime("2026-03-11T17:40:00Z"), End: editTime("2026-03-11T19:04:00Z")}}
		}, func(t *testing.T, e *score.Engine) {
			rows := e.Workouts("2026-03-11", false)
			if len(rows) != 1 || rows[0].Kind != "goop" || *rows[0].Origin != "added" {
				t.Fatal("named effort remains visible")
			}
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			e := engine(t, fixtureState(t, "edit"), "2026-03-12T20:30:00Z", config.Defaults())
			before := map[string]score.Strain{}
			for _, date := range []string{"2026-03-09", "2026-03-10", "2026-03-11", "2026-03-12"} {
				before[date] = e.Strain(date)
			}
			tc.apply(e)
			tc.check(t, e)
			for date, strain := range before {
				if !reflect.DeepEqual(strain, e.Strain(date)) {
					t.Fatal("Day Strain changed", date)
				}
			}
		})
	}
}

func TestMergeGoopAbsorberExceptionPausesAndDeletedReplacement(t *testing.T) {
	for _, goopAbsorbs := range []bool{true, false} {
		e := engine(t, fixtureState(t, "edit"), "2026-03-12T20:30:00Z", config.Defaults())
		before, _ := json.Marshal(e.Strain("2026-03-10"))
		a := activities.Upload{ID: "3f0c0000-0000-4000-8000-0000000000e2", ExerciseType: "BOXING", DisplayName: "Boxing", Start: *editTime("2026-03-10T18:00:00Z"), End: *editTime("2026-03-10T19:10:00Z"), Pauses: []activities.Pause{{Start: *editTime("2026-03-10T18:10:00Z"), End: *editTime("2026-03-10T18:20:00Z")}}}
		e.Activities = []activities.Record{{Upload: a}}
		goopID := "goop-" + a.ID
		absorber, absorbed := bandOne, goopID
		if goopAbsorbs {
			absorber, absorbed = goopID, bandOne
		}
		e.Edits = []activities.Edit{{ID: absorber, Start: &a.Start, End: &a.End, MergeWith: []string{absorbed}}}
		rows := e.Workouts("2026-03-10", true)
		w := workoutByID(t, rows, absorber)
		if hasWorkout(rows, absorbed) || len(w.Merged) != 1 {
			t.Fatal("absorbed entry visible")
		}
		if goopAbsorbs && (w.Paused != 10 || len(w.Pauses) != 1) {
			t.Fatal("goop pauses lost")
		}
		if !goopAbsorbs && (w.Paused != 0 || len(w.Pauses) != 0) {
			t.Fatal("absorbed pauses copied")
		}
		e.Edits[0].Hidden = true
		rows = e.Workouts("2026-03-10", false)
		if hasWorkout(rows, absorber) || hasWorkout(rows, absorbed) {
			t.Fatal("deleted merge revealed a record")
		}
		after, _ := json.Marshal(e.Strain("2026-03-10"))
		if string(before) != string(after) {
			t.Fatal("merge changed Day Strain")
		}
	}
	e := engine(t, fixtureState(t, "edit"), "2026-03-12T20:30:00Z", config.Defaults())
	before := e.Strain("2026-03-10")
	a := activities.Upload{ID: "3f0c0000-0000-4000-8000-0000000000e2", ExerciseType: "BOXING", DisplayName: "Boxing", Start: *editTime("2026-03-10T18:00:00Z"), End: *editTime("2026-03-10T19:10:00Z"), Pauses: []activities.Pause{{Start: *editTime("2026-03-10T18:10:00Z"), End: *editTime("2026-03-10T18:20:00Z")}}}
	e.Activities = []activities.Record{{Upload: a}}
	start, end := editTime("2026-03-10T18:15:00Z"), editTime("2026-03-10T19:00:00Z")
	e.Edits = []activities.Edit{{ID: "goop-" + a.ID, Start: start, End: end}}
	w := workoutByID(t, e.Workouts("2026-03-10", false), "goop-"+a.ID)
	if len(w.Pauses) != 1 || !w.Pauses[0].Start.Equal(*start) || w.Paused != 5 {
		t.Fatal("pauses not clipped to edited window")
	}
	e.Edits[0].Hidden = true
	for _, w := range e.Workouts("2026-03-10", false) {
		if w.ID == bandOne || w.Kind == "detected" {
			t.Fatal("deleted goop revealed replaced record or effort")
		}
	}
	if !reflect.DeepEqual(before, e.Strain("2026-03-10")) {
		t.Fatal("pause clipping changed Day Strain")
	}
}

func TestHeartRateCycleRatesAndNotStarted(t *testing.T) {
	state := fixtureState(t, "edit")
	e := engine(t, state, "2026-03-12T20:30:00Z", config.Defaults())
	day := e.HeartRateDay("2026-03-12")
	if day.RestingHR == nil || *day.RestingHR != 54 || day.MaxHR == nil || *day.MaxHR != 186 || day.End.Format("15:04") != "20:08" || len(day.Minutes) == 0 {
		t.Fatal("cycle heart-rate body")
	}
	span := e.HeartRate(*editTime("2026-03-10T15:05:37Z"), *editTime("2026-03-10T20:30:29Z"))
	if span.Start.Second() != 0 || span.End.Second() != 0 || span.CycleDate != "2026-03-10" || len(span.Minutes) != 325 {
		t.Fatal("minute span")
	}
	rewrite(&state, "daily-resting-heart-rate", "2026-03-10", `"beatsPerMinute":"54"`, `"beatsPerMinute":"60"`)
	past := engine(t, state, "2026-03-12T20:30:00Z", config.Defaults()).HeartRateDay("2026-03-10")
	if past.RestingHR == nil || *past.RestingHR != 60 {
		t.Fatal("past request used today's resting HR")
	}
	e = engine(t, state, "2026-03-12T05:00:00Z", config.Defaults())
	if future := e.HeartRateDay("2026-03-12"); len(future.Minutes) != 0 {
		t.Fatal("not-started cycle has minutes")
	}
}

func TestEditMergeCandidateGapKindsAndCycle(t *testing.T) {
	for _, gap := range []int{15, 16} {
		e := engine(t, fixtureState(t, "edit"), "2026-03-12T20:30:00Z", config.Defaults())
		e.Edits = []activities.Edit{{ID: bandTwo, Hidden: true}}
		next := *editTime("2026-03-10T19:02:00Z")
		next = next.Add(time.Duration(gap) * time.Minute)
		previous := *editTime("2026-03-10T18:05:00Z")
		previous = previous.Add(-time.Duration(gap) * time.Minute)
		e.Activities = []activities.Record{
			{Upload: activities.Upload{ID: "next", ExerciseType: "BOXING", DisplayName: "Boxing", Start: next, End: next.Add(20 * time.Minute)}},
			{Upload: activities.Upload{ID: "previous", ExerciseType: "BOXING", DisplayName: "Boxing", Start: previous.Add(-20 * time.Minute), End: previous}},
		}
		target, err := e.EditTarget(bandOne)
		if err != nil {
			t.Fatal(err)
		}
		if (target.Next != nil) != (gap == 15) || (target.Previous != nil) != (gap == 15) {
			t.Fatal("15-minute candidate boundary")
		}
	}
	e := engine(t, fixtureState(t, "edit"), "2026-03-12T20:30:00Z", config.Defaults())
	e.Activities = []activities.Record{{Upload: activities.Upload{ID: "near-effort", ExerciseType: "BOXING", DisplayName: "Boxing", Start: *editTime("2026-03-11T17:40:00Z"), End: *editTime("2026-03-11T18:00:00Z")}}}
	target, err := e.EditTarget("goop-near-effort")
	if err != nil || target.Next == nil || target.Next.Kind != "detected" {
		t.Fatal("detected candidate", err)
	}
	e.Activities = []activities.Record{
		{Upload: activities.Upload{ID: "before-wake", ExerciseType: "BOXING", DisplayName: "Boxing", Start: *editTime("2026-03-12T06:40:00Z"), End: *editTime("2026-03-12T06:50:00Z")}},
		{Upload: activities.Upload{ID: "after-wake", ExerciseType: "BOXING", DisplayName: "Boxing", Start: *editTime("2026-03-12T06:55:00Z"), End: *editTime("2026-03-12T07:05:00Z")}},
	}
	target, err = e.EditTarget("goop-before-wake")
	if err != nil || target.Next != nil {
		t.Fatal("cross-cycle candidate accepted", err)
	}
	old := engine(t, fixtureState(t, "edit"), "2026-04-10T20:30:00Z", config.Defaults())
	if _, err = old.EditTarget(bandOne); !errors.Is(err, activities.ErrNotFound) {
		t.Fatal("old target in horizon")
	}
}
