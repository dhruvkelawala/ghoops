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

func TestDiagnoseFieldsCountsWithoutValues(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.Contains(r.URL.Path, "daily-oxygen-saturation"):
			w.Write([]byte(`{"dataPoints":[{"name":"a","dailyOxygenSaturation":{"averagePercentage":96.37,"lowerBoundPercentage":93.11,"upperBoundPercentage":98.29}}]}`))
		case strings.Contains(r.URL.Path, "daily-sleep-temperature"):
			w.Write([]byte(`{"dataPoints":[{"name":"b","dailySleepTemperatureDerivations":{"nightlyTemperatureCelsius":-0.43,"baselineTemperatureCelsius":"NaN"}}]}`))
		default:
			if r.URL.Query().Get("pageToken") == "" {
				w.Write([]byte(`{"dataPoints":[{"name":"c","respiratoryRateSleepSummary":{"fullSleepStats":{"breathsPerMinute":14.71}}}],"nextPageToken":"p2"}`))
				return
			}
			w.Write([]byte(`{"dataPoints":[{"name":"c","respiratoryRateSleepSummary":{"fullSleepStats":{"breathsPerMinute":15.29}}}]}`))
		}
	}))
	defer srv.Close()
	c := New(func(context.Context, string) (string, error) { return "token", nil })
	c.BaseURL = srv.URL
	from := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	out := c.DiagnoseFields(context.Background(), from, from.AddDate(0, 0, 30))

	b, _ := json.Marshal(out)
	for _, leak := range []string{"96.37", "93.11", "-0.43", "14.71", "15.29"} {
		if strings.Contains(string(b), leak) {
			t.Fatalf("diagnosis leaked %s: %s", leak, b)
		}
	}
	spo2 := out["daily-oxygen-saturation"].(map[string]any)["fields"].(map[string]map[string]int)
	if spo2["standardDeviationPercentage"]["missing"] != 1 || spo2["averagePercentage"]["in_spec_range"] != 1 {
		t.Fatalf("spo2 counts = %v", spo2)
	}
	temp := out["daily-sleep-temperature-derivations"].(map[string]any)["fields"].(map[string]map[string]int)
	if temp["nightlyTemperatureCelsius"]["in_relative_range"] != 1 || temp["baselineTemperatureCelsius"]["string_NaN"] != 1 {
		t.Fatalf("temperature counts = %v", temp)
	}
	resp := out["respiratory-rate-sleep-summary"].(map[string]any)
	if resp["names_with_differing_copies"] != 1 || resp["pages"] != 2 {
		t.Fatalf("respiratory report = %v", resp)
	}
}
