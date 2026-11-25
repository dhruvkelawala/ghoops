package serve_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestFullStoreRejectsHTTPWritesWithoutChangingFile(t *testing.T) {
	t.Run("activity POST", func(t *testing.T) {
		s := newSleepServer(t, "full", "")
		const name = "activities-v2.enc"
		testutil.WriteLegacyV2File(t, s.store.Dir, name, s.store.Vault, struct {
			Version int `json:"version"`
			activities.Book
		}{1, activities.Book{Activities: []activities.Record{{Upload: activities.Upload{
			ID: "3f0c0000-0000-4000-8000-000000000002", Start: s.now.Add(-time.Hour), End: s.now,
			Live: json.RawMessage(`{"sample":"` + strings.Repeat("x", 17<<20) + `"}`),
		}}}}})
		payload, err := os.ReadFile("../../fixtures/v2/activities/valid.json")
		if err != nil {
			t.Fatal(err)
		}
		assertFullStoreWrite(t, s, name, http.MethodPost, "/v2/activities", string(payload))
	})
	t.Run("journal PUT", func(t *testing.T) {
		s := newSleepServer(t, "full", "")
		testutil.WriteLegacyV2File(t, s.store.Dir, journal.FileName, s.store.Vault, struct {
			Version int `json:"version"`
			journal.Book
		}{1, journal.Book{Entries: []journal.Entry{
			{Date: "2026-03-08", Answers: map[string]bool{strings.Repeat("x", 17<<20): true}},
		}}})
		assertFullStoreWrite(t, s, journal.FileName, http.MethodPut, "/v2/journal/2026-03-09", `{"answers":{"alcohol":true}}`)
	})
}

func assertFullStoreWrite(t *testing.T, s *editServer, name, method, url, payload string) {
	t.Helper()
	path := filepath.Join(s.store.Dir, name)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	w := s.request(method, url, payload, "application/json", true)
	var body v2report.ErrorBody
	if w.Code != http.StatusInsufficientStorage || json.Unmarshal(w.Body.Bytes(), &body) != nil || body.Error == nil || body.Error.Code != "storage_full" {
		t.Fatalf("expected 507 storage_full, got %d %s", w.Code, w.Body)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("the rejected HTTP write changed the file", err)
	}
}
