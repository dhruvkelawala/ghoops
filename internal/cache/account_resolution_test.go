package cache_test

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

type countingAccountFetcher struct{ calls int }

func (f *countingAccountFetcher) Fetch(context.Context, health.Kind, string, time.Time, time.Time) ([]health.Record, error) {
	f.calls++
	return nil, nil
}

func TestSyncRejectsEmptyResolvedAccountBeforeFetchingAndReleasesLock(t *testing.T) {
	store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	fetcher := &countingAccountFetcher{}
	from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
	_, err := cache.Sync(context.Background(), store, fetcher, resolveSyntheticAccount(""), from, from.AddDate(0, 0, 1))
	if err == nil || !strings.Contains(err.Error(), "account") {
		t.Fatalf("collection accepted an empty resolved account: %v", err)
	}
	if fetcher.calls != 0 {
		t.Fatal("collection fetched before validating account ownership")
	}
	if _, err := os.Stat(filepath.Join(store.Dir, "records.enc")); !os.IsNotExist(err) {
		t.Fatal("invalid account collection wrote a cache", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	unlock, err := secure.Lock(ctx, store.Dir, "sync.lock")
	if err != nil {
		t.Fatal("account rejection did not release the collection lock", err)
	}
	unlock()
}

func TestSyncResolutionFailurePreservesCacheAndReleasesLock(t *testing.T) {
	resolutionErr := errors.New("synthetic authorization failure")
	for _, tc := range []struct {
		name    string
		account string
		err     error
	}{
		{name: "credential error", err: resolutionErr},
		{name: "different account", account: "synthetic-other-user"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			if err := store.Save(state(t)); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(store.Dir, "records.enc")
			before, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			fetcher := &countingAccountFetcher{}
			from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
			_, err = cache.Sync(context.Background(), store, fetcher, func(context.Context) (string, error) {
				return tc.account, tc.err
			}, from, from.AddDate(0, 0, 1))
			if err == nil || (tc.err != nil && !errors.Is(err, tc.err)) {
				t.Fatal("collection did not reject the account resolution failure", err)
			}
			if fetcher.calls != 0 {
				t.Fatal("collection fetched before account validation")
			}
			after, readErr := os.ReadFile(path)
			if readErr != nil || !bytes.Equal(before, after) {
				t.Fatal("account resolution failure changed the encrypted cache", readErr)
			}
			ctx, cancel := context.WithCancel(context.Background())
			cancel()
			unlock, err := secure.Lock(ctx, store.Dir, "sync.lock")
			if err != nil {
				t.Fatal("account resolution failure leaked sync.lock", err)
			}
			unlock()
		})
	}
}
