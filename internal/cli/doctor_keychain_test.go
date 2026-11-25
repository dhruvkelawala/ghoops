package cli_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestDoctorKeychainReportsACLsForSelectedProfile(t *testing.T) {
	dir := filepath.Join(testutil.Dir(t), "selected")
	prefix := secure.Service(dir)
	read := func(service string) (bool, error) {
		switch service {
		case prefix + ".cache-key", prefix + ".serve-devices":
			return true, nil
		case prefix + ".oauth":
			return false, nil
		case prefix + ".serve-token":
			return false, secure.ErrNotFound
		default:
			return false, errors.New("unexpected Keychain item")
		}
	}
	opts := cli.Options{Vault: &testutil.Vault{}, ReadKeychainACL: read}
	args := []string{"--state-dir", dir, "doctor", "--keychain"}
	code, stdout, stderr := run(t, append(args, "--json"), opts)
	if code != 0 || stderr != "" {
		t.Fatal("Keychain report failed", code, stderr)
	}
	var report map[string]any
	if err := json.Unmarshal([]byte(stdout), &report); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{
		"schema_version": float64(1),
		"items": map[string]any{
			"cache_key":     map[string]any{"exists": true, "only_installed_binary": true},
			"oauth_session": map[string]any{"exists": true, "only_installed_binary": false},
			"serve_token":   map[string]any{"exists": false, "only_installed_binary": false},
			"serve_devices": map[string]any{"exists": true, "only_installed_binary": true},
		},
	}
	if !reflect.DeepEqual(report, want) {
		t.Fatal("unexpected JSON ACL report", report)
	}
	code, stdout, stderr = run(t, args, opts)
	wantText := "Cache key: exists=true only_installed_binary=true\n" +
		"OAuth session: exists=true only_installed_binary=false\n" +
		"Serve token: exists=false only_installed_binary=false\n" +
		"Serve devices: exists=true only_installed_binary=true\n"
	if code != 0 || stderr != "" || stdout != wantText {
		t.Fatal("unexpected text ACL report", code, stdout, stderr)
	}
}

func TestDoctorKeychainReturnsErrorWhenACLReadFails(t *testing.T) {
	dir := testutil.Dir(t)
	opts := cli.Options{Vault: &testutil.Vault{}, ReadKeychainACL: func(service string) (bool, error) {
		if service == secure.Service(dir)+".cache-key" {
			return true, nil
		}
		return false, errors.New("Keychain unavailable")
	}}
	code, stdout, stderr := run(t, []string{"--state-dir", dir, "doctor", "--keychain", "--json"}, opts)
	if code != 1 || stdout != "" || stderr == "" {
		t.Fatal("failed ACL read produced a report", code, stdout, stderr)
	}
}

func TestDoctorKeychainCannotCombineWithOtherModes(t *testing.T) {
	dir := testutil.Dir(t)
	opts := cli.Options{Vault: &testutil.Vault{}, ReadKeychainACL: func(string) (bool, error) {
		t.Fatal("invalid usage reached the ACL reader")
		return false, nil
	}}
	for _, mode := range []string{"--offline", "--keychain-test", "--live"} {
		if code, stdout, _ := run(t, []string{"--state-dir", dir, "doctor", "--keychain", mode}, opts); code != 2 || stdout != "" {
			t.Fatal("doctor accepted more than one mode", mode, code, stdout)
		}
	}
	if code, stdout, _ := run(t, []string{"--state-dir", dir, "doctor", "--repair"}, opts); code != 2 || stdout != "" {
		t.Fatal("doctor accepted repair without --keychain", code, stdout)
	}
}

type keychainTestVault struct {
	testutil.Vault
	deletes atomic.Int32
}

func (v *keychainTestVault) Delete(item string) error {
	v.deletes.Add(1)
	return v.Vault.Delete(item)
}

func (v *keychainTestVault) acl(dir string, broad ...secure.KeychainItem) func(string) (bool, error) {
	return func(service string) (bool, error) {
		if _, err := v.Vault.Get(service); err != nil {
			return false, err
		}
		for _, item := range broad {
			if service == item.Service(dir) {
				return false, nil
			}
		}
		return true, nil
	}
}

