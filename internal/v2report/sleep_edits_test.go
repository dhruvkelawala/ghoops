package v2report_test

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func sleepBuilder(t *testing.T, fixture, bookName string) *v2report.Builder {
	t.Helper()
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_" + fixture + ".json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	var book activities.Book
	if bookName != "" {
		raw, err = os.ReadFile("../../fixtures/v2/sleep_edit/book_" + bookName + ".json")
		if err != nil {
			t.Fatal(err)
		}
		if err = json.Unmarshal(raw, &book); err != nil {
			t.Fatal(err)
		}
	}
	b, err := v2report.New(state, fixtureTime("2026-03-10T14:30:00Z"), config.Defaults(), v2report.Options{Activities: book.Activities, Edits: book.Edits, SleepEdits: book.SleepEdits, Auth: v2report.Auth{Authorized: true, State: "authorized", Refreshable: true, Missing: []string{}}, ScheduleInstalled: true, Server: v2report.Server{Version: "0.2.0", Revision: "synthetic"}})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestSleepEditBooksAndComputedParity(t *testing.T) {
	for _, name := range []string{"extended", "shortened", "earlier", "orphan"} {
		t.Run(name, func(t *testing.T) {
			got := sleepBuilder(t, "full", name).Sleep("2026-03-10")
			path := "../../fixtures/v2/sleep_edit/sleep_" + name + ".json"
			if *updateGoldens {
				raw, err := json.MarshalIndent(got, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(path, append(raw, '\n'), 0644); err != nil {
					t.Fatal(err)
				}
			}
			raw, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			testutil.CompareJSON(t, got, raw, false)
		})
	}
	extended := sleepBuilder(t, "full", "extended").Sleep("2026-03-10")
	unstaged := sleepBuilder(t, "sleep_unstaged", "").Sleep("2026-03-10")
	computed := func(body any) map[string]any {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		var result map[string]any
		if err = json.Unmarshal(raw, &result); err != nil {
			t.Fatal(err)
		}
		session := result["session"].(map[string]any)
		for _, key := range []string{"type", "processed", "stages_status", "minutes_awake", "minutes_after_wake_up", "minutes_in_sleep_period", "google", "edit", "edit_range"} {
			delete(session, key)
		}
		return result
	}
	if !reflect.DeepEqual(computed(extended), computed(unstaged)) {
		t.Fatal("computed extended sleep differs from Google's extended night")
	}
	base := sleepBuilder(t, "full", "")
	orphan := sleepBuilder(t, "full", "orphan")
	if !reflect.DeepEqual(base.Snapshot(), orphan.Snapshot()) {
		t.Fatal("orphan changed a response")
	}
}

func TestSleepEditMovesBothCyclesAndInsideWorkout(t *testing.T) {
	base, edited := sleepBuilder(t, "full", ""), sleepBuilder(t, "full", "extended")
	for _, date := range []string{"2026-03-09", "2026-03-10"} {
		before, after := base.Day(date), edited.Day(date)
		if reflect.DeepEqual(before.Cycle, after.Cycle) || reflect.DeepEqual(before.Strain, after.Strain) {
			t.Fatal("cycle and Strain report did not recompute", date)
		}
		if !reflect.DeepEqual(before.Workouts, after.Workouts) {
			t.Fatal("extension moved a workout", date)
		}
	}
	neighbours := sleepBuilder(t, "sleep_neighbours", "neighbours").Sleep("2026-03-10").Session.EditRange
	if neighbours.EarliestStart.Format("15:04") != "22:30" || neighbours.LatestEnd.Format("15:04") != "07:30" {
		t.Fatal("neighbour bounds", neighbours)
	}
	inside := sleepBuilder(t, "full", "inside_workout").Sleep("2026-03-10").Session.EditRange
	if inside.LatestEnd.Format("15:04") != "05:00" {
		t.Fatal("inside workout failed to cap wake")
	}
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	json.Unmarshal(raw, &state)
	e, err := score.New(state, fixtureTime("2026-03-10T14:30:00Z"), config.Defaults())
	if err != nil {
		t.Fatal(err)
	}
	raw, err = os.ReadFile("../../fixtures/v2/sleep_edit/book_inside_workout.json")
	if err != nil {
		t.Fatal(err)
	}
	var book activities.Book
	json.Unmarshal(raw, &book)
	e.Activities = book.Activities
	id := "goop-" + book.Activities[0].ID
	find := func(date string) bool {
		for _, w := range e.Workouts(date, false) {
			if w.ID == id {
				return true
			}
		}
		return false
	}
	if !find("2026-03-09") {
		t.Fatal("inside workout was not in previous cycle")
	}
	edit, err := e.ValidateSleepEdit(activities.SleepEdit{Date: "2026-03-10", Start: fixtureTime("2026-03-09T23:12:00Z"), End: fixtureTime("2026-03-10T04:55:00Z")})
	if err != nil {
		t.Fatal(err)
	}
	e.SleepEdits = []activities.SleepEdit{*edit}
	if !find("2026-03-10") || find("2026-03-09") {
		t.Fatal("shorter night did not move inside workout")
	}
}
