package health

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/netx"
)

const Source = "google_health_v4"

type collectionError string

func (e collectionError) Error() string { return string(e) }

// CollectionErrorCode returns a finite, privacy-safe diagnostic. It never uses
// arbitrary error text or the caller-controlled APIError.Code field.
func CollectionErrorCode(err error) string {
	var api *APIError
	if errors.As(err, &api) && api != nil {
		return safeCode(api.Status)
	}
	var validation collectionError
	if errors.As(err, &validation) {
		switch validation {
		case "short awakening missing type":
			return "short_awakening_missing_type"
		case "short awakening invalid type":
			return "short_awakening_invalid_type"
		case "short awakening unspecified type":
			return "short_awakening_unspecified_type"
		case "short awakening missing time":
			return "short_awakening_missing_time"
		case "short awakening invalid time order":
			return "short_awakening_invalid_time_order"
		case "short awakening outside session":
			return "short_awakening_outside_session"
		case "invalid sleep stage interval":
			return "invalid_sleep_stage_interval"
		case "invalid health data point", "invalid data point":
			return "invalid_data_point"
		case "invalid rollup window":
			return "invalid_rollup_window"
		case "invalid Google Health page":
			return "invalid_page"
		case "Google Health repeated a pagination token":
			return "repeated_page_token"
		case "invalid integer health field":
			return "invalid_integer_field"
		case "invalid numeric health field":
			return "invalid_numeric_field"
		case "health record is missing its observation time or requested type":
			return "missing_observation_or_type"
		case "invalid health interval":
			return "invalid_health_interval"
		case "invalid health date":
			return "invalid_health_date"
		case "invalid heart rate measurement":
			return "invalid_heart_rate_measurement"
		case "invalid step count":
			return "invalid_step_count"
		case "invalid sampled RMSSD measurement":
			return "invalid_sampled_rmssd_measurement"
		case "missing resting heart rate measurement":
			return "missing_resting_heart_rate_measurement"
		case "identified data point changed during pagination; retry sync":
			return "data_point_changed_during_pagination"
		case "invalid sleep interval":
			return "invalid_sleep_interval"
		case "sleep duration exceeds session", "sleep stage total exceeds session", "sleep stage summary contradicts asleep duration":
			return "invalid_sleep_summary"
		}
	}
	return "request_failed"
}

type Kind struct {
	ID, Filter string
	Reconcile  bool
}

var Kinds = []Kind{
	{"sleep", "sleep.interval.end_time", true},
	{"daily-heart-rate-variability", "daily_heart_rate_variability.date", false},
	{"heart-rate-variability", "heart_rate_variability.sample_time.physical_time", false},
	{"daily-resting-heart-rate", "daily_resting_heart_rate.date", false},
	{"steps", "steps.interval.start_time", true},
	{"heart-rate", "heart_rate.sample_time.physical_time", true},
	{"exercise", "exercise.interval.civil_start_time", false},
}

type Number float64

type Integer int64

func (n *Integer) UnmarshalJSON(b []byte) error {
	s := string(b)
	if len(b) > 0 && b[0] == '"' {
		if json.Unmarshal(b, &s) != nil {
			return collectionError("invalid integer health field")
		}
	}
	if !json.Valid([]byte(s)) {
		return collectionError("invalid integer health field")
	}
	v, _, err := big.ParseFloat(s, 10, uint(len(s)*4+64), big.ToNearestEven)
	if err != nil {
		return collectionError("invalid integer health field")
	}
	integer, accuracy := v.Int64()
	if accuracy != big.Exact || integer < 0 {
		return collectionError("invalid integer health field")
	}
	*n = Integer(integer)
	return nil
}

func (n *Number) UnmarshalJSON(b []byte) error {
	s := strings.Trim(string(b), "\"")
	v, err := strconv.ParseFloat(s, 64)
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) || v < 0 {
		return collectionError("invalid numeric health field")
	}
	*n = Number(v)
	return nil
}

