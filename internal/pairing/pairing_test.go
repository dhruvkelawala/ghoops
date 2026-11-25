package pairing_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestTokenReuseRotationAndRevoke(t *testing.T) {
	tokens := pairing.Tokens{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	a, err := tokens.Pair(context.Background(), false, now)
	if err != nil {
		t.Fatal(err)
	}
	b, err := tokens.Pair(context.Background(), false, now.Add(time.Hour))
	if err != nil || a != b {
		t.Fatal("pair did not reuse token")
	}
	b, err = tokens.Pair(context.Background(), true, now.Add(time.Hour))
	if err != nil || a.Value == b.Value || len(b.Value) != 48 {
		t.Fatal("rotation failed")
	}
	if err = tokens.Revoke(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err = tokens.Load(); !errors.Is(err, secure.ErrNotFound) {
		t.Fatal("revocation failed")
	}
}
func TestTailscaleHandlerDetection(t *testing.T) {
	for _, tc := range []struct {
		raw  string
		want bool
	}{
		{`{"TCP":{"8787":{"HTTPS":true}},"Web":{"synthetic.ts.net:8787":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8787"}}}}}`, true},
		{`{"TCP":{"443":{"HTTPS":true}},"Web":{"synthetic.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8787"}}}}}`, false},
		{`{"TCP":{"8787":{"HTTPS":true}},"Web":{"synthetic.ts.net:8787":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9999"}}}}}`, false},
	} {
		if got := pairing.ServeConfigured([]byte(tc.raw)); got != tc.want {
			t.Fatalf("configured=%v want %v", got, tc.want)
		}
	}
}
