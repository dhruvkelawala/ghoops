package health_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/health"
)

func bounds(t *testing.T) (time.Time, time.Time) {
	t.Helper()
	loc, err := time.LoadLocation("Europe/London")
	if err != nil {
		t.Fatal(err)
	}
	from, _ := time.ParseInLocation("2006-01-02", "2026-10-25", loc)
	return from, from.AddDate(0, 0, 1)
}
func kind(id string) health.Kind {
	for _, k := range health.Kinds {
		if k.ID == id {
			return k
		}
	}
	panic(id)
}
func client(srv *httptest.Server) *health.Client {
	c := health.New(func(context.Context, string) (string, error) { return "synthetic-access", nil })
	c.BaseURL = srv.URL
	return c
}

func TestCollectionRoutesFiltersPaginationAndDedupe(t *testing.T) {
	from, until := bounds(t)
	var pages atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		pages.Add(1)
		if r.Method != "GET" || r.URL.Path != "/v4/users/me/dataTypes/heart-rate/dataPoints:reconcile" || r.Header.Get("Authorization") != "Bearer synthetic-access" {
			t.Error("request contract")
		}
		filter := r.URL.Query().Get("filter")
		if !strings.Contains(filter, `heart_rate.sample_time.physical_time >= "2026-10-24T23:00:00Z"`) || !strings.Contains(filter, `< "2026-10-26T00:00:00Z"`) {
			t.Error("DST/filter", filter)
		}
		point := json.RawMessage(`{"heartRate":{"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"},"beatsPerMinute":"62"}}`)
		next := "synthetic-page"
		if r.URL.Query().Get("pageToken") != "" {
			next = ""
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"dataPoints": []json.RawMessage{point}, "nextPageToken": next})
	}))
	defer srv.Close()
	records, err := client(srv).Fetch(context.Background(), kind("heart-rate"), "reconciled", from, until)
	if err != nil || len(records) != 1 || pages.Load() != 2 {
		t.Fatal("pagination", len(records), err)
	}
}

func TestEveryDataTypeUsesDocumentedFilter(t *testing.T) {
	from, until := bounds(t)
	for _, k := range health.Kinds {
		t.Run(k.ID, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				q := r.URL.Query()
				if !strings.Contains(q.Get("filter"), k.Filter+" >= ") {
					t.Error("wrong filter", q)
				}
				if q.Get("dataSourceFamily") != "" {
					t.Error("unexpected source filtering")
				}
				if (k.ID == "sleep" || k.ID == "exercise") && q.Get("pageSize") != "25" {
					t.Error("page size")
				}
				if strings.HasSuffix(k.Filter, ".date") && !strings.Contains(q.Get("filter"), `"2026-10-25"`) {
					t.Error("daily date filter")
				}
				_ = json.NewEncoder(w).Encode(map[string]any{"dataPoints": []any{}})
			}))
			defer srv.Close()
			if _, err := client(srv).Fetch(context.Background(), k, "raw", from, until); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestRetryAfterAndUnauthorizedRefresh(t *testing.T) {
	from, until := bounds(t)
	var requests, refreshes atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch requests.Add(1) {
		case 1:
			w.WriteHeader(401)
		case 2:
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(429)
		default:
			if r.Header.Get("Authorization") != "Bearer synthetic-new" {
				t.Error("refreshed bearer")
			}
			_, _ = w.Write([]byte(`{"dataPoints":[]}`))
		}
	}))
	defer srv.Close()
	c := client(srv)
	c.Access = func(ctx context.Context, rejected string) (string, error) {
		if rejected != "" {
			refreshes.Add(1)
			return "synthetic-new", nil
		}
		return "synthetic-access", nil
	}
	if _, err := c.Fetch(context.Background(), kind("steps"), "raw", from, until); err != nil || requests.Load() != 3 || refreshes.Load() != 1 {
		t.Fatal("retry", err)
	}
}