type Date struct {
	Year  int `json:"year"`
	Month int `json:"month"`
	Day   int `json:"day"`
}

func (d Date) String() string { return fmt.Sprintf("%04d-%02d-%02d", d.Year, d.Month, d.Day) }

type Interval struct {
	Start time.Time `json:"startTime"`
	End   time.Time `json:"endTime"`
}
type SampleTime struct {
	Physical time.Time `json:"physicalTime"`
}
type Stage struct {
	Type  string    `json:"type"`
	Start time.Time `json:"startTime"`
	End   time.Time `json:"endTime"`
}
type StageSummary struct {
	Type    string   `json:"type"`
	Minutes *Integer `json:"minutes"`
	Count   *Integer `json:"count"`
}
type Sleep struct {
	Interval        Interval `json:"interval"`
	Type            string   `json:"type"`
	Stages          []Stage  `json:"stages"`
	ShortAwakenings []Stage  `json:"shortAwakenings"`
	Summary         struct {
		MinutesAsleep        *Integer       `json:"minutesAsleep"`
		MinutesAwake         *Integer       `json:"minutesAwake"`
		MinutesInSleepPeriod *Integer       `json:"minutesInSleepPeriod"`
		MinutesToFallAsleep  *Integer       `json:"minutesToFallAsleep"`
		MinutesAfterWakeUp   *Integer       `json:"minutesAfterWakeUp"`
		Stages               []StageSummary `json:"stagesSummary"`
	} `json:"summary"`
	Metadata struct {
		Main         bool   `json:"mainSleep"`
		Processed    *bool  `json:"processed"`
		StagesStatus string `json:"stagesStatus"`
	} `json:"metadata"`
}
type DailyHRV struct {
	Date  Date    `json:"date"`
	RMSSD *Number `json:"averageHeartRateVariabilityMilliseconds"`
}
type HRV struct {
	Sample SampleTime `json:"sampleTime"`
	RMSSD  *Number    `json:"rootMeanSquareOfSuccessiveDifferencesMilliseconds"`
	SDNN   *Number    `json:"standardDeviationMilliseconds"`
}
type RHR struct {
	Date Date     `json:"date"`
	BPM  *Integer `json:"beatsPerMinute"`
}
type Steps struct {
	Interval Interval `json:"interval"`
	Count    *Integer `json:"count"`
}

func (s *Steps) UnmarshalJSON(b []byte) error {
	type steps Steps
	var value steps
	if err := json.Unmarshal(b, &value); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(b, &fields); err != nil {
		return err
	}
	if _, present := fields["count"]; present && value.Count == nil {
		return collectionError("invalid step count")
	}
	*s = Steps(value)
	return nil
}

type HR struct {
	Sample SampleTime `json:"sampleTime"`
	BPM    *Integer   `json:"beatsPerMinute"`
}
type Exercise struct {
	Interval       Interval `json:"interval"`
	Type           string   `json:"exerciseType"`
	ActiveDuration string   `json:"activeDuration"`
}
type DataSource struct {
	Method   string `json:"recordingMethod,omitempty"`
	Platform string `json:"platform,omitempty"`
	Device   struct {
		FormFactor   string `json:"formFactor,omitempty"`
		Manufacturer string `json:"manufacturer,omitempty"`
		DisplayName  string `json:"displayName,omitempty"`
	} `json:"device"`
	Application struct {
		PackageName       string `json:"packageName,omitempty"`
		GoogleWebClientID string `json:"googleWebClientId,omitempty"`
		WebClientID       string `json:"webClientId,omitempty"`
	} `json:"application"`
}

