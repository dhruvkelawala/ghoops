package serve_test

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/dhruvkelawala/ghoops/internal/activities"
)

func TestReportedEditLimitsAreEnforced(t *testing.T) {
	s := newEditServer(t)
	status := s.request("GET", "/v2/status", "", "", true)
	assertEditStatus(t, status, 200, "")
	var body struct {
		Limits activities.Limits `json:"edit_limits"`
	}
	if err := json.Unmarshal(status.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	l := body.Limits
	if l.HorizonDays < 1 || l.ShiftMinutes < 1 || l.MergeGapMinutes < 1 || l.NotesMaxChars < 1 || l.ActiveMinMinutes < 1 || l.ActiveMaxMinutes < 1 || l.HeartRateSpanMaxMinutes < 1 {
		t.Fatalf("missing reported edit limits: %+v", l)
	}
	minute := func(n int) time.Duration { return time.Duration(n) * time.Minute }
	at := func(v string) time.Time {
		t.Helper()
		d, err := time.Parse(time.RFC3339, v)
		if err != nil {
			t.Fatal(err)
		}
		return d
	}
	start, end := at("2026-03-10T18:05:00Z"), at("2026-03-10T19:02:00Z")
	put := func(a, b *time.Time, notes *string, merge []string) *httptest.ResponseRecorder {
		t.Helper()
		if merge == nil {
			merge = []string{}
		}
		raw, err := json.Marshal(map[string]any{"exercise_type": nil, "start": a, "end": b, "notes": notes, "hidden": false, "merge_with": merge})
		if err != nil {
			t.Fatal(err)
		}
		return s.request("PUT", "/v2/edits/"+editTarget, string(raw), "application/json", true)
	}
	a := start.Add(-minute(l.ShiftMinutes))
	assertEditStatus(t, put(&a, &end, nil, nil), 200, "")
	a = a.Add(-time.Minute)
	assertEditStatus(t, put(&a, &end, nil, nil), 400, "start")
	b := end.Add(minute(l.ShiftMinutes))
	assertEditStatus(t, put(&start, &b, nil, nil), 200, "")
	b = b.Add(time.Minute)
	assertEditStatus(t, put(&start, &b, nil, nil), 400, "end")
	neighborStart, neighborEnd := at("2026-03-10T19:16:00Z"), at("2026-03-10T19:38:00Z")
	b = neighborStart.Add(-minute(l.MergeGapMinutes + 1))
	assertEditStatus(t, put(&start, &b, nil, nil), 200, "")
	assertEditStatus(t, put(&start, &neighborEnd, nil, []string{editNeighbor}), 400, "merge_with")
	b = neighborStart.Add(-minute(l.MergeGapMinutes))
	assertEditStatus(t, put(&start, &b, nil, nil), 200, "")
	assertEditStatus(t, put(&start, &neighborEnd, nil, []string{editNeighbor}), 200, "")
	assertEditStatus(t, s.request("DELETE", "/v2/edits/"+editTarget, "", "", true), 200, "")
	note := "  " + strings.Repeat("é", l.NotesMaxChars) + "  "
	saved := put(nil, nil, &note, nil)
	assertEditStatus(t, saved, 200, "")
	var result struct{ Edit activities.Edit }
	if err := json.Unmarshal(saved.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Edit.Notes == nil || utf8.RuneCountInString(*result.Edit.Notes) != l.NotesMaxChars {
		t.Fatal("stored note was not trimmed to reported length")
	}
	note = strings.Repeat("é", l.NotesMaxChars+1)
	assertEditStatus(t, put(nil, nil, &note, nil), 400, "notes")
	b = start.Add(minute(l.ActiveMinMinutes))
	assertEditStatus(t, put(&start, &b, nil, nil), 200, "")
	b = b.Add(-time.Second)
	assertEditStatus(t, put(&start, &b, nil, nil), 400, "active_duration")
	sequence := 0
	post := func(a, b time.Time, note *string, code int, field string) {
		t.Helper()
		sequence++
		raw, err := json.Marshal(activities.Upload{ID: fmt.Sprintf("3f0c0000-0000-4000-8000-%012x", sequence), ExerciseType: "BOXING", DisplayName: "Boxing", Start: a, End: b, Origin: "added", Notes: note})
		if err != nil {
			t.Fatal(err)
		}
		w := s.request("POST", "/v2/activities", string(raw), "application/json", true)
		assertEditStatus(t, w, code, "")
		if field != "" && !strings.Contains(w.Body.String(), "Invalid activity field: "+field+".") {
			t.Fatalf("want activity field %s: %s", field, w.Body)
		}
	}
	b = at("2026-03-12T20:00:00Z")
	a = b.Add(-minute(l.ActiveMaxMinutes))
	post(a, b, nil, 201, "")
	post(a.Add(-time.Minute), b, nil, 400, "active_duration")
	a = b.Add(-minute(l.ActiveMinMinutes))
	post(a, b, nil, 201, "")
	post(a.Add(time.Second), b, nil, 400, "active_duration")
	note = strings.Repeat("é", l.NotesMaxChars)
	post(a, b, &note, 201, "")
	note += "é"
	post(a, b, &note, 400, "notes")
	a = s.now.Add(-time.Duration(l.HorizonDays) * 24 * time.Hour)
	post(a, a.Add(time.Hour), nil, 201, "")
	post(a.Add(-time.Second), a.Add(time.Hour), nil, 400, "start")
	for _, extra := range []int{0, 1} {
		a = b.Add(-minute(l.HeartRateSpanMaxMinutes + extra))
		query := url.Values{"start": {a.Format(time.RFC3339)}, "end": {b.Format(time.RFC3339)}}
		w := s.request("GET", "/v2/heart-rate?"+query.Encode(), "", "", true)
		if extra == 0 {
			assertEditStatus(t, w, 200, "")
		} else {
			assertEditStatus(t, w, 400, "")
			if !strings.Contains(w.Body.String(), `"code":"date_out_of_range"`) {
				t.Fatal(w.Body)
			}
		}
	}
	s.now = at("2026-03-10T20:30:00Z").AddDate(0, 0, l.HorizonDays-1)
	note = "Horizon"
	assertEditStatus(t, put(nil, nil, &note, nil), 200, "")
	s.now = s.now.AddDate(0, 0, 1)
	w := put(nil, nil, &note, nil)
	assertEditStatus(t, w, 404, "")
	if !strings.Contains(w.Body.String(), `"code":"not_found"`) {
		t.Fatal(w.Body)
	}
}