func TestPaginationLoopMalformedAndProviderErrorsFailClosed(t *testing.T) {
	from, until := bounds(t)
	for _, tc := range []struct {
		name   string
		status int
		body   string
	}{{"loop", 200, `{"dataPoints":[],"nextPageToken":"synthetic-loop"}`}, {"malformed", 200, `{"dataPoints":[{"steps":{"count":"10"}}]}`}, {"permission", 403, `{"error":{"message":"synthetic-secret"}}`}, {"redirect", 302, `synthetic-secret`}} {
		t.Run(tc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tc.status)
				_, _ = w.Write([]byte(tc.body))
			}))
			defer srv.Close()
			rows, err := client(srv).Fetch(context.Background(), kind("steps"), "raw", from, until)
			if err == nil || len(rows) != 0 || strings.Contains(err.Error(), "synthetic-secret") {
				t.Fatal("error leaked or passed", err)
			}
		})
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Header().Set("Retry-After", "120"); w.WriteHeader(429) }))
	defer srv.Close()
	_, err := client(srv).Fetch(context.Background(), kind("steps"), "raw", from, until)
	if err == nil {
		t.Fatal("ignored retry budget")
	}
}

func TestMalformedPagesFailWithoutReturningEarlierRecords(t *testing.T) {
	from, until := bounds(t)
	for _, body := range []string{
		`null`, `[]`, `"synthetic-secret"`, `true`, `42`,
		`{"error":{"message":"synthetic-secret"}}`, `{"unrelated":[]}`,
		`{"dataPoints":null}`, `{"dataPoints":{}}`, `{"dataPoints":"synthetic-secret"}`,
		`{"dataPoints":[],"nextPageToken":null}`, `{"dataPoints":[],"nextPageToken":42}`,
		`{"dataPoints":[],"error":{}}`, `{"dataPoints":[]} trailing`,
	} {
		for _, later := range []bool{false, true} {
			t.Run(body+"/later="+strconv.FormatBool(later), func(t *testing.T) {
				var requests atomic.Int32
				srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					requests.Add(1)
					if later && r.URL.Query().Get("pageToken") == "" {
						_, _ = w.Write([]byte(`{"dataPoints":[{"heartRate":{"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"},"beatsPerMinute":"62"}}],"nextPageToken":"second"}`))
						return
					}
					_, _ = w.Write([]byte(body))
				}))
				defer srv.Close()
				rows, err := client(srv).Fetch(context.Background(), kind("heart-rate"), "raw", from, until)
				if err == nil || rows != nil || strings.Contains(err.Error(), "synthetic-secret") {
					t.Fatalf("malformed page accepted or response leaked: records=%d err=%v", len(rows), err)
				}
				wantRequests := int32(1)
				if later {
					wantRequests = 2
				}
				if requests.Load() != wantRequests {
					t.Fatal("did not exercise expected page")
				}
			})
		}
	}
	for _, body := range []string{`{}`, `{"dataPoints":[]}`, `{"nextPageToken":""}`} {
		t.Run("empty/"+body, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte(body)) }))
			defer srv.Close()
			rows, err := client(srv).Fetch(context.Background(), kind("heart-rate"), "raw", from, until)
			if err != nil || len(rows) != 0 {
				t.Fatal("valid protobuf empty page rejected", err)
			}
		})
	}
}

func fetchPoint(t *testing.T, id, point string) ([]health.Record, error) {
	t.Helper()
	from, until := bounds(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"dataPoints": []json.RawMessage{json.RawMessage(point)}})
	}))
	defer srv.Close()
	return client(srv).Fetch(context.Background(), kind(id), "raw", from, until)
}

