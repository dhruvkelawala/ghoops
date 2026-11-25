package testutil

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
)

// Vault contains synthetic values only and replaces the OS credential boundary in tests.
type Vault struct {
	mu      sync.Mutex
	items   map[string][]byte
	FailSet error
}

func (v *Vault) Get(key string) ([]byte, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	data, ok := v.items[key]
	if !ok {
		return nil, secure.ErrNotFound
	}
	return append([]byte{}, data...), nil
}
func (v *Vault) Set(key string, data []byte) error {
	return v.put(key, data, false)
}
func (v *Vault) Create(key string, data []byte) error {
	return v.put(key, data, true)
}
func (v *Vault) put(key string, data []byte, createOnly bool) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.FailSet != nil {
		return v.FailSet
	}
	if _, exists := v.items[key]; createOnly && exists {
		return secure.ErrExists
	}
	if v.items == nil {
		v.items = map[string][]byte{}
	}
	v.items[key] = append([]byte{}, data...)
	return nil
}
func (v *Vault) Delete(key string) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	if _, ok := v.items[key]; !ok {
		return secure.ErrNotFound
	}
	delete(v.items, key)
	return nil
}

func Record(t *testing.T, id, stream, date, synthetic string) health.Record {
	t.Helper()
	if !json.Valid([]byte(synthetic)) {
		t.Fatal("invalid synthetic fixture")
	}
	return health.Record{Type: id, Stream: stream, Date: date, Raw: json.RawMessage(synthetic), Synthetic: true}
}

func Dir(t *testing.T) string {
	t.Helper()
	path, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0700); err != nil {
		t.Fatal(err)
	}
	return path
}
