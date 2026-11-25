package secure

import (
	"crypto/cipher"
	"encoding/json"
	"errors"
)

// FileRoleAAD binds an encrypted file to its role within the profile.
func FileRoleAAD(legacyAAD, role string) []byte {
	return []byte(legacyAAD + "\nrole=" + role)
}

// OpenFileRole reads a role-bound file or a legacy file with the required keys.
func OpenFileRole(aead cipher.AEAD, nonce, ciphertext []byte, legacyAAD, role string, legacyKeys ...string) ([]byte, error) {
	plain, err := aead.Open(nil, nonce, ciphertext, FileRoleAAD(legacyAAD, role))
	if err == nil {
		return plain, nil
	}
	plain, err = aead.Open(nil, nonce, ciphertext, []byte(legacyAAD))
	if err != nil {
		return nil, err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(plain, &fields); err != nil {
		return nil, err
	}
	for _, key := range legacyKeys {
		if _, ok := fields[key]; !ok {
			return nil, errors.New("legacy file is missing a role field")
		}
	}
	return plain, nil
}
