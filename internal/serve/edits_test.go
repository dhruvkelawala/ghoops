package serve_test

import (
	"bytes"
	"context"
	"encoding/json"
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

const editTarget = "7300000000000000101"
const editNeighbor = "7300000000000000102"

type editServer struct {
	handler *serve.Handler
	token   string
	now     time.Time
	store   activities.Store
	config  config.File
	logs    bytes.Buffer
}

func newEditServer(t *testing.T) *editServer {
	t.Helper()
	s := &editServer{now: time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)}
	dir, vault := testutil.Dir(t), &testutil.Vault{}
	store := store2.Store{Dir: dir, Vault: vault}
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_edit.json")
	var state store2.State2
	if err == nil {
		err = json.Unmarshal(raw, &state)
	}
	if err != nil {
		t.Fatal(err)
	}
	if err = store.Save(state, s.now); err != nil {
		t.Fatal(err)
	}
	s.store = activities.Store{Dir: dir, Vault: vault}
	s.config = config.File{Path: filepath.Join(dir, "config.json")}
	tokens := pairing.Tokens{Dir: dir, Vault: vault}
	token, err := tokens.Pair(context.Background(), false, s.now)
	if err != nil {
		t.Fatal(err)
	}
	s.token = token.Value
	s.handler, err = serve.New(serve.Settings{Store: store, Config: s.config, Tokens: tokens, Now: func() time.Time { return s.now }, Log: &s.logs})
	if err != nil {
		t.Fatal(err)
	}
	return s
}
func (s *editServer) request(method, path, body, media string, auth bool) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, path, strings.NewReader(body))
	if auth {
		r.Header.Set("Authorization", "Bearer "+s.token)
	}
	if media != "" {
		r.Header.Set("Content-Type", media)
	}
	w := httptest.NewRecorder()
	s.handler.ServeHTTP(w, r)
	return w
}
func editBody(t *testing.T, name string) string {
	t.Helper()
	raw, err := os.ReadFile("../../fixtures/v2/edits/requests/" + name + ".json")
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}
func assertEditStatus(t *testing.T, w *httptest.ResponseRecorder, status int, field string) {
	t.Helper()
	if w.Code != status {
		t.Fatalf("want %d got %d: %s", status, w.Code, w.Body)
	}
	if field != "" && !strings.Contains(w.Body.String(), "Invalid edit field: "+field+".") {
		t.Fatalf("field %s absent: %s", field, w.Body)
	}
}

