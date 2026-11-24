package serve_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestJournalHTTPRequestCases(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/journal/requests/cases.json")
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Cases []struct {
			Name, Date, Body string
			Status           int
			Field            *string
		}
	}
	if err = json.Unmarshal(raw, &file); err != nil || len(file.Cases) == 0 {
		t.Fatal("cannot read cases", err)
	}
	for _, c := range file.Cases {
		t.Run(c.Name, func(t *testing.T) {
			s := newSleepServer(t, "full", "")
			w := s.request("PUT", "/v2/journal/"+c.Date, c.Body, "application/json", true)
			if w.Code != c.Status {
				t.Fatalf("want %d got %d: %s", c.Status, w.Code, w.Body)
			}
			if c.Field != nil && !strings.Contains(w.Body.String(), "Invalid journal field: "+*c.Field+".") {
				t.Fatalf("want field %s: %s", *c.Field, w.Body)
			}
		})
	}
}

func TestJournalHTTPRoundTripReplayConflictAndSnapshot(t *testing.T) {
	s := newSleepServer(t, "full", "")
	path := "/v2/journal/2026-03-09"
	put := func(body string, status int) string {
		t.Helper()
		w := s.request("PUT", path, body, "application/json", true)
		if w.Code != status {
			t.Fatalf("want %d got %d: %s", status, w.Code, w.Body)
		}
		return w.Body.String()
	}
	var first struct {
		Kind  string         `json:"kind"`
		Date  string         `json:"date"`
		Entry *journal.Entry `json:"entry"`
	}
	if json.Unmarshal([]byte(put(`{"answers":{"alcohol":true,"sauna":false},"if_updated_at":null}`, 200)), &first) != nil || first.Kind != "journal_entry" || first.Date != "2026-03-09" || first.Entry == nil || !first.Entry.Answers["alcohol"] {
		t.Fatal("first PUT", first)
	}
	encrypted := filepath.Join(s.store.Dir, journal.FileName)
	before, err := os.ReadFile(encrypted)
	if err != nil || bytes.Contains(before, []byte("alcohol")) {
		t.Fatal("journal file missing or readable", err)
	}
	s.now = s.now.Add(time.Minute)
	put(`{"answers":{"alcohol":true,"sauna":false},"if_updated_at":null}`, 200)
	if after, _ := os.ReadFile(encrypted); !bytes.Equal(before, after) {
		t.Fatal("a replay rewrote the file")
	}
	if !strings.Contains(put(`{"answers":{"alcohol":false},"if_updated_at":null}`, 409), "This day's journal changed on your Mac.") {
		t.Fatal("stale precondition message")
	}
	stamp := first.Entry.UpdatedAt.Format(time.RFC3339)
	put(`{"answers":{"alcohol":false,"sauna":false},"if_updated_at":"`+stamp+`"}`, 200)
	read := s.request("GET", "/v2/journal", "", "", true)
	if read.Code != 200 || !strings.Contains(read.Body.String(), `"entries":[{"date":"2026-03-09","answers":{"alcohol":false,"sauna":false}`) {
		t.Fatalf("GET /v2/journal: %d %s", read.Code, read.Body)
	}
	snapshot := s.request("GET", "/v2/snapshot", "", "", true)
	var body struct {
		Journal json.RawMessage `json:"journal"`
	}
	if snapshot.Code != 200 || json.Unmarshal(snapshot.Body.Bytes(), &body) != nil {
		t.Fatal("snapshot", snapshot.Code)
	}
	testutil.CompareJSON(t, body.Journal, read.Body.Bytes(), false)
	if strings.Contains(s.request("GET", "/v2/brief", "", "", true).Body.String(), "journal") || strings.Contains(s.request("GET", "/v2/day", "", "", true).Body.String(), "alcohol") {
		t.Fatal("journal reached an agent body")
	}
	if w := s.request("PUT", path, `{"answers":{}}`, "application/json", true); w.Code != 200 || !strings.Contains(w.Body.String(), `"entry":null`) {
		t.Fatal("empty answers must remove the entry", w.Body)
	}
	if strings.Contains(s.logs.String(), "alcohol") || strings.Contains(s.logs.String(), "sauna") {
		t.Fatal("body in logs")
	}
}

func TestJournalHTTPTransport(t *testing.T) {
	s := newSleepServer(t, "full", "")
	path := "/v2/journal/2026-03-09"
	body := `{"answers":{"alcohol":true}}`
	for _, tc := range []struct {
		method, path, body, media string
		status                    int
	}{
		{"PUT", "/v2/journal/", body, "application/json", 404},
		{"PUT", "/v2/journal", body, "application/json", 405},
		{"PUT", path + "?private=1", body, "application/json", 400},
		{"PUT", path + "?", body, "application/json", 400},
		{"PUT", path, body, "text/plain", 400},
		{"PUT", path, strings.Repeat(" ", 65<<10), "application/json", 413},
		{"GET", "/v2/journal?days=0", "", "", 400},
		{"GET", "/v2/journal?days=91", "", "", 400},
		{"GET", "/v2/journal?date=2026-03-09", "", "", 400},
		{"GET", "/v2/journal/", "", "", 404},
	} {
		if w := s.request(tc.method, tc.path, tc.body, tc.media, true); w.Code != tc.status {
			t.Fatalf("%s %s: want %d got %d", tc.method, tc.path, tc.status, w.Code)
		}
	}
	for _, method := range []string{"GET", "POST", "DELETE", "PATCH"} {
		w := s.request(method, path, "", "", true)
		if w.Code != 405 || w.Header().Get("Allow") != "PUT" {
			t.Fatalf("%s: %d Allow=%q", method, w.Code, w.Header().Get("Allow"))
		}
	}
	if w := s.request("PUT", path, body, "application/json", false); w.Code != 401 {
		t.Fatal("unauthenticated PUT", w.Code)
	}
	if w := s.request("GET", "/v2/journal", "", "", false); w.Code != 401 {
		t.Fatal("unauthenticated GET", w.Code)
	}
	if strings.Contains(s.logs.String(), "private") {
		t.Fatal("query in logs")
	}
}
