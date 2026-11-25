package activities_test

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestWriterRefusesOversizedFile(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	store := activities.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	upload := activities.Upload{
		ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING",
		DisplayName: "Boxing", Start: now.Add(-time.Hour), End: now,
	}
	if _, _, err := store.Put(t.Context(), upload, now); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(store.Dir, "activities-v2.enc")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	oversized := upload
	oversized.ID = "3f0c0000-0000-4000-8000-000000000002"
	oversized.Live = []byte(`{"sample":"` + strings.Repeat("x", 17<<20) + `"}`)
	if _, _, err := store.Put(t.Context(), oversized, now); !errors.Is(err, activities.ErrCapacity) {
		t.Fatal("expected the activity file limit", err)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("the rejected write changed the file", err)
	}
	rows, err := store.List()
	if err != nil || len(rows) != 1 || rows[0].ID != upload.ID {
		t.Fatal("the previous activity could not be read", err)
	}
}
