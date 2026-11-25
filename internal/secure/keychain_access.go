package secure

import (
	"errors"
	"fmt"
	"strings"
)

var ErrKeychainAccess = errors.New("Keychain item must trust only the installed binary (run ghoops doctor --keychain)")

func keychainAccessError(service string) error {
	if strings.HasSuffix(service, string(CacheKeyItem)) {
		return fmt.Errorf("encrypted stores need the original cache key: %w", ErrKeychainAccess)
	}
	return ErrKeychainAccess
}

type aclVault struct {
	Vault
	readACL func(string) (bool, error)
}

// WithKeychainACL checks the access list before reading from a supplied vault.
func WithKeychainACL(vault Vault, readACL func(string) (bool, error)) Vault {
	return aclVault{Vault: vault, readACL: readACL}
}

func (v aclVault) Get(service string) ([]byte, error) {
	only, err := v.readACL(service)
	if err != nil {
		return nil, err
	}
	if !only {
		return nil, keychainAccessError(service)
	}
	return v.Vault.Get(service)
}
