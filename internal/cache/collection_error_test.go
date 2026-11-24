package cache_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

type collectionFailureFetcher struct{ err error }

func (f collectionFailureFetcher) Fetch(_ context.Context, k health.Kind, _ string, _, _ time.Time) ([]health.Record, error) {
	if k.ID == "sleep" {
		return nil, f.err
	}
	return nil, nil
}

func TestSyncForeignErrorCodesRetainPriorSleepAndStayPrivate(t *testing.T) {
	for _, tc := range []struct {
		name         string
		err          error
		code, status string
	}{
		{"foreign matching text", errors.New("sleep duration exceeds session"), "request_failed", "unavailable"},
		{"foreign secret", fmt.Errorf("synthetic-private-token: %w", errors.New("invalid Google Health page")), "request_failed", "unavailable"},
		{"API secret code", &health.APIError{Status: 403, Code: "synthetic-private-token"}, "permission_denied", "unavailable"},
		{"wrapped unsupported", fmt.Errorf("synthetic-private-token: %w", &health.APIError{Status: 501, Code: "synthetic-private-token"}), "unsupported", "unsupported"},
		{"nil API error", (*health.APIError)(nil), "request_failed", "unavailable"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			old := cache.Empty()
			old.Account, old.Timezone = "synthetic-user", "UTC"
			lastSuccess := from.Add(-time.Hour)
			for _, stream := range []string{"raw", "reconciled"} {
				old.Records = append(old.Records, testutil.Record(t, "sleep", stream, "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"}}}`))
				old.Coverage = append(old.Coverage, cache.Coverage{Type: "sleep", Stream: stream, Date: "2026-10-12", Status: "ok", SuccessAt: &lastSuccess, Count: 1})
			}
			if err := store.Save(old); err != nil {
				t.Fatal(err)
			}
			result, err := cache.Sync(context.Background(), store, collectionFailureFetcher{tc.err}, resolveSyntheticAccount("synthetic-user"), from, from.AddDate(0, 0, 1))
			if err == nil || result.Complete {
				t.Fatal("failure advertised complete")
			}
			loaded, err := store.Load()
			if err != nil || !reflect.DeepEqual(loaded.Records, old.Records) {
				t.Fatal("prior sleep lost", err)
			}
			for _, coverage := range [][]cache.Coverage{result.Outcomes, loaded.Coverage} {
				for _, c := range coverage {
					if c.Type == "sleep" && (c.Status != tc.status || c.Error != tc.code || c.Count != 1 || c.SuccessAt == nil || !c.SuccessAt.Equal(lastSuccess)) {
						t.Fatal("unsafe code or lost prior metadata", c)
					}
				}
				encoded, err := json.Marshal(coverage)
				if err != nil || strings.Contains(string(encoded), "synthetic-private") {
					t.Fatal("foreign error text leaked", err)
				}
			}
		})
	}
}

func TestCollectionValidationCodesRetainEncryptedSleepSnapshot(t *testing.T) {
	const interval = `"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"}`
	for _, tc := range []struct{ name, body, code string }{
		{"invalid sleep interval", `{"dataPoints":[{"sleep":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T10:00:00Z"}}}]}`, "invalid_sleep_interval"},
		{"invalid short awakening", `{"dataPoints":[{"sleep":{` + interval + `,"shortAwakenings":[{"type":"NOT_A_STAGE","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}]}}]}`, "short_awakening_invalid_type"},
		{"short awakening missing type", `{"dataPoints":[{"sleep":{` + interval + `,"shortAwakenings":[{"startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}]}}]}`, "short_awakening_missing_type"},
		{"short awakening unspecified type", `{"dataPoints":[{"sleep":{` + interval + `,"shortAwakenings":[{"type":"SLEEP_STAGE_TYPE_UNSPECIFIED","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}]}}]}`, "short_awakening_unspecified_type"},
		{"nonawake short missing time", `{"dataPoints":[{"sleep":{` + interval + `,"shortAwakenings":[{"type":"LIGHT","startTime":"2026-10-12T11:00:00Z"}]}}]}`, "short_awakening_missing_time"},
		{"nonawake short reversed time", `{"dataPoints":[{"sleep":{` + interval + `,"shortAwakenings":[{"type":"DEEP","startTime":"2026-10-12T11:05:00Z","endTime":"2026-10-12T11:00:00Z"}]}}]}`, "short_awakening_invalid_time_order"},
		{"nonawake short outside session", `{"dataPoints":[{"sleep":{` + interval + `,"shortAwakenings":[{"type":"REM","startTime":"2026-10-12T11:55:00Z","endTime":"2026-10-12T12:05:00Z"}]}}]}`, "short_awakening_outside_session"},
		{"nonawake short contradictory summary", `{"dataPoints":[{"sleep":{` + interval + `,"shortAwakenings":[{"type":"RESTLESS","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}],"summary":{"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"101"}]}}}]}`, "invalid_sleep_summary"},
		{"invalid sleep stage interval", `{"dataPoints":[{"sleep":{` + interval + `,"stages":[{"type":"LIGHT","startTime":"2026-10-12T09:00:00Z","endTime":"2026-10-12T11:05:00Z"}]}}]}`, "invalid_sleep_stage_interval"},
		{"invalid data point", `{"dataPoints":[{"name":"synthetic-private-name","dataPointName":"synthetic-private-name","sleep":{"interval":{"startTime":"synthetic-private-time"}}}]}`, "invalid_data_point"},
		{"invalid page", `{"dataPoints":[],"synthetic-private-field":"synthetic-private-value"}`, "invalid_page"},
		{"repeated page token", `{"dataPoints":[],"nextPageToken":"synthetic-private-token"}`, "repeated_page_token"},
		{"invalid integer health field", `{"dataPoints":[{"sleep":{` + interval + `,"summary":{"minutesAsleep":"9223372036854775808"}}}]}`, "invalid_integer_field"},
		{"invalid numeric health field", `{"dataPoints":[{"sleep":{` + interval + `},"dailyHeartRateVariability":{"averageHeartRateVariabilityMilliseconds":"synthetic-private-number"}}]}`, "invalid_numeric_field"},
		{"identified point changed", `{"dataPoints":[{"name":"synthetic-private-name","dataPointName":"synthetic-private-name","sleep":{` + interval + `,"summary":{"minutesAsleep":"100"}}}]}`, "data_point_changed_during_pagination"},
		{"asleep exceeds session", `{"dataPoints":[{"sleep":{` + interval + `,"summary":{"minutesAsleep":"121"}}}]}`, "invalid_sleep_summary"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			old := cache.Empty()
			old.Account, old.Timezone = "synthetic-user", "UTC"
			lastSuccess := from.Add(-time.Hour)
			for _, stream := range []string{"raw", "reconciled"} {
				old.Records = append(old.Records, testutil.Record(t, "sleep", stream, "2026-10-12", `{"sleep":{`+interval+`,"shortAwakenings":[{"type":"LIGHT","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}],"summary":{"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"100"},{"type":"AWAKE","minutes":"20"}]}}}`))
				old.Coverage = append(old.Coverage, cache.Coverage{Type: "sleep", Stream: stream, Date: "2026-10-12", Status: "ok", AttemptAt: lastSuccess, SuccessAt: &lastSuccess, Count: 1})
			}
			if err := store.Save(old); err != nil {
				t.Fatal(err)
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if !strings.Contains(r.URL.Path, "/sleep/") {
					fmt.Fprint(w, "{}")
					return
				}
				if r.URL.Query().Get("pageToken") == "" {
					fmt.Fprint(w, `{"dataPoints":[{"name":"synthetic-private-name","dataPointName":"synthetic-private-name","sleep":{`+interval+`}}],"nextPageToken":"synthetic-private-token"}`)
					return
				}
				fmt.Fprint(w, tc.body)
			}))
			defer server.Close()
			provider := health.New(func(context.Context, string) (string, error) { return "synthetic-access", nil })
			provider.BaseURL, provider.HTTP = server.URL, server.Client()
			result, err := cache.Sync(context.Background(), store, provider, resolveSyntheticAccount("synthetic-user"), from, from.AddDate(0, 0, 1))
			if err == nil || result.Complete || result.Records != 0 {
				t.Fatal("failed collection returned partial success", result, err)
			}
			loaded, err := store.Load()
			if err != nil || !reflect.DeepEqual(loaded.Records, old.Records) {
				t.Fatal("prior records replaced by partial page", err)
			}
			for _, coverage := range [][]cache.Coverage{result.Outcomes, loaded.Coverage} {
				failures := 0
				for _, c := range coverage {
					if c.Type != "sleep" {
						if c.Status != "ok" || c.Error != "" {
							t.Fatal("unaffected stream failed", c)
						}
						continue
					}
					failures++
					if c.Status != "unavailable" || c.Error != tc.code || c.Count != 1 || c.SuccessAt == nil || !c.SuccessAt.Equal(lastSuccess) || !c.AttemptAt.After(lastSuccess) {
						t.Fatalf("lost safe diagnostic or prior success: got %+v, want code %s", c, tc.code)
					}
				}
				if failures != 2 {
					t.Fatal("missing sleep stream coverage", failures)
				}
			}
			encoded, err := json.Marshal(result)
			if err != nil {
				t.Fatal(err)
			}
			for _, private := range []string{"synthetic-private", "synthetic-access", "9223372036854775808", "dataPoints", "minutesAsleep"} {
				if strings.Contains(string(encoded), private) {
					t.Fatal("diagnostic disclosed provider contents", private)
				}
			}
		})
	}
}
