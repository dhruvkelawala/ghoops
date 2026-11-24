package auth_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func syntheticSession(t *testing.T, v *testutil.Vault, dir string) {
	t.Helper()
	s := auth.Session{Client: auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"}, AccessToken: "synthetic-old-access", RefreshToken: "synthetic-refresh", ExpiresAt: time.Now().Add(-time.Hour), Scopes: auth.Scopes, HealthUserID: "synthetic-user"}
	b, _ := json.Marshal(s)
	if err := v.Set(secure.Service(dir)+".oauth", b); err != nil {
		t.Fatal(err)
	}
}

func TestConcurrentRefreshPersistsAndRetainsRefreshToken(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	syntheticSession(t, v, dir)
	var requests atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.Method != "POST" {
			t.Error("method")
		}
		_ = r.ParseForm()
		if r.Form.Get("refresh_token") != "synthetic-refresh" || r.Form.Get("client_secret") != "synthetic-secret" {
			t.Error("refresh fields")
		}
		fmtJSON(w, map[string]any{"access_token": "synthetic-new-access", "token_type": "Bearer", "expires_in": 3600})
	}))
	defer srv.Close()
	m := auth.New(v, dir)
	m.TokenURL = srv.URL
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			token, err := m.Access(context.Background(), "")
			if err != nil || token != "synthetic-new-access" {
				t.Errorf("refresh: %v", err)
			}
		}()
	}
	wg.Wait()
	if requests.Load() != 1 {
		t.Fatalf("refresh calls %d", requests.Load())
	}
	fresh := auth.New(v, dir)
	fresh.TokenURL = srv.URL
	token, err := fresh.Access(context.Background(), "")
	if err != nil || token != "synthetic-new-access" || requests.Load() != 1 {
		t.Fatal("fresh manager did not use persisted token", err)
	}
	b, _ := v.Get(secure.Service(dir) + ".oauth")
	var s auth.Session
	_ = json.Unmarshal(b, &s)
	if s.RefreshToken != "synthetic-refresh" {
		t.Fatal("lost refresh token")
	}
	if _, err := fresh.Access(context.Background(), "synthetic-old-access"); err != nil || requests.Load() != 1 {
		t.Fatal("repeated obsolete rejection refreshed again", err)
	}
}

func TestRevocationIsPersistentAndRedacted(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	syntheticSession(t, v, dir)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(400)
		_, _ = io.WriteString(w, `{"error":"invalid_grant","error_description":"synthetic-secret synthetic-refresh"}`)
	}))
	defer srv.Close()
	m := auth.New(v, dir)
	m.TokenURL = srv.URL
	_, err := m.Access(context.Background(), "")
	if !errors.Is(err, auth.ErrLogin) || strings.Contains(err.Error(), "synthetic") {
		t.Fatal("revocation", err)
	}
	s, err := auth.New(v, dir).Status(context.Background())
	if err != nil || s.State != "revoked" || s.Authorized {
		t.Fatal("revocation not persisted", s, err)
	}
}

func TestRefreshFailsClosedWhenPersistenceFails(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	syntheticSession(t, v, dir)
	v.FailSet = errors.New("synthetic Keychain unavailable")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmtJSON(w, map[string]any{"access_token": "synthetic-new", "token_type": "Bearer", "expires_in": 3600})
	}))
	defer srv.Close()
	m := auth.New(v, dir)
	m.TokenURL = srv.URL
	access, err := m.Access(context.Background(), "")
	if err == nil || access != "" {
		t.Fatal("unpersisted token escaped", err)
	}
}

type urlWriter struct{ urls chan string }

