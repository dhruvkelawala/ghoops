package cli_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestActivitiesCompactRecoversOversizedLegacyFile(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	cutoff := now.Add(-30 * 24 * time.Hour)
	expired := now.AddDate(0, 0, -401)
	large := json.RawMessage(`{"sample":"` + strings.Repeat("x", 17<<20) + `"}`)
	book := activities.Book{
		Activities: []activities.Record{
			{Upload: activities.Upload{ID: "old", Start: expired.Add(-time.Hour), End: expired, Live: large}},
			{Upload: activities.Upload{ID: "cutoff", Start: cutoff.Add(-time.Hour), End: cutoff, Live: json.RawMessage(`{"samples":2}`)}},
			{Upload: activities.Upload{ID: "recent", Start: now.Add(-time.Hour), End: now, Live: json.RawMessage(`{"samples":3}`)}},
		},
		Edits:      []activities.Edit{{ID: "edit", Hidden: true, UpdatedAt: expired}},
		SleepEdits: []activities.SleepEdit{{Date: "2025-01-01", UpdatedAt: expired}},
		Ratings:    []activities.Rating{{ID: "rating", UpdatedAt: expired}},
	}
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	store := activities.Store{Dir: dir, Vault: vault}
	path := filepath.Join(dir, "activities-v2.enc")
	testutil.WriteLegacyV2File(t, dir, filepath.Base(path), vault, struct {
		Version int `json:"version"`
		activities.Book
	}{1, book})
	before, err := os.Stat(path)
	if err != nil || before.Size() <= 17<<20 {
		t.Fatal("expected a legacy file above 17 MiB", err)
	}
	expected, err := store.Load()
	if err != nil || len(expected.Activities) != 3 {
		t.Fatal("oversized legacy activities could not be read", err)
	}
	expected.Activities[0].Live = nil

	options := cli.Options{Vault: vault, Now: func() time.Time { return now }}
	code, stdout, stderr := run(t, []string{"--state-dir", dir, "activities", "compact", "--json"}, options)
	var response struct {
		v2report.Envelope
		activities.Compaction
	}
	if code != 0 || stderr != "" || json.Unmarshal([]byte(stdout), &response) != nil || response.Kind != "activities_compact" {
		t.Fatal("compaction did not return a success envelope", code, stderr)
	}
	after, err := os.Stat(path)
	if err != nil || after.Size() > 16<<20 {
		t.Fatal("compaction did not shrink the file below 16 MiB", err)
	}
	want := activities.Compaction{Activities: 3, LiveRemoved: 1, BytesBefore: int(before.Size()), BytesAfter: int(after.Size())}
	if response.Compaction != want {
		t.Fatalf("compaction counts = %+v, want %+v", response.Compaction, want)
	}
	got, err := store.Load()
	if err != nil || !reflect.DeepEqual(got, expected) {
		t.Fatal("compaction changed data beyond the old estimate", err)
	}
}

func TestActivitiesCompactKeepsFileWhenResultIsTooLarge(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	oldEnd := now.AddDate(0, 0, -31)
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	path := filepath.Join(dir, "activities-v2.enc")
	testutil.WriteLegacyV2File(t, dir, filepath.Base(path), vault, struct {
		Version int `json:"version"`
		activities.Book
	}{1, activities.Book{Activities: []activities.Record{
		{Upload: activities.Upload{ID: "old", End: oldEnd, Live: json.RawMessage(`{"samples":1}`)}},
		{Upload: activities.Upload{ID: "recent", End: now, Live: json.RawMessage(`{"sample":"` + strings.Repeat("x", 17<<20) + `"}`)}},
	}}})
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	code, stdout, stderr := run(t, []string{"--state-dir", dir, "activities", "compact"}, cli.Options{Vault: vault, Now: func() time.Time { return now }})
	var body v2report.ErrorBody
	if code != 1 || stdout != "" || json.Unmarshal([]byte(stderr), &body) != nil || body.Error == nil || body.Error.Code != "storage_full" {
		t.Fatal("compaction did not report storage_full", code, stderr)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(after, before) {
		t.Fatal("failed compaction changed the legacy activity file", err)
	}
}
