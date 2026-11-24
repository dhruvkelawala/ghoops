package health

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// DiagnoseFields pages the streams that failed v2 validation and reports, per field,
// how many records have it missing, inside the spec range or outside it. It also counts
// data point names that repeat with different content. Counts only, never values.
func (c *Client) DiagnoseFields(ctx context.Context, from, until time.Time) map[string]any {
	type field struct {
		path      []string
		low, high float64
		alt       [2]float64 // a second range to test, e.g. relative values near zero
	}
	streams := []struct {
		t      ProbeType
		union  string
		fields map[string]field
	}{
		{ProbeType{"daily-oxygen-saturation", "daily"}, "dailyOxygenSaturation", map[string]field{
			"averagePercentage":           {[]string{"averagePercentage"}, 0, 100, [2]float64{-1, -1}},
			"lowerBoundPercentage":        {[]string{"lowerBoundPercentage"}, 0, 100, [2]float64{-1, -1}},
			"upperBoundPercentage":        {[]string{"upperBoundPercentage"}, 0, 100, [2]float64{-1, -1}},
			"standardDeviationPercentage": {[]string{"standardDeviationPercentage"}, 0, 100, [2]float64{-1, -1}},
		}},
		{ProbeType{"daily-sleep-temperature-derivations", "daily"}, "dailySleepTemperatureDerivations", map[string]field{
			"nightlyTemperatureCelsius":       {[]string{"nightlyTemperatureCelsius"}, 20, 45, [2]float64{-10, 10}},
			"baselineTemperatureCelsius":      {[]string{"baselineTemperatureCelsius"}, 20, 45, [2]float64{-10, 10}},
			"relativeNightlyStddev30dCelsius": {[]string{"relativeNightlyStddev30dCelsius"}, 0, 10, [2]float64{-1, -1}},
		}},
		{ProbeType{"respiratory-rate-sleep-summary", "sample"}, "respiratoryRateSleepSummary", map[string]field{
			"fullSleepStats.breathsPerMinute":  {[]string{"fullSleepStats", "breathsPerMinute"}, 4, 60, [2]float64{-1, -1}},
			"deepSleepStats.breathsPerMinute":  {[]string{"deepSleepStats", "breathsPerMinute"}, 4, 60, [2]float64{-1, -1}},
			"lightSleepStats.breathsPerMinute": {[]string{"lightSleepStats", "breathsPerMinute"}, 4, 60, [2]float64{-1, -1}},
			"remSleepStats.breathsPerMinute":   {[]string{"remSleepStats", "breathsPerMinute"}, 4, 60, [2]float64{-1, -1}},
		}},
	}
	out := map[string]any{}
	for _, s := range streams {
		report := map[string]any{}
		counts := map[string]map[string]int{}
		for name := range s.fields {
			counts[name] = map[string]int{}
		}
		otherKeys := map[string]int{}
		names := map[string]map[string]bool{}
		seen := map[string]int{}
		nameShapes := map[string]int{}
		records, pages, unnamed := 0, 0, 0
		q := url.Values{"filter": {probeFilter(s.t, from, until)}, "pageSize": {"1440"}}
		path := c.BaseURL + "/v4/users/me/dataTypes/" + s.t.ID + "/dataPoints"
		for pages < 50 {
			b, err := c.get(ctx, path+"?"+q.Encode())
			if err != nil {
				report["error"] = fmt.Sprintf("%T", err)
				if api, ok := err.(*APIError); ok {
					report["error"] = fmt.Sprintf("http_%d_%s", api.Status, api.Code)
				}
				break
			}
			pages++
			var page struct {
				Points []map[string]json.RawMessage `json:"dataPoints"`
				Next   string                       `json:"nextPageToken"`
			}
			if json.Unmarshal(b, &page) != nil {
				report["error"] = "invalid_page"
				break
			}
			for _, p := range page.Points {
				records++
				var name string
				_ = json.Unmarshal(p["name"], &name)
				canonical, _ := json.Marshal(p)
				h := fmt.Sprintf("%x", sha256.Sum256(canonical))
				if name == "" {
					unnamed++
				} else {
					shape := "other"
					switch {
					case strings.HasSuffix(name, "/dataPoints/"):
						shape = "collection_prefix_only"
					case strings.Contains(name, "/dataPoints/"):
						shape = "has_point_id"
					}
					nameShapes[shape]++
					if names[name] == nil {
						names[name] = map[string]bool{}
					}
					names[name][h] = true
					seen[name]++
				}
				var body map[string]any
				_ = json.Unmarshal(p[s.union], &body)
				if body == nil {
					counts["_union_missing"] = map[string]int{"records": counts["_union_missing"]["records"] + 1}
					continue
				}
				for k := range body {
					if _, ok := s.fields[k]; !ok && k != "date" && k != "sampleTime" {
						otherKeys[k]++
					}
				}
				for fname, f := range s.fields {
					var v any = body
					for _, step := range f.path {
						m, ok := v.(map[string]any)
						if !ok {
							v = nil
							break
						}
						v = m[step]
					}
					switch n := v.(type) {
					case nil:
						counts[fname]["missing"]++
					case float64:
						switch {
						case n >= f.low && n <= f.high:
							counts[fname]["in_spec_range"]++
						case f.alt[0] != f.alt[1] && n >= f.alt[0] && n <= f.alt[1]:
							counts[fname]["in_relative_range"]++
						case n == 0:
							counts[fname]["zero"]++
						case n < f.low:
							counts[fname]["below_range"]++
						default:
							counts[fname]["above_range"]++
						}
					case string:
						switch n {
						case "NaN", "Infinity", "-Infinity":
							counts[fname]["string_"+n]++
						default:
							counts[fname]["string_other"]++
						}
					default:
						counts[fname]["not_a_number"]++
					}
				}
			}
			if page.Next == "" {
				break
			}
			q.Set("pageToken", page.Next)
		}
		changed, repeated := 0, 0
		for name, hashes := range names {
			if len(hashes) > 1 {
				changed++
			}
			if seen[name] > 1 {
				repeated++
			}
		}
		report["names_seen_more_than_once"] = repeated
		report["name_shapes"] = nameShapes
		report["records"], report["pages"], report["unnamed"] = records, pages, unnamed
		report["distinct_names"], report["names_with_differing_copies"] = len(names), changed
		report["fields"], report["other_keys"] = counts, otherKeys
		out[s.t.ID] = report
	}
	return out
}
