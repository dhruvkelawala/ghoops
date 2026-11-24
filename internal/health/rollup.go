package health

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"time"
)

type RollupMinute struct {
	Start         int64
	Min, Avg, Max float64
}

type RollupDay struct {
	Date  string
	Value json.RawMessage
}

func (c *Client) RollUp(ctx context.Context, from time.Time) ([]RollupMinute, error) {
	until := from.AddDate(0, 0, 1)
	body := map[string]any{
		"range":      map[string]string{"startTime": from.UTC().Format(time.RFC3339), "endTime": until.UTC().Format(time.RFC3339)},
		"windowSize": "60s", "pageSize": 1500,
	}
	pages, err := c.rollupPages(ctx, "heart-rate", "rollUp", body)
	if err != nil {
		return nil, err
	}
	type window struct {
		Start time.Time `json:"startTime"`
		End   time.Time `json:"endTime"`
		HR    *struct {
			Min json.RawMessage `json:"beatsPerMinuteMin"`
			Avg json.RawMessage `json:"beatsPerMinuteAvg"`
			Max json.RawMessage `json:"beatsPerMinuteMax"`
		} `json:"heartRate"`
	}
	windows := []window{}
	for _, raw := range pages {
		var w window
		if json.Unmarshal(raw, &w) != nil {
			return nil, collectionError("invalid rollup window")
		}
		windows = append(windows, w)
	}
	sort.Slice(windows, func(i, j int) bool { return windows[i].Start.Before(windows[j].Start) })
	minutes := []RollupMinute{}
	previous := from
	for _, w := range windows {
		if w.Start.Before(from) || w.Start.Before(previous) || w.End.After(until) || w.End.Sub(w.Start) != time.Minute || w.Start.Unix()%60 != 0 || w.Start.Nanosecond() != 0 {
			return nil, collectionError("invalid rollup window")
		}
		previous = w.End
		if w.HR == nil {
			continue
		}
		avg, low, high := rollupNumber(w.HR.Avg), rollupNumber(w.HR.Min), rollupNumber(w.HR.Max)
		if !inRange(avg, 1, 300) {
			continue
		}
		if !inRange(low, 1, 300) || !inRange(high, 1, 300) {
			return nil, collectionError("invalid data point")
		}
		minutes = append(minutes, RollupMinute{w.Start.Unix(), float64(*low), float64(*avg), float64(*high)})
	}
	return minutes, nil
}

func rollupNumber(raw json.RawMessage) *Number {
	var n Number
	if len(raw) == 0 || string(raw) == "null" || json.Unmarshal(raw, &n) != nil {
		return nil
	}
	return &n
}

