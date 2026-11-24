package cli_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestCLIRefreshPersistsFreshTokenWithoutPrintingCredentials(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	session := auth.Session{Client: auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"}, AccessToken: "synthetic-existing-access", RefreshToken: "synthetic-refresh", ExpiresAt: time.Now().Add(5 * time.Minute), Scopes: auth.Scopes, HealthUserID: "synthetic-user"}
	encoded, err := json.Marshal(session)
	if err != nil {
		t.Fatal(err)
	}
	if err := vault.Set(secure.Service(dir)+".oauth", encoded); err != nil {
		t.Fatal(err)
	}
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.Method != http.MethodPost {
			t.Error("refresh did not use OAuth POST")
		}
		if err := r.ParseForm(); err != nil || r.Form.Get("grant_type") != "refresh_token" || r.Form.Get("refresh_token") != "synthetic-refresh" {
			t.Error("incorrect refresh grant")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"synthetic-renewed-access","token_type":"Bearer","expires_in":3600}`))
	}))
	defer server.Close()
	manager := auth.New(vault, dir)
	manager.TokenURL = server.URL
	code, out, stderr := run(t, []string{"--state-dir", dir, "auth", "refresh", "--json"}, cli.Options{Vault: vault, Auth: manager})
	if code != 0 || stderr != "" {
		t.Fatalf("explicit refresh failed: exit %d, %s", code, stderr)
	}
	if requests.Load() != 1 {
		t.Fatalf("expected one refresh request, got %d", requests.Load())
	}
	if strings.Contains(out, "synthetic-") || strings.Contains(out, "access_token") || strings.Contains(out, "refresh_token") {
		t.Fatal("refresh output disclosed credential material")
	}
	var status auth.Status
	if err := json.Unmarshal([]byte(out), &status); err != nil || !status.Authorized || status.ExpiresAt == nil || !status.ExpiresAt.After(session.ExpiresAt) {
		t.Fatal("refresh did not report renewed authorization status")
	}
	fresh := auth.New(vault, dir)
	fresh.TokenURL = server.URL
	access, err := fresh.Access(context.Background(), "")
	if err != nil || access != "synthetic-renewed-access" || requests.Load() != 1 {
		t.Fatal("fresh manager could not reuse persisted refreshed token")
	}
}