type Point struct {
	Name           string                       `json:"name"`
	ReconciledName string                       `json:"dataPointName"`
	DataSource     *DataSource                  `json:"dataSource"`
	Sleep          *Sleep                       `json:"sleep"`
	DailyHRV       *DailyHRV                    `json:"dailyHeartRateVariability"`
	HRV            *HRV                         `json:"heartRateVariability"`
	RHR            *RHR                         `json:"dailyRestingHeartRate"`
	Steps          *Steps                       `json:"steps"`
	HR             *HR                          `json:"heartRate"`
	Exercise       *Exercise                    `json:"exercise"`
	DailyRR        *DailyRespiratoryRate        `json:"dailyRespiratoryRate"`
	Oxygen         *DailyOxygenSaturation       `json:"dailyOxygenSaturation"`
	Temperature    *DailyTemperature            `json:"dailySleepTemperatureDerivations"`
	Zones          *DailyHeartRateZones         `json:"dailyHeartRateZones"`
	VO2            *DailyVO2Max                 `json:"dailyVo2Max"`
	RespSummary    *RespiratorySleepSummary     `json:"respiratoryRateSleepSummary"`
	IRN            *IrregularRhythmNotification `json:"irregularRhythmNotification"`
}

type Record struct {
	Type      string          `json:"data_type"`
	Stream    string          `json:"stream"`
	Date      string          `json:"date"`
	Raw       json.RawMessage `json:"data_point"`
	Synthetic bool            `json:"synthetic_fixture,omitempty"`
}

// Identity returns the point name, excluding collection paths without a point ID.
func (r Record) Identity() string {
	var identity struct {
		Name       string `json:"name"`
		Reconciled string `json:"dataPointName"`
	}
	if json.Unmarshal(r.Raw, &identity) != nil {
		return ""
	}
	name := identity.Name
	if r.Stream == "reconciled" {
		name = identity.Reconciled
	}
	if strings.HasSuffix(name, "/dataPoints/") {
		return ""
	}
	return name
}

func Decode(r Record) (Point, error) {
	var p Point
	if err := json.Unmarshal(r.Raw, &p); err != nil {
		var validation collectionError
		if errors.As(err, &validation) {
			return p, validation
		}
		return p, collectionError("invalid health data point")
	}
	if _, err := DateFor(p, r.Type, time.UTC); err != nil {
		return p, err
	}
	if p.HR != nil && (p.HR.BPM == nil || *p.HR.BPM < 1 || *p.HR.BPM > 300) {
		return p, collectionError("invalid heart rate measurement")
	}
	if p.Steps != nil && p.Steps.Count != nil && *p.Steps.Count > 1000000 {
		return p, collectionError("invalid step count")
	}
	if p.HRV != nil && p.HRV.RMSSD != nil && (*p.HRV.RMSSD < 1 || *p.HRV.RMSSD > 200) {
		return p, collectionError("invalid sampled RMSSD measurement")
	}
	if p.RHR != nil && p.RHR.BPM == nil {
		return p, collectionError("missing resting heart rate measurement")
	}
	if p.Sleep != nil {
		sl := p.Sleep
		minutes := sl.Interval.End.Sub(sl.Interval.Start).Minutes()
		if sl.Summary.MinutesAsleep != nil && float64(*sl.Summary.MinutesAsleep) > minutes {
			return p, collectionError("sleep duration exceeds session")
		}
		total, sleeping, notSleeping := 0.0, 0.0, 0.0
		for _, stage := range sl.Summary.Stages {
			if stage.Minutes != nil {
				v := float64(*stage.Minutes)
				total += v
				switch stage.Type {
				case "ASLEEP", "LIGHT", "DEEP", "REM":
					sleeping += v
				case "AWAKE", "RESTLESS":
					notSleeping += v
				}
			}
		}
		if total > minutes {
			return p, collectionError("sleep stage total exceeds session")
		}
		// The API defines minutesAsleep to exclude AWAKE and RESTLESS.
		// https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints#Sleep.SleepSummary
		if sl.Summary.MinutesAsleep != nil {
			asleep := float64(*sl.Summary.MinutesAsleep)
			if sleeping > asleep || notSleeping+asleep > minutes {
				return p, collectionError("sleep stage summary contradicts asleep duration")
			}
		}
		for _, awake := range sl.ShortAwakenings {
			switch awake.Type {
			case "AWAKE", "LIGHT", "DEEP", "REM", "ASLEEP", "RESTLESS":
			case "":
				return p, collectionError("short awakening missing type")
			case "SLEEP_STAGE_TYPE_UNSPECIFIED":
				return p, collectionError("short awakening unspecified type")
			default:
				return p, collectionError("short awakening invalid type")
			}
			if awake.Start.IsZero() || awake.End.IsZero() {
				return p, collectionError("short awakening missing time")
			}
			if !awake.End.After(awake.Start) {
				return p, collectionError("short awakening invalid time order")
			}
			if awake.Start.Before(sl.Interval.Start) || awake.End.After(sl.Interval.End) {
				return p, collectionError("short awakening outside session")
			}
		}
		stages := append([]Stage{}, sl.Stages...)
		sort.Slice(stages, func(i, j int) bool { return stages[i].Start.Before(stages[j].Start) })
		cursor := sl.Interval.Start
		for _, stage := range stages {
			if stage.Start.Before(cursor) || !stage.End.After(stage.Start) || stage.End.After(sl.Interval.End) {
				return p, collectionError("invalid sleep stage interval")
			}
			cursor = stage.End
		}
	}
	return p, nil
}

