package cli_test

import (
	"encoding/json"
	"errors"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/secure"
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
}
