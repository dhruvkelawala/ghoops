package auth_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func storedSession(t *testing.T, v *testutil.Vault, dir string) auth.Session {
	t.Helper()
	b, err := v.Get(secure.Service(dir) + ".oauth")
	if err != nil {
		t.Fatal(err)
	}
	var s auth.Session
	if err := json.Unmarshal(b, &s); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestRefreshScopePresenceControlsInheritance(t *testing.T) {
	for _, tc := range []struct {
		name  string
		scope *string
	}{
		{"omitted", nil},
		{"explicitly_empty", stringPointer("")},
		{"unrequested", stringPointer("https://www.googleapis.com/auth/unrelated.readonly")},
		{"write_only", stringPointer(strings.TrimSuffix(auth.Scopes[0], ".readonly"))},
	} {
		t.Run(tc.name, func(t *testing.T) {
			v := &testutil.Vault{}
			dir := testutil.Dir(t)
			syntheticSession(t, v, dir)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body := map[string]any{"access_token": "synthetic-new-access", "refresh_token": "synthetic-rotated-refresh", "token_type": "Bearer", "expires_in": 3600}
				if tc.scope != nil {
					body["scope"] = *tc.scope
				}
				fmtJSON(w, body)
			}))
			defer server.Close()
			m := auth.New(v, dir)
			m.TokenURL = server.URL
			access, err := m.Access(context.Background(), "")
			if tc.scope == nil {
				if err != nil || access != "synthetic-new-access" {
					t.Fatalf("omitted scopes must inherit: access=%q err=%v", access, err)
				}
			} else if err == nil || access != "" || !strings.Contains(err.Error(), "permissions") {
				t.Fatalf("no requested read permissions must return clear error: access=%q err=%v", access, err)
			}
			s := storedSession(t, v, dir)
			wantScopes := auth.Scopes
			if tc.scope != nil {
				wantScopes = strings.Fields(*tc.scope)
			}
			if s.RefreshToken != "synthetic-rotated-refresh" || s.AccessToken != "synthetic-new-access" || !reflect.DeepEqual(s.Scopes, wantScopes) {
				t.Fatalf("rotation or exact scope state lost: %+v", s)
			}
			fresh := auth.New(v, dir)
			access, err = fresh.Access(context.Background(), "")
			if tc.scope != nil && (err == nil || access != "") {
				t.Fatalf("persisted zero permissions bypassed: access=%q err=%v", access, err)
			}
			status, err := fresh.Status(context.Background())
			wantState := "authorized"
			if tc.scope != nil {
				wantState = "missing_permissions"
			}
			if err != nil || status.State != wantState || status.Authorized != (tc.scope == nil) || !status.Refreshable {
				t.Fatalf("refreshed permission state = %+v, err=%v", status, err)
			}
		})
	}
}

func TestStatusReportsRequestedPermissions(t *testing.T) {
	for _, tc := range []struct {
		name       string
		scopes     []string
		state      string
		authorized bool
		partial    bool
	}{
		{"full", auth.Scopes, "authorized", true, false},
		{"partial", auth.Scopes[:1], "partial_permissions", true, true},
		{"empty", []string{}, "missing_permissions", false, false},
		{"unknown", []string{"https://www.googleapis.com/auth/unrelated.readonly"}, "missing_permissions", false, false},
		{"write", []string{strings.TrimSuffix(auth.Scopes[0], ".readonly")}, "missing_permissions", false, false},
		{"revoked", auth.Scopes[:1], "revoked", false, true},
		{"expired_access", auth.Scopes[:1], "refresh_required", true, true},
		{"expired_refresh", auth.Scopes[:1], "reauthorization_required", true, true},
		{"not_authorized", nil, "not_authorized", false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			v := &testutil.Vault{}
			dir := testutil.Dir(t)
			if tc.name != "not_authorized" {
				syntheticSession(t, v, dir)
				s := storedSession(t, v, dir)
				s.Scopes = tc.scopes
				s.ExpiresAt = time.Now().Add(time.Hour)
				s.Revoked = tc.name == "revoked"
				if tc.name == "expired_access" {
					s.ExpiresAt = time.Now().Add(-time.Hour)
				}
				if tc.name == "expired_refresh" {
					expired := time.Now().Add(-time.Hour)
					s.RefreshExpiresAt = &expired
				}
				b, _ := json.Marshal(s)
				if err := v.Set(secure.Service(dir)+".oauth", b); err != nil {
					t.Fatal(err)
				}
			}
			status, err := auth.New(v, dir).Status(context.Background())
			if err != nil || status.State != tc.state || status.Authorized != tc.authorized {
				t.Fatalf("permission status = %+v, err=%v", status, err)
			}
			b, _ := json.Marshal(status)
			var permissions struct {
				MissingScopes      []string `json:"missing_scopes"`
				PartialPermissions bool     `json:"partial_permissions"`
			}
			_ = json.Unmarshal(b, &permissions)
			wantMissing := []string{}
			for _, requested := range auth.Scopes {
				found := false
				for _, granted := range tc.scopes {
					found = found || granted == requested
				}
				if !found {
					wantMissing = append(wantMissing, requested)
				}
			}
			if !reflect.DeepEqual(permissions.MissingScopes, wantMissing) || permissions.PartialPermissions != tc.partial {
				t.Fatalf("status must expose exact missing read scopes and partial permissions: %s", b)
			}
		})
	}
}

