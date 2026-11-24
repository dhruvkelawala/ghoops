package cli_test

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestConcurrentV2CollectExitsWithCollectInProgress(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	unlock, err := (store2.Store{Dir: dir, Vault: vault}).Lock()
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	code, out, stderr := run(t, []string{"--state-dir", dir, "collect", "--quiet"}, cli.Options{Vault: vault})
	var body struct {
		Version int `json:"schema_version"`
		Error   struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if code != 1 || out != "" || json.Unmarshal([]byte(stderr), &body) != nil || body.Version != 2 || body.Error.Code != "collect_in_progress" {
		t.Fatal("concurrent collect did not return the v2 error", code, out, stderr)
	}
}

type collectionGateVault struct {
	testutil.Vault
	dir    string
	read   chan error
	resume chan struct{}
	once   sync.Once
}

func (v *collectionGateVault) Get(key string) ([]byte, error) {
	if key == secure.Service(v.dir)+".oauth" {
		v.once.Do(func() {
			ctx, cancel := context.WithCancel(context.Background())
			cancel()
			unlock, err := secure.Lock(ctx, v.dir, "sync.lock")
			if err == nil {
				unlock()
			}
			v.read <- err
			<-v.resume
		})
	}
	return v.Vault.Get(key)
}

type credentialSyntheticFetcher struct {
	manager *auth.Manager
	tokens  []string
}

func TestCLICollectionCancelledWaitingForLockDoesNotReadOAuth(t *testing.T) {
	dir := testutil.Dir(t)
	unlock, err := secure.Lock(context.Background(), dir, "sync.lock")
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	vault := &collectionGateVault{dir: dir, read: make(chan error, 1), resume: make(chan struct{})}
	close(vault.resume)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	var out, stderr bytes.Buffer
	code := cli.Run(ctx, []string{"--state-dir", dir, "sync", "--days", "1"}, strings.NewReader(""), &out, &stderr, cli.Options{Vault: vault, Fetcher: emptySyntheticFetcher{}})
	if code != 1 || !strings.Contains(stderr.String(), "waiting for local state lock") {
		t.Fatalf("cancelled collection did not stop at the held lock: exit %d, %s", code, stderr.String())
	}
	select {
	case <-vault.read:
		t.Fatal("cancelled collection read an OAuth snapshot before acquiring sync.lock")
	default:
	}
	state, err := (cache.Store{Dir: dir, Vault: vault}).Load()
	if err != nil || state.Account != "" || len(state.Records) != 0 || len(state.Coverage) != 0 {
		t.Fatal("cancelled collection changed the cold profile", err)
	}
}

func (f *credentialSyntheticFetcher) Fetch(ctx context.Context, _ health.Kind, _ string, _, _ time.Time) ([]health.Record, error) {
	token, err := f.manager.Access(ctx, "")
	if err == nil {
		f.tokens = append(f.tokens, token)
	}
	return nil, err
}

func TestCLIColdProfileOAuthReadIsProtectedFromConcurrentLogout(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &collectionGateVault{dir: dir, read: make(chan error, 1), resume: make(chan struct{})}
	session := auth.Session{Client: auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret"}, AccessToken: "synthetic-account-A-access", RefreshToken: "synthetic-refresh", ExpiresAt: time.Now().Add(time.Hour), Scopes: auth.Scopes, HealthUserID: "synthetic-account-A"}
	encoded, err := json.Marshal(session)
	if err != nil {
		t.Fatal(err)
	}
	if err := vault.Set(secure.Service(dir)+".oauth", encoded); err != nil {
		t.Fatal(err)
	}
	manager := auth.New(vault, dir)
	fetcher := &credentialSyntheticFetcher{manager: manager}
	opts := cli.Options{Vault: vault, Auth: manager, Fetcher: fetcher, Now: func() time.Time { return time.Date(2026, 10, 13, 12, 0, 0, 0, time.UTC) }}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan int, 1)
	var out, stderr bytes.Buffer
	go func() {
		done <- cli.Run(ctx, []string{"--state-dir", dir, "sync", "--days", "1"}, strings.NewReader(""), &out, &stderr, opts)
	}()
	var resume sync.Once
	defer func() { resume.Do(func() { close(vault.resume) }) }()
	select {
	case lockErr := <-vault.read:
		if lockErr == nil {
			resume.Do(func() { close(vault.resume) })
			<-done
			t.Fatal("collection read OAuth before acquiring sync.lock; a cold-profile account switch can bind fetched records to the wrong account")
		}
		if lockErr.Error() != "timed out waiting for local state lock" {
			t.Fatal("collection lock probe failed for a reason other than contention", lockErr)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("collection never reached the synthetic credential boundary")
	}
	logoutCtx, cancelLogout := context.WithCancel(context.Background())
	cancelLogout()
	var logoutOut, logoutErr bytes.Buffer
	code := cli.Run(logoutCtx, []string{"--state-dir", dir, "auth", "logout"}, strings.NewReader(""), &logoutOut, &logoutErr, opts)
	if code != 1 || !strings.Contains(logoutErr.String(), "waiting for local state lock") {
		t.Errorf("cancelled concurrent logout was not excluded: exit %d, %s", code, logoutErr.String())
	}
	resume.Do(func() { close(vault.resume) })
	select {
	case code := <-done:
		if code != 0 || stderr.Len() != 0 {
			t.Fatalf("collection failed: exit %d, %s", code, stderr.String())
		}
	case <-time.After(5 * time.Second):
		t.Fatal("collection deadlocked after the OAuth read resumed")
	}
	state, err := (cache.Store{Dir: dir, Vault: vault}).Load()
	if err != nil || state.Account != "synthetic-account-A" || len(fetcher.tokens) == 0 {
		t.Fatalf("cold profile was not bound to the fetched account: account %q, tokens %d, error %v", state.Account, len(fetcher.tokens), err)
	}
	for _, token := range fetcher.tokens {
		if token != "synthetic-account-A-access" {
			t.Fatal("fetch used credentials from a different account")
		}
	}
	code, _, logoutText := run(t, []string{"--state-dir", dir, "auth", "logout"}, opts)
	if code != 0 || logoutText != "" {
		t.Fatal("collection failed to release sync.lock", code, logoutText)
	}
	if _, err := vault.Get(secure.Service(dir) + ".oauth"); err != secure.ErrNotFound {
		t.Fatal("logout did not remove the synthetic session", err)
	}
	if _, err := (cache.Store{Dir: dir, Vault: vault}).Load(); err != nil {
		t.Fatal("logout did not retain the synthetic encrypted cache", err)
	}
}
