package health

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestV2InputFixtureRecordsValidate(t *testing.T) {
	files, _ := filepath.Glob("../../fixtures/v2/inputs/*.json")
	for _, file := range files {
		var state struct {
			Records []Record `json:"records"`
		}
		b, err := os.ReadFile(file)
		if err != nil || json.Unmarshal(b, &state) != nil {
			t.Fatal("fixture could not load", err)
		}
		for _, record := range state.Records {
			if _, err := DecodeV2(record); err != nil {
				t.Fatalf("%s %s: %s", file, record.Type, CollectionErrorCode(err))
			}
		}
	}
}

func TestRollUpRejectsInvalidWindowsAndCountsOnlyCoveredMinutes(t *testing.T) {
	for _, tc := range []struct {
		name, windows, code string
		count               int
	}{
		{"covered", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z","heartRate":{"beatsPerMinuteMin":56,"beatsPerMinuteAvg":62,"beatsPerMinuteMax":70}}`, "", 1},
		{"missing_hr", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z"}`, "", 0},
		{"missing_avg", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z","heartRate":{}}`, "", 0},
		{"high_avg", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z","heartRate":{"beatsPerMinuteAvg":301}}`, "", 0},
		{"negative_avg", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z","heartRate":{"beatsPerMinuteAvg":-1}}`, "", 0},
		{"nonfinite_avg", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z","heartRate":{"beatsPerMinuteAvg":"NaN"}}`, "", 0},
		{"long", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:02:00Z"}`, "invalid_rollup_window", 0},
		{"outside", `{"startTime":"2026-03-09T23:59:00Z","endTime":"2026-03-10T00:00:00Z"}`, "invalid_rollup_window", 0},
		{"unaligned", `{"startTime":"2026-03-10T00:00:30Z","endTime":"2026-03-10T00:01:30Z"}`, "invalid_rollup_window", 0},
		{"overlap", `{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z"},{"startTime":"2026-03-10T00:00:00Z","endTime":"2026-03-10T00:01:00Z"}`, "invalid_rollup_window", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"rollupDataPoints":[`+tc.windows+`]}`) }))
			defer server.Close()
			client := New(func(context.Context, string) (string, error) { return "synthetic", nil })
			client.BaseURL = server.URL
			minutes, err := client.RollUp(context.Background(), time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC))
			if tc.code != "" {
				if err == nil || CollectionErrorCode(err) != tc.code {
					t.Fatal("wrong validation error", err)
				}
				return
			}
			if err != nil || len(minutes) != tc.count {
				t.Fatal("wrong covered minutes", len(minutes), err)
			}
		})
	}
}

func TestRollUpFollowsPagesAndRejectsRepeatedTokens(t *testing.T) {
	for _, repeat := range []bool{false, true} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			if body["pageToken"] == nil {
				fmt.Fprint(w, `{"rollupDataPoints":[],"nextPageToken":"synthetic-page"}`)
			} else if repeat {
				fmt.Fprint(w, `{"nextPageToken":"synthetic-page"}`)
			} else {
				fmt.Fprint(w, `{"rollupDataPoints":[{"startTime":"2026-03-10T00:01:00Z","endTime":"2026-03-10T00:02:00Z","heartRate":{"beatsPerMinuteMin":60,"beatsPerMinuteAvg":65,"beatsPerMinuteMax":70}}]}`)
			}
		}))
		client := New(func(context.Context, string) (string, error) { return "synthetic", nil })
		client.BaseURL = server.URL
		minutes, err := client.RollUp(context.Background(), time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC))
		server.Close()
		if repeat {
			if err == nil || CollectionErrorCode(err) != "repeated_page_token" {
				t.Fatal(err)
			}
		} else if err != nil || len(minutes) != 1 || client.RequestCount() != 2 {
			t.Fatal("pagination failed", err)
		}
	}
}

func TestDailyRollUpDistinguishesMissingFromObservedZero(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"rollupDataPoints":[{"civilStartTime":{"date":{"year":2026,"month":3,"day":8}}},{"civilStartTime":{"date":{"year":2026,"month":3,"day":9}},"steps":{"countSum":"0"}},{"civilStartTime":{"date":{"year":2026,"month":3,"day":10}},"steps":{"countSum":"123"}}]}`)
	}))
	defer server.Close()
	client := New(func(context.Context, string) (string, error) { return "synthetic", nil })
	client.BaseURL = server.URL
	from := time.Date(2026, 3, 8, 0, 0, 0, 0, time.UTC)
	days, err := client.DailyRollUp(context.Background(), "steps", from, from.AddDate(0, 0, 3))
	if err != nil || len(days) != 2 || days[0].Date != "2026-03-09" || !strings.Contains(string(days[0].Value), `"countSum":"0"`) {
		t.Fatal("zero/missing semantics changed", err)
	}
}

func TestV2NewTypeValidationAndIRNPrivacyThroughFetch(t *testing.T) {
	for _, tc := range []struct {
		id, body string
		valid    bool
	}{
		{"daily-respiratory-rate", `{"dailyRespiratoryRate":{"date":{"year":2026,"month":3,"day":10},"breathsPerMinute":16}}`, true},
		{"daily-respiratory-rate", `{"dailyRespiratoryRate":{"date":{"year":2026,"month":3,"day":10},"breathsPerMinute":61}}`, false},
		{"daily-oxygen-saturation", `{"dailyOxygenSaturation":{"date":{"year":2026,"month":3,"day":10},"averagePercentage":101,"lowerBoundPercentage":94,"upperBoundPercentage":99,"standardDeviationPercentage":1}}`, false},
		{"daily-sleep-temperature-derivations", `{"dailySleepTemperatureDerivations":{"date":{"year":2026,"month":3,"day":10},"nightlyTemperatureCelsius":46}}`, false},
		{"daily-heart-rate-zones", `{"dailyHeartRateZones":{"date":{"year":2026,"month":3,"day":10},"heartRateZones":[{"minBeatsPerMinute":29,"maxBeatsPerMinute":100}]}}`, false},
		{"daily-vo2-max", `{"dailyVo2Max":{"date":{"year":2026,"month":3,"day":10},"vo2Max":101}}`, false},
		{"daily-vo2-max", `{"dailyVo2Max":{"date":{"year":2026,"month":3,"day":10}}}`, false},
		{"irregular-rhythm-notification", `{"irregularRhythmNotification":{"interval":{"startTime":"2026-03-10T01:00:00Z","endTime":"2026-03-10T01:30:00Z"},"alertWindows":[{"heartBeats":["private-beat"]}]}}`, true},
	} {
		t.Run(tc.id+tc.body, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"dataPoints":[`+tc.body+`]}`) }))
			defer server.Close()
			client := New(func(context.Context, string) (string, error) { return "synthetic", nil })
			client.BaseURL = server.URL
			var kind Kind
			for _, k := range V2Kinds {
				if k.ID == tc.id {
					kind = k
				}
			}
			from := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
			records, err := client.FetchV2(context.Background(), kind, "raw", from, from.AddDate(0, 0, 1))
			if (err == nil) != tc.valid {
				t.Fatal("validation mismatch", err)
			}
			if tc.valid && (len(records) != 1 || strings.Contains(string(records[0].Raw), "alertWindows") || strings.Contains(string(records[0].Raw), "private-beat")) {
				t.Fatal("IRN sensitive fields retained or record lost")
			}
		})
	}
}
