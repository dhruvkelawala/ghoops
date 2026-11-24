package health

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestProbeV2ChecksShapesWithoutReturningValues(t *testing.T) {
	loc, _ := time.LoadLocation("Europe/London")
	from := time.Date(2026, 3, 28, 0, 0, 0, 0, loc)
	until := from.AddDate(0, 0, 3)
	requests := map[string]int{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests[r.URL.Path]++
		if r.Header.Get("Authorization") != "Bearer synthetic-token" || r.URL.Query().Get("pageToken") != "" {
			t.Error("probe must authenticate and fetch only the first page")
		}
		switch {
		case strings.HasSuffix(r.URL.Path, ":rollUp"):
			var body struct {
				Range struct {
					Start time.Time `json:"startTime"`
					End   time.Time `json:"endTime"`
				} `json:"range"`
				Window string `json:"windowSize"`
				Size   int    `json:"pageSize"`
			}
			if json.NewDecoder(r.Body).Decode(&body) != nil || r.Method != "POST" || body.Window != "60s" || body.Size != 1500 || !body.Range.Start.Equal(from) || !body.Range.End.Equal(from.AddDate(0, 0, 1)) {
				t.Error("roll-up request differs from data.md §2.2")
			}
			fmt.Fprint(w, `{"rollupDataPoints":[{"startTime":"2026-03-28T00:00:00Z","endTime":"2026-03-28T00:01:00Z","heartRate":{"beatsPerMinuteAvg":83.731,"beatsPerMinuteMin":71,"beatsPerMinuteMax":94}},{"startTime":"2026-03-28T00:01:00Z","endTime":"2026-03-28T00:02:00Z"}],"nextPageToken":"private-page"}`)
		case strings.HasSuffix(r.URL.Path, ":dailyRollUp"):
			var body struct {
				Range struct {
					Start struct {
						Date Date `json:"date"`
					} `json:"start"`
					End struct {
						Date Date `json:"date"`
					} `json:"end"`
				} `json:"range"`
				Window int `json:"windowSizeDays"`
				Size   int `json:"pageSize"`
			}
			if json.NewDecoder(r.Body).Decode(&body) != nil || r.Method != "POST" || body.Range.Start.Date.String() != "2026-03-28" || body.Range.End.Date.String() != "2026-03-31" || body.Window != 1 {
				t.Error("daily roll-up request differs from data.md §2.2")
			}
			if strings.Contains(r.URL.Path, "/total-calories/") && body.Size != 14 || !strings.Contains(r.URL.Path, "/total-calories/") && body.Size != 90 {
				t.Error("wrong daily roll-up page size")
			}
			fmt.Fprint(w, `{"rollupDataPoints":[{"steps":{"countSum":"87654321"}}]}`)
		case strings.HasSuffix(r.URL.Path, "/profile"):
			fmt.Fprint(w, `{"age":37,"name":"private-person"}`)
		case strings.HasSuffix(r.URL.Path, "/pairedDevices"):
			if r.URL.Query().Get("pageSize") != "10" {
				t.Error("wrong pairedDevices page size")
			}
			fmt.Fprint(w, `{"pairedDevices":[{"deviceType":"TRACKER","lastSyncTime":"2026-03-30T12:34:56Z","deviceVersion":"private-device","batteryLevel":83}]}`)
		case strings.Contains(r.URL.Path, "/dataTypes/"):
			if r.Method != "GET" || !strings.Contains(r.URL.Query().Get("filter"), " >= ") {
				t.Error("missing read-only filtered request")
			}
			switch {
			case strings.Contains(r.URL.Path, "/sleep/"):
				if !strings.HasSuffix(r.URL.Path, ":reconcile") || !strings.Contains(r.URL.Query().Get("filter"), `sleep.interval.end_time < "2026-03-30T23:00:00Z"`) {
					t.Error("sleep must use reconcile with London UTC bounds")
				}
				fmt.Fprint(w, `{"dataPoints":[{"sleep":{"interval":{"startTime":"2026-03-27T22:15:00Z","endTime":"2026-03-28T07:16:00Z"},"metadata":{"mainSleep":true}}}]}`)
			case strings.Contains(r.URL.Path, "/exercise/"):
				if r.URL.Query().Get("pageSize") != "25" || r.URL.Query().Get("filter") != `exercise.interval.civil_start_time >= "2026-03-27" AND exercise.interval.civil_start_time < "2026-04-01"` {
					t.Error("exercise must widen civil dates")
				}
				fmt.Fprint(w, `{}`)
			case strings.Contains(r.URL.Path, "/daily-"):
				fmt.Fprint(w, `{"dataPoints":[{"name":"private-record","dailyHeartRateVariability":{"date":{"year":2026,"month":3,"day":28},"averageHeartRateVariabilityMilliseconds":46.317}},{"dailyHeartRateVariability":{"date":{"year":2026,"month":3,"day":29},"averageHeartRateVariabilityMilliseconds":57.319}}],"nextPageToken":"private-page"}`)
			default:
				fmt.Fprint(w, `{}`)
			}
		default:
			fmt.Fprint(w, `{}`)
		}
	}))
	defer server.Close()
	client := New(func(context.Context, string) (string, error) { return "synthetic-token", nil })
	client.BaseURL = server.URL
	results := client.ProbeV2(context.Background(), from, until)
	if len(results) != 21 || len(requests) != 21 {
		t.Fatalf("expected 21 streams, got %d results and %d routes", len(results), len(requests))
	}
	byStream := map[string]ProbeV2Result{}
	for _, result := range results {
		byStream[result.Stream] = result
		if result.HTTP != 200 {
			t.Fatal(result)
		}
		for _, value := range result.Checks {
			switch value.(type) {
			case bool, int:
			default:
				t.Fatal("probe emitted a value other than a count or boolean")
			}
		}
	}
	for _, n := range requests {
		if n != 1 {
			t.Fatal("probe followed a page token or repeated a stream")
		}
	}
	if r := byStream["heart-rate/rollUp"]; r.Records != 2 || r.Checks["with_avg"] != 1 || r.Checks["without_heart_rate"] != 1 || r.Checks["window_seconds_all_60"] != true || r.Checks["next_page"] != true {
		t.Fatal(r)
	}
	if r := byStream["daily-heart-rate-variability/list"]; r.Checks["dates_matching_main_sleep_end_date"] != 1 || r.Checks["hrv_dates"] != 2 {
		t.Fatal(r)
	}
	if byStream["user/profile"].Checks["age_present"] != true || byStream["user/paired-devices"].Checks["tracker_with_last_sync_time"] != true || byStream["irregular-rhythm-notification/list"].Checks["filter_accepted"] != true {
		t.Fatal("missing resource checks")
	}
	encoded, _ := json.Marshal(results)
	for _, secret := range []string{"83.731", "87654321", "46.317", "57.319", "private-", "2026-03-", "synthetic-token"} {
		if strings.Contains(string(encoded), secret) {
			t.Fatal("probe leaked a fixture value")
		}
	}
}

