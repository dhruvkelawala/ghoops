package activities_test

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

type firstWriteVault struct {
	mu      sync.Mutex
	key     []byte
	reads   int
	writes  int
	arrived chan struct{}
}

func (v *firstWriteVault) Get(string) ([]byte, error) {
	v.mu.Lock()
	v.reads++
	n := v.reads
	if n == 2 {
		close(v.arrived)
	}
	key := append([]byte(nil), v.key...)
	v.mu.Unlock()
	if n <= 2 {
		<-v.arrived
		return nil, secure.ErrNotFound
	}
	if len(key) == 0 {
		return nil, secure.ErrNotFound
	}
	return key, nil
}
func (v *firstWriteVault) Set(_ string, key []byte) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.key = append([]byte(nil), key...)
	v.writes++
	return nil
}
func (v *firstWriteVault) Create(_ string, key []byte) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.key != nil {
		return secure.ErrExists
	}
	v.key = append([]byte(nil), key...)
	v.writes++
	return nil
}
func (*firstWriteVault) Delete(string) error { return nil }

func TestFirstActivityAndCollectorWritesShareOneKey(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &firstWriteVault{arrived: make(chan struct{})}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	mac := store2.Store{Dir: dir, Vault: vault}
	phone := activities.Store{Dir: dir, Vault: vault}
	errors := make(chan error, 2)
	go func() { errors <- mac.Save(store2.Empty(), now) }()
	go func() {
		_, _, err := phone.Put(context.Background(), activities.Upload{ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING", DisplayName: "Boxing", Start: now.Add(-time.Hour), End: now}, now)
		errors <- err
	}()
	for range 2 {
		if err := <-errors; err != nil {
			t.Fatal(err)
		}
	}
	if vault.writes != 1 {
		t.Fatalf("created %d encryption keys, want 1", vault.writes)
	}
	if _, err := mac.Load(); err != nil {
		t.Fatal(err)
	}
	if rows, err := phone.List(); err != nil || len(rows) != 1 {
		t.Fatalf("activity round trip: count=%d error=%v", len(rows), err)
	}
}