func (w urlWriter) Write(b []byte) (int, error) {
	w.urls <- strings.TrimSpace(string(b))
	return len(b), nil
}
func fmtJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func TestLoginLoopbackStatePKCEAndIdentity(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	m := auth.New(v, dir)
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	m.CallbackURL = "http://" + l.Addr().String() + "/oauth/callback"
	_ = l.Close()
	urls := make(chan string, 1)
	var challenge string
	var exchanges atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/token":
			exchanges.Add(1)
			_ = r.ParseForm()
			verifier := r.Form.Get("code_verifier")
			hash := sha256.Sum256([]byte(verifier))
			if len(verifier) < 43 || base64.RawURLEncoding.EncodeToString(hash[:]) != challenge || r.Form.Get("code") != "synthetic-code" {
				t.Error("PKCE exchange mismatch")
			}
			fmtJSON(w, map[string]any{"access_token": "synthetic-access", "refresh_token": "synthetic-refresh", "token_type": "Bearer", "expires_in": 3600, "scope": strings.Join(auth.Scopes, " ")})
		case "/identity":
			if r.Method != "GET" || r.Header.Get("Authorization") != "Bearer synthetic-access" {
				t.Error("identity request")
			}
			fmtJSON(w, map[string]string{"healthUserId": "synthetic-user"})
		default:
			t.Error("unexpected route")
			w.WriteHeader(404)
		}
	}))
	defer srv.Close()
	m.TokenURL = srv.URL + "/token"
	m.IdentityURL = srv.URL + "/identity"
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- m.Login(ctx, auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"}, "", true, urlWriter{urls})
	}()
	var authorizationURL string
	select {
	case authorizationURL = <-urls:
	case err := <-done:
		t.Fatalf("login stopped before URL: %v", err)
	case <-ctx.Done():
		t.Fatal("login did not display URL")
	}
	u, _ := url.Parse(authorizationURL)
	q := u.Query()
	challenge = q.Get("code_challenge")
	if q.Get("access_type") != "offline" || q.Get("code_challenge_method") != "S256" || q.Get("scope") != strings.Join(auth.Scopes, " ") || len(q.Get("state")) < 43 || q.Get("redirect_uri") != m.CallbackURL {
		t.Fatal("unsafe authorization parameters", q)
	}
	bad, err := http.Get(m.CallbackURL + "?state=wrong&code=synthetic-code")
	if err != nil {
		t.Fatal(err)
	}
	bad.Body.Close()
	if bad.StatusCode != 400 || exchanges.Load() != 0 {
		t.Fatal("invalid state accepted")
	}
	good, err := http.Get(m.CallbackURL + "?" + url.Values{"state": {q.Get("state")}, "code": {"synthetic-code"}}.Encode())
	if err != nil {
		t.Fatal(err)
	}
	good.Body.Close()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	status, err := m.Status(context.Background())
	if err != nil || !status.Authorized || !status.Linked || !status.Refreshable {
		t.Fatal(status, err)
	}
}

func TestClientFileSafetyAndLogout(t *testing.T) {
	dir := testutil.Dir(t)
	path := filepath.Join(dir, "synthetic-client.json")
	content := `{"web":{"client_id":"synthetic","client_secret":"synthetic-secret","redirect_uris":["` + auth.Callback + `"]}}`
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := auth.LoadClient(path, auth.Callback); err == nil {
		t.Fatal("accepted readable client secret")
	}
	_ = os.Chmod(path, 0600)
	if _, err := auth.LoadClient(path, auth.Callback); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "synthetic-link")
	_ = os.Symlink(path, link)
	if _, err := auth.LoadClient(link, auth.Callback); err == nil {
		t.Fatal("accepted symlink")
	}
	v := &testutil.Vault{}
	syntheticSession(t, v, dir)
	m := auth.New(v, dir)
	if err := m.Logout(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	s, err := m.Status(context.Background())
	if err != nil || s.Authorized || s.State != "not_authorized" {
		t.Fatal(s, err)
	}
	var b bytes.Buffer
	_ = json.NewEncoder(&b).Encode(s)
	if strings.Contains(b.String(), "synthetic-secret") {
		t.Fatal("status leaked secret")
	}
}

func TestRefreshRotationPersistsAndKnownExpiryBlocksNetwork(t *testing.T) {
	dir := testutil.Dir(t)
	v := &testutil.Vault{}
	syntheticSession(t, v, dir)
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		call := calls.Add(1)
		_ = r.ParseForm()
		expected := "synthetic-refresh"
		if call > 1 {
			expected = "synthetic-rotated-refresh"
		}
		if r.Form.Get("refresh_token") != expected {
			t.Error("refresh rotation not persisted")
		}
		fmtJSON(w, map[string]any{"access_token": "synthetic-rotated-access", "refresh_token": "synthetic-rotated-refresh", "token_type": "Bearer", "expires_in": 3600, "refresh_token_expires_in": 86400})
	}))
	defer server.Close()
	m := auth.New(v, dir)
	m.TokenURL = server.URL
	if _, err := m.Access(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	fresh := auth.New(v, dir)
	fresh.TokenURL = server.URL
	if _, err := fresh.Access(context.Background(), "synthetic-rotated-access"); err != nil || calls.Load() != 2 {
		t.Fatal("rotated refresh", err)
	}
	b, _ := v.Get(secure.Service(dir) + ".oauth")
	var s auth.Session
	_ = json.Unmarshal(b, &s)
	expired := time.Now().Add(-time.Hour)
	s.ExpiresAt = expired
	s.RefreshExpiresAt = &expired
	b, _ = json.Marshal(s)
	_ = v.Set(secure.Service(dir)+".oauth", b)
	if _, err := fresh.Access(context.Background(), ""); !errors.Is(err, auth.ErrLogin) || calls.Load() != 2 {
		t.Fatal("expired refresh token sent", err)
	}
}
