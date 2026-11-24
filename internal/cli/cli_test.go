package cli_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func run(t *testing.T, args []string, options cli.Options) (int, string, string) {
	t.Helper()
	var out, err bytes.Buffer
	code := cli.Run(context.Background(), args, strings.NewReader(""), &out, &err, options)
	return code, out.String(), err.String()
}
func TestCLIHelpVersionUsageAndEmptyOfflineSummary(t *testing.T) {
	dir := filepath.Join(testutil.Dir(t), "state")
	opts := cli.Options{Version: "synthetic-version", Revision: "synthetic-revision", Vault: &testutil.Vault{}}
	for _, args := range [][]string{{"help"}, {"--help"}, {"sync", "--help"}, {"version", "--json"}, {"doctor", "--offline", "--json"}, {"today", "--json"}} {
		code, out, err := run(t, append([]string{"--state-dir", dir}, args...), opts)
		if code != 0 || out == "" || err != "" {
			t.Fatal(args, code, out, err)
		}
		if args[0] == "today" {
			if !strings.Contains(out, `"status":"not_synced"`) || !strings.Contains(out, `"value":null`) {
				t.Fatal("missing status", out)
			}
		}
	}
	for _, args := range [][]string{{"unknown"}, {"sync", "--days", "0"}, {"summary", "--from", "2026-02-30", "--to", "2026-03-01"}, {"today", "--days", "7"}, {"auth", "login"}, {"sync", "--days", "7", "--from", "2026-01-01", "--to", "2026-01-02"}} {
		code, _, _ := run(t, append([]string{"--state-dir", dir}, args...), opts)
		if code != 2 {
			t.Fatal(args, code)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "records.enc")); !os.IsNotExist(err) {
		t.Fatal("offline summary created cache")
	}
}

