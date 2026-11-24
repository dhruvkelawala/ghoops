package cache_test

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/report"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestHTTPMalformedPageRetainsEncryptedSnapshotAndMarksSummaryUnavailable(t *testing.T) {
	for _, response := range []string{"null", `{"error":{"code":500}}`, `{"dataPoints":null}`, `{"dataPoints":{}}`, "later-page-null"} {
		t.Run(response, func(t *testing.T) {
			from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
			until := from.AddDate(0, 0, 1)
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			old := state(t)
			old.Timezone = "UTC"
			reconciled := old.Records[0]
			reconciled.Stream = "reconciled"
			old.Records = append(old.Records, reconciled)
			lastSuccess := time.Now().Add(-time.Hour)
			for _, stream := range []string{"raw", "reconciled"} {
				old.Coverage = append(old.Coverage, cache.Coverage{Type: "steps", Stream: stream, Date: "2026-10-12", Status: "ok", AttemptAt: lastSuccess, SuccessAt: &lastSuccess, Count: 1})
			}
			if err := store.Save(old); err != nil {
				t.Fatal(err)
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body := "{}"
				if strings.Contains(r.URL.Path, "/steps/") {
					body = response
					if response == "later-page-null" {
						body = "null"
						if r.URL.Query().Get("pageToken") == "" {
							body = `{"dataPoints":[{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":"999"}}],"nextPageToken":"synthetic-next"}`
						}
					}
				}
				fmt.Fprint(w, body)
			}))
			defer server.Close()
			provider := health.New(func(context.Context, string) (string, error) { return "synthetic-access", nil })
			provider.BaseURL = server.URL
			result, err := cache.Sync(context.Background(), store, provider, resolveSyntheticAccount("synthetic-user"), from, until)
			if err == nil || result.Complete {
				t.Fatal("malformed HTTP response passed collection", result, err)
			}
			loaded, err := store.Load()
			if err != nil || !reflect.DeepEqual(loaded.Records, old.Records) {
				t.Fatal("prior encrypted records were lost or partial new pages escaped", err)
			}
			for _, coverage := range loaded.Coverage {
				if coverage.Type == "steps" && (coverage.Status != "unavailable" || coverage.Count != 1 || coverage.SuccessAt == nil || !coverage.SuccessAt.Equal(lastSuccess)) {
					t.Fatal("failure erased prior success/count metadata", coverage)
				}
			}
			metric := report.Days(loaded, from, until, time.Now()).Days[0].Steps
			if metric.Status != "unavailable" || !metric.Stale || metric.Value == nil || *metric.Value != 123 {
				t.Fatal("retained data falsely reported as fresh available", metric)
			}
		})
	}
}

func TestMovedSleepCoverageRemainsStaleThroughPublicSummary(t *testing.T) {
	from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
	oldFrom := from.AddDate(0, 0, -2)
	store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	old := cache.Empty()
	old.Account, old.Timezone = "synthetic-user", "UTC"
	old.Records = []health.Record{namedIntervalRecord(t, "sleep", "reconciled", "2026-10-10", "synthetic-moved")}
	lastSuccess := time.Now().Add(-time.Hour)
	old.Coverage = []cache.Coverage{{Type: "sleep", Stream: "reconciled", Date: "2026-10-10", Status: "ok", AttemptAt: lastSuccess, SuccessAt: &lastSuccess, Count: 1}}
	if err := store.Save(old); err != nil {
		t.Fatal(err)
	}
	fetcher := movedRecordFetcher{kind: "sleep", stream: "reconciled", records: []health.Record{namedIntervalRecord(t, "sleep", "reconciled", "2026-10-12", "synthetic-moved")}}
	if _, err := cache.Sync(context.Background(), store, fetcher, resolveSyntheticAccount("synthetic-user"), from, from.AddDate(0, 0, 1)); err != nil {
		t.Fatal(err)
	}
	loaded, err := store.Load()
	if err != nil {
		t.Fatal(err)
	}
	historical := report.Days(loaded, oldFrom, oldFrom.AddDate(0, 0, 1), time.Now()).Days[0].Sleep.Duration
	if historical.Status != "stale" || !historical.Stale || historical.Value != nil || historical.LastSync == nil || !historical.LastSync.Equal(lastSuccess) {
		t.Fatal("old date falsely claims complete sleep after timestamp move", historical)
	}
	fresh := report.Days(loaded, from, from.AddDate(0, 0, 1), time.Now()).Days[0].Sleep.Duration
	if fresh.Status != "available" || fresh.Stale || fresh.Value == nil || *fresh.Value != 60 {
		t.Fatal("new date does not expose refreshed observation", fresh)
	}
}
