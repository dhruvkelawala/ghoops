package cli_test

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestActivityRateSetsClearsAndShowsInWorkouts(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	dir, vault := testutil.Dir(t), &testutil.Vault{}
	now := time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_edit.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	if err = (store2.Store{Dir: dir, Vault: vault}).Save(state, now); err != nil {
		t.Fatal(err)
	}
	opts := cli.Options{Vault: vault, Now: func() time.Time { return now }}
	invoke := func(want int, args ...string) string {
		t.Helper()
		code, out, stderr := run(t, append([]string{"--state-dir", dir}, args...), opts)
		if code != want {
			t.Fatalf("%v: exit want %d got %d: %s", args, want, code, stderr)
		}
		return out
	}
	id := "7300000000000000101"
	var got v2report.RatingResponse
	if err = json.Unmarshal([]byte(invoke(0, "activity", "rate", "--id", id, "--rpe", "7")), &got); err != nil {
		t.Fatal(err)
	}
	want := v2report.RatingResponse{Envelope: v2report.CommandEnvelope("rating", now), ID: id, Rating: &activities.Rating{ID: id, RPE: 7, UpdatedAt: now}}
	if !reflect.DeepEqual(got.Rating, want.Rating) || got.Kind != "rating" || got.ID != id {
		t.Fatalf("rate body %+v", got)
	}
	var workouts struct {
		Workouts []struct {
			ID  string `json:"id"`
			RPE *int   `json:"rpe"`
		} `json:"workouts"`
	}
	if err = json.Unmarshal([]byte(invoke(0, "workouts", "--days", "30")), &workouts); err != nil {
		t.Fatal(err)
	}
	rated := 0
	for _, w := range workouts.Workouts {
		if w.RPE != nil {
			rated++
			if w.ID != id || *w.RPE != 7 {
				t.Fatal("wrong workout rated", w.ID)
			}
		}
	}
	if rated != 1 {
		t.Fatal("rated workouts", rated)
	}
	for _, args := range [][]string{{"--id", id}, {"--id", id, "--rpe", "5", "--clear"}} {
		invoke(2, append([]string{"activity", "rate"}, args...)...)
	}
	for _, args := range [][]string{{"--id", id, "--rpe", "11"}, {"--id", id, "--rpe", "x"}, {"--id", "effort-2026-03-11T18:04:00Z", "--rpe", "5"}} {
		invoke(2, append([]string{"activity", "rate"}, args...)...)
	}
	invoke(2, "activity", "rate", "--id", "7300000000000000999", "--rpe", "5")
	if err = json.Unmarshal([]byte(invoke(0, "activity", "rate", "--id", id, "--clear")), &got); err != nil || got.Rating != nil {
		t.Fatal("clear", err)
	}
	invoke(2, "activity", "rate", "--id", id, "--clear")
}
