package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"sync/atomic"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/netx"
	"github.com/dhruvkelawala/ghoops/internal/secure"
)

const Callback = "http://127.0.0.1:8765/oauth/callback"
const authURL = "https://accounts.google.com/o/oauth2/v2/auth"
const tokenURL = "https://oauth2.googleapis.com/token"

var Scopes = []string{
	"https://www.googleapis.com/auth/googlehealth.sleep.readonly",
	"https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
	"https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
	"https://www.googleapis.com/auth/googlehealth.profile.readonly",
	"https://www.googleapis.com/auth/googlehealth.settings.readonly",
	"https://www.googleapis.com/auth/googlehealth.irn.readonly",
	"https://www.googleapis.com/auth/googlehealth.location.readonly",
}

var ErrLogin = errors.New("authorization missing, expired or revoked; run ghoops auth login")
var ErrPermissions = errors.New("requested read permissions are missing; run ghoops auth login and grant at least one requested read scope")
var ErrProfileOwner = errors.New("another account already owns this profile; use a separate --state-dir")
var ErrAccountChanged = errors.New("account changed during collection; cache unchanged")

type ClientSpec struct {
	ID        string   `json:"client_id"`
	Secret    string   `json:"client_secret"`
	Redirects []string `json:"redirect_uris,omitempty"`
	AuthURI   string   `json:"auth_uri,omitempty"`
	TokenURI  string   `json:"token_uri,omitempty"`
}

type Session struct {
	Client           ClientSpec `json:"client"`
	AccessToken      string     `json:"access_token"`
	RefreshToken     string     `json:"refresh_token"`
	ExpiresAt        time.Time  `json:"expires_at"`
	RefreshExpiresAt *time.Time `json:"refresh_expires_at,omitempty"`
	Scopes           []string   `json:"scopes"`
	HealthUserID     string     `json:"health_user_id"`
	Revoked          bool       `json:"revoked"`
}

type Status struct {
	Authorized         bool       `json:"authorized"`
	Linked             bool       `json:"linked"`
	Refreshable        bool       `json:"refreshable"`
	ExpiresAt          *time.Time `json:"access_expires_at"`
	RefreshExpiresAt   *time.Time `json:"refresh_expires_at"`
	Scopes             []string   `json:"scopes"`
	MissingScopes      []string   `json:"missing_scopes"`
	PartialPermissions bool       `json:"partial_permissions"`
	State              string     `json:"state"`
}

type Manager struct {
	Vault        secure.Vault
	Dir          string
	HTTP         *http.Client
	AuthorizeURL string
	TokenURL     string
	IdentityURL  string
	RevokeURL    string
	CallbackURL  string
}

func New(v secure.Vault, dir string) *Manager {
	return &Manager{Vault: v, Dir: dir, HTTP: netx.Client(), AuthorizeURL: authURL, TokenURL: tokenURL, IdentityURL: "https://health.googleapis.com/v4/users/me/identity", RevokeURL: "https://oauth2.googleapis.com/revoke", CallbackURL: Callback}
}

func (m *Manager) item() string { return secure.OAuthSessionItem.Service(m.Dir) }

func (m *Manager) load() (Session, error) {
	var s Session
	b, err := m.Vault.Get(m.item())
	if errors.Is(err, secure.ErrNotFound) {
		return s, ErrLogin
	}
	if err != nil {
		return s, err
	}
	if json.Unmarshal(b, &s) != nil || s.Client.ID == "" || s.Client.Secret == "" || s.HealthUserID == "" {
		return s, errors.New("stored OAuth session is invalid; authorize again")
	}
	return s, nil
}

func (m *Manager) save(s Session) error {
	b, err := json.Marshal(s)
	if err != nil {
		return errors.New("cannot encode OAuth session")
	}
	return m.Vault.Set(m.item(), b)
}

