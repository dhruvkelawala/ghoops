package serve_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

func newSleepServer(t *testing.T, fixture, bookName string) *editServer {
	t.Helper()
	s := newEditServer(t)
	s.now = time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	name := fixture
	if name == "sleep_no_stages" {
		name = "full"
	}
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_" + name + ".json")
	var state store2.State2
	if err == nil {
		err = json.Unmarshal(raw, &state)
	}
	if err != nil {
		t.Fatal(err)
	}
	if fixture == "sleep_no_stages" {
		for i, record := range state.Records {
			if record.Type == "sleep" && record.Date == "2026-03-10" {
				var point map[string]any
				if err = json.Unmarshal(record.Raw, &point); err != nil {
					t.Fatal(err)
				}
				point["sleep"].(map[string]any)["stages"] = []any{}
				state.Records[i].Raw, err = json.Marshal(point)
				if err != nil {
					t.Fatal(err)
				}
			}
		}
	}
	if err = (store2.Store{Dir: s.store.Dir, Vault: s.store.Vault}).Save(state, s.now); err != nil {
		t.Fatal(err)
	}
	if bookName != "" {
		raw, err = os.ReadFile("../../fixtures/v2/sleep_edit/book_" + bookName + ".json")
		var book activities.Book
		if err == nil {
			err = json.Unmarshal(raw, &book)
		}
		if err != nil {
			t.Fatal(err)
		}
		for _, row := range book.Activities {
			if _, _, err = s.store.Put(t.Context(), row.Upload, s.now); err != nil {
				t.Fatal(err)
			}
		}
		for _, row := range book.SleepEdits {
			if _, err = s.store.PutSleepEdit(t.Context(), row.Date, s.now, activities.EditPrecondition{}, func(activities.Book) (*activities.SleepEdit, error) { return &row, nil }); err != nil {
				t.Fatal(err)
			}
		}
	}
	return s
}

func TestSleepEditHTTPValidationVectors(t *testing.T) {
	paths, err := filepath.Glob("../../fixtures/v2/sleep_edit/requests/*.json")
	if err != nil || len(paths) == 0 {
		t.Fatal("no request vectors", err)
	}
	for _, path := range paths {
		t.Run(filepath.Base(path), func(t *testing.T) {
			raw, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var tc struct {
				Name, Date, Store, Book, Field string
				Body                           json.RawMessage
				Status                         int
			}
			if err = json.Unmarshal(raw, &tc); err != nil {
				t.Fatal(err)
			}
			s := newSleepServer(t, tc.Store, tc.Book)
			assertEditStatus(t, s.request("PUT", "/v2/sleep-edits/"+tc.Date, string(tc.Body), "application/json", true), tc.Status, tc.Field)
		})
	}
}

func TestSleepEditHTTPReplayConflictNormalizationAndRestore(t *testing.T) {
	s := newSleepServer(t, "full", "")
	path := "/v2/sleep-edits/2026-03-10"
	body := `{"start":"2026-03-09T23:12:00Z","end":"2026-03-10T07:41:00Z","if_updated_at":null,"future":true}`
	put := func(raw string) string {
		t.Helper()
		w := s.request("PUT", path, raw, "application/json", true)
		assertEditStatus(t, w, 200, "")
		return w.Body.String()
	}
	first := put(body)
	encrypted := filepath.Join(s.store.Dir, "activities-v2.enc")
	before, err := os.ReadFile(encrypted)
	if err != nil {
		t.Fatal(err)
	}
	s.now = s.now.Add(time.Minute)
	replay := put(body)
	var a, b struct {
		SleepEdit activities.SleepEdit `json:"sleep_edit"`
	}
	if json.Unmarshal([]byte(first), &a) != nil || json.Unmarshal([]byte(replay), &b) != nil || !a.SleepEdit.UpdatedAt.Equal(b.SleepEdit.UpdatedAt) {
		t.Fatal("replay changed updated_at")
	}
	after, err := os.ReadFile(encrypted)
	if err != nil || string(before) != string(after) {
		t.Fatal("replay rewrote encrypted file", err)
	}
	assertEditStatus(t, s.request("PUT", path, strings.Replace(body, "07:41", "07:42", 1), "application/json", true), 409, "")
	read := s.request("GET", "/v2/sleep?date=2026-03-10", "", "", true)
	assertEditStatus(t, read, 200, "")
	if !strings.Contains(read.Body.String(), `"asleep_minutes":487`) || !strings.Contains(read.Body.String(), `"end":"2026-03-10T07:41:00Z"`) {
		t.Fatal("stored edit did not reach read")
	}
	put(`{"start":"2026-03-09T23:12:00Z","end":"2026-03-10T06:29:00Z"}`)
	book, err := s.store.Load()
	if err != nil || len(book.SleepEdits) != 0 {
		t.Fatal("Google window did not normalize to no edit", err)
	}
	put(body)
	s.now = s.now.AddDate(0, 0, 31)
	assertEditStatus(t, s.request("DELETE", path, "", "", true), 200, "")
	assertEditStatus(t, s.request("DELETE", path, "", "", true), 404, "")
}

func TestSleepEditHTTPTransport(t *testing.T) {
	s := newSleepServer(t, "full", "")
	path := "/v2/sleep-edits/2026-03-10"
	body := `{"start":"2026-03-09T23:12:00Z","end":"2026-03-10T07:41:00Z"}`
	for _, tc := range []struct {
		method, path, body, media string
		status                    int
	}{
		{"PUT", "/v2/sleep-edits", body, "application/json", 404}, {"PUT", "/v2/sleep-edits/", body, "application/json", 404},
		{"PUT", path + "?private=1", body, "application/json", 400}, {"PUT", path + "?", body, "application/json", 400},
		{"PUT", path, body, "text/plain", 400}, {"PUT", path, strings.Repeat(" ", 65<<10), "application/json", 413},
		{"DELETE", path, "{}", "application/json", 400},
	} {
		assertEditStatus(t, s.request(tc.method, tc.path, tc.body, tc.media, true), tc.status, "")
	}
	for _, method := range []string{"GET", "POST", "PATCH"} {
		w := s.request(method, path, "", "", true)
		assertEditStatus(t, w, 405, "")
		if w.Header().Get("Allow") != "PUT, DELETE" {
			t.Fatal("wrong Allow")
		}
	}
	for _, method := range []string{"PUT", "DELETE"} {
		assertEditStatus(t, s.request(method, path, body, "application/json", false), 401, "")
	}
	if strings.Contains(s.logs.String(), "23:12") || strings.Contains(s.logs.String(), "private") {
		t.Fatal("body or query in logs")
	}
}