func loginWithConsent(t *testing.T, scope *string, refresh string, identityStatus int, expected string) (*auth.Manager, *testutil.Vault, string, error) {
	t.Helper()
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	m := auth.New(v, dir)
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	m.CallbackURL = "http://" + listener.Addr().String() + "/oauth/callback"
	_ = listener.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/token":
			response := map[string]any{"access_token": "synthetic-consent-access", "refresh_token": refresh, "token_type": "Bearer", "expires_in": 3600}
			if scope != nil {
				response["scope"] = *scope
			}
			fmtJSON(w, response)
		case "/identity":
			if r.Header.Get("Authorization") != "Bearer synthetic-consent-access" {
				t.Error("identity used wrong token")
			}
			w.WriteHeader(identityStatus)
			fmtJSON(w, map[string]string{"healthUserId": "synthetic-user"})
		default:
			t.Error("unexpected OAuth route")
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(server.Close)
	m.TokenURL = server.URL + "/token"
	m.IdentityURL = server.URL + "/identity"
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	urls := make(chan string, 1)
	done := make(chan error, 1)
	go func() {
		done <- m.Login(ctx, auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"}, expected, true, urlWriter{urls})
	}()
	var authorizationURL string
	select {
	case authorizationURL = <-urls:
	case err := <-done:
		t.Fatalf("login stopped before URL: %v", err)
	case <-ctx.Done():
		t.Fatal("login did not display URL")
	}
	u, err := url.Parse(authorizationURL)
	if err != nil {
		t.Fatal(err)
	}
	if u.Query().Get("scope") != strings.Join(auth.Scopes, " ") {
		t.Fatal("requested scopes changed")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, m.CallbackURL+"?"+url.Values{"state": {u.Query().Get("state")}, "code": {"synthetic-code"}}.Encode(), nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	return m, v, dir, <-done
}

func TestLoginAcceptsPartialConsent(t *testing.T) {
	for _, scope := range auth.Scopes {
		t.Run(scope, func(t *testing.T) {
			m, v, dir, err := loginWithConsent(t, &scope, "synthetic-offline-refresh", http.StatusOK, "synthetic-user")
			if err != nil {
				t.Fatalf("partial consent must preserve permitted streams: %v", err)
			}
			s := storedSession(t, v, dir)
			if s.HealthUserID != "synthetic-user" || s.RefreshToken != "synthetic-offline-refresh" || !reflect.DeepEqual(s.Scopes, []string{scope}) {
				t.Fatalf("partial grant not persisted: %+v", s)
			}
			status, err := m.Status(context.Background())
			if err != nil || status.State != "partial_permissions" || !status.Authorized {
				t.Fatalf("partial status = %+v, err=%v", status, err)
			}
			if access, err := m.Access(context.Background(), ""); err != nil || access != "synthetic-consent-access" {
				t.Fatalf("permitted access blocked: access=%q err=%v", access, err)
			}
		})
	}
}

func TestLoginRejectsMissingPermissionsWithClearFeedback(t *testing.T) {
	for _, tc := range []struct {
		name  string
		scope *string
	}{
		{"omitted", nil},
		{"empty", stringPointer("")},
		{"unknown", stringPointer("https://www.googleapis.com/auth/unrelated.readonly")},
		{"write", stringPointer(strings.TrimSuffix(auth.Scopes[0], ".readonly"))},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, v, dir, err := loginWithConsent(t, tc.scope, "synthetic-offline-refresh", http.StatusOK, "")
			if !errors.Is(err, auth.ErrPermissions) {
				t.Fatalf("missing consent must explain permissions: %v", err)
			}
			if _, err := v.Get(secure.Service(dir) + ".oauth"); !errors.Is(err, secure.ErrNotFound) {
				t.Fatal("zero-consent login saved a session", err)
			}
		})
	}
}