func (m *Manager) Status(ctx context.Context) (Status, error) {
	unlock, err := secure.Lock(ctx, m.Dir, "auth.lock")
	if err != nil {
		return Status{}, err
	}
	defer unlock()
	s, err := m.load()
	if errors.Is(err, ErrLogin) {
		return Status{State: "not_authorized", Scopes: []string{}, MissingScopes: missingScopes(nil)}, nil
	}
	if err != nil {
		return Status{}, err
	}
	state := "authorized"
	missing := missingScopes(s.Scopes)
	permitted := len(missing) < len(Scopes)
	partial := permitted && len(missing) > 0
	refreshable := s.RefreshToken != "" && !s.Revoked && (s.RefreshExpiresAt == nil || time.Now().Before(*s.RefreshExpiresAt))
	if s.Revoked {
		state = "revoked"
	} else if !refreshable {
		state = "reauthorization_required"
	} else if !permitted {
		state = "missing_permissions"
	} else if !time.Now().Before(s.ExpiresAt) {
		state = "refresh_required"
	} else if partial {
		state = "partial_permissions"
	}
	return Status{Authorized: permitted && !s.Revoked && (refreshable || time.Now().Before(s.ExpiresAt)), Linked: true, Refreshable: refreshable, ExpiresAt: &s.ExpiresAt, RefreshExpiresAt: s.RefreshExpiresAt, Scopes: s.Scopes, MissingScopes: missing, PartialPermissions: partial, State: state}, nil
}

func (m *Manager) Access(ctx context.Context, rejected string) (string, error) {
	return m.access(ctx, rejected, false, "")
}

// AccessForAccount checks the stored account under the same lock used to read or refresh its token.
func (m *Manager) AccessForAccount(ctx context.Context, account, rejected string) (string, error) {
	return m.access(ctx, rejected, false, account)
}

func (m *Manager) access(ctx context.Context, rejected string, force bool, account string) (string, error) {
	unlock, err := secure.Lock(ctx, m.Dir, "auth.lock")
	if err != nil {
		return "", err
	}
	defer unlock()
	s, err := m.load()
	if account != "" && (errors.Is(err, ErrLogin) || (err == nil && s.HealthUserID != account)) {
		return "", ErrAccountChanged
	}
	if err != nil {
		return "", err
	}
	if s.Revoked {
		return "", ErrLogin
	}
	if !force && s.ExpiresAt.After(time.Now().Add(time.Minute)) && (rejected == "" || rejected != s.AccessToken) {
		if !hasReadScope(s.Scopes) {
			return "", ErrPermissions
		}
		return s.AccessToken, nil
	}
	if s.RefreshToken == "" || (s.RefreshExpiresAt != nil && !time.Now().Before(*s.RefreshExpiresAt)) {
		return "", ErrLogin
	}
	newSession, err := m.exchange(ctx, s.Client, url.Values{"grant_type": {"refresh_token"}, "refresh_token": {s.RefreshToken}})
	if err != nil {
		if errors.Is(err, ErrLogin) {
			s.Revoked = true
			if saveErr := m.save(s); saveErr != nil {
				return "", saveErr
			}
		}
		return "", err
	}
	if newSession.RefreshToken == "" {
		newSession.RefreshToken = s.RefreshToken
	}
	if newSession.RefreshExpiresAt == nil {
		newSession.RefreshExpiresAt = s.RefreshExpiresAt
	}
	if newSession.Scopes == nil {
		newSession.Scopes = s.Scopes
	}
	newSession.HealthUserID = s.HealthUserID
	if err := m.save(newSession); err != nil {
		return "", err
	}
	if !hasReadScope(newSession.Scopes) {
		return "", ErrPermissions
	}
	return newSession.AccessToken, nil
}

func (m *Manager) Refresh(ctx context.Context) error {
	_, err := m.access(ctx, "", true, "")
	return err
}

func hasReadScope(scopes []string) bool {
	for _, granted := range scopes {
		for _, requested := range Scopes {
			if granted == requested {
				return true
			}
		}
	}
	return false
}

func missingScopes(scopes []string) []string {
	set := map[string]bool{}
	for _, s := range scopes {
		set[s] = true
	}
	missing := []string{}
	for _, s := range Scopes {
		if !set[s] {
			missing = append(missing, s)
		}
	}
	return missing
}

func LoadClient(path string, callback string) (ClientSpec, error) {
	var file struct {
		Web ClientSpec `json:"web"`
	}
	f, err := secure.OpenPrivate(path, os.O_RDONLY)
	if err != nil {
		return ClientSpec{}, errors.New("cannot read private client file; it must be owned by you with permissions 0600")
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, 65537))
	if err != nil || len(b) > 65536 || json.Unmarshal(b, &file) != nil {
		return ClientSpec{}, errors.New("invalid Web OAuth client JSON")
	}
	c := file.Web
	if c.ID == "" || c.Secret == "" {
		return c, errors.New("client file must contain a Web OAuth client_id and client_secret")
	}
	if (c.AuthURI != "" && c.AuthURI != authURL && c.AuthURI != "https://accounts.google.com/o/oauth2/auth") || (c.TokenURI != "" && c.TokenURI != tokenURL) {
		return c, errors.New("client file specifies untrusted OAuth endpoints")
	}
	found := false
	for _, r := range c.Redirects {
		if r == callback {
			found = true
		}
	}
	if !found {
		return c, fmt.Errorf("Web OAuth client must register %s", callback)
	}
	return c, nil
}

