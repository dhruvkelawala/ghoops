package cli_test

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestActivityCommandsRoundTrip(t *testing.T) {
	dir := testutil.Dir(t)
	options := cli.Options{Vault: &testutil.Vault{}, Now: func() time.Time { return time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC) }}
	invoke := func(args ...string) string {
		t.Helper()
		code, out, stderr := run(t, append([]string{"--state-dir", dir, "activity"}, args...), options)
		if code != 0 {
			t.Fatalf("exit %d %s", code, stderr)
		}
		return out
	}
	out := invoke("add", "--type", "BOXING", "--start", "2026-03-10T12:00:00Z", "--end", "2026-03-10T13:00:00Z")
	var created struct{ Activity struct{ ID string } }
	if json.Unmarshal([]byte(out), &created) != nil || created.Activity.ID == "" {
		t.Fatal("missing generated ID")
	}
	var list struct{ Activities []struct{ ID string } }
	json.Unmarshal([]byte(invoke("list")), &list)
	if len(list.Activities) != 1 || list.Activities[0].ID != created.Activity.ID {
		t.Fatal("activity not listed")
	}
	invoke("delete", "--id", created.Activity.ID)
	json.Unmarshal([]byte(invoke("list")), &list)
	if len(list.Activities) != 0 {
		t.Fatal("deleted activity listed")
	}
}
