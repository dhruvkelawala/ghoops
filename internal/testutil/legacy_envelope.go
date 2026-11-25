package testutil

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

// WriteLegacyV2File writes a synthetic file in the original uncapped envelope.
func WriteLegacyV2File(t *testing.T, dir, name string, vault secure.Vault, body any) []byte {
	t.Helper()
	key, err := secure.CacheKey(dir, vault, true)
	if err != nil {
		t.Fatal(err)
	}
	aead := v2AEAD(t, key)
	plain, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		t.Fatal(err)
	}
	const header = "ghealth-cache-v2\n"
	encrypted := aead.Seal(append([]byte(header), nonce...), nonce, plain, []byte(header+secure.Service(dir)))
	if err := os.WriteFile(filepath.Join(dir, name), encrypted, 0600); err != nil {
		t.Fatal(err)
	}
	return key
}

// CheckV2FileRole verifies the saved file against the original key and both AAD formats.
func CheckV2FileRole(t *testing.T, dir, name, role string, key []byte) {
	t.Helper()
	aead := v2AEAD(t, key)
	encrypted, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		t.Fatal(err)
	}
	const header = "ghealth-cache-v2\n"
	nonceEnd := len(header) + aead.NonceSize()
	if len(encrypted) < nonceEnd+aead.Overhead() || string(encrypted[:len(header)]) != header {
		t.Fatal("invalid v2 envelope")
	}
	nonce, ciphertext := encrypted[len(header):nonceEnd], encrypted[nonceEnd:]
	legacyAAD := header + secure.Service(dir)
	if _, err := aead.Open(nil, nonce, ciphertext, []byte(legacyAAD)); err == nil {
		t.Fatal("the saved file still opens with legacy AAD")
	}
	if _, err := aead.Open(nil, nonce, ciphertext, []byte(legacyAAD+"\nrole="+role)); err != nil {
		t.Fatal("the original key and the expected role could not open the saved file", err)
	}
}

func v2AEAD(t *testing.T, key []byte) cipher.AEAD {
	t.Helper()
	block, err := aes.NewCipher(key)
	if err != nil {
		t.Fatal(err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		t.Fatal(err)
	}
	return aead
}
