package serve_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/serve"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestHTTPMatchesCLIBuilderAndProtectsTransport(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	store := store2.Store{Dir: dir, Vault: vault}
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	if err = store.Save(state, now); err != nil {
		t.Fatal(err)
	}
	tokens := pairing.Tokens{Dir: dir, Vault: vault}
	token, err := tokens.Pair(context.Background(), false, now)
	if err != nil {
		t.Fatal(err)
	}
	file := config.File{Path: filepath.Join(dir, "config.json")}
	var logs bytes.Buffer
	options := v2report.Options{Auth: v2report.Auth{Missing: []string{}}}
	handler, err := serve.New(serve.Settings{Store: store, Config: file, Tokens: tokens, Options: func(context.Context) v2report.Options { return options }, Now: func() time.Time { return now }, Log: &logs})
	if err != nil {
		t.Fatal(err)
	}
	request := func(method, path, value string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, nil)
		if value != "" {
			r.Header.Set("Authorization", "Bearer "+value)
		}
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		return w
	}
	builder, err := v2report.New(state, now, config.Defaults(), options)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ kind, query string }{{"day", "date=2026-03-10"}, {"sleep", ""}, {"days", "days=7"}, {"workouts", "days=2"}, {"status", ""}, {"snapshot", ""}, {"brief", "include_values=true"}, {"brief", "part=evening&include_values=true"}, {"week", "date=2026-03-08"}, {"week", ""}, {"brief", "date=2026-03-08&part=week&include_values=true"}} {
		w := request("GET", "/v2/"+tc.kind+"?"+tc.query, token.Value)
		if w.Code != 200 {
			t.Fatal(w.Code, w.Body.String())
		}
		params, _ := url.ParseQuery(tc.query)
		body, err := builder.Build(tc.kind, params)
		if err != nil {
			t.Fatal(err)
		}
		var expected bytes.Buffer
		json.NewEncoder(&expected).Encode(body)
		if !bytes.Equal(w.Body.Bytes(), expected.Bytes()) {
			t.Fatalf("%s HTTP differs from CLI body", tc.kind)
		}
		if w.Header().Get("Cache-Control") != "no-store" || w.Header().Get("X-Ghealth-Schema") != "2" || w.Header().Get("Content-Type") != "application/json; charset=utf-8" {
			t.Fatal(w.Header())
		}
	}
	for _, tc := range []struct {
		method, path, token, code string
		status                    int
	}{
		{"GET", "/v2/status", "", "unauthorized", 401},
		{"GET", "/v2/status", "wrong", "unauthorized", 401},
		{"POST", "/v2/day", token.Value, "method_not_allowed", 405},
		{"GET", "/v2/day/", token.Value, "not_found", 404},
		{"GET", "/v2/day?secret_query=private", token.Value, "invalid_request", 400},
		{"GET", "/v2/day?date=2026-03-11", token.Value, "date_out_of_range", 400},
		{"GET", "/v2/status?bad=%zz", token.Value, "invalid_request", 400},
		{"GET", "/v2/week/", token.Value, "not_found", 404},
		{"GET", "/v2/week?end=2026-03-08", token.Value, "invalid_request", 400},
		{"GET", "/v2/week?date=2026-03-11", token.Value, "date_out_of_range", 400},
	} {
		w := request(tc.method, tc.path, tc.token)
		var e v2report.ErrorBody
		if w.Code != tc.status || json.Unmarshal(w.Body.Bytes(), &e) != nil || e.Error.Code != tc.code {
			t.Fatalf("%s %d %s", tc.path, w.Code, w.Body)
		}
	}
	if strings.Contains(logs.String(), "private") || strings.Contains(logs.String(), "secret_query") || strings.Contains(logs.String(), token.Value) {
		t.Fatal("request secrets in log")
	}
	for _, query := range []string{"part=noon", "part=", "part=morning&part=evening"} {
		w := request("GET", "/v2/brief?"+query, token.Value)
		var body v2report.ErrorBody
		if w.Code != 400 || json.Unmarshal(w.Body.Bytes(), &body) != nil || body.Error.Code != "invalid_request" || !strings.Contains(body.Error.Message, "part") {
			t.Fatalf("brief part %s: %d %s", query, w.Code, w.Body)
		}
	}
	for _, tc := range []struct{ key, value string }{{"strain_intent", "restore"}, {"wake_target", "06:45"}} {
		if _, err := file.Set(tc.key, tc.value); err != nil {
			t.Fatal(err)
		}
	}
	w := request("GET", "/v2/day?date=2026-03-10", token.Value)
	var day v2report.Day
	if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &day) != nil || day.Config == nil || day.Config.StrainIntent != "restore" || day.Config.WakeTarget == nil || *day.Config.WakeTarget != "06:45" || day.StrainTarget.Low == nil || *day.StrainTarget.Low != 10.3 || day.StrainTarget.Position == nil || *day.StrainTarget.Position != "within" {
		t.Fatal("server did not pick up config without restart", w.Code, w.Body.String())
	}
	for nights, want := range map[string]string{"4": "met", "6": "not_met"} {
		if _, err := file.Set("week_sleep_nights", nights); err != nil {
			t.Fatal(err)
		}
		var week v2report.Week
		if w := request("GET", "/v2/week?date=2026-03-08", token.Value); w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &week) != nil || week.Targets.Sleep.Status != want {
			t.Fatalf("week_sleep_nights %s: want sleep %s, got %d %s", nights, want, w.Code, w.Body.String())
		}
	}
	rotated, err := tokens.Pair(context.Background(), true, now)
	if err != nil {
		t.Fatal(err)
	}
	now = now.Add(5 * time.Second)
	if w := request("GET", "/v2/status", rotated.Value); w.Code != 200 {
		t.Fatal("rotation not accepted", w.Code)
	}
	if w := request("GET", "/v2/status", token.Value); w.Code != 401 {
		t.Fatal("old token accepted", w.Code)
	}
	if err = tokens.Revoke(context.Background()); err != nil {
		t.Fatal(err)
	}
	now = now.Add(5 * time.Second)
	if w := request("GET", "/v2/status", rotated.Value); w.Code != 401 {
		t.Fatal("revoked token accepted")
	}
	// A replaced encrypted file must be reopened; no collect lock is needed.
	if err = os.WriteFile(filepath.Join(dir, "records-v2.enc"), []byte("broken"), 0600); err != nil {
		t.Fatal(err)
	}
	token, err = tokens.Pair(context.Background(), false, now)
	if err != nil {
		t.Fatal(err)
	}
	now = now.Add(5 * time.Second)
	if w := request("GET", "/v2/status", token.Value); w.Code != 503 {
		t.Fatal("corrupt replacement served", w.Code)
	}
}
func TestAuthLimiterAndLoopbackOnly(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	dir := testutil.Dir(t)
	h, err := serve.New(serve.Settings{Tokens: pairing.Tokens{Dir: dir, Vault: &testutil.Vault{}}, Now: func() time.Time { return now }})
	if err != nil {
		t.Fatal(err)
	}
	for i := 1; i <= 11; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v2/status", nil))
		expected := 401
		if i == 11 {
			expected = 429
		}
		if w.Code != expected {
			t.Fatalf("attempt %d: %d", i, w.Code)
		}
		if i == 11 && w.Header().Get("Retry-After") != "60" {
			t.Fatal("missing retry header")
		}
	}
	now = now.Add(60 * time.Second)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/v2/status", nil))
	if w.Code != 401 {
		t.Fatal("limiter did not clear")
	}
	for _, address := range []string{"0.0.0.0:0", "localhost:0", "[::1]:0"} {
		if l, err := serve.Listen(address); err == nil {
			l.Close()
			t.Fatalf("accepted %s", address)
		}
	}
	l, err := serve.Listen("127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	l.Close()
}