func TestCollectorRequiresBoundedIntegerHeartRateAndSteps(t *testing.T) {
	for _, tc := range []struct {
		id, field, observation string
		valid, invalid         []string
	}{
		{"heart-rate", "beatsPerMinute", `"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"}`, []string{`1`, `"300"`}, []string{`0`, `"301"`, `1.5`, `"1.00000000000000001"`, `"9223372036854775808"`, `null`, ""}},
		{"steps", "count", `"interval":{"startTime":"2026-10-25T12:00:00Z","endTime":"2026-10-25T12:01:00Z"}`, []string{`0`, `"1000000"`}, []string{`1.5`, `"1000001"`, `"1.00000000000000001"`, `null`}},
		{"daily-resting-heart-rate", "beatsPerMinute", `"date":{"year":2026,"month":10,"day":25}`, []string{`"62"`}, []string{`1.5`, `"9223372036854775808"`, `null`, ""}},
	} {
		union := map[string]string{"heart-rate": "heartRate", "steps": "steps", "daily-resting-heart-rate": "dailyRestingHeartRate"}[tc.id]
		for _, valid := range []bool{false, true} {
			values := tc.invalid
			if valid {
				values = tc.valid
			}
			for _, value := range values {
				t.Run(tc.id+"/"+value, func(t *testing.T) {
					point := `{"` + union + `":{` + tc.observation
					if value != "" {
						point += `,"` + tc.field + `":` + value
					}
					point += `}}`
					rows, err := fetchPoint(t, tc.id, point)
					if valid {
						if err != nil || len(rows) != 1 {
							t.Fatalf("valid measurement rejected: %v", err)
						}
					} else if err == nil || rows != nil {
						t.Fatal("invalid measurement accepted", err)
					}
				})
			}
		}
	}
}

func TestCollectorBoundsOnlySampledRMSSDAndPreservesOptionalAbsence(t *testing.T) {
	for _, tc := range []struct {
		value string
		valid bool
	}{
		{`0`, false}, {`201`, false}, {`1`, true}, {`200`, true}, {`42.5`, true}, {`null`, true}, {"", true},
	} {
		t.Run(tc.value, func(t *testing.T) {
			point := `{"heartRateVariability":{"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"},"standardDeviationMilliseconds":60`
			if tc.value != "" {
				point += `,"rootMeanSquareOfSuccessiveDifferencesMilliseconds":` + tc.value
			}
			point += `}}`
			rows, err := fetchPoint(t, "heart-rate-variability", point)
			if tc.valid {
				if err != nil || len(rows) != 1 {
					t.Fatal("valid optional HRV rejected", err)
				}
				p, err := health.Decode(rows[0])
				if err != nil || p.HRV.SDNN == nil || ((tc.value == "" || tc.value == `null`) && p.HRV.RMSSD != nil) {
					t.Fatal("optional value fabricated", err)
				}
			} else if err == nil || rows != nil {
				t.Fatal("out-of-range sampled RMSSD accepted")
			}
		})
	}
	rows, err := fetchPoint(t, "daily-heart-rate-variability", `{"dailyHeartRateVariability":{"date":{"year":2026,"month":10,"day":25},"averageHeartRateVariabilityMilliseconds":201}}`)
	if err != nil || len(rows) != 1 {
		t.Fatal("sampled RMSSD bound applied to daily HRV", err)
	}
}

func TestCollectorRejectsImpossibleSleepSummaryAndKeepsPartialStages(t *testing.T) {
	for _, tc := range []struct {
		name, summary string
		valid         bool
	}{
		{"stage longer than session", `"stagesSummary":[{"type":"LIGHT","minutes":"240"}]`, false},
		{"combined stages exceed session", `"stagesSummary":[{"type":"LIGHT","minutes":"80"},{"type":"REM","minutes":"60"}]`, false},
		{"fractional stage", `"stagesSummary":[{"type":"LIGHT","minutes":1.5}]`, false},
		{"fractional segment count", `"stagesSummary":[{"type":"LIGHT","minutes":"60","count":"1.5"}]`, false},
		{"fractional asleep", `"minutesAsleep":"60.5"`, false},
		{"asleep exceeds session", `"minutesAsleep":"121"`, false},
		{"partial stages", `"stagesSummary":[{"type":"LIGHT","minutes":"60"}]`, true},
		{"complete stages", `"stagesSummary":[{"type":"LIGHT","minutes":"100"},{"type":"AWAKE","minutes":"20"}],"minutesAsleep":"100"`, true},
		{"no summary measurements", `"stagesSummary":[]`, true},
		{"absent stage minutes", `"stagesSummary":[{"type":"LIGHT"}]`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			point := `{"sleep":{"interval":{"startTime":"2026-10-25T10:00:00Z","endTime":"2026-10-25T12:00:00Z"},"summary":{` + tc.summary + `}}}`
			rows, err := fetchPoint(t, "sleep", point)
			if tc.valid {
				if err != nil || len(rows) != 1 {
					t.Fatal("valid sleep rejected", err)
				}
			} else if err == nil || rows != nil {
				t.Fatal("impossible sleep accepted")
			}
		})
	}
}

