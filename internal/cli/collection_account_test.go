package cli_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/collect"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

const (
	syntheticOwner = "synthetic-account-A"
	otherAccount   = "synthetic-account-B"
)

func syntheticSession(t *testing.T, account string) []byte {
	t.Helper()
	session := auth.Session{
		Client:      auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"},
		AccessToken: account + "-access", RefreshToken: "synthetic-refresh",
		ExpiresAt: time.Now().Add(time.Hour), Scopes: auth.Scopes, HealthUserID: account,
	}
	encoded, err := json.Marshal(session)
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

func TestV2OnlyProfileKeepsOwnerThroughLogoutAndLogin(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	key := bytes.Repeat([]byte{1}, 32)
	keyItem := secure.Service(dir) + ".cache-key"
	if err := vault.Set(keyItem, key); err != nil {
		t.Fatal(err)
	}
	store := store2.Store{Dir: dir, Vault: vault}
	state := store2.Empty()
	state.Account = syntheticOwner
	if err := store.Save(state, now); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "records-v2.enc")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sessionItem := secure.Service(dir) + ".oauth"
	if err := vault.Set(sessionItem, syntheticSession(t, syntheticOwner)); err != nil {
		t.Fatal(err)
	}

	manager := auth.New(vault, dir)
	var another atomic.Bool
	another.Store(true)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/token":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"access_token": "synthetic-login-access", "refresh_token": "synthetic-login-refresh",
				"token_type": "Bearer", "expires_in": 3600, "scope": strings.Join(auth.Scopes, " "),
			})
		case "/identity":
			account := syntheticOwner
			if another.Load() {
				account = otherAccount
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"healthUserId": account})
		default:
			t.Error("login unexpectedly contacted the provider beyond the stub routes")
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(server.Close)
	manager.AuthorizeURL, manager.TokenURL, manager.IdentityURL = server.URL+"/consent", server.URL+"/token", server.URL+"/identity"
	args := syntheticLoginArgs(t, manager)
	opts := cli.Options{Auth: manager, Vault: vault, Now: func() time.Time { return now }}
	if code, _, stderr := run(t, []string{"--state-dir", dir, "auth", "logout"}, opts); code != 0 || stderr != "" {
		t.Fatal("synthetic logout failed", code, stderr)
	}
	if code, _, stderr := run(t, []string{"--state-dir", dir, "day", "--date", "2026-03-10"}, opts); code != 0 || stderr != "" {
		t.Fatal("offline read after logout failed", code, stderr)
	}
	if code, stderr := completeSyntheticLogin(t, manager, args, opts); code != 1 || !strings.Contains(stderr, "another account already owns this profile; use a separate --state-dir") {
		t.Fatal("v2-only profile did not refuse a different account", code, stderr)
	}
	if _, err := vault.Get(sessionItem); err != secure.ErrNotFound {
		t.Fatal("the refused login wrote credentials", err)
	}
	another.Store(false)
	if code, stderr := completeSyntheticLogin(t, manager, args, opts); code != 0 || stderr != "" {
		t.Fatal("login refused the original account", code, stderr)
	}
	if account, err := manager.Account(t.Context()); err != nil || account != syntheticOwner {
		t.Fatal("the original account could not log in", err)
	}
	loaded, err := store.Load()
	if err != nil || loaded.Account != syntheticOwner {
		t.Fatal("the original owner could not reopen the v2 store", err)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("logout or login rewrote the v2 store", err)
	}
	if kept, err := vault.Get(keyItem); err != nil || !bytes.Equal(kept, key) {
		t.Fatal("logout or login changed the encryption key", err)
	}
}

func TestLoginRefusesDisagreeingCacheOwners(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	v1 := cache.Empty()
	v1.Account = syntheticOwner
	if err := (cache.Store{Dir: dir, Vault: vault}).Save(v1); err != nil {
		t.Fatal(err)
	}
	v2 := store2.Empty()
	v2.Account = otherAccount
	if err := (store2.Store{Dir: dir, Vault: vault}).Save(v2, time.Now()); err != nil {
		t.Fatal(err)
	}
	manager := auth.New(vault, dir)
	manager.AuthorizeURL = "https://mac-a.invalid/consent"
	args := syntheticLoginArgs(t, manager)
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	var stdout, stderr bytes.Buffer
	code := cli.Run(ctx, args, nil, &stdout, &stderr, cli.Options{Vault: vault, Auth: manager})
	if code != 1 || stdout.Len() != 0 || !strings.Contains(stderr.String(), "another account already owns this profile; use a separate --state-dir") {
		t.Fatal("different store owners did not stop login before consent", code, stderr.String())
	}
}

type accountSwitchVault struct {
	testutil.Vault
	item        string
	nextSession []byte
	switchNext  atomic.Bool
	readSwitch  atomic.Bool
}