func TestEditHTTPValidationAndTransport(t *testing.T) {
	s := newEditServer(t)
	raw := editBody(t, "edit")
	var base map[string]any
	if err := json.Unmarshal([]byte(raw), &base); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		field string
		value any
	}{
		{"exercise_type", "NOT_A_SPORT"}, {"exercise_type", 3}, {"start", nil}, {"end", "bad"},
		{"end", "2026-03-10T17:55:00Z"}, {"end", "2026-03-12T20:36:00Z"},
		{"start", "2026-03-10T12:00:00Z"}, {"end", "2026-03-10T23:00:00Z"},
		{"notes", " "}, {"notes", strings.Repeat("a", 501)}, {"hidden", nil}, {"hidden", "true"},
		{"merge_with", nil}, {"merge_with", []string{editTarget}}, {"merge_with", []string{"missing"}},
		{"merge_with", []string{"a", "b", "c", "d", "e"}}, {"merge_with", []string{"effort-2026-03-11T18:04:00Z"}},
	} {
		body := map[string]any{}
		for key, value := range base {
			body[key] = value
		}
		body[tc.field] = tc.value
		data, _ := json.Marshal(body)
		assertEditStatus(t, s.request("PUT", "/v2/edits/"+editTarget, string(data), "application/json", true), 400, tc.field)
	}
	for key := range base {
		body := map[string]any{}
		for k, v := range base {
			if k != key {
				body[k] = v
			}
		}
		data, _ := json.Marshal(body)
		assertEditStatus(t, s.request("PUT", "/v2/edits/"+editTarget, string(data), "application/json", true), 400, key)
	}
	short := strings.ReplaceAll(raw, "2026-03-10T19:12:00Z", "2026-03-10T17:56:30Z")
	short = strings.ReplaceAll(short, "2026-03-10T17:56:00Z", "2026-03-10T18:05:00Z")
	short = strings.ReplaceAll(short, "2026-03-10T17:56:30Z", "2026-03-10T18:05:30Z")
	assertEditStatus(t, s.request("PUT", "/v2/edits/"+editTarget, short, "application/json", true), 400, "active_duration")
	for _, body := range []string{"null", "[]", "invalid"} {
		assertEditStatus(t, s.request("PUT", "/v2/edits/"+editTarget, body, "application/json", true), 400, "body")
	}
	for _, tc := range []struct {
		method, path, body, media string
		status                    int
	}{
		{"PUT", "/v2/edits/unknown", raw, "application/json", 404},
		{"PUT", "/v2/edits/effort-2026-03-11T18:04:00Z", raw, "application/json", 400},
		{"PUT", "/v2/edits/a/b", raw, "application/json", 400},
		{"PUT", "/v2/edits/" + editTarget, strings.Repeat(" ", 70<<10), "application/json", 413},
		{"PUT", "/v2/edits/" + editTarget + "?private=1", raw, "application/json", 400},
		{"PUT", "/v2/edits/" + editTarget + "?", raw, "application/json", 400},
		{"PUT", "/v2/edits/" + editTarget, raw, "text/plain", 400},
		{"DELETE", "/v2/edits/" + editTarget, "{}", "application/json", 400},
		{"PUT", "/v2/edits", raw, "application/json", 404}, {"PUT", "/v2/edits/", raw, "application/json", 404},
	} {
		assertEditStatus(t, s.request(tc.method, tc.path, tc.body, tc.media, true), tc.status, "")
	}
	for _, method := range []string{"PATCH", "POST", "GET"} {
		w := s.request(method, "/v2/edits/"+editTarget, "", "", true)
		assertEditStatus(t, w, 405, "")
		if w.Header().Get("Allow") != "PUT, DELETE" {
			t.Fatal("edit Allow", w.Header())
		}
	}
	for _, tc := range []struct{ method, path, allow string }{{"GET", "/v2/activities", "POST"}, {"POST", "/v2/activities/a", "DELETE"}, {"PUT", "/v2/heart-rate", "GET"}} {
		w := s.request(tc.method, tc.path, "", "", true)
		assertEditStatus(t, w, 405, "")
		if w.Header().Get("Allow") != tc.allow {
			t.Fatal("path Allow", w.Header())
		}
	}
	for _, method := range []string{"PUT", "DELETE"} {
		assertEditStatus(t, s.request(method, "/v2/edits/"+editTarget, raw, "application/json", false), 401, "")
	}
	if strings.Contains(s.logs.String(), "Sparring") || strings.Contains(s.logs.String(), "private") || strings.Contains(s.logs.String(), "?") {
		t.Fatal("body or query in logs")
	}
	empty := `{"exercise_type":null,"start":null,"end":null,"notes":null,"hidden":false,"merge_with":[],"future_key":true}`
	normalized := s.request("PUT", "/v2/edits/"+editTarget, empty, "application/json", true)
	assertEditStatus(t, normalized, 200, "")
	if !strings.Contains(normalized.Body.String(), `"edit":null`) {
		t.Fatal("empty edit retained")
	}
	long := `{"id":"3f0c0000-0000-4000-8000-0000000000e5","exercise_type":"BOXING","display_name":"Boxing","start":"2026-03-12T07:00:00Z","end":"2026-03-12T19:00:00Z","origin":"added"}`
	assertEditStatus(t, s.request("POST", "/v2/activities", long, "application/json", true), 201, "")
	longEdit := `{"exercise_type":null,"start":"2026-03-12T07:00:00Z","end":"2026-03-12T19:01:00Z","notes":null,"hidden":false,"merge_with":[]}`
	assertEditStatus(t, s.request("PUT", "/v2/edits/goop-3f0c0000-0000-4000-8000-0000000000e5", longEdit, "application/json", true), 400, "active_duration")

	s.now = s.now.AddDate(0, 0, 31)
	assertEditStatus(t, s.request("PUT", "/v2/edits/"+editTarget, `{"exercise_type":null,"start":null,"end":null,"notes":null,"hidden":false,"merge_with":[]}`, "application/json", true), 404, "")
}