func TestProbeV2ReportsRejectedRoutesAndInvalidWindows(t *testing.T) {
	for _, window := range []struct {
		name, body string
		all60      bool
	}{
		{"long", `{"rollupDataPoints":[{"startTime":"2026-03-28T00:00:00Z","endTime":"2026-03-28T00:02:00Z"}]}`, false},
		{"missing", `{"rollupDataPoints":[{}]}`, false},
		{"empty", `{}`, true},
	} {
		t.Run(window.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch {
				case strings.HasSuffix(r.URL.Path, "/profile"):
					w.WriteHeader(403)
				case strings.Contains(r.URL.Path, "/irregular-rhythm-notification/"):
					w.WriteHeader(400)
				case strings.HasSuffix(r.URL.Path, ":rollUp"):
					fmt.Fprint(w, window.body)
				default:
					fmt.Fprint(w, `{}`)
				}
			}))
			defer server.Close()
			client := New(func(context.Context, string) (string, error) { return "synthetic", nil })
			client.BaseURL = server.URL
			from := time.Date(2026, 3, 28, 0, 0, 0, 0, time.UTC)
			for _, result := range client.ProbeV2(context.Background(), from, from.AddDate(0, 0, 3)) {
				switch result.Stream {
				case "heart-rate/rollUp":
					if result.Checks["window_seconds_all_60"] != window.all60 {
						t.Fatal(result)
					}
				case "user/profile":
					if result.HTTP != 403 || result.Checks["age_present"] != false {
						t.Fatal(result)
					}
				case "irregular-rhythm-notification/list":
					if result.HTTP != 400 || result.Checks["filter_accepted"] != false {
						t.Fatal(result)
					}
				}
			}
		})
	}
}
