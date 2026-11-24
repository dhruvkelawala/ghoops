package serve_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func ratingOf(t *testing.T, body string) *activities.Rating {
	t.Helper()
	var response v2report.RatingResponse
	if err := json.Unmarshal([]byte(body), &response); err != nil || response.Kind != "rating" {
		t.Fatalf("rating body: %v %s", err, body)
	}
	return response.Rating
}

func workoutRPE(t *testing.T, s *editServer, id string) (rpe *int, found bool) {
	t.Helper()
	w := s.request("GET", "/v2/workouts?days=30", "", "", true)
	var body struct {
		Workouts []map[string]json.RawMessage `json:"workouts"`
	}
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &body) != nil {
		t.Fatalf("workouts: %d %s", w.Code, w.Body)
	}
	for _, workout := range body.Workouts {
		var wid string
		json.Unmarshal(workout["id"], &wid)
		raw, present := workout["rpe"]
		if !present {
			t.Fatalf("workout %s has no rpe key", wid)
		}
		if wid == id {
			json.Unmarshal(raw, &rpe)
			return rpe, true
		}
	}
	return nil, false
}

func TestRatingHTTPValidationLookupAndReplay(t *testing.T) {
	s := newEditServer(t)
	put := func(id, body string) string {
		return s.request("PUT", "/v2/ratings/"+id, body, "application/json", true).Body.String()
	}
	for _, tc := range []struct{ id, body, field string }{
		{"effort-2026-03-11T18:04:00Z", `{"rpe":5}`, "id"},
		{editTarget, `[]`, "body"}, {editTarget, `invalid`, "body"}, {editTarget, `{}`, "rpe"},
		{editTarget, `{"rpe":null}`, "rpe"}, {editTarget, `{"rpe":7.5}`, "rpe"}, {editTarget, `{"rpe":"7"}`, "rpe"},
		{editTarget, `{"rpe":-1}`, "rpe"}, {editTarget, `{"rpe":11}`, "rpe"},
	} {
		assertEditStatus(t, s.request("PUT", "/v2/ratings/"+tc.id, tc.body, "application/json", true), 400, tc.field)
	}
	assertEditStatus(t, s.request("PUT", "/v2/ratings/7300000000000000999", `{"rpe":5}`, "application/json", true), 404, "")
	if rpe, found := workoutRPE(t, s, editTarget); !found || rpe != nil {
		t.Fatal("unrated workout should carry rpe null")
	}
	first := ratingOf(t, put(editTarget, `{"rpe":7.0}`))
	if first == nil || first.RPE != 7 || first.ID != editTarget {
		t.Fatal("stored rating", first)
	}
	s.now = s.now.Add(time.Minute)
	replay := ratingOf(t, put(editTarget, `{"rpe":7,"extra":true}`))
	if !replay.UpdatedAt.Equal(first.UpdatedAt) {
		t.Fatal("replay changed updated_at")
	}
	if rpe, _ := workoutRPE(t, s, editTarget); rpe == nil || *rpe != 7 {
		t.Fatal("workouts body lacks the rating")
	}
	// Ratings follow the edit horizon: 30 days ending on the default date.
	s.now = time.Date(2026, 4, 9, 20, 30, 0, 0, time.UTC)
	assertEditStatus(t, s.request("PUT", "/v2/ratings/7300000000000000100", `{"rpe":4}`, "application/json", true), 404, "")
	assertEditStatus(t, s.request("PUT", "/v2/ratings/7300000000000000103", `{"rpe":4}`, "application/json", true), 200, "")
}

func TestRatingHTTPGoopHiddenDeleteAndTransport(t *testing.T) {
	s := newEditServer(t)
	activity := `{"id":"3f0c0000-0000-4000-8000-0000000000e2","exercise_type":"BOXING","display_name":"Boxing","start":"2026-03-11T18:04:00Z","end":"2026-03-11T19:04:00Z","origin":"added"}`
	assertEditStatus(t, s.request("POST", "/v2/activities", activity, "application/json", true), 201, "")
	goop := "goop-3f0c0000-0000-4000-8000-0000000000e2"
	assertEditStatus(t, s.request("PUT", "/v2/ratings/"+goop, `{"rpe":8}`, "application/json", true), 200, "")
	if rpe, _ := workoutRPE(t, s, goop); rpe == nil || *rpe != 8 {
		t.Fatal("ghoops session rating")
	}
	assertEditStatus(t, s.request("PUT", "/v2/ratings/"+editTarget, `{"rpe":6}`, "application/json", true), 200, "")
	hide := `{"exercise_type":null,"start":null,"end":null,"notes":null,"hidden":true,"merge_with":[]}`
	assertEditStatus(t, s.request("PUT", "/v2/edits/"+editTarget, hide, "application/json", true), 200, "")
	if _, found := workoutRPE(t, s, editTarget); found {
		t.Fatal("hidden workout shown")
	}
	book, err := s.store.Load()
	if err != nil || len(book.Ratings) != 2 {
		t.Fatal("hidden workout's rating dropped", err)
	}
	assertEditStatus(t, s.request("DELETE", "/v2/edits/"+editTarget, "", "", true), 200, "")
	if rpe, _ := workoutRPE(t, s, editTarget); rpe == nil || *rpe != 6 {
		t.Fatal("unhidden workout lost its rating")
	}
	deleted := s.request("DELETE", "/v2/ratings/"+editTarget, "", "", true)
	if deleted.Code != 200 || ratingOf(t, deleted.Body.String()) != nil {
		t.Fatal("delete", deleted.Code, deleted.Body)
	}
	assertEditStatus(t, s.request("DELETE", "/v2/ratings/"+editTarget, "", "", true), 404, "")
	for _, tc := range []struct {
		method, path, body, media string
		status                    int
	}{
		{"GET", "/v2/ratings/" + editTarget, "", "", 405},
		{"POST", "/v2/ratings/" + editTarget, `{"rpe":5}`, "application/json", 405},
		{"PUT", "/v2/ratings", `{"rpe":5}`, "application/json", 404},
		{"PUT", "/v2/ratings/", `{"rpe":5}`, "application/json", 404},
		{"PUT", "/v2/ratings/" + editTarget + "?x=1", `{"rpe":5}`, "application/json", 400},
		{"PUT", "/v2/ratings/" + editTarget, `{"rpe":5}`, "text/plain", 400},
		{"PUT", "/v2/ratings/" + editTarget, `{"rpe":5}` + strings.Repeat(" ", 65537), "application/json", 413},
		{"DELETE", "/v2/ratings/" + goop, `{}`, "application/json", 400},
	} {
		w := s.request(tc.method, tc.path, tc.body, tc.media, true)
		if w.Code != tc.status {
			t.Fatalf("%s %s: want %d got %d %s", tc.method, tc.path, tc.status, w.Code, w.Body)
		}
		if tc.status == 405 && w.Header().Get("Allow") != "PUT, DELETE" {
			t.Fatal("Allow header", w.Header().Get("Allow"))
		}
	}
	if w := s.request("PUT", "/v2/ratings/"+editTarget, `{"rpe":5}`, "application/json", false); w.Code != 401 {
		t.Fatal("unauthenticated rating", w.Code)
	}
	if strings.Contains(s.logs.String(), `"rpe"`) {
		t.Fatal("log carries a body")
	}
}
