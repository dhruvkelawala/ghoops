package serve_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/serve"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestActivityHTTPPersistenceAndValidation(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	tokens := pairing.Tokens{Dir: dir, Vault: vault}
	token, err := tokens.Pair(context.Background(), false, now)
	if err != nil {
		t.Fatal(err)
	}
	var logs bytes.Buffer
	settings := serve.Settings{Store: store2.Store{Dir: dir, Vault: vault}, Config: config.File{Path: filepath.Join(dir, "config.json")}, Tokens: tokens, Now: func() time.Time { return now }, Log: &logs}
	h, err := serve.New(settings)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(h)
	defer server.Close()
	request := func(method, path string, body []byte, content, auth string) (int, []byte) {
		t.Helper()
		r, _ := http.NewRequest(method, server.URL+path, bytes.NewReader(body))
		r.Header.Set("Content-Type", content)
		if auth != "" {
			r.Header.Set("Authorization", "Bearer "+auth)
		}
		resp, e := http.DefaultClient.Do(r)
		if e != nil {
			t.Fatal(e)
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		return resp.StatusCode, b
	}
	valid, err := os.ReadFile("../../fixtures/v2/activities/valid.json")
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		method, path  string
		body          []byte
		content, auth string
		status        int
	}{
		{"POST", "/v2/activities", valid, "application/json", "", 401},
		{"POST", "/v2/activities", valid, "text/plain", token.Value, 400},
		{"POST", "/v2/activities", bytes.Repeat([]byte(" "), 65537), "application/json", token.Value, 413},
		{"PUT", "/v2/activities", valid, "application/json", token.Value, 405},
		{"POST", "/v2/activities?bad=1", valid, "application/json", token.Value, 400},
		{"POST", "/v2/activities", valid, "application/json", token.Value, 201},
		{"POST", "/v2/activities", valid, "application/json", token.Value, 200},
		{"POST", "/v2/activities", bytes.Replace(valid, []byte("Boxing"), []byte("Changed"), 1), "application/json", token.Value, 409},
	} {
		status, body := request(tc.method, tc.path, tc.body, tc.content, tc.auth)
		if status != tc.status {
			t.Fatalf("%s %s: status %d want %d", tc.method, tc.path, status, tc.status)
		}
		if (status == 201 || status == 200) && bytes.Contains(body, []byte(`"live":`)) {
			t.Fatal("activity response echoed the phone's estimates")
		}
	}
	entries, _ := os.ReadDir("../../fixtures/v2/activities")
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), "invalid-") {
			continue
		}
		t.Run(entry.Name(), func(t *testing.T) {
			b, _ := os.ReadFile("../../fixtures/v2/activities/" + entry.Name())
			status, response := request("POST", "/v2/activities", b, "application/json", token.Value)
			field := strings.TrimSuffix(strings.TrimPrefix(entry.Name(), "invalid-"), ".json")
			if status != 400 || !bytes.Contains(response, []byte(field)) {
				t.Fatalf("validation %d: %s", status, response)
			}
		})
	}
	rows, err := (activities.Store{Dir: dir, Vault: vault}).List()
	if err != nil || len(rows) != 1 || rows[0].DisplayName != "Boxing" {
		t.Fatalf("round trip: count=%d error=%v", len(rows), err)
	}
	for _, name := range []string{"activities-v2.enc", "activities.lock"} {
		b, _ := os.ReadFile(filepath.Join(dir, name))
		if bytes.Contains(b, []byte("Boxing")) {
			t.Fatal("plaintext activity on disk")
		}
	}
	h2, err := serve.New(settings)
	if err != nil {
		t.Fatal(err)
	}
	recorder := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/v2/workouts?days=1", nil)
	r.Header.Set("Authorization", "Bearer "+token.Value)
	h2.ServeHTTP(recorder, r)
	var workouts struct{ Workouts []struct{ Kind string } }
	json.Unmarshal(recorder.Body.Bytes(), &workouts)
	if recorder.Code != 200 || len(workouts.Workouts) != 1 || workouts.Workouts[0].Kind != "goop" {
		t.Fatal("persisted workout unavailable after restart")
	}
	status, body := request("GET", "/v2/days?days=1", nil, "", token.Value)
	var days struct {
		Days []struct{ Workouts, Detected int }
	}
	if err := json.Unmarshal(body, &days); err != nil || status != 200 || len(days.Days) != 1 || days.Days[0].Workouts != 1 || days.Days[0].Detected != 0 {
		t.Fatal("GOOP activity missing from day-row workout count")
	}
	status, body = request("GET", "/v2/brief?date=2026-03-10", nil, "", token.Value)
	var brief struct{ Workouts []struct{ Kind string } }
	if err := json.Unmarshal(body, &brief); err != nil || status != 200 || len(brief.Workouts) != 1 || brief.Workouts[0].Kind != "goop" {
		t.Fatal("GOOP activity missing from brief")
	}
	id := rows[0].ID
	for _, want := range []int{200, 404} {
		if status, _ := request("DELETE", "/v2/activities/"+id, nil, "", token.Value); status != want {
			t.Fatalf("delete status %d want %d", status, want)
		}
	}
	status, body = request("GET", "/v2/days?days=1", nil, "", token.Value)
	if err := json.Unmarshal(body, &days); err != nil || status != 200 || len(days.Days) != 1 || days.Days[0].Workouts != 0 {
		t.Fatal("deleted activity remains in day-row count")
	}

	var added map[string]any
	if err := json.Unmarshal(valid, &added); err != nil {
		t.Fatal(err)
	}
	added["id"] = "3f0c0000-0000-4000-8000-000000000002"
	added["origin"] = "added"
	added["notes"] = "  Synthetic POST note  "
	added["start"] = now.Add(-20 * 24 * time.Hour).Format(time.RFC3339)
	added["end"] = now.Add(-20*24*time.Hour + time.Hour).Format(time.RFC3339)
	delete(added, "live")
	delete(added, "pauses")
	payload, _ := json.Marshal(added)
	firstStatus, first := request("POST", "/v2/activities", payload, "application/json", token.Value)
	replayStatus, replay := request("POST", "/v2/activities", payload, "application/json", token.Value)
	var addedBody struct {
		Activity struct {
			Origin string
			Notes  string
		}
	}
	if firstStatus != 201 || replayStatus != 200 || !bytes.Equal(first, replay) || json.Unmarshal(first, &addedBody) != nil || addedBody.Activity.Origin != "added" || addedBody.Activity.Notes != "Synthetic POST note" {
		t.Fatal("added POST/replay contract")
	}
	added["live"] = map[string]any{}
	payload, _ = json.Marshal(added)
	if status, body := request("POST", "/v2/activities", payload, "application/json", token.Value); status != 400 || !bytes.Contains(body, []byte("Invalid activity field: live.")) {
		t.Fatal("added live accepted")
	}

	if strings.Contains(logs.String(), "Boxing") || strings.Contains(logs.String(), token.Value) || strings.Contains(logs.String(), "display_name") || strings.Contains(logs.String(), "Synthetic POST note") {
		t.Fatal("request body or token logged")
	}
}
