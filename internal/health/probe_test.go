package health

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestProbeReportsCountsAndDeniedRoutesWithoutValues(t *testing.T) {
	var rollUpMethods []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, ":dailyRollUp"):
			rollUpMethods = append(rollUpMethods, r.Method)
			w.Write([]byte(`{"rollupDataPoints":[{"steps":{"countSum":"9876"}}]}`))
		case r.URL.Path == "/v4/users/me/profile":
			w.WriteHeader(http.StatusForbidden)
		case strings.Contains(r.URL.Path, "/dataTypes/sleep/"):
			if !strings.Contains(r.URL.Query().Get("filter"), "sleep.interval.end_time >= ") {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			w.Write([]byte(`{"dataPoints":[{"sleep":{}},{"sleep":{}}],"nextPageToken":"n"}`))
		case strings.Contains(r.URL.Path, "/dataTypes/"):
			w.Write([]byte(`{}`))
		default:
			w.Write([]byte(`{"name":"users/123"}`))
		}
	}))
	defer srv.Close()
	c := New(func(context.Context, string) (string, error) { return "token", nil })
	c.BaseURL = srv.URL
	from := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	results := c.Probe(context.Background(), from, from.AddDate(0, 0, 7))

	byKey := map[string]ProbeResult{}
	for _, r := range results {
		byKey[r.Target+" "+r.Method] = r
	}
	if r := byKey["sleep list"]; r.Status != "records" || r.Records != 2 || !r.More {
		t.Fatalf("sleep = %+v", r)
	}
	if r := byKey["users/me/profile get"]; r.Status != "error" || r.Error != "http_403_permission_denied" {
		t.Fatalf("profile = %+v", r)
	}
	if r := byKey["weight list"]; r.Status != "empty" {
		t.Fatalf("weight = %+v", r)
	}
	if r := byKey["steps dailyRollUp"]; r.Status != "records" || r.Records != 1 {
		t.Fatalf("steps roll-up = %+v", r)
	}
	for _, m := range rollUpMethods {
		if m != http.MethodPost {
			t.Fatalf("roll-up used %s", m)
		}
	}
	out, _ := json.Marshal(results)
	if strings.Contains(string(out), "9876") || strings.Contains(string(out), "users/123") {
		t.Fatalf("probe leaked a record value: %s", out)
	}
}
