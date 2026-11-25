//go:build darwin && cgo

package cli

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"regexp"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/serve"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestPairTerminalKeepsLegacyAccessUntilApproval(t *testing.T) {
	hasCredential := regexp.MustCompile(`ghv[23]_[A-Za-z0-9_-]{43}`).MatchString
	for _, tc := range []struct {
		name, answer string
		exit, status int
	}{
		{"approve", "y\n", 0, 200},
		{"decline", "n\n", 1, 401},
		{"expire", "", 1, 401},
	} {
		t.Run(tc.name, func(t *testing.T) {
			usePairingTailnet(t)
			dir, vault := testutil.Dir(t), &testutil.Vault{}
			var clock atomic.Int64
			clock.Store(time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC).UnixNano())
			now := func() time.Time { return time.Unix(0, clock.Load()).UTC() }
			tokens := pairing.Tokens{Dir: dir, Vault: vault}
			legacy, err := tokens.Pair(t.Context(), false, now())
			if err != nil {
				t.Fatal(err)
			}
			handler, err := serve.New(serve.Settings{
				Store: store2.Store{Dir: dir, Vault: vault}, Now: now, MacName: "Mac A",
				Config: config.File{Path: filepath.Join(dir, "config.json")}, Tokens: tokens,
			})
			if err != nil {
				t.Fatal(err)
			}
			server := httptest.NewServer(handler)
			defer server.Close()
			ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
			defer cancel()
			status := func(path, credential string, want int) *string {
				t.Helper()
				request, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL+path, nil)
				if err != nil {
					t.Fatal(err)
				}
				request.Header.Set("Authorization", "Bearer "+credential)
				response, err := server.Client().Do(request)
				if err != nil {
					t.Fatal(err)
				}
				defer response.Body.Close()
				if response.StatusCode != want {
					t.Fatalf("%s got %d, want %d", path, response.StatusCode, want)
				}
				if path != "/v2/status" || want != 200 {
					return nil
				}
				var body v2report.Status
				if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
					t.Fatal(err)
				}
				return body.Server.ProfileID
			}
			if profile := status("/v2/status", legacy.Value, 200); profile != nil {
				t.Fatal("empty profile should not have an ID")
			}
			in, input := io.Pipe()
			defer in.Close()
			defer input.Close()
			output, out := io.Pipe()
			defer output.Close()
			defer out.Close()
			var stderr bytes.Buffer
			options := Options{Vault: vault, Now: now}
			done := make(chan int, 1)
			go func() {
				done <- Run(ctx, []string{"--state-dir", dir, "pair"}, in, out, &stderr, options)
				out.Close()
			}()
			scanner := bufio.NewScanner(output)
			read := func(prefix string) string {
				t.Helper()
				for scanner.Scan() {
					line := scanner.Text()
					if hasCredential(line) {
						t.Fatal("the terminal printed a device credential")
					}
					if value, found := strings.CutPrefix(line, prefix); found {
						return value
					}
				}
				t.Fatal("the terminal ended before the expected prompt")
				return ""
			}
			payload := strings.Fields(read("GHOOPS1 "))
			if len(payload) != 2 || payload[0] != "https://mac-a.invalid:8787" || len(payload[1]) != 43 {
				t.Fatal("invalid enrolment payload")
			}
			requestBody, err := json.Marshal(map[string]string{"code": payload[1], "device_name": "Fixture iPhone"})
			if err != nil {
				t.Fatal(err)
			}
			response, err := server.Client().Post(server.URL+"/v2/pair/redeem", "application/json", bytes.NewReader(requestBody))
			if err != nil {
				t.Fatal(err)
			}
			var redeemed v2report.PairRedeem
			decodeErr := json.NewDecoder(response.Body).Decode(&redeemed)
			response.Body.Close()
			if response.StatusCode != 201 || decodeErr != nil {
				t.Fatalf("redeem returned HTTP %d", response.StatusCode)
			}
			if code := read("Verification code: "); code != redeemed.VerificationCode || len(code) != 6 {
				t.Fatal("the terminal and redeem response verification codes differ")
			}
			read("Is the same code on your iPhone? Pair it? [y/N]")
			if profile := status("/v2/status", legacy.Value, 200); profile == nil || *profile != redeemed.ProfileID || len(*profile) != 22 {
				t.Fatal("pair should create a stable profile ID before the first collect")
			}
			if tc.answer == "" {
				clock.Add(int64(pairing.EnrolmentDuration))
			} else if _, err := io.WriteString(input, tc.answer); err != nil {
				t.Fatal(err)
			}
			for scanner.Scan() {
				if hasCredential(scanner.Text()) {
					t.Fatal("the terminal printed a device credential")
				}
			}
			if err := scanner.Err(); err != nil {
				t.Fatal(err)
			}
			if exit := <-done; exit != tc.exit || hasCredential(stderr.String()) {
				t.Fatalf("pair exited %d, want %d, or printed a credential", exit, tc.exit)
			}
			clock.Add(int64(5 * time.Second))
			status("/v2/status", redeemed.Credential, tc.status)
			status("/v2/pair/status", redeemed.Credential, tc.status)
			wantLegacy := 200
			if tc.exit == 0 {
				wantLegacy = 401
			}
			status("/v2/status", legacy.Value, wantLegacy)
			var listed, commandErrors bytes.Buffer
			exit := Run(ctx, []string{"--state-dir", dir, "pair", "devices", "--json"}, nil, &listed, &commandErrors, options)
			var devices v2report.PairDevices
			if exit != 0 || json.Unmarshal(listed.Bytes(), &devices) != nil || hasCredential(listed.String()) {
				t.Fatal("pair devices should return metadata without credentials")
			}
			if tc.exit == 0 {
				if len(devices.Devices) != 1 || devices.Devices[0].ID != redeemed.DeviceID || devices.Devices[0].State != "active" || devices.Devices[0].Approved == nil {
					t.Fatal("the approved phone was not listed as active")
				}
				var revoked bytes.Buffer
				exit := Run(ctx, []string{"--state-dir", dir, "pair", "revoke", redeemed.DeviceID, "--json"}, nil, &revoked, io.Discard, options)
				var body v2report.Pair
				if exit != 0 || json.Unmarshal(revoked.Bytes(), &body) != nil || body.Kind != "pair" || body.Paired || hasCredential(revoked.String()) {
					t.Fatalf("pair revoke exited %d or did not return the revoke body", exit)
				}
				clock.Add(int64(5 * time.Second))
				status("/v2/status", redeemed.Credential, 401)
			} else if len(devices.Devices) != 1 || devices.Devices[0].ID != "legacy" {
				t.Fatal("only the legacy pairing should remain")
			}
			redeemed.Credential, redeemed.VerificationCode = "ghv3_<redacted>", "<code>"
			var capture bytes.Buffer
			encoder := json.NewEncoder(&capture)
			encoder.SetEscapeHTML(false)
			if err := encoder.Encode(redeemed); err != nil {
				t.Fatal(err)
			}
			t.Log(`POST /v2/pair/redeem {"code":"<code>","device_name":"Fixture iPhone"}`)
			t.Logf("HTTP 201 %s", strings.TrimSpace(capture.String()))
			t.Logf("Verification code matches terminal, pair exit %d, GET /v2/status %d", tc.exit, tc.status)
			t.Logf("Legacy GET /v2/status before enrolment 200, pending 200, after %s %d", tc.name, wantLegacy)
		})
	}
}