func randomString() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", errors.New("cannot generate OAuth randomness")
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func (m *Manager) Login(ctx context.Context, client ClientSpec, expectedAccount string, noBrowser bool, output io.Writer) error {
	unlock, err := secure.Lock(ctx, m.Dir, "auth.lock")
	if err != nil {
		return err
	}
	defer unlock()
	old, oldErr := m.load()
	if oldErr != nil && !errors.Is(oldErr, ErrLogin) {
		return oldErr
	}
	state, err := randomString()
	if err != nil {
		return err
	}
	verifier, err := randomString()
	if err != nil {
		return err
	}
	challenge := sha256.Sum256([]byte(verifier))
	callback, err := url.Parse(m.CallbackURL)
	if err != nil || callback.Scheme != "http" || callback.Hostname() != "127.0.0.1" || callback.Port() == "" || callback.Path != "/oauth/callback" {
		return errors.New("invalid loopback callback")
	}
	listener, err := net.Listen("tcp4", callback.Host)
	if err != nil {
		return errors.New("cannot bind loopback callback; port may already be in use")
	}
	defer listener.Close()
	type callbackResult struct {
		code   string
		denied bool
	}
	result := make(chan callbackResult, 1)
	var used atomic.Bool
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'none'")
		q := r.URL.Query()
		if r.Method != http.MethodGet || r.URL.Path != callback.Path || r.Host != callback.Host || len(q["state"]) != 1 || subtle.ConstantTimeCompare([]byte(q.Get("state")), []byte(state)) != 1 {
			http.Error(w, "Invalid authorization callback.", http.StatusBadRequest)
			return
		}
		if (q.Get("error") == "" && (len(q["code"]) != 1 || q.Get("code") == "")) || used.Swap(true) {
			http.Error(w, "Invalid authorization callback.", http.StatusBadRequest)
			return
		}
		result <- callbackResult{code: q.Get("code"), denied: q.Get("error") != ""}
		_, _ = io.WriteString(w, "Authorization received. Return to your terminal.")
	})
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 5 * time.Second, MaxHeaderBytes: 8192, ErrorLog: log.New(io.Discard, "", 0)}
	serverErr := make(chan error, 1)
	go func() { serverErr <- server.Serve(listener) }()
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if server.Shutdown(shutdownCtx) != nil {
			_ = server.Close()
		}
	}()
	u, err := url.Parse(m.AuthorizeURL)
	if err != nil {
		return errors.New("invalid authorization endpoint")
	}
	u.RawQuery = url.Values{"client_id": {client.ID}, "redirect_uri": {m.CallbackURL}, "response_type": {"code"}, "access_type": {"offline"}, "scope": {strings.Join(Scopes, " ")}, "prompt": {"consent"}, "state": {state}, "code_challenge": {base64.RawURLEncoding.EncodeToString(challenge[:])}, "code_challenge_method": {"S256"}}.Encode()
	if _, err := fmt.Fprintln(output, u.String()); err != nil {
		return errors.New("cannot display authorization URL")
	}
	if !noBrowser {
		if err := exec.CommandContext(ctx, "/usr/bin/open", u.String()).Run(); err != nil {
			return errors.New("cannot open system browser; retry with --no-browser")
		}
	}
	select {
	case <-ctx.Done():
		return errors.New("authorization timed out or cancelled")
	case <-serverErr:
		return errors.New("loopback callback server stopped")
	case r := <-result:
		if r.denied {
			return errors.New("authorization denied")
		}
		s, err := m.exchange(ctx, client, url.Values{"grant_type": {"authorization_code"}, "code": {r.code}, "redirect_uri": {m.CallbackURL}, "code_verifier": {verifier}})
		if err != nil {
			return err
		}
		if !hasReadScope(s.Scopes) {
			return ErrPermissions
		}
		if s.RefreshToken == "" {
			return errors.New("offline access is required; authorize again")
		}
		id, err := m.identity(ctx, s.AccessToken)
		if err != nil {
			return err
		}
		s.HealthUserID = id
		if (old.HealthUserID != "" && old.HealthUserID != id) || (expectedAccount != "" && expectedAccount != id) {
			return ErrProfileOwner
		}
		return m.save(s)
	}
}