func TestEditHTTPReplayMergeConflictsDeleteRestoreAndAlias(t *testing.T) {
	s := newEditServer(t)
	put := func(id, raw string) *httptest.ResponseRecorder {
		return s.request("PUT", "/v2/edits/"+id, raw, "application/json", true)
	}
	first := put(editTarget, editBody(t, "edit"))
	assertEditStatus(t, first, 200, "")
	s.now = s.now.Add(time.Minute)
	replay := put(editTarget, editBody(t, "edit"))
	assertEditStatus(t, replay, 200, "")
	var a, b struct{ Edit activities.Edit }
	json.Unmarshal(first.Body.Bytes(), &a)
	json.Unmarshal(replay.Body.Bytes(), &b)
	if !a.Edit.UpdatedAt.Equal(b.Edit.UpdatedAt) {
		t.Fatal("replay changed timestamp")
	}
	assertEditStatus(t, put(editTarget, editBody(t, "merge")), 200, "")
	assertEditStatus(t, put(editTarget, editBody(t, "merge")), 200, "")
	conflict := put(editNeighbor, editBody(t, "edit"))
	assertEditStatus(t, conflict, 409, "")
	if !strings.Contains(conflict.Body.String(), "This activity is merged into another.") {
		t.Fatal(conflict.Body)
	}
	other := strings.ReplaceAll(editBody(t, "merge"), editNeighbor, editTarget)
	conflict = put("7300000000000000100", other)
	assertEditStatus(t, conflict, 409, "")
	if !strings.Contains(conflict.Body.String(), "A merged activity is already part of another.") {
		t.Fatal(conflict.Body)
	}
	deleted := strings.ReplaceAll(editBody(t, "merge"), `"hidden": false`, `"hidden": true`)
	assertEditStatus(t, put(editTarget, deleted), 200, "")
	rows := s.request("GET", "/v2/workouts?from=2026-03-10&to=2026-03-10", "", "", true)
	if strings.Contains(rows.Body.String(), editTarget) || strings.Contains(rows.Body.String(), editNeighbor) || strings.Contains(rows.Body.String(), `"kind":"detected"`) {
		t.Fatal("deleted merge revealed entry")
	}
	assertEditStatus(t, put(editTarget, editBody(t, "merge")), 200, "")
	assertEditStatus(t, s.request("DELETE", "/v2/edits/"+editTarget, "", "", true), 200, "")
	assertEditStatus(t, s.request("DELETE", "/v2/edits/"+editTarget, "", "", true), 404, "")
	rows = s.request("GET", "/v2/workouts?from=2026-03-10&to=2026-03-10", "", "", true)
	if !strings.Contains(rows.Body.String(), editNeighbor) {
		t.Fatal("restore did not unmerge")
	}
	if _, err := s.config.Set("sport_alias.KICKBOXING", "BOXING"); err != nil {
		t.Fatal(err)
	}
	rows = s.request("GET", "/v2/workouts?from=2026-03-10&to=2026-03-10", "", "", true)
	var workouts struct {
		Workouts []struct {
			ExerciseType string `json:"exercise_type"`
			Original     struct {
				ExerciseType string `json:"exercise_type"`
			}
		}
	}
	json.Unmarshal(rows.Body.Bytes(), &workouts)
	if len(workouts.Workouts) != 2 || workouts.Workouts[0].ExerciseType != "BOXING" || workouts.Workouts[0].Original.ExerciseType != "KICKBOXING" {
		t.Fatal("alias not reloaded")
	}
	if _, err := s.config.Unset("sport_alias.KICKBOXING"); err != nil {
		t.Fatal(err)
	}
	goop := `{"id":"3f0c0000-0000-4000-8000-0000000000e4","exercise_type":"BOXING","display_name":"Boxing","start":"2026-03-10T19:40:00Z","end":"2026-03-10T19:50:00Z","origin":"added"}`
	assertEditStatus(t, s.request("POST", "/v2/activities", goop, "application/json", true), 201, "")
	candidate := `{"exercise_type":null,"start":"2026-03-10T19:16:00Z","end":"2026-03-10T19:50:00Z","notes":null,"hidden":false,"merge_with":["goop-3f0c0000-0000-4000-8000-0000000000e4"]}`
	assertEditStatus(t, put(editNeighbor, candidate), 200, "")
	conflict = put(editTarget, editBody(t, "merge"))
	assertEditStatus(t, conflict, 409, "")
	if !strings.Contains(conflict.Body.String(), "A merged activity is already part of another.") {
		t.Fatal(conflict.Body)
	}
}

func TestHeartRateHTTPQueriesAndBody(t *testing.T) {
	s := newEditServer(t)
	for _, query := range []string{"date=2026-03-10", "start=2026-03-10T15:05:00Z&end=2026-03-10T20:30:00Z"} {
		w := s.request("GET", "/v2/heart-rate?"+query, "", "", true)
		assertEditStatus(t, w, 200, "")
		var b struct {
			Kind    string
			Minutes []any
		}
		json.Unmarshal(w.Body.Bytes(), &b)
		if b.Kind != "heart_rate" || len(b.Minutes) == 0 {
			t.Fatal("heart-rate body absent")
		}
	}
	for _, query := range []string{"bad=1", "date=bad", "start=2026-03-10T00:00:00Z&end=2026-03-10T19:00:00Z"} {
		assertEditStatus(t, s.request("GET", "/v2/heart-rate?"+query, "", "", true), 400, "")
	}
}
