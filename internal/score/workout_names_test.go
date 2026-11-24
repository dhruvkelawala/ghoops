package score_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

func TestWorkoutNamesFollowSportList(t *testing.T) {
	state := fixtureState(t, "one_name")
	seen := map[string]bool{}
	for _, record := range state.Records {
		var point struct {
			Name     string `json:"name"`
			Exercise struct {
				Type string `json:"exerciseType"`
				Name string `json:"displayName"`
			} `json:"exercise"`
		}
		if err := json.Unmarshal(record.Raw, &point); err != nil {
			t.Fatal(err)
		}
		kind, watch := point.Exercise.Type, point.Exercise.Name
		want, listed := activities.Sports[kind]
		if !listed {
			want = watch
		} else if want == watch {
			t.Fatalf("fixture watch name must differ for %s", kind)
		}
		seen[kind] = true
		t.Run(kind, func(t *testing.T) {
			for _, stateName := range []string{"recorded", "notes", "window", "sport", "named", "live"} {
				if !listed && (stateName == "sport" || stateName == "named" || stateName == "live") {
					continue
				}
				t.Run(stateName, func(t *testing.T) {
					e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
					id := point.Name[strings.LastIndex(point.Name, "/")+1:]
					base := workoutByID(t, e.Workouts("2026-03-10", false), id)
					switch stateName {
					case "notes":
						e.Edits = []activities.Edit{{ID: id, Notes: editText("Synthetic note")}}
					case "window":
						end := base.End.Add(time.Minute)
						e.Edits = []activities.Edit{{ID: id, Start: &base.Start, End: &end}}
					case "sport":
						e.Edits = []activities.Edit{{ID: id, ExerciseType: &kind}}
					case "named", "live":
						e = engine(t, store2.Empty(), "2026-03-10T14:30:00Z", config.Defaults())
						origin := "added"
						if stateName == "live" {
							origin = "live"
						}
						id = "goop-3f0c0000-0000-4000-8000-000000000001"
						e.Activities = []activities.Record{{Upload: activities.Upload{ID: strings.TrimPrefix(id, "goop-"), ExerciseType: kind, DisplayName: watch, Start: base.Start, End: base.End, Origin: origin}}}
					}
					w := workoutByID(t, e.Workouts("2026-03-10", false), id)
					if w.Name == nil {
						t.Fatal("display_name is missing")
					}
					if *w.Name != want {
						t.Errorf("display_name = %q, want %q", *w.Name, want)
					}
					if w.Original == nil || w.Original.Name == nil || *w.Original.Name != want {
						t.Errorf("original display_name must be %q", want)
					}
				})
			}
		})
	}
	for kind := range activities.Sports {
		if !seen[kind] {
			t.Errorf("fixture missing listed sport %s", kind)
		}
	}
	if !seen["SKIING"] {
		t.Error("fixture missing unlisted sport")
	}
}
