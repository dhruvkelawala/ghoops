package serve

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestValidBearerPassesDuringLockout(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	tokens := pairing.Tokens{Dir: dir, Vault: vault}
	token, err := tokens.Pair(context.Background(), false, now)
	if err != nil {
		t.Fatal(err)
	}
	h, err := New(Settings{
		Store:  store2.Store{Dir: dir, Vault: vault},
		Config: config.File{Path: filepath.Join(dir, "config.json")},
		Tokens: tokens,
		Now:    func() time.Time { return now },
	})
	if err != nil {
		t.Fatal(err)
	}
	for range 11 {
		h.failures = append(h.failures, now)
	}
	r := httptest.NewRequest(http.MethodGet, "/v2/status", nil)
	r.Header.Set("Authorization", "Bearer "+token.Value)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("paired request got %d, want 200", w.Code)
	}
}

func TestFailureListBounded(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	h, err := New(Settings{
		Tokens: pairing.Tokens{Dir: testutil.Dir(t), Vault: &testutil.Vault{}},
		Now:    func() time.Time { return now },
	})
	if err != nil {
		t.Fatal(err)
	}
	for range 1000 {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/v2/status", nil))
	}
	if len(h.failures) > 11 {
		t.Fatalf("stored %d failures, want at most 11", len(h.failures))
	}
}
