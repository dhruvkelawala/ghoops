package cache_test

import (
	"bytes"
	"sync"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

type firstReadGate struct {
	*testutil.Vault
	once   sync.Once
	read   chan struct{}
	resume chan struct{}
}

type racingCreator struct {
	testutil.Vault
	winner []byte
}

func (v *racingCreator) Create(item string, key []byte) error {
	if err := v.Vault.Set(item, v.winner); err != nil {
		return err
	}
	return v.Vault.Create(item, key)
}

func TestCacheKeyReadsWinnerOnDuplicate(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &racingCreator{winner: bytes.Repeat([]byte{1}, 32)}
	key, err := secure.CacheKey(dir, vault, true)
	if err != nil || !bytes.Equal(key, vault.winner) {
		t.Fatal("cache key did not match the already created item", err)
	}
}

func (v *firstReadGate) Get(item string) ([]byte, error) {
	key, err := v.Vault.Get(item)
	v.once.Do(func() {
		close(v.read)
		<-v.resume
	})
	return key, err
}

func TestV1AndV2KeyCreationShareOneKey(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	v1Vault := &firstReadGate{Vault: vault, read: make(chan struct{}), resume: make(chan struct{})}
	v1 := cache.Store{Dir: dir, Vault: v1Vault}
	v2 := store2.Store{Dir: dir, Vault: vault}
	oldState := state(t)
	saved := make(chan error, 1)
	go func() { saved <- v1.Save(oldState) }()

	<-v1Vault.read
	newState := store2.Empty()
	newState.Account = oldState.Account
	saveErr := v2.Save(newState, time.Now())
	winner, err := vault.Get(secure.Service(dir) + ".cache-key")
	close(v1Vault.resume)
	if saveErr != nil {
		t.Fatal(saveErr)
	}
	if err != nil {
		t.Fatal(err)
	}
	if err := <-saved; err != nil {
		t.Fatal(err)
	}
	if got, err := v1.Load(); err != nil || got.Account != oldState.Account {
		t.Fatalf("v1 load: expected account=%t err=%v", got.Account == oldState.Account, err)
	}
	if got, err := v2.Load(); err != nil || got.Account != newState.Account {
		t.Fatalf("v2 load: expected account=%t err=%v", got.Account == newState.Account, err)
	}
	if got, err := vault.Get(secure.Service(dir) + ".cache-key"); err != nil || !bytes.Equal(got, winner) {
		t.Fatal("the first key did not survive", err)
	}
}
