package cli_test

import (
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestEditCommandsKeepUnspecifiedFieldsMergeHideRestoreAndListOrphans(t *testing.T) {
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
		code, out, stderr := run(t, append([]string{"--state-dir", dir, "activity"}, args...), opts)
		if code != want {
			t.Fatalf("exit want %d got %d: %s", want, code, stderr)
		}
		if code != 0 {
			var body v2report.ErrorBody
			if json.Unmarshal([]byte(stderr), &body) != nil || body.Error == nil {
				t.Fatal("schema-2 error absent")
			}
			return stderr
		}
		return out
	}
	id := "7300000000000000101"
	invoke(0, "edit", "--id", id, "--type", "BOXING", "--start", "2026-03-10T17:56:00Z", "--end", "2026-03-10T19:12:00Z", "--notes", "  Synthetic note  ")
	var body v2report.EditResponse
	json.Unmarshal([]byte(invoke(0, "hide", "--id", id)), &body)
	if body.Edit == nil || !body.Edit.Hidden || body.Edit.Notes == nil || *body.Edit.Notes != "Synthetic note" || *body.Edit.ExerciseType != "BOXING" {
		t.Fatal("hide dropped fields")
	}
	invoke(0, "unhide", "--id", id)
	json.Unmarshal([]byte(invoke(0, "merge", "--id", id, "--with", "7300000000000000102")), &body)
	if body.Edit.End.Format("15:04") != "19:38" || len(body.Edit.MergeWith) != 1 || *body.Edit.Notes != "Synthetic note" {
		t.Fatal("merge dropped fields or union")
	}
	invoke(2, "edit", "--id", "7300000000000000102", "--type", "BOXING")
	invoke(0, "restore", "--id", id)
	invoke(2, "restore", "--id", id)
	invoke(0, "edit", "--id", id, "--notes", "Synthetic note")
	json.Unmarshal([]byte(invoke(0, "edit", "--id", id, "--type", "band", "--band-window", "--clear-notes")), &body)
	if body.Edit != nil {
		t.Fatal("empty override not removed")
	}
	for _, args := range [][]string{
		{"edit", "--id", id, "--start", "2026-03-10T18:00:00Z"},
		{"edit", "--id", id, "--notes", "a", "--clear-notes"},
		{"edit", "--id", "effort-x", "--type", "BOXING"},
		{"merge", "--id", id, "--with", "missing"}, {"edits", "--days", "0"},
	} {
		invoke(2, args...)
	}
	store := activities.Store{Dir: dir, Vault: vault}
	note := "Synthetic orphan"
	if _, err = store.PutEdit(t.Context(), activities.Edit{ID: "missing", Notes: &note}, now); err != nil {
		t.Fatal(err)
	}
	invoke(0, "edit", "--id", id, "--type", "BOXING")
	var list struct {
		Edits []struct {
			ID      string
			Applies bool
		}
	}
	json.Unmarshal([]byte(invoke(0, "edits")), &list)
	if len(list.Edits) != 2 {
		t.Fatal("edits list count")
	}
	for _, edit := range list.Edits {
		if edit.Applies != (edit.ID == id) {
			t.Fatal("orphan applies")
		}
	}
	added := invoke(0, "add", "--type", "BOXING", "--start", "2026-03-11T18:04:00Z", "--end", "2026-03-11T19:04:00Z", "--origin", "added", "--notes", "Synthetic added note")
	var result struct{ Activity activities.Record }
	json.Unmarshal([]byte(added), &result)
	if result.Activity.Origin != "added" || result.Activity.Notes == nil {
		t.Fatal("add origin and notes")
	}
}

func TestHeartRateCLIUsesBuilderAndSchemaErrors(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	opts := cli.Options{Vault: &testutil.Vault{}, Now: func() time.Time { return time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC) }}
	dir := testutil.Dir(t)
	for _, args := range [][]string{{"--date", "2026-03-10"}, {"--start", "2026-03-10T17:00:00Z", "--end", "2026-03-10T18:00:00Z"}, {"--start", "bad", "--end", "bad"}, {"--date", "2026-03-10", "--start", "bad"}} {
		code, out, stderr := run(t, append([]string{"--state-dir", dir, "heart-rate"}, args...), opts)
		if len(args) == 2 || args[1] == "2026-03-10T17:00:00Z" {
			if code != 0 {
				t.Fatal(code, stderr)
			}
			var body v2report.HeartRate
			if json.Unmarshal([]byte(out), &body) != nil || body.Kind != "heart_rate" {
				t.Fatal("read body")
			}
		} else {
			var body v2report.ErrorBody
			if code != 2 || json.Unmarshal([]byte(stderr), &body) != nil || body.Error.Code != "invalid_request" {
				t.Fatal("read error", code, stderr)
			}
		}
	}
}