func (m *Manager) exchange(ctx context.Context, client ClientSpec, values url.Values) (Session, error) {
	values.Set("client_id", client.ID)
	values.Set("client_secret", client.Secret)
	for attempt := 0; attempt < 4; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, m.TokenURL, strings.NewReader(values.Encode()))
		if err != nil {
			return Session{}, errors.New("invalid token request")
		}
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		resp, err := m.HTTP.Do(req)
		if err != nil {
			return Session{}, errors.New("OAuth network request failed")
		}
		body, err := netx.Read(resp)
		if err != nil {
			return Session{}, err
		}
		if (resp.StatusCode == 429 || resp.StatusCode >= 500) && attempt < 3 {
			if err := netx.Wait(ctx, attempt, resp.Header.Get("Retry-After")); err != nil {
				return Session{}, err
			}
			continue
		}
		var token struct {
			Access         string  `json:"access_token"`
			Refresh        string  `json:"refresh_token"`
			Expires        int64   `json:"expires_in"`
			RefreshExpires int64   `json:"refresh_token_expires_in"`
			Scope          *string `json:"scope"`
			Type           string  `json:"token_type"`
			Error          string  `json:"error"`
		}
		if json.Unmarshal(body, &token) != nil {
			return Session{}, errors.New("invalid OAuth response")
		}
		if token.Error == "invalid_grant" {
			return Session{}, ErrLogin
		}
		if resp.StatusCode != 200 || token.Error != "" {
			return Session{}, fmt.Errorf("OAuth request rejected (HTTP %d); check client setup and consent", resp.StatusCode)
		}
		if token.Access == "" || token.Expires <= 0 || token.Expires > 86400 || !strings.EqualFold(token.Type, "Bearer") {
			return Session{}, errors.New("incomplete OAuth token response")
		}
		s := Session{Client: client, AccessToken: token.Access, RefreshToken: token.Refresh, ExpiresAt: time.Now().Add(time.Duration(token.Expires) * time.Second)}
		if token.Scope != nil {
			s.Scopes = strings.Fields(*token.Scope)
		}
		if token.RefreshExpires > 0 && token.RefreshExpires <= 315360000 {
			t := time.Now().Add(time.Duration(token.RefreshExpires) * time.Second)
			s.RefreshExpiresAt = &t
		}
		return s, nil
	}
	return Session{}, errors.New("OAuth retries exhausted")
}

func (m *Manager) identity(ctx context.Context, access string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, m.IdentityURL, nil)
	if err != nil {
		return "", errors.New("invalid identity endpoint")
	}
	req.Header.Set("Authorization", "Bearer "+access)
	resp, err := m.HTTP.Do(req)
	if err != nil {
		return "", errors.New("Google Health identity request failed")
	}
	b, err := netx.Read(resp)
	if err != nil {
		return "", err
	}
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("Google Health account link check failed (HTTP %d); link your account in the Google Health app and check API access", resp.StatusCode)
	}
	var id struct {
		HealthUserID string `json:"healthUserId"`
	}
	if json.Unmarshal(b, &id) != nil || id.HealthUserID == "" {
		return "", errors.New("Google Health identity response is incomplete")
	}
	return id.HealthUserID, nil
}

func (m *Manager) Account(ctx context.Context) (string, error) {
	unlock, err := secure.Lock(ctx, m.Dir, "auth.lock")
	if err != nil {
		return "", err
	}
	defer unlock()
	s, err := m.load()
	if err != nil {
		return "", err
	}
	return s.HealthUserID, nil
}

func (m *Manager) Logout(ctx context.Context, revoke bool) error {
	unlock, err := secure.Lock(ctx, m.Dir, "auth.lock")
	if err != nil {
		return err
	}
	defer unlock()
	if revoke {
		s, err := m.load()
		if err != nil {
			return err
		}
		token := s.RefreshToken
		if token == "" {
			token = s.AccessToken
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, m.RevokeURL, strings.NewReader(url.Values{"token": {token}}.Encode()))
		if err != nil {
			return errors.New("invalid revocation request")
		}
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		resp, err := m.HTTP.Do(req)
		if err != nil {
			return errors.New("revocation request failed; local credentials retained; use logout without --revoke to remove locally")
		}
		_, readErr := netx.Read(resp)
		if readErr != nil {
			return readErr
		}
		if resp.StatusCode != 200 {
			return fmt.Errorf("revocation failed (HTTP %d); local credentials retained", resp.StatusCode)
		}
	}
	err = m.Vault.Delete(m.item())
	if errors.Is(err, secure.ErrNotFound) {
		return nil
	}
	return err
}
