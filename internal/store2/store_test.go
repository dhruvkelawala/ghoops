package store2

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestEncryptedV2RoundTripPreservesV1AndSeparatesAAD(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	v1 := cache.Store{Dir: dir, Vault: vault}
	if err := v1.Save(cache.Empty()); err != nil {
		t.Fatal(err)
	}
	v1Path, v2Path := filepath.Join(dir, "records.enc"), filepath.Join(dir, "records-v2.enc")
	before, _ := os.ReadFile(v1Path)
	state, err := LoadPlainForTest("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	store := Store{Dir: dir, Vault: vault}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	if err := store.Save(state, now); err != nil {
		t.Fatal(err)
	}
	loaded, err := store.Load()
	if err != nil || !reflect.DeepEqual(state, loaded) {
		t.Fatal("v2 round-trip failed", err)
	}
	after, _ := os.ReadFile(v1Path)
	if !bytes.Equal(before, after) {
		t.Fatal("v2 save touched v1 bytes")
	}
	v2Bytes, _ := os.ReadFile(v2Path)
	if bytes.Contains(v2Bytes, []byte("synthetic-account")) {
		t.Fatal("plaintext found in encrypted store")
	}
	info, _ := os.Stat(v2Path)
	if info.Mode().Perm() != 0600 {
		t.Fatal("v2 cache permissions")
	}
	for _, rewriteHeader := range []bool{false, true} {
		v1Bytes, v2 := append([]byte(nil), before...), append([]byte(nil), v2Bytes...)
		if rewriteHeader {
			copy(v1Bytes, []byte(header))
			copy(v2, []byte("ghealth-cache-v1\n"))
		}
		if err := os.WriteFile(v2Path, v1Bytes, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := store.Load(); err == nil {
			t.Fatal("v1 file opened as v2")
		}
		if err := os.WriteFile(v1Path, v2, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := v1.Load(); err == nil {
			t.Fatal("v2 file opened as v1")
		}
	}
	corrupt := append([]byte(nil), v2Bytes...)
	corrupt[len(corrupt)-1] ^= 1
	_ = os.WriteFile(v2Path, corrupt, 0600)
	if _, err := store.Load(); err == nil {
		t.Fatal("corrupt file did not fail closed")
	}
}

func TestRetentionKeeps400LondonDaysAndLast50Runs(t *testing.T) {
	loc, _ := time.LoadLocation("Europe/London")
	now := time.Date(2026, 10, 25, 23, 30, 0, 0, loc)
	state := Empty()
	for _, age := range []int{400, 401} {
		date := now.AddDate(0, 0, -age).Format("2006-01-02")
		state.Records = append(state.Records, health.Record{Type: "sleep", Date: date, Raw: json.RawMessage(`{}`)})
		state.HRMinutes = append(state.HRMinutes, MinuteDay{Date: date, Windows: []Minute{}})
		state.DailyRollups = append(state.DailyRollups, DailyRollup{Type: "steps", Date: date, Value: json.RawMessage(`{}`)})
		state.Coverage = append(state.Coverage, cache.Coverage{Date: date})
	}
	for i := 0; i < 51; i++ {
		state.Runs = append(state.Runs, Run{StartedAt: now.Add(time.Duration(i) * time.Minute)})
	}
	store := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	if err := store.Save(state, now); err != nil {
		t.Fatal(err)
	}
	loaded, err := store.Load()
	if err != nil || len(loaded.Records) != 1 || len(loaded.HRMinutes) != 1 || len(loaded.DailyRollups) != 1 || len(loaded.Coverage) != 1 || len(loaded.Runs) != 50 {
		t.Fatal("retention failed", err)
	}
	if loaded.Records[0].Date != now.AddDate(0, 0, -400).Format("2006-01-02") || !loaded.Runs[0].StartedAt.Equal(state.Runs[1].StartedAt) {
		t.Fatal("retention boundary changed")
	}
}

func TestAllPlainInputFixturesLoad(t *testing.T) {
	files, err := filepath.Glob("../../fixtures/v2/inputs/*.json")
	if err != nil || len(files) == 0 {
		t.Fatal("no input fixtures found", err)
	}
	for _, file := range files {
		state, err := LoadPlainForTest(file)
		if err != nil || len(state.Records) == 0 || len(state.HRMinutes) == 0 || len(state.User) != 4 {
			t.Fatal(file, err)
		}
	}
}

func TestCollectLockIsNonblockingAndIndependentOfV1(t *testing.T) {
	store := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	unlock, err := store.Lock()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Lock(); !errors.Is(err, ErrCollectInProgress) {
		t.Fatal("concurrent collect must fail without waiting", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	v1Unlock, err := secure.Lock(ctx, store.Dir, "sync.lock")
	if err != nil {
		t.Fatal("v2 collect blocked the v1 sync lock", err)
	}
	v1Unlock()
	unlock()
	unlock, err = store.Lock()
	if err != nil {
		t.Fatal("collect lock not released", err)
	}
	unlock()
}

func TestOversizedV2FileFailsClosed(t *testing.T) {
	store := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	file, err := os.OpenFile(filepath.Join(store.Dir, "records-v2.enc"), os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	if err := file.Truncate(MaxSize + 1); err != nil {
		t.Fatal(err)
	}
	file.Close()
	if _, err := store.Load(); err == nil {
		t.Fatal("oversized store accepted")
	}
}