func TestPartialLoginStillRequiresOfflineVerifiedIdentity(t *testing.T) {
	for _, tc := range []struct {
		name           string
		refresh        string
		identityStatus int
		expected       string
		message        string
	}{
		{"no_offline_token", "", http.StatusOK, "", "offline access"},
		{"identity_denied", "synthetic-refresh", http.StatusForbidden, "", "account link check failed"},
		{"different_account", "synthetic-refresh", http.StatusOK, "synthetic-other-user", "another account"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, v, dir, err := loginWithConsent(t, &auth.Scopes[0], tc.refresh, tc.identityStatus, tc.expected)
			if err == nil || !strings.Contains(err.Error(), tc.message) {
				t.Fatalf("partial grant bypassed offline or identity check: %v", err)
			}
			if _, err := v.Get(secure.Service(dir) + ".oauth"); !errors.Is(err, secure.ErrNotFound) {
				t.Fatal("invalid partial login saved session", err)
			}
		})
	}
}

func TestReducedScopeRefreshFailsClosedOnPersistenceFailure(t *testing.T) {
	for _, scope := range []string{auth.Scopes[0], ""} {
		t.Run(scope, func(t *testing.T) {
			v := &testutil.Vault{}
			dir := testutil.Dir(t)
			syntheticSession(t, v, dir)
			before, _ := v.Get(secure.Service(dir) + ".oauth")
			failure := errors.New("synthetic persistence unavailable")
			v.FailSet = failure
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				fmtJSON(w, map[string]any{"access_token": "synthetic-new-access", "refresh_token": "synthetic-rotated-refresh", "token_type": "Bearer", "expires_in": 3600, "scope": scope})
			}))
			defer server.Close()
			m := auth.New(v, dir)
			m.TokenURL = server.URL
			if access, err := m.Access(context.Background(), ""); access != "" || !errors.Is(err, failure) {
				t.Fatalf("persistence failure must take precedence over permission state: access=%q err=%v", access, err)
			}
			after, _ := v.Get(secure.Service(dir) + ".oauth")
			if string(before) != string(after) {
				t.Fatal("failed persistence changed session")
			}
		})
	}
}

func stringPointer(s string) *string { return &s }

func TestReducedScopeRefreshPersistsRotation(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	syntheticSession(t, v, dir)
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		_ = r.ParseForm()
		want := "synthetic-refresh"
		if calls > 1 {
			want = "synthetic-rotated-refresh"
		}
		if r.Form.Get("refresh_token") != want {
			t.Errorf("refresh token = %q, want %q", r.Form.Get("refresh_token"), want)
		}
		fmtJSON(w, map[string]any{"access_token": "synthetic-reduced-access", "refresh_token": "synthetic-rotated-refresh", "token_type": "Bearer", "expires_in": 3600, "refresh_token_expires_in": 86400, "scope": auth.Scopes[0]})
	}))
	defer server.Close()
	m := auth.New(v, dir)
	m.TokenURL = server.URL
	access, err := m.Access(context.Background(), "")
	if err != nil || access != "synthetic-reduced-access" {
		t.Fatalf("permitted stream cannot use reduced grant: access=%q err=%v", access, err)
	}
	s := storedSession(t, v, dir)
	if s.RefreshToken != "synthetic-rotated-refresh" || s.HealthUserID != "synthetic-user" || !reflect.DeepEqual(s.Scopes, auth.Scopes[:1]) || s.RefreshExpiresAt == nil || !s.RefreshExpiresAt.After(time.Now()) {
		t.Fatalf("rotation or reduced grant not persisted: %+v", s)
	}
	fresh := auth.New(v, dir)
	fresh.TokenURL = server.URL
	if err := fresh.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if calls != 2 {
		t.Fatalf("forced refresh calls = %d, want 2", calls)
	}
}
