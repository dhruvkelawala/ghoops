package collect_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/collect"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

type provider struct {
	server *httptest.Server
	client *health.Client
	calls  atomic.Int32
	active atomic.Int32
	peak   atomic.Int32
}

func syntheticProvider(t *testing.T, failed string, code int, firstBatch int32) *provider {
	t.Helper()
	p := &provider{}
	ready := make(chan struct{})
	var arrived atomic.Int32
	p.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		request := p.calls.Add(1)
		active := p.active.Add(1)
		defer p.active.Add(-1)
		for old := p.peak.Load(); active > old; old = p.peak.Load() {
			if p.peak.CompareAndSwap(old, active) {
				break
			}
		}
		if request <= firstBatch {
			if arrived.Add(1) == firstBatch {
				close(ready)
			}
			select {
			case <-ready:
			case <-r.Context().Done():
				return
			case <-time.After(5 * time.Second):
				t.Error("the first batch of collector requests did not overlap")
				w.WriteHeader(http.StatusServiceUnavailable)
				return
			}
		}
		if failed != "" && strings.Contains(r.URL.Path, failed) {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(code)
			return
		}
		switch {
		case strings.HasSuffix(r.URL.Path, ":rollUp"):
			var body struct {
				Range struct {
					Start time.Time `json:"startTime"`
					End   time.Time `json:"endTime"`
				} `json:"range"`
			}
			if json.NewDecoder(r.Body).Decode(&body) != nil {
				t.Error("invalid roll-up request")
				return
			}
			windows := []map[string]any{}
			for at := body.Range.Start; at.Before(body.Range.End); at = at.Add(time.Minute) {
				windows = append(windows, map[string]any{"startTime": at.Format(time.RFC3339), "endTime": at.Add(time.Minute).Format(time.RFC3339), "heartRate": map[string]int{"beatsPerMinuteMin": 60, "beatsPerMinuteAvg": 62, "beatsPerMinuteMax": 66}})
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"rollupDataPoints": windows})
		case strings.HasSuffix(r.URL.Path, "/pairedDevices"):
			fmt.Fprint(w, `{"pairedDevices":[{"deviceType":"TRACKER","lastSyncTime":"2026-03-10T14:08:00Z","macAddress":"synthetic-private-address"}]}`)
		default:
			fmt.Fprint(w, `{}`)
		}
	}))
	t.Cleanup(p.server.Close)
	p.client = health.New(nil)
	p.client.BaseURL = p.server.URL
	return p
}

func syntheticManager(t *testing.T, store store2.Store) *auth.Manager {
	t.Helper()
	session := auth.Session{
		Client:      auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"},
		AccessToken: "synthetic-token", ExpiresAt: time.Now().Add(time.Hour),
		Scopes: auth.Scopes, HealthUserID: "synthetic-account",
	}
	data, err := json.Marshal(session)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.Vault.Set(secure.Service(store.Dir)+".oauth", data); err != nil {
		t.Fatal(err)
	}
	return auth.New(store.Vault, store.Dir)
}

func TestCollectStatusesRetainFailedCoreMinutesAndLimitConcurrency(t *testing.T) {
	for _, tc := range []struct {
		name, failed, status string
		http, exit           int
		core                 bool
	}{
		{"success", "", "ok", 0, 0, true},
		{"user_forbidden", "/profile", "ok", 403, 0, true},
		{"noncore_forbidden", "/daily-respiratory-rate/", "ok", 403, 0, true},
		{"noncore_failure", "/daily-respiratory-rate/", "partial", 500, 1, true},
		{"core_failure", "/heart-rate/", "failed", 500, 1, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := syntheticProvider(t, tc.failed, tc.http, 4)
			store := store2.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			from := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
			previous := store2.Empty()
			previous.Account = "synthetic-account"
			previous.HRMinutes = []store2.MinuteDay{{Date: "2026-03-10", Windows: []store2.Minute{{Start: from.Unix(), Min: 70, Avg: 74, Max: 80}}}}
			if err := store.Save(previous, from); err != nil {
				t.Fatal(err)
			}
			result, err := collect.Run(context.Background(), store, p.client, syntheticManager(t, store), collect.Options{From: from, Until: from.AddDate(0, 0, 1), Now: func() time.Time { return from.Add(15 * time.Hour) }})
			if (err != nil) != (tc.exit != 0) || result.Status != tc.status || result.CoreComplete != tc.core || len(result.Streams) != 17 || result.Requests != int(p.calls.Load()) {
				t.Fatalf("unexpected run: %+v, %v", result, err)
			}
			if p.peak.Load() != 4 {
				t.Fatal("expected four concurrent requests", p.peak.Load())
			}
			loaded, err := store.Load()
			if err != nil || len(loaded.Runs) != 1 || loaded.Runs[0].Status != tc.status {
				t.Fatal("run history missing", err)
			}
			if strings.Contains(string(loaded.User["paired_devices"].Body), "macAddress") {
				t.Fatal("paired device address was stored")
			}
			if tc.failed == "/profile" && loaded.User["profile"].Status != "permission_missing" {
				t.Fatal("403 was not permission_missing")
			}
			if tc.status == "failed" {
				if len(loaded.HRMinutes) != 1 || len(loaded.HRMinutes[0].Windows) != 1 || loaded.HRMinutes[0].Windows[0].Avg != 74 {
					t.Fatal("failed core fetch discarded previous minutes")
				}
			} else if len(loaded.HRMinutes[0].Windows) != 1440 {
				t.Fatal("successful fetch did not replace the day")
			}
		})
	}
}

