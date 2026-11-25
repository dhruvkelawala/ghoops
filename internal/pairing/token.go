package pairing

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

type Token struct {
	Value   string    `json:"token"`
	Created time.Time `json:"created_at"`
}
type Tokens struct {
	Vault secure.Vault
	Dir   string
}

func (t Tokens) Load() (Token, error) {
	var token Token
	data, err := t.Vault.Get(secure.ServeTokenItem.Service(t.Dir))
	if err != nil {
		return token, err
	}
	if json.Unmarshal(data, &token) != nil || len(token.Value) != 48 || token.Value[:5] != "ghv2_" || token.Created.IsZero() {
		return Token{}, errors.New("invalid pairing token")
	}
	decoded, err := base64.RawURLEncoding.DecodeString(token.Value[5:])
	if err != nil || len(decoded) != 32 {
		return Token{}, errors.New("invalid pairing token")
	}
	return token, nil
}
func (t Tokens) Pair(ctx context.Context, rotate bool, now time.Time) (Token, error) {
	unlock, err := secure.Lock(ctx, t.Dir, "pair.lock")
	if err != nil {
		return Token{}, err
	}
	defer unlock()
	token, err := t.Load()
	if err == nil && !rotate {
		return token, nil
	}
	if err != nil && !errors.Is(err, secure.ErrNotFound) {
		return Token{}, err
	}
	random := make([]byte, 32)
	if _, err = rand.Read(random); err != nil {
		return Token{}, errors.New("cannot create pairing token")
	}
	token = Token{Value: "ghv2_" + base64.RawURLEncoding.EncodeToString(random), Created: now.UTC()}
	data, err := json.Marshal(token)
	if err != nil {
		return Token{}, err
	}
	if err = t.Vault.Set(secure.ServeTokenItem.Service(t.Dir), data); err != nil {
		return Token{}, err
	}
	return token, nil
}
func (t Tokens) Revoke(ctx context.Context) error {
	unlock, err := secure.Lock(ctx, t.Dir, "pair.lock")
	if err != nil {
		return err
	}
	defer unlock()
	return t.revokeLocked()
}

func (t Tokens) revokeLocked() error {
	err := t.Vault.Delete(secure.ServeTokenItem.Service(t.Dir))
	if errors.Is(err, secure.ErrNotFound) {
		return nil
	}
	return err
}