func DateFor(p Point, id string, loc *time.Location) (string, error) {
	var t time.Time
	var interval *Interval
	var date string
	switch id {
	case "sleep":
		if p.Sleep != nil {
			interval = &p.Sleep.Interval
			t = interval.End
		}
	case "daily-heart-rate-variability":
		if p.DailyHRV != nil {
			date = p.DailyHRV.Date.String()
		}
	case "heart-rate-variability":
		if p.HRV != nil {
			t = p.HRV.Sample.Physical
		}
	case "daily-resting-heart-rate":
		if p.RHR != nil {
			date = p.RHR.Date.String()
		}
	case "steps":
		if p.Steps != nil {
			interval = &p.Steps.Interval
			t = interval.Start
		}
	case "heart-rate":
		if p.HR != nil {
			t = p.HR.Sample.Physical
		}
	case "exercise":
		if p.Exercise != nil {
			interval = &p.Exercise.Interval
			t = interval.Start
		}
	case "daily-respiratory-rate":
		if p.DailyRR != nil {
			date = p.DailyRR.Date.String()
		}
	case "daily-oxygen-saturation":
		if p.Oxygen != nil {
			date = p.Oxygen.Date.String()
		}
	case "daily-sleep-temperature-derivations":
		if p.Temperature != nil {
			date = p.Temperature.Date.String()
		}
	case "daily-heart-rate-zones":
		if p.Zones != nil {
			date = p.Zones.Date.String()
		}
	case "daily-vo2-max":
		if p.VO2 != nil {
			date = p.VO2.Date.String()
		}
	case "respiratory-rate-sleep-summary":
		if p.RespSummary != nil {
			t = p.RespSummary.Sample.Physical
		}
	case "irregular-rhythm-notification":
		if p.IRN != nil {
			interval = &p.IRN.Interval
			t = interval.Start
		}
	default:
		return "", errors.New("unsupported data type")
	}
	if interval != nil && (interval.Start.IsZero() || interval.End.IsZero() || !interval.End.After(interval.Start)) {
		if id == "sleep" {
			return "", collectionError("invalid sleep interval")
		}
		return "", collectionError("invalid health interval")
	}
	if date != "" {
		if _, err := time.Parse("2006-01-02", date); err != nil {
			return "", collectionError("invalid health date")
		}
		return date, nil
	}
	if t.IsZero() {
		return "", collectionError("health record is missing its observation time or requested type")
	}
	return t.In(loc).Format("2006-01-02"), nil
}

type Access func(context.Context, string) (string, error)
type Client struct {
	HTTP     *http.Client
	BaseURL  string
	Access   Access
	requests atomic.Int64
}

