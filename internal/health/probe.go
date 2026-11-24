package health

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

// ProbeType names one Google Health data type and how its observation time is filtered.
type ProbeType struct {
	ID     string
	Record string // daily, sample, interval, session or rollup
}

// ProbeTypes lists every readable v4 data type. Write-only types are excluded.
var ProbeTypes = []ProbeType{
	{"active-energy-burned", "interval"}, {"active-minutes", "interval"}, {"active-zone-minutes", "interval"},
	{"activity-level", "interval"}, {"altitude", "interval"}, {"blood-glucose", "sample"}, {"body-fat", "sample"},
	{"calories-in-heart-rate-zone", "rollup"}, {"core-body-temperature", "sample"},
	{"daily-heart-rate-variability", "daily"}, {"daily-heart-rate-zones", "daily"}, {"daily-oxygen-saturation", "daily"},
	{"daily-respiratory-rate", "daily"}, {"daily-resting-heart-rate", "daily"},
	{"daily-sleep-temperature-derivations", "daily"}, {"daily-vo2-max", "daily"}, {"distance", "interval"},
	{"electrocardiogram", "session"}, {"exercise", "session"}, {"floors", "rollup"}, {"heart-rate", "sample"},
	{"heart-rate-variability", "sample"}, {"height", "sample"}, {"hydration-log", "session"},
	{"irregular-rhythm-notification", "session"}, {"nutrition-log", "session"}, {"oxygen-saturation", "sample"},
	{"respiratory-rate-sleep-summary", "sample"}, {"run-vo2-max", "sample"}, {"sedentary-period", "interval"},
	{"skin-temperature-sensors", "sample"}, {"sleep", "session"}, {"steps", "interval"},
	{"swim-lengths-data", "interval"}, {"time-in-heart-rate-zone", "interval"}, {"total-calories", "rollup"},
	{"vo2-max", "sample"}, {"weight", "sample"},
}

// ProbeResult reports whether a route returned records. It never carries record values.
type ProbeResult struct {
	Target  string `json:"target"`
	Method  string `json:"method"`
	Status  string `json:"status"` // records, empty or error
	Records int    `json:"records"`
	More    bool   `json:"more_pages"`
	Error   string `json:"error,omitempty"`
}

func snake(id string) string {
	b := []byte(id)
	for i := range b {
		if b[i] == '-' {
			b[i] = '_'
		}
	}
	return string(b)
}

func probeFilter(t ProbeType, from, until time.Time) string {
	field := snake(t.ID)
	lower, upper := from.UTC().Format(time.RFC3339), until.UTC().Format(time.RFC3339)
	switch {
	case t.Record == "daily":
		field += ".date"
		lower, upper = from.Format("2006-01-02"), until.Format("2006-01-02")
	case t.Record == "sample":
		field += ".sample_time.physical_time"
	case t.ID == "exercise":
		field += ".interval.civil_start_time"
		lower, upper = from.Format("2006-01-02"), until.Format("2006-01-02")
	case t.ID == "sleep":
		field += ".interval.end_time"
	default:
		field += ".interval.start_time"
	}
	return fmt.Sprintf("%s >= %q AND %s < %q", field, lower, field, upper)
}

func civil(t time.Time) map[string]any {
	return map[string]any{"date": map[string]int{"year": t.Year(), "month": int(t.Month()), "day": t.Day()}, "time": map[string]int{}}
}

func count(b []byte, key string) (int, bool, error) {
	var page map[string]json.RawMessage
	if json.Unmarshal(b, &page) != nil {
		return 0, false, errors.New("invalid_page")
	}
	var items []json.RawMessage
	if raw, ok := page[key]; ok && json.Unmarshal(raw, &items) != nil {
		return 0, false, errors.New("invalid_page")
	}
	var next string
	_ = json.Unmarshal(page["nextPageToken"], &next)
	return len(items), next != "", nil
}

func result(target, method string, b []byte, err error, key string) ProbeResult {
	r := ProbeResult{Target: target, Method: method}
	if err != nil {
		r.Status = "error"
		var api *APIError
		if errors.As(err, &api) {
			r.Error = fmt.Sprintf("http_%d_%s", api.Status, api.Code)
		} else {
			r.Error = "request_failed"
		}
		return r
	}
	n, more, cerr := count(b, key)
	if cerr != nil {
		r.Status, r.Error = "error", cerr.Error()
		return r
	}
	r.Records, r.More = n, more
	r.Status = "empty"
	if n > 0 || key == "" {
		r.Status = "records"
	}
	return r
}

// Probe asks every readable route for one page over [from, until) and returns counts only.
func (c *Client) Probe(ctx context.Context, from, until time.Time) []ProbeResult {
	out := []ProbeResult{}
	base := c.BaseURL + "/v4/users/me"
	for _, user := range []struct{ path, key string }{{"/identity", ""}, {"/profile", ""}, {"/settings", ""}, {"/pairedDevices", "pairedDevices"}, {"/irnProfile", ""}} {
		b, err := c.get(ctx, base+user.path)
		out = append(out, result("users/me"+user.path, "get", b, err, user.key))
	}
	for _, t := range ProbeTypes {
		path := base + "/dataTypes/" + t.ID + "/dataPoints"
		if t.Record == "rollup" {
			continue
		}
		q := url.Values{"pageSize": {"1000"}, "filter": {probeFilter(t, from, until)}}
		if t.Record == "session" {
			q.Set("pageSize", "25")
		}
		b, err := c.get(ctx, path+"?"+q.Encode())
		out = append(out, result(t.ID, "list", b, err, "dataPoints"))
	}
	body, _ := json.Marshal(map[string]any{"range": map[string]any{"start": civil(from), "end": civil(until)}, "windowSizeDays": 1})
	for _, id := range []string{"total-calories", "calories-in-heart-rate-zone", "floors", "active-zone-minutes", "time-in-heart-rate-zone", "heart-rate", "daily-heart-rate-variability", "daily-resting-heart-rate", "steps"} {
		b, err := c.do(ctx, http.MethodPost, base+"/dataTypes/"+id+"/dataPoints:dailyRollUp", body)
		out = append(out, result(id, "dailyRollUp", b, err, "rollupDataPoints"))
	}
	return out
}
