package pairing

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"os/exec"
	"strings"
)

var ErrInvalidURL = errors.New("pairing URL must use HTTPS")

const ServeCommand = "tailscale serve --bg --https=8787 http://127.0.0.1:8787"

type Tailnet struct {
	URL, Name  string
	Configured bool
}

func Discover(ctx context.Context, override string) (Tailnet, error) {
	if override != "" {
		if err := validateURL(override); err != nil {
			return Tailnet{}, err
		}
	}
	binary, err := exec.LookPath("tailscale")
	if err != nil {
		binary = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
	}
	raw, err := exec.CommandContext(ctx, binary, "status", "--json").Output()
	if err != nil {
		return Tailnet{}, errors.New("Tailscale status unavailable")
	}
	var status struct {
		Self struct{ DNSName string }
	}
	if json.Unmarshal(raw, &status) != nil {
		return Tailnet{}, errors.New("invalid Tailscale status")
	}
	base := override
	if base == "" {
		dns := strings.TrimSuffix(status.Self.DNSName, ".")
		if dns == "" {
			return Tailnet{}, errors.New("Tailscale DNS name unavailable")
		}
		base = "https://" + dns + ":8787"
	}
	if err := validateURL(base); err != nil {
		return Tailnet{}, err
	}
	raw, err = exec.CommandContext(ctx, binary, "serve", "status", "--json").Output()
	configured := err == nil && ServeConfigured(raw)
	return Tailnet{URL: strings.TrimRight(base, "/"), Configured: configured}, nil
}
func ServeConfigured(raw []byte) bool {
	var status struct {
		TCP map[string]struct{ HTTPS bool }
		Web map[string]struct {
			Handlers map[string]struct{ Proxy string }
		}
	}
	if json.Unmarshal(raw, &status) != nil || !status.TCP["8787"].HTTPS {
		return false
	}
	for host, web := range status.Web {
		if strings.HasSuffix(host, ":8787") && web.Handlers["/"].Proxy == "http://127.0.0.1:8787" {
			return true
		}
	}
	return false
}
func validateURL(base string) error {
	parsed, err := url.Parse(base)
	if err != nil || parsed.Scheme != "https" || parsed.Hostname() == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
		return ErrInvalidURL
	}
	return nil
}
