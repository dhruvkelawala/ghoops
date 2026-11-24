package cli_test

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestSleepCommandsReadEditKeepEndpointsRestoreAndListOrphans(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	dir, vault := testutil.Dir(t), &testutil.Vault{}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
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
		code, out, stderr := run(t, append([]string{"--state-dir", dir, "sleep"}, args...), opts)
		if code != want {
			t.Fatalf("want exit %d got %d: %s", want, code, stderr)
		}
		if want != 0 {
			return stderr
		}
		return out
	}
	if !strings.Contains(invoke(0, "--date", "2026-03-10", "--json"), `"kind":"sleep"`) {
		t.Fatal("sleep no longer reads")
	}
	invoke(0, "edit", "--date", "2026-03-10", "--end", "2026-03-10T07:41:00Z")
	var response v2report.SleepEditResponse
	if json.Unmarshal([]byte(invoke(0, "edit", "--date", "2026-03-10", "--start", "2026-03-09T22:40:00Z")), &response) != nil || response.SleepEdit == nil || response.SleepEdit.End.Format("15:04") != "07:41" {
		t.Fatal("omitted end did not keep effective wake")
	}
	store := activities.Store{Dir: dir, Vault: vault}
	if _, err = store.PutSleepEdit(t.Context(), "2026-03-05", now, activities.EditPrecondition{}, func(activities.Book) (*activities.SleepEdit, error) {
		return &activities.SleepEdit{Start: now.Add(-120 * time.Hour), End: now.Add(-112 * time.Hour)}, nil
	}); err != nil {
		t.Fatal(err)
	}
	var list struct {
		SleepEdits []struct {
			Date    string
			Applies bool
		} `json:"sleep_edits"`
	}
	if err = json.Unmarshal([]byte(invoke(0, "edits")), &list); err != nil || len(list.SleepEdits) != 2 {
		t.Fatal("missing stored edits", err)
	}
	for _, edit := range list.SleepEdits {
		if edit.Applies != (edit.Date == "2026-03-10") {
			t.Fatal("orphan applies incorrectly")
		}
	}
	invoke(2, "edits", "--days", "0")
	invoke(2, "edit", "--date", "2026-03-10", "--end", "bad")
	invoke(0, "restore", "--date", "2026-03-10")
	invoke(2, "restore", "--date", "2026-03-10")
}