func TestKeychainReadsWithPairedDeviceAndNoLegacyToken(t *testing.T) {
	dir, vault, now := testutil.Dir(t), &keychainTestVault{}, time.Now()
	state := store2.Empty()
	state.Account = syntheticOwner
	store := store2.Store{Dir: dir, Vault: vault}
	if err := store.Save(state, now); err != nil {
		t.Fatal(err)
	}
	if err := vault.Set(secure.OAuthSessionItem.Service(dir), syntheticSession(t, syntheticOwner)); err != nil {
		t.Fatal(err)
	}
	devices := pairing.Devices{Dir: dir, Vault: vault}
	code, err := devices.Create(t.Context(), now)
	if err != nil {
		t.Fatal(err)
	}
	device, err := devices.Redeem(t.Context(), code, "Synthetic phone", now)
	if err != nil {
		t.Fatal(err)
	}
	if err := devices.Approve(t.Context(), code, now); err != nil {
		t.Fatal(err)
	}
	vault.deletes.Store(0)
	if _, err := vault.Get(secure.ServeTokenItem.Service(dir)); !errors.Is(err, secure.ErrNotFound) {
		t.Fatal("expected an absent legacy token", err)
	}
	var requests atomic.Int32
	opts := syntheticCollection(t, dir, vault, now, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+syntheticOwner+"-access" {
			t.Error("stub did not receive the synthetic OAuth session")
		}
		requests.Add(1)
		_, _ = io.WriteString(w, "{}")
	})
	opts.ReadKeychainACL = vault.acl(dir)
	for _, check := range []struct {
		args []string
		want string
	}{
		{[]string{"status"}, `"authorized":true`},
		{[]string{"collect", "--days", "1", "--quiet"}, `"status":"ok"`},
		{[]string{"pair", "devices", "--json"}, `"state":"active"`},
	} {
		exit, stdout, stderr := run(t, append([]string{"--state-dir", dir}, check.args...), opts)
		if exit != 0 || stderr != "" || !strings.Contains(stdout, check.want) {
			t.Fatal("command failed with restricted Keychain items and no legacy token", check.args[0], exit, stderr)
		}
	}
	if requests.Load() == 0 {
		t.Fatal("collect did not reach the loopback provider")
	}
	if logs := checkKeychainServe(t, dir, device.Credential, opts); strings.Contains(logs, "no pairing token") || strings.Contains(logs, "doctor --keychain") {
		t.Fatal("server warned about the absent legacy token")
	}
	if exit, stdout, stderr := run(t, []string{"--state-dir", dir, "doctor", "--keychain", "--repair"}, opts); exit != 0 || stderr != "" || stdout != "No Keychain credentials needed repair.\n" {
		t.Fatal("repair treated the absent legacy token as a fault", exit, stderr)
	}
	if vault.deletes.Load() != 0 {
		t.Fatal("an ordinary read or clean repair attempted to delete an item")
	}
}

