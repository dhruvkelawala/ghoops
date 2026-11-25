package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func usePairingTailnet(t *testing.T) {
	t.Helper()
	t.Setenv("HOME", testutil.Dir(t))
	bin := t.TempDir()
	t.Setenv("PATH", bin)
	stub := `#!/bin/sh
case "$1" in
	status) printf '%s\n' '{"Self":{"DNSName":"mac-a.invalid.","HostName":"Mac A"}}' ;;
	serve) printf '%s\n' '{"TCP":{"8787":{"HTTPS":true}},"Web":{"mac-a.invalid:8787":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8787"}}}}}' ;;
	*) exit 1 ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "tailscale"), []byte(stub), 0700); err != nil {
		t.Fatal(err)
	}
}

func TestPairRemovedOptions(t *testing.T) {
	usePairingTailnet(t)
	for _, tc := range []struct {
		option, message string
	}{
		{"--json", "pair uses the terminal and cannot be combined with --json"},
		{"--rotate", "Revoke a device with ghoops pair revoke <device>, then run ghoops pair."},
		{"--rotate=false", "Revoke a device with ghoops pair revoke <device>, then run ghoops pair."},
		{"--enrol", ""},
	} {
		t.Run(tc.option, func(t *testing.T) {
			var out, stderr bytes.Buffer
			code := Run(t.Context(), []string{"--state-dir", testutil.Dir(t), "pair", tc.option}, nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
			var body v2report.ErrorBody
			if code != 2 || out.Len() != 0 || json.Unmarshal(stderr.Bytes(), &body) != nil ||
				body.Error.Code != "invalid_request" || (tc.message != "" && body.Error.Message != tc.message) ||
				strings.Contains(stderr.String(), "ghv") {
				t.Fatalf("pair %s: exit=%d, unexpected output", tc.option, code)
			}
		})
	}
}

func TestPairRejectsInvalidURLAsUsageBeforeDiscovery(t *testing.T) {
	usePairingTailnet(t)
	for _, value := range []string{"http://synthetic.invalid", "https://user:synthetic-secret@synthetic.invalid", "https://"} {
		var out, stderr bytes.Buffer
		code := Run(t.Context(), []string{"--state-dir", testutil.Dir(t), "pair", "--url", value}, nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
		if code != 2 || len(out.Bytes()) != 0 || !strings.Contains(stderr.String(), "url must use https://") || strings.Contains(stderr.String(), "synthetic-secret") {
			t.Fatalf("invalid pair URL: exit=%d %s", code, stderr.String())
		}
	}
}