func TestCollectorChecksAsleepAgainstKnownStageSummaryBounds(t *testing.T) {
	for _, tc := range []struct {
		name, summary string
		valid         bool
	}{
		{"all awake and all asleep", `"minutesAsleep":"120","stagesSummary":[{"type":"AWAKE","minutes":"120"}]`, false},
		{"awake plus asleep exceeds session", `"minutesAsleep":"100","stagesSummary":[{"type":"AWAKE","minutes":"21"}]`, false},
		{"known sleeping exceeds asleep", `"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"70"},{"type":"DEEP","minutes":"31"}]`, false},
		{"classic sleeping exceeds asleep", `"minutesAsleep":"60","stagesSummary":[{"type":"ASLEEP","minutes":"61"}]`, false},
		{"restless is not asleep", `"minutesAsleep":"100","stagesSummary":[{"type":"RESTLESS","minutes":"21"}]`, false},
		{"partial stages below known asleep", `"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"60"},{"type":"AWAKE","minutes":"10"}]`, true},
		{"missing stage totals", `"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"60"},{"type":"REM"}]`, true},
		{"known stages equal asleep", `"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"70"},{"type":"DEEP","minutes":"30"},{"type":"AWAKE","minutes":"20"}]`, true},
		{"classic summary", `"minutesAsleep":"90","stagesSummary":[{"type":"ASLEEP","minutes":"90"},{"type":"RESTLESS","minutes":"20"},{"type":"AWAKE","minutes":"10"}]`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rows, err := fetchPoint(t, "sleep", `{"sleep":{"interval":{"startTime":"2026-10-25T10:00:00Z","endTime":"2026-10-25T12:00:00Z"},"summary":{`+tc.summary+`}}}`)
			if tc.valid {
				if err != nil || len(rows) != 1 {
					t.Fatalf("valid partial summary rejected: %v", err)
				}
			} else if err == nil || rows != nil {
				t.Fatal("contradictory summary accepted", err)
			}
		})
	}
}

func TestCollectorPreservesOmittedStepCountAsObservedTrueZero(t *testing.T) {
	point := `{"steps":{"interval":{"startTime":"2026-10-25T12:00:00Z","endTime":"2026-10-25T12:01:00Z"}}}`
	rows, err := fetchPoint(t, "steps", point)
	if err != nil || len(rows) != 1 {
		t.Fatal("documented stationary interval rejected", err)
	}
	if string(rows[0].Raw) != point {
		t.Fatal("raw record changed")
	}
	p, err := health.Decode(rows[0])
	if err != nil || p.Steps == nil || p.Steps.Count != nil {
		t.Fatal("omitted raw count not preserved", err)
	}
}