func New(access Access) *Client {
	return &Client{HTTP: netx.Client(), BaseURL: "https://health.googleapis.com", Access: access}
}

type APIError struct {
	Status int
	Code   string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("Google Health request failed (HTTP %d, %s)", e.Status, e.Code)
}

func safeCode(status int) string {
	switch status {
	case 400:
		return "invalid_request_or_account_unlinked"
	case 401:
		return "unauthorized"
	case 403:
		return "permission_denied"
	case 404:
		return "not_found"
	case 429:
		return "rate_limited"
	case 501:
		return "unsupported"
	default:
		return "provider_error"
	}
}

func (c *Client) Fetch(ctx context.Context, kind Kind, stream string, from, until time.Time) ([]Record, error) {
	return c.fetch(ctx, kind, stream, from, until, false)
}

func (c *Client) FetchV2(ctx context.Context, kind Kind, stream string, from, until time.Time) ([]Record, error) {
	return c.fetch(ctx, kind, stream, from, until, true)
}

func (c *Client) fetch(ctx context.Context, kind Kind, stream string, from, until time.Time, v2 bool) ([]Record, error) {
	if stream != "raw" && (stream != "reconciled" || !kind.Reconcile) {
		return nil, errors.New("invalid collection stream")
	}
	valid := false
	kinds := Kinds
	if v2 {
		kinds = V2Kinds
	}
	for _, k := range kinds {
		if k == kind {
			valid = true
		}
	}
	if !valid {
		return nil, errors.New("invalid data type")
	}
	lower, upper := from.UTC().Format(time.RFC3339), until.UTC().Format(time.RFC3339)
	if strings.HasSuffix(kind.Filter, ".date") {
		lower, upper = from.Format("2006-01-02"), until.Format("2006-01-02")
	}
	if kind.ID == "exercise" {
		lower, upper = from.AddDate(0, 0, -1).Format("2006-01-02"), until.AddDate(0, 0, 1).Format("2006-01-02")
	}
	query := url.Values{"filter": {fmt.Sprintf("%s >= %q AND %s < %q", kind.Filter, lower, kind.Filter, upper)}, "pageSize": {"1440"}}
	if kind.ID == "sleep" || kind.ID == "exercise" || v2 && kind.ID == "irregular-rhythm-notification" {
		query.Set("pageSize", "25")
	}
	path := "/v4/users/me/dataTypes/" + kind.ID + "/dataPoints"
	if stream == "reconciled" {
		path += ":reconcile"
	}
	seenPages := map[string]bool{}
	seenRecords := map[string]bool{}
	seenNames := map[string]string{}
	out := []Record{}
	for page := 0; page < 1000; page++ {
		b, err := c.get(ctx, c.BaseURL+path+"?"+query.Encode())
		if err != nil {
			return nil, err
		}
		var result struct {
			Points    []json.RawMessage `json:"dataPoints"`
			Next      string            `json:"nextPageToken"`
			Synthetic bool              `json:"synthetic_fixture"`
		}
		var fields map[string]json.RawMessage
		if json.Unmarshal(b, &fields) != nil || fields == nil {
			return nil, collectionError("invalid Google Health page")
		}
		for key, value := range fields {
			switch key {
			case "dataPoints":
				if len(value) == 0 || value[0] != '[' {
					return nil, collectionError("invalid Google Health page")
				}
			case "nextPageToken":
				if len(value) == 0 || value[0] != '"' {
					return nil, collectionError("invalid Google Health page")
				}
			case "synthetic_fixture":
			default:
				return nil, collectionError("invalid Google Health page")
			}
		}
		if json.Unmarshal(b, &result) != nil {
			return nil, collectionError("invalid Google Health page")
		}
		for _, raw := range result.Points {
			if v2 && kind.ID == "irregular-rhythm-notification" {
				raw, err = stripIRN(raw)
				if err != nil {
					return nil, err
				}
			}
			r := Record{Type: kind.ID, Stream: stream, Raw: raw, Synthetic: result.Synthetic}
			var p Point
			if v2 {
				r, p, err = decodeV2(r)
				raw = r.Raw
			} else {
				p, err = Decode(r)
			}
			if err != nil {
				return nil, err
			}
			r.Date, err = DateFor(p, kind.ID, from.Location())
			if err != nil {
				return nil, err
			}
			if r.Date < from.Format("2006-01-02") || r.Date >= until.Format("2006-01-02") {
				continue
			}
			var compact any
			decoder := json.NewDecoder(strings.NewReader(string(raw)))
			decoder.UseNumber()
			if decoder.Decode(&compact) != nil {
				return nil, collectionError("invalid data point")
			}
			canonical, _ := json.Marshal(compact)
			key := fmt.Sprintf("%x", sha256.Sum256(canonical))
			name := p.Name
			if stream == "reconciled" {
				name = p.ReconciledName
			}
			if v2 {
				name = r.Identity()
			}
			if name != "" {
				if prior, ok := seenNames[name]; ok && prior != key {
					return nil, collectionError("identified data point changed during pagination; retry sync")
				}
				seenNames[name] = key
			}
			if seenRecords[key] {
				continue
			}
			seenRecords[key] = true
			out = append(out, r)
			if len(out) > 1000000 {
				return nil, errors.New("collection record limit exceeded; use a smaller date range")
			}
		}
		if result.Next == "" {
			sort.SliceStable(out, func(i, j int) bool {
				if out[i].Date != out[j].Date {
					return out[i].Date < out[j].Date
				}
				return string(out[i].Raw) < string(out[j].Raw)
			})
			return out, nil
		}
		if seenPages[result.Next] {
			return nil, collectionError("Google Health repeated a pagination token")
		}
		seenPages[result.Next] = true
		query.Set("pageToken", result.Next)
	}
	return nil, errors.New("pagination limit exceeded; use a smaller date range")
}

