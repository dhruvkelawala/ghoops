package health

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/url"
	"time"
)

type ProbeV2Result struct {
	Stream  string         `json:"stream"`
	HTTP    int            `json:"http"`
	Records int            `json:"records"`
	Checks  map[string]any `json:"checks"`
}

// ProbeV2 checks the v2 routes' first pages and returns counts and booleans only.
func (c *Client) ProbeV2(ctx context.Context, from, until time.Time) []ProbeV2Result {
	base := c.BaseURL + "/v4/users/me"
	results := []ProbeV2Result{}
	wakeDates := map[string]bool{}
	for _, typ := range []ProbeType{
		{"sleep", "session"},
		{"daily-heart-rate-variability", "daily"},
		{"daily-resting-heart-rate", "daily"},
		{"daily-respiratory-rate", "daily"},
		{"daily-oxygen-saturation", "daily"},
		{"daily-sleep-temperature-derivations", "daily"},
		{"daily-heart-rate-zones", "daily"},
		{"daily-vo2-max", "daily"},
		{"respiratory-rate-sleep-summary", "sample"},
		{"heart-rate-variability", "sample"},
		{"exercise", "session"},
		{"irregular-rhythm-notification", "session"},
	} {
		route, pageSize := "list", "1440"
		path := base + "/dataTypes/" + typ.ID + "/dataPoints"
		if typ.ID == "sleep" {
			route = "reconcile"
			path += ":reconcile"
		}
		if typ.Record == "session" {
			pageSize = "25"
		}
		lower, upper := from, until
		if typ.ID == "exercise" {
			lower, upper = from.AddDate(0, 0, -1), until.AddDate(0, 0, 1)
		}
		q := url.Values{"filter": {probeFilter(typ, lower, upper)}, "pageSize": {pageSize}}
		b, err := c.get(ctx, path+"?"+q.Encode())
		r, points := probeV2Page(typ.ID+"/"+route, b, err, "dataPoints")
		if typ.ID == "sleep" {
			wakeDates = probeWakeDates(points, from, until)
		}
		if typ.Record == "daily" {
			dates := map[string]bool{}
			for _, raw := range points {
				var point map[string]json.RawMessage
				if json.Unmarshal(raw, &point) == nil {
					for _, body := range point {
						var value struct {
							Date Date `json:"date"`
						}
						if json.Unmarshal(body, &value) != nil {
							continue
						}
						date := value.Date.String()
						if _, err := time.Parse("2006-01-02", date); err == nil && date >= from.Format("2006-01-02") && date < until.Format("2006-01-02") {
							dates[date] = true
						}
					}
				}
			}
			matches := 0
			for date := range dates {
				if wakeDates[date] {
					matches++
				}
			}
			r.Checks["dates"], r.Checks["dates_matching_main_sleep_end_date"] = len(dates), matches
			if typ.ID == "daily-heart-rate-variability" {
				r.Checks["hrv_dates"] = len(dates)
			}
		}
		if typ.ID == "irregular-rhythm-notification" {
			r.Checks["filter_accepted"] = r.HTTP == http.StatusOK
		}
		results = append(results, r)
	}
	body, _ := json.Marshal(map[string]any{
		"range":      map[string]string{"startTime": from.UTC().Format(time.RFC3339), "endTime": from.AddDate(0, 0, 1).UTC().Format(time.RFC3339)},
		"windowSize": "60s", "pageSize": 1500,
	})
	b, err := c.do(ctx, http.MethodPost, base+"/dataTypes/heart-rate/dataPoints:rollUp", body)
	r, windows := probeV2Page("heart-rate/rollUp", b, err, "rollupDataPoints")
	all60, withAvg, withoutHR := true, 0, 0
	for _, raw := range windows {
		var window struct {
			Start time.Time `json:"startTime"`
			End   time.Time `json:"endTime"`
			HR    *struct {
				Avg *Number `json:"beatsPerMinuteAvg"`
			} `json:"heartRate"`
		}
		if json.Unmarshal(raw, &window) != nil {
			r.Checks["valid_json"] = false
			all60 = false
			continue
		}
		all60 = all60 && !window.Start.IsZero() && window.End.Sub(window.Start) == time.Minute
		if window.HR == nil {
			withoutHR++
		} else if window.HR.Avg != nil && !math.IsNaN(float64(*window.HR.Avg)) && !math.IsInf(float64(*window.HR.Avg), 0) && *window.HR.Avg >= 1 && *window.HR.Avg <= 300 {
			withAvg++
		}
	}
	r.Checks["window_seconds_all_60"], r.Checks["with_avg"], r.Checks["without_heart_rate"] = all60, withAvg, withoutHR
	results = append(results, r)
	for _, id := range []string{"steps", "active-zone-minutes", "total-calories", "distance"} {
		pageSize := 90
		if id == "total-calories" {
			pageSize = 14
		}
		body, _ = json.Marshal(map[string]any{"range": map[string]any{"start": probeV2Civil(from), "end": probeV2Civil(until)}, "windowSizeDays": 1, "pageSize": pageSize})
		b, err := c.do(ctx, http.MethodPost, base+"/dataTypes/"+id+"/dataPoints:dailyRollUp", body)
		r, _ := probeV2Page(id+"/dailyRollUp", b, err, "rollupDataPoints")
		results = append(results, r)
	}
	for _, user := range []struct{ stream, path, key string }{
		{"user/profile", "/profile", ""}, {"user/settings", "/settings", ""},
		{"user/paired-devices", "/pairedDevices?pageSize=10", "pairedDevices"}, {"user/irn-profile", "/irnProfile", ""},
	} {
		b, err := c.get(ctx, base+user.path)
		r, points := probeV2Page(user.stream, b, err, user.key)
		if user.stream == "user/profile" {
			var profile struct {
				Age *int `json:"age"`
			}
			r.Checks["age_present"] = json.Unmarshal(b, &profile) == nil && profile.Age != nil
		}
		if user.stream == "user/paired-devices" {
			found := false
			for _, raw := range points {
				var device struct {
					Type string    `json:"deviceType"`
					Sync time.Time `json:"lastSyncTime"`
				}
				if json.Unmarshal(raw, &device) == nil && device.Type == "TRACKER" && !device.Sync.IsZero() {
					found = true
				}
			}
			r.Checks["tracker_with_last_sync_time"] = found
		}
		results = append(results, r)
	}
	return results
}

