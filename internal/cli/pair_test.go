package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestPairRejectsInvalidURLAsUsageBeforeDiscovery(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	t.Setenv("PATH", t.TempDir())
	for _, value := range []string{"http://synthetic.invalid", "https://user:synthetic-secret@synthetic.invalid", "https://"} {
		var out, stderr bytes.Buffer
		code := Run(context.Background(), []string{"--state-dir", testutil.Dir(t), "pair", "--url", value, "--json"}, nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
		var body v2report.ErrorBody
		if code != 2 || len(out.Bytes()) != 0 || json.Unmarshal(stderr.Bytes(), &body) != nil || body.Error.Code != "invalid_request" || !strings.Contains(body.Error.Message, "url") || strings.Contains(stderr.String(), "synthetic-secret") {
			t.Fatalf("invalid pair URL: exit=%d %s", code, stderr.String())
		}
	}
}
