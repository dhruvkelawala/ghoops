package auth_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestForcedRefreshPreservesRotationAfterScopeLoss(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	syntheticSession(t, v, dir)
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		_ = r.ParseForm()
		want := "synthetic-refresh"
		if calls > 1 {
			want = fmt.Sprintf("synthetic-rotation-%d", calls-1)
		}
		if r.Form.Get("refresh_token") != want {
			t.Error("lost rotation after missing-permissions error")
		}
		response := map[string]any{"access_token": fmt.Sprintf("synthetic-access-%d", calls), "refresh_token": fmt.Sprintf("synthetic-rotation-%d", calls), "token_type": "Bearer", "expires_in": 3600}
		if calls == 1 {
			response["scope"] = ""
		} else if calls == 3 {
			response["scope"] = auth.Scopes[0]
		}
		fmtJSON(w, response)
	}))
	defer server.Close()
	m := auth.New(v, dir)
	m.TokenURL = server.URL
	for i := 1; i <= 3; i++ {
		err := m.Refresh(context.Background())
		if i < 3 && !errors.Is(err, auth.ErrPermissions) {
			t.Fatalf("scope loss or omitted scopes reused stale grant: %v", err)
		}
		if i == 3 && err != nil {
			t.Fatalf("new requested read grant did not recover: %v", err)
		}
		if calls != i {
			t.Fatalf("forced refresh exchanged %d times, want %d", calls, i)
		}
		if s := storedSession(t, v, dir); s.RefreshToken != fmt.Sprintf("synthetic-rotation-%d", i) {
			t.Fatal("rotation not persisted")
		}
	}
	status, err := m.Status(context.Background())
	if err != nil || status.State != "partial_permissions" || !status.Authorized {
		t.Fatalf("recovered grant status = %+v, err=%v", status, err)
	}
}

func TestConcurrentForcedRefreshSerializesRotations(t *testing.T) {
	v := &testutil.Vault{}
	dir := testutil.Dir(t)
	syntheticSession(t, v, dir)
	var calls atomic.Int32
	var active atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if active.Add(1) != 1 {
			t.Error("concurrent exchanges escaped auth lock")
		}
		defer active.Add(-1)
		call := calls.Add(1)
		_ = r.ParseForm()
		want := "synthetic-refresh"
		if call > 1 {
			want = fmt.Sprintf("synthetic-rotation-%d", call-1)
		}
		if r.Form.Get("refresh_token") != want {
			t.Errorf("call %d used %q, want persisted %q", call, r.Form.Get("refresh_token"), want)
		}
		fmtJSON(w, map[string]any{"access_token": fmt.Sprintf("synthetic-access-%d", call), "refresh_token": fmt.Sprintf("synthetic-rotation-%d", call), "token_type": "Bearer", "expires_in": 3600})
	}))
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	start := make(chan struct{})
	done := make(chan error, 6)
	for i := 0; i < 6; i++ {
		m := auth.New(v, dir)
		m.TokenURL = server.URL
		go func() {
			<-start
			done <- m.Refresh(ctx)
		}()
	}
	close(start)
	for i := 0; i < 6; i++ {
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}
	if calls.Load() != 6 {
		t.Fatalf("each explicit request must exchange once, got %d", calls.Load())
	}
	if s := storedSession(t, v, dir); s.RefreshToken != "synthetic-rotation-6" {
		t.Fatalf("last rotation not persisted: %+v", s)
	}
}

func TestForcedRefreshCancellationRetainsSession(t *testing.T) {
	for _, phase := range []string{"waiting_for_lock", "in_flight"} {
		t.Run(phase, func(t *testing.T) {
			v := &testutil.Vault{}
			dir := testutil.Dir(t)
			syntheticSession(t, v, dir)
			before, _ := v.Get(secure.Service(dir) + ".oauth")
			started := make(chan struct{})
			release := make(chan struct{})
			var calls atomic.Int32
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				close(started)
				select {
				case <-r.Context().Done():
				case <-release:
				}
			}))
			defer server.Close()
			defer close(release)
			m := auth.New(v, dir)
			m.TokenURL = server.URL
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			if phase == "waiting_for_lock" {
				unlock, err := secure.Lock(context.Background(), dir, "auth.lock")
				if err != nil {
					t.Fatal(err)
				}
				defer unlock()
			}
			done := make(chan error, 1)
			go func() { done <- m.Refresh(ctx) }()
			if phase == "in_flight" {
				select {
				case <-started:
				case <-ctx.Done():
					t.Fatal("refresh never reached token endpoint")
				}
			}
			cancel()
			select {
			case err := <-done:
				if err == nil {
					t.Fatal("cancelled refresh succeeded")
				}
			case <-time.After(3 * time.Second):
				t.Fatal("refresh ignored cancellation")
			}
			if phase == "waiting_for_lock" && calls.Load() != 0 {
				t.Fatal("cancelled lock wait reached token endpoint")
			}
			after, _ := v.Get(secure.Service(dir) + ".oauth")
			if string(before) != string(after) {
				t.Fatal("cancelled refresh modified session")
			}
		})
	}
}

func TestForcedRefreshExchangesExactlyOnce(t *testing.T) {
	for _, tc := range []struct {
		name    string
		expires time.Duration
	}{
		{"expired", -time.Hour},
		{"near_expiry", 30 * time.Second},
		{"valid", time.Hour},
	} {
		t.Run(tc.name, func(t *testing.T) {
			v := &testutil.Vault{}
			dir := testutil.Dir(t)
			syntheticSession(t, v, dir)
			s := storedSession(t, v, dir)
			s.ExpiresAt = time.Now().Add(tc.expires)
			b, _ := json.Marshal(s)
			if err := v.Set(secure.Service(dir)+".oauth", b); err != nil {
				t.Fatal(err)
			}
			calls := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls++
				_ = r.ParseForm()
				want := "synthetic-refresh"
				if calls > 1 {
					want = fmt.Sprintf("synthetic-rotation-%d", calls-1)
				}
				if r.Form.Get("refresh_token") != want {
					t.Error("rotation was not persisted before next exchange")
				}
				fmtJSON(w, map[string]any{"access_token": fmt.Sprintf("synthetic-access-%d", calls), "refresh_token": fmt.Sprintf("synthetic-rotation-%d", calls), "token_type": "Bearer", "expires_in": 3600})
			}))
			defer server.Close()
			m := auth.New(v, dir)
			m.TokenURL = server.URL
			if err := m.Refresh(context.Background()); err != nil {
				t.Fatal(err)
			}
			if calls != 1 {
				t.Fatalf("one explicit refresh must exchange once, got %d", calls)
			}
			persisted := storedSession(t, v, dir)
			if persisted.RefreshToken != "synthetic-rotation-1" || persisted.AccessToken != "synthetic-access-1" {
				t.Fatalf("forced refresh rotation not saved: %+v", persisted)
			}
		})
	}
}