func TestCollectLondonDSTDays(t *testing.T) {
	loc, _ := time.LoadLocation("Europe/London")
	for _, tc := range []struct {
		date    string
		windows int
	}{{"2026-03-29", 1380}, {"2026-10-25", 1500}} {
		t.Run(tc.date, func(t *testing.T) {
			p := syntheticProvider(t, "", 0, 0)
			from, _ := time.ParseInLocation("2006-01-02", tc.date, loc)
			store := store2.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			result, err := collect.Run(context.Background(), store, p.client, syntheticManager(t, store), collect.Options{From: from, Until: from.AddDate(0, 0, 1), Now: func() time.Time { return from.Add(12 * time.Hour) }})
			if err != nil || result.Status != "ok" {
				t.Fatal(err)
			}
			state, err := store.Load()
			if err != nil || len(state.HRMinutes) != 1 || len(state.HRMinutes[0].Windows) != tc.windows {
				t.Fatal("wrong London DST window count", err)
			}
		})
	}
}

func TestSettlePassRunsOncePerLondonDayAfterNoon(t *testing.T) {
	p := syntheticProvider(t, "", 0, 0)
	store := store2.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	manager := syntheticManager(t, store)
	loc, _ := time.LoadLocation("Europe/London")
	for _, tc := range []struct{ at, pass, from string }{
		{"2026-07-10T11:59:00", "hot", "2026-07-08"},
		{"2026-07-10T12:00:00", "settle", "2026-07-01"},
		{"2026-07-10T18:00:00", "hot", "2026-07-08"},
		{"2026-07-11T12:00:00", "settle", "2026-07-02"},
	} {
		now, _ := time.ParseInLocation("2006-01-02T15:04:05", tc.at, loc)
		result, err := collect.Run(context.Background(), store, p.client, manager, collect.Options{Now: func() time.Time { return now }})
		if err != nil || result.Pass != tc.pass || result.From != tc.from {
			t.Fatalf("plan mismatch: %+v %v", result, err)
		}
	}
}

func TestCancelledCollectSavesNothing(t *testing.T) {
	p := syntheticProvider(t, "", 0, 0)
	store := store2.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 10, 15, 0, 0, 0, time.UTC)
	if err := store.Save(store2.Empty(), now); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(store.Dir, "records-v2.enc")
	before, _ := os.ReadFile(path)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := collect.Run(ctx, store, p.client, syntheticManager(t, store), collect.Options{Now: func() time.Time { return now }})
	after, _ := os.ReadFile(path)
	if err == nil || !bytes.Equal(before, after) {
		t.Fatal("cancelled run saved data")
	}
}

func TestCollectionNameDoesNotReplaceRecordsOutsideRequestedDates(t *testing.T) {
	p := syntheticProvider(t, "", 0, 0)
	base := p.server.Config.Handler
	p.server.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/daily-respiratory-rate/") {
			fmt.Fprint(w, `{"dataPoints":[{"name":"users/me/dataTypes/daily-respiratory-rate/dataPoints/","dailyRespiratoryRate":{"date":{"year":2026,"month":3,"day":10},"breathsPerMinute":16}}]}`)
			return
		}
		base.ServeHTTP(w, r)
	})
	store := store2.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	from := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
	previous := store2.Empty()
	previous.Records = []health.Record{{Type: "daily-respiratory-rate", Stream: "raw", Date: "2026-03-09", Raw: json.RawMessage(`{"name":"users/me/dataTypes/daily-respiratory-rate/dataPoints/","dailyRespiratoryRate":{"date":{"year":2026,"month":3,"day":9},"breathsPerMinute":17}}`)}}
	if err := store.Save(previous, from); err != nil {
		t.Fatal(err)
	}
	_, err := collect.Run(context.Background(), store, p.client, syntheticManager(t, store), collect.Options{From: from, Until: from.AddDate(0, 0, 1), Now: func() time.Time { return from.Add(15 * time.Hour) }})
	if err != nil {
		t.Fatal(err)
	}
	state, err := store.Load()
	if err != nil || len(state.Records) != 2 || state.Records[0].Date != "2026-03-09" || state.Records[1].Date != "2026-03-10" {
		t.Fatal("collection name removed unrelated stored day", err)
	}
}