func (c *Client) get(ctx context.Context, endpoint string) ([]byte, error) {
	return c.do(ctx, http.MethodGet, endpoint, nil)
}

// do sends one read request. POST is used only for Google's read-only roll-up routes.
func (c *Client) do(ctx context.Context, method, endpoint string, body []byte) ([]byte, error) {
	access, err := c.Access(ctx, "")
	if err != nil {
		return nil, err
	}
	refreshed := false
	for attempt := 0; attempt < 5; attempt++ {
		var reader io.Reader
		if body != nil {
			reader = bytes.NewReader(body)
		}
		req, err := http.NewRequestWithContext(ctx, method, endpoint, reader)
		if err != nil {
			return nil, errors.New("invalid Google Health endpoint")
		}
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}
		req.Header.Set("Authorization", "Bearer "+access)
		req.Header.Set("Accept", "application/json")
		c.requests.Add(1)
		resp, err := c.HTTP.Do(req)
		if err != nil {
			if attempt < 3 {
				if err := netx.Wait(ctx, attempt, ""); err != nil {
					return nil, errors.New("Google Health request cancelled")
				}
				continue
			}
			return nil, errors.New("Google Health network request failed")
		}
		body, err := netx.Read(resp)
		if err != nil {
			return nil, err
		}
		if resp.StatusCode == 200 {
			return body, nil
		}
		if resp.StatusCode == 401 && !refreshed {
			access, err = c.Access(ctx, access)
			if err != nil {
				return nil, err
			}
			refreshed = true
			continue
		}
		if (resp.StatusCode == 429 || resp.StatusCode >= 500) && attempt < 3 {
			if err := netx.Wait(ctx, attempt, resp.Header.Get("Retry-After")); err != nil {
				return nil, err
			}
			continue
		}
		return nil, &APIError{Status: resp.StatusCode, Code: safeCode(resp.StatusCode)}
	}
	return nil, errors.New("Google Health retries exhausted")
}
