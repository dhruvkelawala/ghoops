package serve

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

type pairingVault struct {
	testutil.Vault
	unavailable string
}

func (v *pairingVault) Get(item string) ([]byte, error) {
	if v.unavailable != "" && strings.HasSuffix(item, v.unavailable) {
		return nil, errors.New("fixture credential store unavailable")
	}
	return v.Vault.Get(item)
}

type pairingTestServer struct {
	t       *testing.T
	now     time.Time
	expires time.Time
	devices pairing.Devices
	legacy  string
	vault   *pairingVault
	handler *Handler
}

func newPairingTestServer(t *testing.T) *pairingTestServer {
	t.Helper()
	dir := testutil.Dir(t)
	vault := &pairingVault{}
	server := &pairingTestServer{
		t: t, now: time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC),
		devices: pairing.Devices{Dir: dir, Vault: vault}, vault: vault,
	}
	tokens := pairing.Tokens{Dir: dir, Vault: vault}
	token, err := tokens.Pair(t.Context(), false, server.now)
	if err != nil {
		t.Fatal(err)
	}
	server.legacy = token.Value
	server.handler, err = New(Settings{
		Tokens: tokens, Store: store2.Store{Dir: dir, Vault: vault}, MacName: "Mac A",
		Config: config.File{Path: filepath.Join(dir, "config.json")}, Now: func() time.Time { return server.now },
	})
	if err != nil {
		t.Fatal(err)
	}
	return server
}

func (s *pairingTestServer) request(method, path, bearer string, body []byte, want int) *httptest.ResponseRecorder {
	s.t.Helper()
	r := httptest.NewRequest(method, "https://mac-a.invalid"+path, bytes.NewReader(body))
	if bearer != "" {
		r.Header.Set("Authorization", "Bearer "+bearer)
	}
	if body != nil {
		r.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	s.handler.ServeHTTP(w, r)
	if w.Code != want {
		s.t.Fatalf("%s %s returned %d, want %d", method, path, w.Code, want)
	}
	return w
}

func (s *pairingTestServer) create() string {
	s.t.Helper()
	code, err := s.devices.Create(s.t.Context(), s.now)
	if err != nil {
		s.t.Fatal(err)
	}
	s.expires = s.now.Add(pairing.EnrolmentDuration)
	return code
}

func redeemBody(code string) []byte {
	body, _ := json.Marshal(map[string]string{"code": code, "device_name": "Fixture iPhone"})
	return body
}

func (s *pairingTestServer) redeem(code string) v2report.PairRedeem {
	s.t.Helper()
	w := s.request(http.MethodPost, "/v2/pair/redeem", "", redeemBody(code), 201)
	var redeemed v2report.PairRedeem
	if json.Unmarshal(w.Body.Bytes(), &redeemed) != nil ||
		redeemed.Kind != "pair_redeem" || redeemed.MacName != "Mac A" ||
		!regexp.MustCompile(`^[0-9]{6}$`).MatchString(redeemed.VerificationCode) ||
		!regexp.MustCompile(`^dev_[a-f0-9]{12}$`).MatchString(redeemed.DeviceID) ||
		!strings.HasPrefix(redeemed.Credential, "ghv3_") || len(redeemed.Credential) != 48 ||
		len(redeemed.ProfileID) != 22 || !redeemed.ExpiresAt.Equal(s.expires) {
		s.t.Fatal("invalid enrolment response fields")
	}
	return redeemed
}

func (s *pairingTestServer) status(device v2report.PairRedeem, wantState string) {
	s.t.Helper()
	w := s.request(http.MethodGet, "/v2/pair/status", device.Credential, nil, 200)
	var status v2report.PairStatus
	if json.Unmarshal(w.Body.Bytes(), &status) != nil || status.Kind != "pair_status" ||
		status.DeviceID != device.DeviceID || status.State != wantState {
		s.t.Fatalf("device status did not report %s", wantState)
	}
}

func (s *pairingTestServer) approve(code string) {
	s.t.Helper()
	if err := s.devices.Approve(s.t.Context(), code, s.now); err != nil {
		s.t.Fatal(err)
	}
	s.now = s.now.Add(5 * time.Second)
}

func TestPairingEnrolmentAndDeviceRevocation(t *testing.T) {
	s := newPairingTestServer(t)
	s.request(http.MethodGet, "/v2/status", s.legacy, nil, 200)

	code := s.create()
	first := s.redeem(code)
	s.request(http.MethodGet, "/v2/status", s.legacy, nil, 200)
	s.request(http.MethodGet, "/v2/status", first.Credential, nil, 401)
	if len(s.handler.failures) != 0 {
		t.Fatal("the pending device consumed an authentication failure")
	}
	s.status(first, "pending")
	s.request(http.MethodPost, "/v2/pair/redeem", "", redeemBody(code), 401)
	s.approve(code)
	s.status(first, "active")
	s.request(http.MethodGet, "/v2/status", first.Credential, nil, 200)
	s.request(http.MethodGet, "/v2/status", s.legacy, nil, 401)

	code = s.create()
	second := s.redeem(code)
	s.approve(code)
	if err := s.devices.Revoke(t.Context(), first.DeviceID); err != nil {
		t.Fatal(err)
	}
	s.now = s.now.Add(5 * time.Second)
	s.request(http.MethodGet, "/v2/pair/status", first.Credential, nil, 401)
	s.request(http.MethodGet, "/v2/status", second.Credential, nil, 200)
}

func TestPairingRedeemChecksRequestAndExpiry(t *testing.T) {
	s := newPairingTestServer(t)
	code := s.create()
	s.request(http.MethodPost, "/v2/pair/redeem", s.legacy, redeemBody(code), 400)
	s.request(http.MethodPost, "/v2/pair/redeem", "", bytes.Repeat([]byte(" "), 1025), 413)
	w := s.request(http.MethodPost, "/v2/pair/redeem", "", redeemBody("fixture-wrong"), 401)
	var failure v2report.ErrorBody
	if json.Unmarshal(w.Body.Bytes(), &failure) != nil || failure.Error == nil ||
		failure.Error.Message != "Pairing code expired or already used." || len(s.handler.failures) != 1 {
		t.Fatal("wrong code did not report and count one failed authentication")
	}
	s.now = s.now.Add(pairing.EnrolmentDuration)
	s.request(http.MethodPost, "/v2/pair/redeem", "", redeemBody(code), 401)
	for i := 1; i <= 11; i++ {
		want := 401
		if i >= 10 {
			want = 429
		}
		s.request(http.MethodPost, "/v2/pair/redeem", "", redeemBody("fixture-wrong"), want)
	}
	s.request(http.MethodGet, "/v2/status", s.legacy, nil, 200)
	_ = s.redeem(s.create())
}

func TestCredentialReadErrorsReturnUnavailableWithoutCounting(t *testing.T) {
	for _, item := range []string{".serve-token", ".serve-devices"} {
		t.Run(item, func(t *testing.T) {
			s := newPairingTestServer(t)
			code := s.create()
			s.request(http.MethodGet, "/v2/status", "fixture-invalid", nil, 401)
			s.now = s.now.Add(5 * time.Second)
			s.vault.unavailable = item
			s.request(http.MethodGet, "/v2/status", s.legacy, nil, 503)
			s.request(http.MethodPost, "/v2/pair/redeem", "", redeemBody(code), 503)
			if len(s.handler.failures) != 1 {
				t.Fatal("credential read errors changed the failure count")
			}
			s.now = s.now.Add(5 * time.Second)
			s.vault.unavailable = ""
			_ = s.redeem(code)
		})
	}
}
