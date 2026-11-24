package auth_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestLoadClientRejectsAuthorizationAliasLookalikes(t *testing.T) {
	for _, tc := range []struct {
		name      string
		authorize string
		token     string
	}{
		{"http_alias", "http://accounts.google.com/o/oauth2/auth", "https://oauth2.googleapis.com/token"},
		{"lookalike_host", "https://accounts.google.com.attacker.example/o/oauth2/auth", "https://oauth2.googleapis.com/token"},
		{"userinfo_host", "https://accounts.google.com@attacker.example/o/oauth2/auth", "https://oauth2.googleapis.com/token"},
		{"query", "https://accounts.google.com/o/oauth2/auth?redirect=attacker", "https://oauth2.googleapis.com/token"},
		{"appended_path", "https://accounts.google.com/o/oauth2/auth/extra", "https://oauth2.googleapis.com/token"},
		{"trailing_slash", "https://accounts.google.com/o/oauth2/auth/", "https://oauth2.googleapis.com/token"},
		{"untrusted_token_host", "https://accounts.google.com/o/oauth2/auth", "https://oauth2.googleapis.com.attacker.example/token"},
		{"http_token", "https://accounts.google.com/o/oauth2/auth", "http://oauth2.googleapis.com/token"},
		{"token_query", "https://accounts.google.com/o/oauth2/auth", "https://oauth2.googleapis.com/token?extra=1"},
		{"token_path", "https://accounts.google.com/o/oauth2/auth", "https://oauth2.googleapis.com/token/extra"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(testutil.Dir(t), "synthetic-client.json")
			client := auth.ClientSpec{ID: "synthetic-client", Secret: "synthetic-secret", Redirects: []string{auth.Callback}, AuthURI: tc.authorize, TokenURI: tc.token}
			b, err := json.Marshal(map[string]auth.ClientSpec{"web": client})
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, b, 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := auth.LoadClient(path, auth.Callback); err == nil {
				t.Fatal("accepted non-exact endpoint alias")
			}
		})
	}
}

func TestLoadClientAcceptsGoogleDownloadedAuthorizationURI(t *testing.T) {
	dir := testutil.Dir(t)
	path := filepath.Join(dir, "synthetic-google-client.json")
	input := auth.ClientSpec{
		ID:        "synthetic-client",
		Secret:    "synthetic-secret",
		Redirects: []string{auth.Callback},
		AuthURI:   "https://accounts.google.com/o/oauth2/auth",
		TokenURI:  "https://oauth2.googleapis.com/token",
	}
	data, err := json.Marshal(map[string]auth.ClientSpec{"web": input})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	got, err := auth.LoadClient(path, auth.Callback)
	if err != nil {
		t.Fatalf("official downloaded Google client URI must load: %v", err)
	}
	if got.ID != input.ID || got.Secret != input.Secret {
		t.Fatal("client identity changed while loading")
	}
	manager := auth.New(&testutil.Vault{}, dir)
	if manager.AuthorizeURL != "https://accounts.google.com/o/oauth2/v2/auth" {
		t.Fatal("runtime must continue to use the fixed v2 authorization endpoint")
	}
}
