package cache_test

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func resolveSyntheticAccount(account string) func(context.Context) (string, error) {
	return func(context.Context) (string, error) { return account, nil }
}

func state(t *testing.T) cache.State {
	t.Helper()
	s := cache.Empty()
	s.Account = "synthetic-user"
	s.Timezone = "Europe/London"
	s.Records = append(s.Records, testutil.Record(t, "steps", "raw", "2026-10-12", `{"dataSource":{"platform":"FITBIT"},"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":"123"}}`))
	return s
}

type concurrentSyntheticFetcher struct {
	row        health.Record
	active     atomic.Int32
	overlapped atomic.Bool
}

func (f *concurrentSyntheticFetcher) Fetch(ctx context.Context, k health.Kind, stream string, from, until time.Time) ([]health.Record, error) {
	if f.active.Add(1) > 1 {
		f.overlapped.Store(true)
	}
	defer f.active.Add(-1)
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(time.Millisecond):
	}
	if k.ID != "steps" {
		return nil, nil
	}
	r := f.row
	r.Stream = stream
	r.Date = from.Format("2006-01-02")
	r.Raw = []byte(strings.ReplaceAll(string(r.Raw), "2026-10-12", r.Date))
	return []health.Record{r}, nil
}
func TestConcurrentSyncSerializesAndPreservesOtherRange(t *testing.T) {
	loc, _ := time.LoadLocation("Europe/London")
	from, _ := time.ParseInLocation("2006-01-02", "2026-10-12", loc)
	store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	fetcher := &concurrentSyntheticFetcher{row: state(t).Records[0]}
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(day int) {
			defer wg.Done()
			start := from.AddDate(0, 0, day)
			if _, err := cache.Sync(context.Background(), store, fetcher, resolveSyntheticAccount("synthetic-user"), start, start.AddDate(0, 0, 1)); err != nil {
				t.Error(err)
			}
		}(i)
	}
	wg.Wait()
	loaded, err := store.Load()
	if err != nil || len(loaded.Records) != 4 || fetcher.overlapped.Load() {
		t.Fatal("sync isolation failed", len(loaded.Records), err)
	}
}

func TestEncryptedRoundTripTamperAndPermissions(t *testing.T) {
	v := &testutil.Vault{}
	store := cache.Store{Dir: testutil.Dir(t), Vault: v}
	s := state(t)
	if err := store.Save(s); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(store.Dir, "records.enc")
	first, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(first, []byte("synthetic-user")) || bytes.Contains(first, []byte(`"steps"`)) {
		t.Fatal("plaintext health cache")
	}
	fi, _ := os.Stat(path)
	if fi.Mode().Perm() != 0600 {
		t.Fatal("cache permissions", fi.Mode())
	}
	loaded, err := store.Load()
	if err != nil || len(loaded.Records) != 1 || !bytes.Equal(loaded.Records[0].Raw, s.Records[0].Raw) {
		t.Fatal("round trip", err)
	}
	if err := store.Save(s); err != nil {
		t.Fatal(err)
	}
	second, _ := os.ReadFile(path)
	if bytes.Equal(first, second) {
		t.Fatal("reused encryption nonce")
	}
	second[len(second)-1] ^= 1
	_ = os.WriteFile(path, second, 0600)
	if _, err := store.Load(); err == nil {
		t.Fatal("tampering accepted")
	}
}

func TestMissingKeyUnsafeFilesAndNoFallback(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	store := cache.Store{Dir: dir, Vault: v}
	if err := store.Save(state(t)); err != nil {
		t.Fatal(err)
	}
	_ = v.Delete(secure.Service(dir) + ".cache-key")
	if _, err := store.Load(); err == nil {
		t.Fatal("missing key silently regenerated")
	}
	unsafe := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	target := filepath.Join(testutil.Dir(t), "unrelated")
	_ = os.WriteFile(target, []byte("do not change"), 0600)
	_ = os.Symlink(target, filepath.Join(unsafe.Dir, "records.enc"))
	if err := unsafe.Save(state(t)); err == nil {
		t.Fatal("symlink overwritten")
	}
	got, _ := os.ReadFile(target)
	if string(got) != "do not change" {
		t.Fatal("unrelated file touched")
	}
	failure := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{FailSet: errors.New("synthetic Keychain failure")}}
	if err := failure.Save(state(t)); err == nil {
		t.Fatal("plaintext fallback")
	}
	entries, err := os.ReadDir(failure.Dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() != "cache-key.lock" {
			t.Fatal("wrote data despite Keychain failure")
		}
	}
}

type syntheticFetcher struct {
	record health.Record
	fail   bool
}

func (f syntheticFetcher) Fetch(ctx context.Context, k health.Kind, stream string, from, until time.Time) ([]health.Record, error) {
	if f.fail && k.ID == "steps" {
		return nil, &health.APIError{Status: 403, Code: "permission_denied"}
	}
	if k.ID == f.record.Type {
		r := f.record
		r.Stream = stream
		return []health.Record{r}, nil
	}
	return []health.Record{}, nil
}

func TestSyncReplacementFailuresAndAccountIsolation(t *testing.T) {
	loc, _ := time.LoadLocation("Europe/London")
	from, _ := time.ParseInLocation("2006-01-02", "2026-10-12", loc)
	until := from.AddDate(0, 0, 1)
	store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	row := state(t).Records[0]
	r, err := cache.Sync(context.Background(), store, syntheticFetcher{record: row}, resolveSyntheticAccount("synthetic-user"), from, until)
	if err != nil || !r.Complete || r.Records != 2 {
		t.Fatal("first sync", r, err)
	}
	if _, err := cache.Sync(context.Background(), store, syntheticFetcher{record: row}, resolveSyntheticAccount("synthetic-user"), from, until); err != nil {
		t.Fatal(err)
	}
	s, _ := store.Load()
	if len(s.Records) != 2 {
		t.Fatal("sync duplicate", len(s.Records))
	}
	r, err = cache.Sync(context.Background(), store, syntheticFetcher{record: row, fail: true}, resolveSyntheticAccount("synthetic-user"), from, until)
	if err == nil || r.Complete {
		t.Fatal("partial pass")
	}
	s, _ = store.Load()
	if len(s.Records) != 2 {
		t.Fatal("deleted prior records on failure")
	}
	for _, c := range s.Coverage {
		if c.Type == "steps" && (c.Status != "unavailable" || c.SuccessAt == nil || c.Count != 1) {
			t.Fatal("failure coverage", c)
		}
	}
	if _, err := cache.Sync(context.Background(), store, syntheticFetcher{}, resolveSyntheticAccount("synthetic-other-user"), from, until); err == nil {
		t.Fatal("mixed accounts")
	}
	if _, err := cache.Sync(context.Background(), store, syntheticFetcher{}, resolveSyntheticAccount("synthetic-user"), from, until); err != nil {
		t.Fatal(err)
	}
	s, _ = store.Load()
	if len(s.Records) != 0 {
		t.Fatal("remote deletions not reflected")
	}
}