func probeV2Civil(t time.Time) map[string]any {
	return map[string]any{"date": Date{t.Year(), int(t.Month()), t.Day()}}
}

func probeV2Page(stream string, b []byte, err error, key string) (ProbeV2Result, []json.RawMessage) {
	r := ProbeV2Result{Stream: stream, Checks: map[string]any{}}
	if err != nil {
		var api *APIError
		if errors.As(err, &api) && api != nil {
			r.HTTP = api.Status
		}
		return r, nil
	}
	r.HTTP = http.StatusOK
	var page map[string]json.RawMessage
	if json.Unmarshal(b, &page) != nil || page == nil {
		r.Checks["valid_json"] = false
		return r, nil
	}
	var points []json.RawMessage
	if key == "" {
		r.Records = 1
		return r, nil
	}
	if raw, ok := page[key]; ok && (len(raw) == 0 || raw[0] != '[' || json.Unmarshal(raw, &points) != nil) {
		r.Checks["valid_json"] = false
		return r, nil
	}
	var next string
	if raw, ok := page["nextPageToken"]; ok && json.Unmarshal(raw, &next) != nil {
		r.Checks["valid_json"] = false
	}
	r.Records, r.Checks["next_page"] = len(points), next != ""
	return r, points
}

func probeWakeDates(points []json.RawMessage, from, until time.Time) map[string]bool {
	byDate := map[string][]Sleep{}
	for _, raw := range points {
		var point Point
		if json.Unmarshal(raw, &point) == nil && point.Sleep != nil {
			sleep := *point.Sleep
			date := sleep.Interval.End.In(from.Location()).Format("2006-01-02")
			if !sleep.Interval.Start.IsZero() && sleep.Interval.End.After(sleep.Interval.Start) && date >= from.Format("2006-01-02") && date < until.Format("2006-01-02") {
				byDate[date] = append(byDate[date], sleep)
			}
		}
	}
	dates := map[string]bool{}
	for date, sleeps := range byDate {
		for _, sleep := range sleeps {
			if sleep.Metadata.Main || sleep.Interval.End.Sub(sleep.Interval.Start) >= 180*time.Minute {
				dates[date] = true
			}
		}
	}
	return dates
}
