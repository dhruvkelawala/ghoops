package cache_test

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/report"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestKnownNonAwakeShortSegmentsSyncPreservesMeasuredSleep(t *testing.T) {
	for _, stage := range []string{"LIGHT", "DEEP", "REM", "ASLEEP", "RESTLESS"} {
		t.Run(stage, func(t *testing.T) {
			from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
			until := from.AddDate(0, 0, 1)
			point := `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"stages":[{"type":"LIGHT","startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"}],"shortAwakenings":[{"type":"` + stage + `","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}],"summary":{"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"60"},{"type":"DEEP","minutes":"30"},{"type":"REM","minutes":"10"},{"type":"AWAKE","minutes":"20"}]}}}`
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/v4/users/me/dataTypes/sleep/dataPoints" || r.URL.Path == "/v4/users/me/dataTypes/sleep/dataPoints:reconcile" {
					fmt.Fprint(w, `{"synthetic_fixture":true,"dataPoints":[`+point+`]}`)
					return
				}
				fmt.Fprint(w, "{}")
			}))
			defer server.Close()
			provider := health.New(func(context.Context, string) (string, error) { return "synthetic-access", nil })
			provider.BaseURL, provider.HTTP = server.URL, server.Client()
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			result, err := cache.Sync(context.Background(), store, provider, resolveSyntheticAccount("synthetic-user"), from, until)
			if err != nil || !result.Complete || result.Records != 2 {
				t.Fatalf("schema-shaped short segments rejected: %+v, %v", result, err)
			}
			loaded, err := store.Load()
			if err != nil || len(loaded.Records) != 2 {
				t.Fatal("encrypted snapshot not readable", err)
			}
			for _, stream := range []string{"raw", "reconciled"} {
				foundRecord, foundCoverage := false, false
				for _, row := range loaded.Records {
					if row.Type == "sleep" && row.Stream == stream {
						foundRecord = true
						if !row.Synthetic || !bytes.Equal(row.Raw, []byte(point)) {
							t.Fatal("raw short segment retagged or mutated", stream)
						}
					}
				}
				for _, coverage := range [][]cache.Coverage{result.Outcomes, loaded.Coverage} {
					foundCoverage = false
					for _, c := range coverage {
						if c.Type == "sleep" && c.Stream == stream {
							foundCoverage = true
							if c.Status != "ok" || c.Error != "" || c.Count != 1 || c.SuccessAt == nil || !c.SuccessAt.Equal(c.AttemptAt) {
								t.Fatal("sleep stream not fresh and successful", c)
							}
						}
					}
					if !foundCoverage {
						t.Fatal("sleep coverage absent", stream)
					}
				}
				if !foundRecord {
					t.Fatal("sleep record absent", stream)
				}
			}
			ciphertext, err := os.ReadFile(filepath.Join(store.Dir, "records.enc"))
			if err != nil || bytes.Contains(ciphertext, []byte("shortAwakenings")) || bytes.Contains(ciphertext, []byte("synthetic-user")) {
				t.Fatal("sleep snapshot is not encrypted", err)
			}
			summary := report.Days(loaded, from, until, time.Now())
			sleep := summary.Days[0].Sleep
			if !strings.Contains(strings.Join(sleep.Duration.Warnings, ";"), "non-AWAKE short-awakening segments preclude sleep timeline interpretation") {
				t.Fatal("timeline ambiguity not disclosed", sleep.Duration.Warnings)
			}
			if !summary.Synthetic || sleep.Duration.Status != "available" || sleep.Duration.Stale || sleep.Duration.Value == nil || *sleep.Duration.Value != 100 {
				t.Fatal("observed asleep duration lost or replaced by time in bed", sleep.Duration)
			}
			for key, want := range map[string]float64{"LIGHT": 60, "DEEP": 30, "REM": 10, "AWAKE": 20} {
				m := sleep.Stages[key]
				if m.Status != "available" || m.Stale || m.Value == nil || *m.Value != want {
					t.Fatal("measured stage summary lost or changed by short segment", key, m)
				}
			}
		})
	}
}