func TestCLIAuthorizationMissingAndLiveEmptyCannotPass(t *testing.T) {
	dir := testutil.Dir(t)
	v := &testutil.Vault{}
	opts := cli.Options{Vault: v}
	code, _, stderr := run(t, []string{"--state-dir", dir, "--json", "doctor", "--live"}, opts)
	if code != 1 || !strings.Contains(stderr, "authorization missing") {
		t.Fatal("missing auth live passed", code, stderr)
	}
	s := auth.Session{Client: auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"}, AccessToken: "synthetic-access", RefreshToken: "synthetic-refresh", ExpiresAt: time.Now().Add(time.Hour), Scopes: auth.Scopes, HealthUserID: "synthetic-user"}
	b, _ := json.Marshal(s)
	_ = v.Set(secure.Service(dir)+".oauth", b)
	opts.Fetcher = emptySyntheticFetcher{}
	code, stdout, stderr := run(t, []string{"--state-dir", dir, "--json", "doctor", "--live"}, opts)
	if code != 1 || !strings.Contains(stdout, `"complete":false`) || !strings.Contains(stderr, "no empty or synthetic pass") || strings.Contains(stdout, "synthetic-secret") {
		t.Fatal("empty live passed", code, stdout, stderr)
	}
	opts.Fetcher = nonemptySyntheticFetcher{record: testutil.Record(t, "steps", "raw", time.Now().In(time.FixedZone("synthetic", 0)).Format("2006-01-02"), `{"steps":{"count":"1"}}`)}
	code, _, stderr = run(t, []string{"--state-dir", dir, "--json", "doctor", "--live"}, opts)
	if code != 1 || !strings.Contains(stderr, "explicitly synthetic fixture") {
		t.Fatal("synthetic fixture live gate did not reject", code, stderr)
	}
}

type emptySyntheticFetcher struct{}

func (emptySyntheticFetcher) Fetch(context.Context, health.Kind, string, time.Time, time.Time) ([]health.Record, error) {
	return nil, nil
}

type nonemptySyntheticFetcher struct{ record health.Record }

func (f nonemptySyntheticFetcher) Fetch(_ context.Context, k health.Kind, stream string, from, until time.Time) ([]health.Record, error) {
	if k.ID == f.record.Type {
		r := f.record
		r.Stream = stream
		r.Date = from.Format("2006-01-02")
		return []health.Record{r}, nil
	}
	return nil, nil
}

func TestCLIPrivateExportRefusesOverwrite(t *testing.T) {
	dir := testutil.Dir(t)
	v := &testutil.Vault{}
	s := cache.Empty()
	s.Records = append(s.Records, testutil.Record(t, "steps", "raw", "2026-10-12", `{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":"123"}}`))
	if err := (cache.Store{Dir: dir, Vault: v}).Save(s); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(testutil.Dir(t), "synthetic-export.json")
	opts := cli.Options{Vault: v, Now: func() time.Time { return time.Date(2026, 10, 13, 12, 0, 0, 0, time.UTC) }}
	args := []string{"--state-dir", dir, "data", "export", "--from", "2026-10-12", "--to", "2026-10-12", "--output", path}
	code, stdout, stderr := run(t, args, opts)
	if code != 0 || stderr != "" || !strings.Contains(stdout, `"exported_records":1`) {
		t.Fatal(code, stdout, stderr)
	}
	fi, _ := os.Stat(path)
	if fi.Mode().Perm() != 0600 {
		t.Fatal("export permissions")
	}
	code, _, _ = run(t, args, opts)
	if code != 1 {
		t.Fatal("overwrote private export")
	}
}

func TestSyntheticEndToEndCollectSummarizeExport(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	session := auth.Session{Client: auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"}, AccessToken: "synthetic-access", RefreshToken: "synthetic-refresh", ExpiresAt: time.Now().Add(time.Hour), Scopes: auth.Scopes, HealthUserID: "synthetic-user"}
	encoded, _ := json.Marshal(session)
	_ = vault.Set(secure.Service(dir)+".oauth", encoded)
	fixtures := map[string]string{
		"sleep":                        `"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T06:00:00Z"},"summary":{"minutesAsleep":"420","stagesSummary":[{"type":"LIGHT","minutes":"240"},{"type":"DEEP","minutes":"120"},{"type":"REM","minutes":"60"},{"type":"AWAKE","minutes":"60"}]}}`,
		"daily-heart-rate-variability": `"dailyHeartRateVariability":{"date":{"year":2026,"month":10,"day":12},"averageHeartRateVariabilityMilliseconds":42}`,
		"heart-rate-variability":       `"heartRateVariability":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"rootMeanSquareOfSuccessiveDifferencesMilliseconds":44}`,
		"daily-resting-heart-rate":     `"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12},"beatsPerMinute":"56"}`,
		"steps":                        `"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":"123"}`,
		"heart-rate":                   `"heartRate":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"beatsPerMinute":"62"}`,
		"exercise":                     `"exercise":{"exerciseType":"WEIGHTS","activeDuration":"3000s","interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T13:00:00Z"}}`,
	}
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.Method != "GET" || r.Header.Get("Authorization") != "Bearer synthetic-access" {
			t.Error("read-only authenticated request")
		}
		parts := strings.Split(r.URL.Path, "/")
		if len(parts) != 7 {
			t.Error("v4 route", r.URL.Path)
			w.WriteHeader(404)
			return
		}
		fixture, ok := fixtures[parts[5]]
		if !ok {
			t.Error("unexpected type")
			w.WriteHeader(404)
			return
		}
		_, _ = w.Write([]byte(`{"synthetic_fixture":true,"dataPoints":[{"dataSource":{"device":{"formFactor":"WATCH","displayName":"synthetic fixture"}},` + fixture + `}]}`))
	}))
	defer server.Close()
	manager := auth.New(vault, dir)
	provider := health.New(manager.Access)
	provider.BaseURL = server.URL
	options := cli.Options{Vault: vault, Auth: manager, Fetcher: provider, Now: func() time.Time { return time.Date(2026, 10, 13, 12, 0, 0, 0, time.UTC) }}
	code, out, stderr := run(t, []string{"--state-dir", dir, "sync", "--from", "2026-10-12", "--to", "2026-10-12", "--json"}, options)
	if code != 0 || stderr != "" || calls.Load() != 10 {
		t.Fatal("synthetic collection", code, calls.Load(), out, stderr)
	}
	cacheBytes, _ := os.ReadFile(filepath.Join(dir, "records.enc"))
	if bytes.Contains(cacheBytes, []byte("synthetic")) || bytes.Contains(cacheBytes, []byte("steps")) {
		t.Fatal("unencrypted end-to-end cache")
	}
	code, out, stderr = run(t, []string{"--state-dir", dir, "today", "--date", "2026-10-12", "--json"}, options)
	var result struct {
		Days []struct {
			Steps struct {
				Value *float64 `json:"value"`
			} `json:"steps"`
			Sleep struct {
				Minutes struct {
					Value *float64 `json:"value"`
				} `json:"asleep_minutes"`
			} `json:"sleep"`
		}
	}
	if code != 0 || stderr != "" || json.Unmarshal([]byte(out), &result) != nil || len(result.Days) != 1 || result.Days[0].Steps.Value == nil || *result.Days[0].Steps.Value != 123 || result.Days[0].Sleep.Minutes.Value == nil || *result.Days[0].Sleep.Minutes.Value != 420 {
		t.Fatal("synthetic summary", code, stderr)
	}
	code, out, stderr = run(t, []string{"--state-dir", dir, "data", "export", "--from", "2026-10-12", "--to", "2026-10-12"}, options)
	var exported struct {
		Records []health.Record `json:"records"`
	}
	if code != 0 || stderr != "" || json.Unmarshal([]byte(out), &exported) != nil || len(exported.Records) != 10 || calls.Load() != 10 {
		t.Fatal("offline raw export or unexpected network", code, stderr)
	}
}