func checkKeychainServe(t *testing.T, dir, credential string, opts cli.Options) string {
	t.Helper()
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	_ = listener.Close()
	_, port, err := net.SplitHostPort(address)
	if err != nil || port == "8787" {
		t.Fatal("failed to reserve an isolated port")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()
	done := make(chan int, 1)
	var logs bytes.Buffer
	go func() {
		done <- cli.Run(ctx, []string{"--state-dir", dir, "serve", "--port", port}, nil, io.Discard, &logs, opts)
	}()
	client := &http.Client{Transport: &http.Transport{}}
	defer client.CloseIdleConnections()
	for _, route := range []string{"/v2/status", "/v2/snapshot", "/v2/pair/status"} {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://"+address+route, nil)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Authorization", "Bearer "+credential)
		for {
			response, err := client.Do(req)
			if err == nil {
				_, _ = io.Copy(io.Discard, response.Body)
				response.Body.Close()
				if response.StatusCode != http.StatusOK || response.Header.Get("X-Ghealth-Schema") != "2" {
					t.Fatal("paired request failed", route, response.StatusCode)
				}
				break
			}
			select {
			case exit := <-done:
				t.Fatal("serve exited before the request", exit, logs.String())
			case <-ctx.Done():
				t.Fatal("serve did not answer", route)
			case <-time.After(10 * time.Millisecond):
			}
		}
	}
	cancel()
	if exit := <-done; exit != 0 {
		t.Fatal("serve failed", exit)
	}
	return logs.String()
}

func TestKeychainRefusalLeavesCredentialsUntilExplicitRepair(t *testing.T) {
	dir, vault := testutil.Dir(t), &keychainTestVault{}
	items := []secure.KeychainItem{secure.OAuthSessionItem, secure.ServeDevicesItem, secure.ServeTokenItem}
	if err := vault.Set(secure.CacheKeyItem.Service(dir), make([]byte, 32)); err != nil {
		t.Fatal(err)
	}
	for _, item := range items {
		if err := vault.Set(item.Service(dir), []byte("synthetic credential")); err != nil {
			t.Fatal(err)
		}
	}
	if err := vault.Set(secure.ServeDevicesItem.Service(dir), []byte(`{"version":1,"devices":[]}`)); err != nil {
		t.Fatal(err)
	}
	opts := cli.Options{Vault: vault, ReadKeychainACL: vault.acl(dir, items...)}
	for _, args := range [][]string{{"status"}, {"auth", "status"}, {"pair", "devices"}} {
		exit, stdout, stderr := run(t, append([]string{"--state-dir", dir}, args...), opts)
		if exit != 1 || stdout != "" || !strings.Contains(stderr, "run ghoops doctor --keychain") {
			t.Fatal("expected a refusal with doctor instructions", args, exit, stderr)
		}
	}
	legacyOnly := cli.Options{Vault: vault, ReadKeychainACL: vault.acl(dir, secure.ServeTokenItem)}
	if exit, stdout, stderr := run(t, []string{"--state-dir", dir, "pair", "devices"}, legacyOnly); exit != 1 || stdout != "" || !strings.Contains(stderr, "run ghoops doctor --keychain") {
		t.Fatal("pair devices did not refuse a present legacy token with a broad ACL", exit, stderr)
	}
	if exit, _, _ := run(t, []string{"--state-dir", dir, "doctor", "--keychain"}, opts); exit != 0 || vault.deletes.Load() != 0 {
		t.Fatal("a read or report attempted to delete credentials")
	}
	exit, stdout, stderr := run(t, []string{"--state-dir", dir, "doctor", "--keychain", "--repair"}, opts)
	if exit != 0 || stderr != "" || !strings.Contains(stdout, "Log in again with ghoops auth login --client-file PATH.") || !strings.Contains(stdout, "Pair again with ghoops pair.") {
		t.Fatal("repair did not give recovery instructions", exit, stderr)
	}
	for _, item := range items {
		if _, err := vault.Get(item.Service(dir)); !errors.Is(err, secure.ErrNotFound) {
			t.Fatal("repair retained an unsafe credential", item, err)
		}
	}
	if _, err := vault.Get(secure.CacheKeyItem.Service(dir)); err != nil || vault.deletes.Load() != 3 {
		t.Fatal("repair touched the cache key or skipped a credential", err)
	}
}

func TestKeychainRefusesUnsafeCacheKeyWithoutReplacingIt(t *testing.T) {
	dir, vault, now := testutil.Dir(t), &keychainTestVault{}, time.Now()
	state := store2.Empty()
	if err := (store2.Store{Dir: dir, Vault: vault}).Save(state, now); err != nil {
		t.Fatal(err)
	}
	service := secure.CacheKeyItem.Service(dir)
	key, err := vault.Get(service)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "records-v2.enc")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	opts := cli.Options{Vault: vault, ReadKeychainACL: vault.acl(dir, secure.CacheKeyItem)}
	for _, args := range [][]string{{"status"}, {"collect", "--quiet"}, {"activity", "edits"}, {"doctor", "--keychain", "--repair"}} {
		exit, stdout, stderr := run(t, append([]string{"--state-dir", dir}, args...), opts)
		if exit != 1 || stdout != "" || !strings.Contains(stderr, "original") {
			t.Fatal("unsafe cache key was not refused clearly", args, exit, stderr)
		}
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("refusal changed encrypted records", err)
	}
	if got, err := vault.Get(service); err != nil || !bytes.Equal(got, key) || vault.deletes.Load() != 0 {
		t.Fatal("refusal removed or replaced the cache key", err)
	}
}
