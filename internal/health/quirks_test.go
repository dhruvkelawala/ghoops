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

func TestProviderQuirksThroughFetch(t *testing.T) {
	date := `"date":{"year":2026,"month":3,"day":10}`
	for _, tc := range []struct {
		name, id, body string
		valid          bool
	}{
		{"spo2_missing_sd", "daily-oxygen-saturation", `{"dailyOxygenSaturation":{` + date + `,"averagePercentage":97,"lowerBoundPercentage":95,"upperBoundPercentage":99}}`, true},
		{"spo2_invalid_sd", "daily-oxygen-saturation", `{"dailyOxygenSaturation":{` + date + `,"averagePercentage":97,"lowerBoundPercentage":95,"upperBoundPercentage":99,"standardDeviationPercentage":101}}`, false},
		{"temperature_nan", "daily-sleep-temperature-derivations", `{"dailySleepTemperatureDerivations":{` + date + `,"nightlyTemperatureCelsius":33,"baselineTemperatureCelsius":"NaN","relativeNightlyStddev30dCelsius":"NaN"}}`, true},
		{"temperature_infinity", "daily-sleep-temperature-derivations", `{"dailySleepTemperatureDerivations":{` + date + `,"nightlyTemperatureCelsius":33,"baselineTemperatureCelsius":"Infinity","relativeNightlyStddev30dCelsius":"-Infinity"}}`, true},
		{"required_nan", "daily-sleep-temperature-derivations", `{"dailySleepTemperatureDerivations":{` + date + `,"nightlyTemperatureCelsius":"NaN"}}`, false},
		{"rem_zero", "respiratory-rate-sleep-summary", `{"respiratoryRateSleepSummary":{"sampleTime":{"physicalTime":"2026-03-10T07:00:00Z"},"fullSleepStats":{"breathsPerMinute":16},"remSleepStats":{"breathsPerMinute":0}}}`, true},
		{"rem_two", "respiratory-rate-sleep-summary", `{"respiratoryRateSleepSummary":{"sampleTime":{"physicalTime":"2026-03-10T07:00:00Z"},"fullSleepStats":{"breathsPerMinute":16},"remSleepStats":{"breathsPerMinute":2}}}`, false},
		{"full_missing", "respiratory-rate-sleep-summary", `{"respiratoryRateSleepSummary":{"sampleTime":{"physicalTime":"2026-03-10T07:00:00Z"},"remSleepStats":{"breathsPerMinute":16}}}`, false},
		{"full_zero", "respiratory-rate-sleep-summary", `{"respiratoryRateSleepSummary":{"sampleTime":{"physicalTime":"2026-03-10T07:00:00Z"},"fullSleepStats":{"breathsPerMinute":0}}}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
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
			if !tc.valid {
				if err == nil || CollectionErrorCode(err) != "invalid_data_point" {
					t.Fatal("invalid input accepted", err)
				}
				return
			}
			if err != nil || len(records) != 1 {
				t.Fatal("valid provider record rejected", err)
			}
			p, err := DecodeV2(records[0])
			if err != nil {
				t.Fatal(err)
			}
			if p.Temperature != nil && (p.Temperature.Baseline != nil || p.Temperature.SD != nil || strings.Contains(string(records[0].Raw), "Infinity") || strings.Contains(string(records[0].Raw), "NaN")) {
				t.Fatal("optional nonfinite field was not stored and read as null")
			}
			if p.Oxygen != nil && p.Oxygen.SD != nil {
				t.Fatal("missing SD is not null")
			}
			if p.RespSummary != nil {
				b, _ := json.Marshal(p.RespSummary.REM)
				if string(b) != `{"breathsPerMinute":null}` || !strings.Contains(string(records[0].Raw), `"breathsPerMinute":0`) {
					t.Fatal("unmeasured stage must stay stored and read as null")
				}
			}
		})
	}
}

func TestCollectionNamesAcrossPagesAreUnnamed(t *testing.T) {
	for _, id := range []string{"respiratory-rate-sleep-summary", "daily-respiratory-rate"} {
		for _, suffix := range []string{"", "point-id"} {
			t.Run(id+suffix, func(t *testing.T) {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					next, bpm := `,"nextPageToken":"page-two"`, 16
					if r.URL.Query().Get("pageToken") != "" {
						next, bpm = "", 17
					}
					body := fmt.Sprintf(`"dailyRespiratoryRate":{"date":{"year":2026,"month":3,"day":10},"breathsPerMinute":%d}`, bpm)
					if id == "respiratory-rate-sleep-summary" {
						body = fmt.Sprintf(`"respiratoryRateSleepSummary":{"sampleTime":{"physicalTime":"2026-03-10T07:00:00Z"},"fullSleepStats":{"breathsPerMinute":%d}}`, bpm)
					}
					point := fmt.Sprintf(`{"name":"users/me/dataTypes/%s/dataPoints/%s",%s}`, id, suffix, body)
					fmt.Fprintf(w, `{"dataPoints":[%s,%s]%s}`, point, point, next)
				}))
				defer server.Close()
				client := New(func(context.Context, string) (string, error) { return "synthetic", nil })
				client.BaseURL = server.URL
				var kind Kind
				for _, k := range V2Kinds {
					if k.ID == id {
						kind = k
					}
				}
				from := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
				records, err := client.FetchV2(context.Background(), kind, "raw", from, from.AddDate(0, 0, 1))
				if suffix != "" {
					if err == nil || CollectionErrorCode(err) != "data_point_changed_during_pagination" {
						t.Fatal("identified mutation not rejected", err)
					}
					return
				}
				if err != nil || len(records) != 2 {
					t.Fatal("unnamed copies not deduplicated by content", len(records), err)
				}
			})
		}
	}
}
