package v2report_test

import (
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

const editID = "7300000000000000101"
const mergeID = "7300000000000000102"

func fixtureTime(value string) time.Time {
	at, err := time.Parse(time.RFC3339, value)
	if err != nil {
		panic(err)
	}
	return at
}
func fixturePointer[T any](value T) *T { return &value }
func fixtureEdit() activities.Edit {
	return activities.Edit{ID: editID, ExerciseType: fixturePointer("BOXING"), Start: fixturePointer(fixtureTime("2026-03-10T17:56:00Z")), End: fixturePointer(fixtureTime("2026-03-10T19:12:00Z")), Notes: fixturePointer("Sparring, 6 rounds of 3 minutes."), MergeWith: []string{}, UpdatedAt: fixtureTime("2026-03-12T20:30:00Z")}
}
func fixtureBook(state string) activities.Book {
	book := activities.Book{Activities: []activities.Record{}, Edits: []activities.Edit{}, SleepEdits: []activities.SleepEdit{}, Ratings: []activities.Rating{}}
	if state == "unedited" || state == "alias" {
		return book
	}
	edit := fixtureEdit()
	if state == "merged" || state == "deleted_merged" {
		edit.End = fixturePointer(fixtureTime("2026-03-10T19:38:00Z"))
		edit.MergeWith = []string{mergeID}
	}
	if state == "deleted" || state == "deleted_merged" {
		edit.Hidden = true
	}
	book.Edits = append(book.Edits, edit)
	if state == "rated" {
		book.Ratings = append(book.Ratings, activities.Rating{ID: editID, RPE: 7, UpdatedAt: fixtureTime("2026-03-12T09:00:00Z")})
	}
	if state == "named" || state == "added" {
		kind, name, id, start, end := "RUNNING", "Running", "3f0c0000-0000-4000-8000-0000000000e1", "2026-03-12T07:10:00Z", "2026-03-12T07:41:00Z"
		if state == "added" {
			kind, name, id, start, end = "BOXING", "Boxing", "3f0c0000-0000-4000-8000-0000000000e2", "2026-03-11T18:04:00Z", "2026-03-11T19:04:00Z"
		}
		book.Activities = append(book.Activities, activities.Record{Upload: activities.Upload{ID: id, ExerciseType: kind, DisplayName: name, Start: fixtureTime(start), End: fixtureTime(end), Pauses: []activities.Pause{}, Origin: "added"}, CreatedAt: fixtureTime("2026-03-12T20:30:00Z")})
	}
	return book
}
func editInput(t *testing.T) store2.State2 {
	t.Helper()
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_edit.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	return state
}
func editBuilder(t *testing.T, state store2.State2, book activities.Book, cfg config.Values) *v2report.Builder {
	t.Helper()
	b, err := v2report.New(state, fixtureTime("2026-03-12T20:30:00Z"), cfg, v2report.Options{Activities: book.Activities, Edits: book.Edits, Ratings: book.Ratings, Auth: v2report.Auth{Authorized: true, State: "authorized", Refreshable: true, Missing: []string{}}, ScheduleInstalled: true, Server: v2report.Server{Version: "0.2.0", Revision: "synthetic", ProfileID: fixturePointer(fixtureProfileID)}})
	if err != nil {
		t.Fatal(err)
	}
	return b
}
func editGolden(t *testing.T, name string, body any) {
	t.Helper()
	path := filepath.Join("../../fixtures/v2/edits", name+".json")
	if *updateGoldens {
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		raw, err := json.MarshalIndent(body, "", "  ")
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
	testutil.CompareJSON(t, body, raw, false)
}
func editRequest(edit activities.Edit) map[string]any {
	return map[string]any{"exercise_type": edit.ExerciseType, "start": edit.Start, "end": edit.End, "notes": edit.Notes, "hidden": edit.Hidden, "merge_with": edit.MergeWith}
}

func TestEditGoldenBooksRequestsAndSnapshots(t *testing.T) {
	state := editInput(t)
	for _, name := range []string{"unedited", "edited", "merged", "deleted", "deleted_merged", "named", "added", "alias", "rated"} {
		t.Run(name, func(t *testing.T) {
			book := fixtureBook(name)
			editGolden(t, "book_"+name, book)
			cfg := config.Defaults()
			if name == "alias" {
				cfg.SportAliases["KICKBOXING"] = "BOXING"
			}
			b := editBuilder(t, state, book, cfg)
			editGolden(t, "snapshot_"+name, b.Snapshot())
		})
	}
	for name, state := range map[string]string{"edit": "edited", "merge": "merged", "delete": "deleted", "undo": "edited", "delete_merged": "deleted_merged", "undo_merged": "merged"} {
		editGolden(t, "requests/"+name, editRequest(fixtureBook(state).Edits[0]))
	}
	editGolden(t, "requests/rate", map[string]int{"rpe": 7})
	for name, state := range map[string]string{"name": "named", "add": "added"} {
		a := fixtureBook(state).Activities[0]
		editGolden(t, "requests/"+name, map[string]any{"id": a.ID, "exercise_type": a.ExerciseType, "display_name": a.DisplayName, "start": a.Start, "end": a.End, "pauses": a.Pauses, "origin": a.Origin})
	}
}

func TestEditHiddenExcludedFromEveryBodyAndStrength(t *testing.T) {
	state := editInput(t)
	book := fixtureBook("deleted")
	book.Edits[0].ExerciseType = fixturePointer("WEIGHTLIFTING")
	b := editBuilder(t, state, book, config.Defaults())
	for _, w := range b.Workouts("2026-03-10", "2026-03-10").Workouts {
		if w.ID == editID {
			t.Fatal("hidden workout in workouts")
		}
	}
	day := b.Day("2026-03-10")
	if day.Strength == nil || *day.Strength != 0 {
		t.Fatal("hidden workout in strength")
	}
	for _, w := range day.Workouts {
		if w.ID == editID {
			t.Fatal("hidden workout in day")
		}
	}
	rows := b.Days("2026-03-10", "2026-03-10").Days
	if len(rows) != 1 || rows[0].Workouts != 1 {
		t.Fatal("hidden workout in days count")
	}
	brief := b.Brief("2026-03-10", true, "morning")
	if len(brief.Workouts) != 1 || *brief.Workouts[0].Type != "KICKBOXING" {
		t.Fatal("hidden workout in brief")
	}
	snap := b.Snapshot()
	for _, w := range snap.Workouts.Workouts {
		if w.ID == editID {
			t.Fatal("hidden workout in snapshot")
		}
	}
	original := editBuilder(t, state, fixtureBook("unedited"), config.Defaults()).Day("2026-03-10").Strain
	if !reflect.DeepEqual(original, day.Strain) {
		t.Fatal("hidden edit changed Day Strain")
	}
}

func TestHeartRateGoldenQueriesAndErrors(t *testing.T) {
	b := editBuilder(t, editInput(t), fixtureBook("unedited"), config.Defaults())
	for _, tc := range []struct{ name, query string }{
		{"heart_rate_tue", "start=2026-03-10T15:05:00Z&end=2026-03-10T20:30:00Z"},
		{"heart_rate_thu_effort", "start=2026-03-12T04:10:00Z&end=2026-03-12T10:41:00Z"},
		{"heart_rate_day_2026-03-09", "date=2026-03-09"}, {"heart_rate_day_2026-03-10", "date=2026-03-10"}, {"heart_rate_day_2026-03-11", "date=2026-03-11"}, {"heart_rate_day_2026-03-12", "date=2026-03-12"},
	} {
		params, _ := url.ParseQuery(tc.query)
		body, err := b.Build("heart_rate", params)
		if err != nil {
			t.Fatal(err)
		}
		editGolden(t, tc.name, body)
	}
	for _, tc := range []struct{ query, code string }{
		{"", "invalid_request"}, {"date=2026-03-10&start=2026-03-10T10:00:00Z", "invalid_request"},
		{"start=bad&end=2026-03-10T20:30:00Z", "invalid_request"}, {"start=2026-03-10T20:30:00Z&end=bad", "invalid_request"},
		{"start=2026-03-10T20:30:00Z&end=2026-03-10T20:30:00Z", "invalid_request"},
		{"start=2026-03-10T00:00:00Z&end=2026-03-10T19:00:00Z", "date_out_of_range"},
		{"start=2026-03-12T20:00:00Z&end=2026-03-12T20:36:00Z", "date_out_of_range"},
		{"date=2026-03-10&date=2026-03-11", "invalid_request"}, {"date=bad", "invalid_request"}, {"date=2026-03-10&bad=1", "invalid_request"},
	} {
		params, _ := url.ParseQuery(tc.query)
		_, err := b.Build("heart_rate", params)
		if e, ok := err.(*v2report.Error); !ok || e.Code != tc.code {
			t.Fatalf("heart-rate query: want %s got %v", tc.code, err)
		}
	}
}

type previewExpected struct {
	Strain   *float64     `json:"strain"`
	Trimp    *float64     `json:"trimp"`
	Average  *float64     `json:"avg_hr_bpm"`
	Peak     *float64     `json:"peak_hr_bpm"`
	Zones    *score.Zones `json:"zones_minutes"`
	Coverage *float64     `json:"hr_coverage"`
	Elapsed  float64      `json:"elapsed_minutes"`
	Paused   int          `json:"paused_minutes"`
}
type previewCase struct {
	Name      string             `json:"name"`
	HeartRate v2report.HeartRate `json:"heart_rate"`
	Window    struct {
		Start time.Time `json:"start"`
		End   time.Time `json:"end"`
	} `json:"window"`
	Pauses   []activities.Pause `json:"pauses"`
	Expected previewExpected    `json:"expected"`
}

func TestEditPreviewParityGolden(t *testing.T) {
	cases := []previewCase{}
	for _, name := range []string{"edited", "original", "merged", "wednesday-effort", "twenty-minute-gap", "goop-pause", "no-resting-hr"} {
		state := editInput(t)
		book := fixtureBook("edited")
		id := editID
		day := "2026-03-10"
		if name == "original" {
			book = fixtureBook("unedited")
		}
		if name == "merged" {
			book = fixtureBook("merged")
		}
		if name == "wednesday-effort" {
			book = fixtureBook("unedited")
			id = "effort-2026-03-11T18:04:00Z"
			day = "2026-03-11"
		}
		if name == "twenty-minute-gap" {
			for i := range state.HRMinutes {
				kept := state.HRMinutes[i].Windows[:0]
				for _, m := range state.HRMinutes[i].Windows {
					if m.Start < fixtureTime("2026-03-10T18:20:00Z").Unix() || m.Start >= fixtureTime("2026-03-10T18:40:00Z").Unix() {
						kept = append(kept, m)
					}
				}
				state.HRMinutes[i].Windows = kept
			}
		}
		if name == "no-resting-hr" {
			kept := state.Records[:0]
			for _, r := range state.Records {
				if r.Type != "daily-resting-heart-rate" {
					kept = append(kept, r)
				}
			}
			state.Records = kept
		}
		if name == "goop-pause" {
			a := activities.Upload{ID: "3f0c0000-0000-4000-8000-0000000000e3", ExerciseType: "BOXING", DisplayName: "Boxing", Start: fixtureTime("2026-03-10T17:56:00Z"), End: fixtureTime("2026-03-10T19:12:00Z"), Origin: "live", Pauses: []activities.Pause{{Start: fixtureTime("2026-03-10T18:10:05Z"), End: fixtureTime("2026-03-10T18:20:00Z")}}}
			book = activities.Book{Activities: []activities.Record{{Upload: a}}, Edits: []activities.Edit{}}
			id = "goop-" + a.ID
		}
		b := editBuilder(t, state, book, config.Defaults())
		var target *score.Workout
		for _, w := range b.Workouts(day, day).Workouts {
			if w.ID == id {
				target = &w
				break
			}
		}
		if target == nil {
			t.Fatal("parity workout absent", name)
		}
		params := url.Values{"start": {target.Start.Add(-30 * time.Minute).Format(time.RFC3339)}, "end": {target.End.Add(30 * time.Minute).Format(time.RFC3339)}}
		body, err := b.Build("heart_rate", params)
		if err != nil {
			t.Fatal(err)
		}
		c := previewCase{Name: name, HeartRate: body.(v2report.HeartRate), Pauses: target.Pauses, Expected: previewExpected{Strain: target.Strain, Trimp: target.Trimp, Average: target.Avg, Peak: target.Peak, Zones: target.Zones, Coverage: target.Coverage, Elapsed: target.Elapsed, Paused: target.Paused}}
		c.Window.Start, c.Window.End = target.Start, target.End
		cases = append(cases, c)
	}
	editGolden(t, "preview_parity", struct {
		Synthetic bool          `json:"synthetic_fixture"`
		Cases     []previewCase `json:"cases"`
	}{true, cases})
}