func TestCollectorValidatesEveryShortAwakeningWithinSession(t *testing.T) {
	for _, tc := range []struct {
		name, awakenings string
		valid            bool
	}{
		{"outside session", `[{"type":"AWAKE","startTime":"2026-10-25T09:00:00Z","endTime":"2026-10-25T09:05:00Z"}]`, false},
		{"past session end", `[{"type":"AWAKE","startTime":"2026-10-25T11:55:00Z","endTime":"2026-10-25T12:05:00Z"}]`, false},
		{"reversed", `[{"type":"AWAKE","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T10:30:00Z"}]`, false},
		{"empty interval", `[{"type":"AWAKE","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T11:00:00Z"}]`, false},
		{"missing start", `[{"type":"AWAKE","endTime":"2026-10-25T11:00:00Z"}]`, false},
		{"unknown type", `[{"type":"NOT_A_STAGE","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T11:05:00Z"}]`, false},
		{"explicit nonawake type", `[{"type":"LIGHT","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T11:05:00Z"}]`, true},
		{"nonawake missing end", `[{"type":"LIGHT","startTime":"2026-10-25T11:00:00Z"}]`, false},
		{"nonawake outside session", `[{"type":"REM","startTime":"2026-10-25T11:55:00Z","endTime":"2026-10-25T12:05:00Z"}]`, false},
		{"crosses adjacent stages", `[{"type":"AWAKE","startTime":"2026-10-25T10:55:00Z","endTime":"2026-10-25T11:05:00Z"}]`, true},
		{"overlapping events", `[{"type":"AWAKE","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T11:05:00Z"},{"type":"AWAKE","startTime":"2026-10-25T11:03:00Z","endTime":"2026-10-25T11:10:00Z"}]`, true},
	} {
		for _, detail := range []string{
			`"stages":[{"type":"LIGHT","startTime":"2026-10-25T10:00:00Z","endTime":"2026-10-25T11:00:00Z"},{"type":"REM","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T12:00:00Z"}]`,
			`"summary":{"minutesAsleep":"100"}`,
		} {
			t.Run(tc.name+"/"+detail, func(t *testing.T) {
				rows, err := fetchPoint(t, "sleep", `{"sleep":{"interval":{"startTime":"2026-10-25T10:00:00Z","endTime":"2026-10-25T12:00:00Z"},`+detail+`,"shortAwakenings":`+tc.awakenings+`}}`)
				if tc.valid {
					if err != nil || len(rows) != 1 {
						t.Fatalf("valid awakening rejected: %v", err)
					}
				} else if err == nil || rows != nil {
					t.Fatal("invalid awakening accepted", err)
				}
			})
		}
	}
}

func TestCollectorRejectsImpossibleSleepStageTimelines(t *testing.T) {
	for _, stages := range []string{
		`[{"type":"LIGHT","startTime":"2026-10-25T09:00:00Z","endTime":"2026-10-25T12:00:00Z"}]`,
		`[{"type":"LIGHT","startTime":"2026-10-25T10:00:00Z","endTime":"2026-10-25T11:30:00Z"},{"type":"REM","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T12:00:00Z"}]`,
		`[{"type":"LIGHT","startTime":"2026-10-25T11:00:00Z","endTime":"2026-10-25T10:00:00Z"}]`,
	} {
		t.Run(stages, func(t *testing.T) {
			rows, err := fetchPoint(t, "sleep", `{"sleep":{"interval":{"startTime":"2026-10-25T10:00:00Z","endTime":"2026-10-25T12:00:00Z"},"stages":`+stages+`}}`)
			if err == nil || rows != nil {
				t.Fatal("impossible timeline accepted")
			}
		})
	}
}

func TestCollectorAcceptsWholeProtoJSONIntegerNumbersWithoutRoundingFractions(t *testing.T) {
	for _, tc := range []struct {
		value string
		valid bool
	}{
		{`1e2`, true}, {`"1e2"`, true}, {`1.0`, true}, {`"300.0"`, true},
		{`"1.000000000000000000000000000000000000000000000000001"`, false},
		{`"1e-1000000"`, false}, {`"1/1"`, false}, {`"1_0"`, false},
	} {
		t.Run(tc.value, func(t *testing.T) {
			rows, err := fetchPoint(t, "heart-rate", `{"heartRate":{"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"},"beatsPerMinute":`+tc.value+`}}`)
			if tc.valid {
				if err != nil || len(rows) != 1 {
					t.Fatal("valid whole ProtoJSON integer rejected", err)
				}
			} else if err == nil || rows != nil {
				t.Fatal("fractional or malformed integer accepted")
			}
		})
	}
}