func (v *accountSwitchVault) Get(item string) ([]byte, error) {
	if item == v.item && v.switchNext.CompareAndSwap(true, false) {
		v.readSwitch.Store(true)
		return v.nextSession, nil
	}
	return v.Vault.Get(item)
}

func TestCLIV2CollectKeepsStoreWhenAccountChanges(t *testing.T) {
	for _, stage := range []string{"before another token", "after the final request"} {
		t.Run(stage, func(t *testing.T) {
			dir := testutil.Dir(t)
			now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
			item := secure.Service(dir) + ".oauth"
			vault := &accountSwitchVault{item: item, nextSession: syntheticSession(t, otherAccount)}
			if err := vault.Set(item, syntheticSession(t, syntheticOwner)); err != nil {
				t.Fatal(err)
			}
			state := store2.Empty()
			state.Account = syntheticOwner
			store := store2.Store{Dir: dir, Vault: vault}
			if err := store.Save(state, now); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(dir, "records-v2.enc")
			before, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}

			total := int32(len(collect.Streams()) + 4)
			var requests atomic.Int32
			afterFinal := stage == "after the final request"
			options := syntheticCollection(t, dir, vault, now, func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer "+syntheticOwner+"-access" {
					t.Error("the provider received credentials from a different account")
				}
				count := requests.Add(1)
				switch {
				case !afterFinal && count == 1:
					vault.switchNext.Store(true)
				case afterFinal && count == total:
					if err := vault.Set(item, vault.nextSession); err != nil {
						t.Error(err)
					}
				}
				_, _ = io.WriteString(w, "{}")
			})
			code, stdout, stderr := run(t, []string{"--state-dir", dir, "collect", "--days", "1", "--quiet"}, options)
			var body struct {
				Error struct{ Code, Message string }
			}
			if code != 1 || stdout != "" || json.Unmarshal([]byte(stderr), &body) != nil ||
				body.Error.Code != "collect_failed" || body.Error.Message != "account changed during collection; cache unchanged" {
				t.Fatal("account switch did not abort collection", code, stderr)
			}
			if requests.Load() == 0 || afterFinal && requests.Load() != total || !afterFinal && !vault.readSwitch.Load() {
				t.Fatal("account switch did not reach the intended boundary", requests.Load())
			}
			after, err := os.ReadFile(path)
			if err != nil || !bytes.Equal(before, after) {
				t.Fatal("account switch rewrote the store", err)
			}
		})
	}
}

func syntheticCollection(t *testing.T, dir string, vault secure.Vault, now time.Time, handler http.HandlerFunc) cli.Options {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	manager := auth.New(vault, dir)
	manager.AuthorizeURL, manager.TokenURL = server.URL+"/consent", server.URL+"/token"
	client := health.New(manager.Access)
	client.BaseURL, client.HTTP = server.URL, server.Client()
	return cli.Options{Auth: manager, Vault: vault, Fetcher: client, Now: func() time.Time { return now }}
}

func syntheticLoginArgs(t *testing.T, manager *auth.Manager) []string {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	manager.CallbackURL = "http://" + listener.Addr().String() + "/oauth/callback"
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	clientFile := filepath.Join(manager.Dir, "synthetic-client.json")
	client := fmt.Sprintf(`{"web":{"client_id":"synthetic-client","client_secret":"synthetic-secret","redirect_uris":[%q]}}`, manager.CallbackURL)
	if err := os.WriteFile(clientFile, []byte(client), 0600); err != nil {
		t.Fatal(err)
	}
	return []string{"--state-dir", manager.Dir, "auth", "login", "--client-file", clientFile, "--no-browser"}
}

type consentWriter chan string

func (w consentWriter) Write(data []byte) (int, error) {
	if text := strings.TrimSpace(string(data)); strings.HasPrefix(text, "http") {
		w <- text
	}
	return len(data), nil
}

func completeSyntheticLogin(t *testing.T, manager *auth.Manager, args []string, options cli.Options) (int, string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	consent := make(consentWriter, 1)
	done := make(chan int, 1)
	var stderr bytes.Buffer
	go func() { done <- cli.Run(ctx, args, nil, consent, &stderr, options) }()
	var address string
	select {
	case address = <-consent:
	case code := <-done:
		return code, stderr.String()
	case <-ctx.Done():
		t.Fatal("synthetic login did not reach consent")
	}
	consentURL, err := url.Parse(address)
	if err != nil {
		t.Fatal("invalid synthetic consent URL")
	}
	query := url.Values{"state": {consentURL.Query().Get("state")}, "code": {"synthetic-code"}}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, manager.CallbackURL+"?"+query.Encode(), nil)
	if err != nil {
		t.Fatal("invalid synthetic callback")
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal("synthetic callback failed")
	}
	_, _ = io.Copy(io.Discard, response.Body)
	response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatal("synthetic callback status", response.StatusCode)
	}
	select {
	case code := <-done:
		return code, stderr.String()
	case <-ctx.Done():
		t.Fatal("synthetic login did not finish")
	}
	return 1, ""
}