func (c *Client) DailyRollUp(ctx context.Context, id string, from, until time.Time) ([]RollupDay, error) {
	field, size := "", 90
	switch id {
	case "steps":
		field = "steps"
	case "active-zone-minutes":
		field = "activeZoneMinutes"
	case "total-calories":
		field, size = "totalCalories", 14
	case "distance":
		field = "distance"
	default:
		return nil, collectionError("invalid data point")
	}
	if !from.Before(until) || from.AddDate(0, 0, size).Before(until) {
		return nil, collectionError("invalid data point")
	}
	body := map[string]any{"range": map[string]any{"start": probeV2Civil(from), "end": probeV2Civil(until)}, "windowSizeDays": 1, "pageSize": size}
	pages, err := c.rollupPages(ctx, id, "dailyRollUp", body)
	if err != nil {
		return nil, err
	}
	days := []RollupDay{}
	seen := map[string]string{}
	for _, raw := range pages {
		var day struct {
			Start struct {
				Date Date `json:"date"`
			} `json:"civilStartTime"`
		}
		var fields map[string]json.RawMessage
		if json.Unmarshal(raw, &day) != nil || json.Unmarshal(raw, &fields) != nil {
			return nil, collectionError("invalid data point")
		}
		date := day.Start.Date.String()
		if _, err := time.Parse("2006-01-02", date); err != nil {
			return nil, collectionError("invalid health date")
		}
		if date < from.Format("2006-01-02") || date >= until.Format("2006-01-02") {
			continue
		}
		var value map[string]json.RawMessage
		if len(fields[field]) == 0 || string(fields[field]) == "null" {
			continue
		}
		if json.Unmarshal(fields[field], &value) != nil || value == nil {
			return nil, collectionError("invalid data point")
		}
		keys := []string{}
		switch id {
		case "steps":
			keys = []string{"countSum"}
		case "active-zone-minutes":
			keys = []string{"sumInFatBurnHeartZone", "sumInCardioHeartZone", "sumInPeakHeartZone"}
		case "total-calories":
			keys = []string{"kcalSum"}
		case "distance":
			keys = []string{"millimetersSum"}
		}
		present := false
		for _, key := range keys {
			if b, ok := value[key]; ok {
				var n Number
				if string(b) == "null" || json.Unmarshal(b, &n) != nil {
					return nil, collectionError("invalid data point")
				}
				if id == "steps" || id == "distance" {
					var n Integer
					if json.Unmarshal(b, &n) != nil {
						return nil, collectionError("invalid data point")
					}
				}
				present = true
			}
		}
		if !present {
			continue
		}
		if prior, ok := seen[date]; ok {
			if prior != string(raw) {
				return nil, collectionError("identified data point changed during pagination; retry sync")
			}
			continue
		}
		seen[date] = string(raw)
		days = append(days, RollupDay{date, raw})
	}
	sort.Slice(days, func(i, j int) bool { return days[i].Date < days[j].Date })
	return days, nil
}

func (c *Client) UserResource(ctx context.Context, resource string) (json.RawMessage, error) {
	path := ""
	switch resource {
	case "profile":
		path = "profile"
	case "settings":
		path = "settings"
	case "paired_devices":
		path = "pairedDevices?pageSize=10"
	case "irn_profile":
		path = "irnProfile"
	default:
		return nil, collectionError("invalid data point")
	}
	b, err := c.get(ctx, c.BaseURL+"/v4/users/me/"+path)
	if err != nil {
		return nil, err
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(b, &fields) != nil || fields == nil {
		return nil, collectionError("invalid data point")
	}
	if resource == "paired_devices" {
		var devices []map[string]json.RawMessage
		if raw, ok := fields["pairedDevices"]; ok {
			if len(raw) == 0 || raw[0] != '[' || json.Unmarshal(raw, &devices) != nil {
				return nil, collectionError("invalid data point")
			}
			for _, device := range devices {
				delete(device, "macAddress")
			}
			fields["pairedDevices"], _ = json.Marshal(devices)
		}
		return json.Marshal(fields)
	}
	return b, nil
}

func (c *Client) rollupPages(ctx context.Context, id, route string, body map[string]any) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	seen := map[string]bool{}
	for page := 0; page < 1000; page++ {
		encoded, _ := json.Marshal(body)
		b, err := c.do(ctx, http.MethodPost, c.BaseURL+"/v4/users/me/dataTypes/"+id+"/dataPoints:"+route, encoded)
		if err != nil {
			return nil, err
		}
		var result struct {
			Points []json.RawMessage `json:"rollupDataPoints"`
			Next   string            `json:"nextPageToken"`
		}
		var fields map[string]json.RawMessage
		if json.Unmarshal(b, &fields) != nil || fields == nil || json.Unmarshal(b, &result) != nil {
			return nil, collectionError("invalid Google Health page")
		}
		if raw, ok := fields["rollupDataPoints"]; ok && (len(raw) == 0 || raw[0] != '[') {
			return nil, collectionError("invalid Google Health page")
		}
		out = append(out, result.Points...)
		if len(out) > 1000000 {
			return nil, collectionError("invalid Google Health page")
		}
		if result.Next == "" {
			return out, nil
		}
		if seen[result.Next] {
			return nil, collectionError("Google Health repeated a pagination token")
		}
		seen[result.Next] = true
		body["pageToken"] = result.Next
	}
	return nil, collectionError("invalid Google Health page")
}