func TestMalformedMeasurementOnLaterPageDoesNotReturnEarlierRecords(t *testing.T) {
	from, until := bounds(t)
	for _, stream := range []string{"raw", "reconciled"} {
		t.Run(stream, func(t *testing.T) {
			var requests atomic.Int32
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				requests.Add(1)
				bpm, next := "62", "second"
				if r.URL.Query().Get("pageToken") != "" {
					bpm, next = "301", ""
				}
				point := json.RawMessage(`{"heartRate":{"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"},"beatsPerMinute":"` + bpm + `"}}`)
				_ = json.NewEncoder(w).Encode(map[string]any{"dataPoints": []json.RawMessage{point}, "nextPageToken": next})
			}))
			defer srv.Close()
			rows, err := client(srv).Fetch(context.Background(), kind("heart-rate"), stream, from, until)
			if err == nil || rows != nil || requests.Load() != 2 {
				t.Fatal("partial collection escaped invalid measurement page", err)
			}
		})
	}
}

func TestCollectorAcceptsAllSupportedSyntheticV4Shapes(t *testing.T) {
	for _, tc := range []struct{ id, raw string }{
		{"sleep", `{"sleep":{"interval":{"startTime":"2026-10-24T22:00:00Z","endTime":"2026-10-25T06:00:00Z"},"type":"STAGES","summary":{"minutesAsleep":"420","stagesSummary":[{"type":"LIGHT","minutes":"240","count":"3"},{"type":"DEEP","minutes":"90"},{"type":"REM","minutes":"90"},{"type":"AWAKE","minutes":"60"}]}}}`},
		{"daily-heart-rate-variability", `{"dailyHeartRateVariability":{"date":{"year":2026,"month":10,"day":25},"entropy":2.3}}`},
		{"heart-rate-variability", `{"heartRateVariability":{"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"},"standardDeviationMilliseconds":60}}`},
		{"daily-resting-heart-rate", `{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":25},"beatsPerMinute":"62"}}`},
		{"steps", `{"steps":{"interval":{"startTime":"2026-10-25T12:00:00Z","endTime":"2026-10-25T12:01:00Z"},"count":"0"}}`},
		{"heart-rate", `{"heartRate":{"sampleTime":{"physicalTime":"2026-10-25T12:00:00Z"},"beatsPerMinute":"62"}}`},
		{"exercise", `{"exercise":{"interval":{"startTime":"2026-10-25T12:00:00Z","endTime":"2026-10-25T13:00:00Z"},"exerciseType":"STRENGTH_TRAINING","activeDuration":"3000s"}}`},
	} {
		t.Run(tc.id, func(t *testing.T) {
			rows, err := fetchPoint(t, tc.id, tc.raw)
			if err != nil || len(rows) != 1 {
				t.Fatal("valid v4 shape rejected", err)
			}
		})
	}
}

func TestCancellationAndUnsupported(t *testing.T) {
	from, until := bounds(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(501) }))
	defer srv.Close()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := client(srv).Fetch(ctx, kind("steps"), "raw", from, until); err == nil {
		t.Fatal("cancel ignored")
	}
	_, err := client(srv).Fetch(context.Background(), kind("steps"), "raw", from, until)
	var api *health.APIError
	if !errors.As(err, &api) || api.Status != 501 {
		t.Fatal("unsupported not explicit", err)
	}
}

func TestSpringDSTAndRedirectDoesNotExposeBearer(t *testing.T) {
	loc, _ := time.LoadLocation("Europe/London")
	from, _ := time.ParseInLocation("2006-01-02", "2026-03-29", loc)
	until := from.AddDate(0, 0, 1)
	var redirected atomic.Bool
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { redirected.Store(true) }))
	defer target.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		filter := r.URL.Query().Get("filter")
		if !strings.Contains(filter, `>= "2026-03-29T00:00:00Z"`) || !strings.Contains(filter, `< "2026-03-29T23:00:00Z"`) {
			t.Error("23-hour DST boundary", filter)
		}
		http.Redirect(w, r, target.URL, http.StatusFound)
	}))
	defer server.Close()
	if _, err := client(server).Fetch(context.Background(), kind("steps"), "raw", from, until); err == nil || redirected.Load() {
		t.Fatal("redirect followed with credentials", err)
	}
}
