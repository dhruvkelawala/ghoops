//go:build !darwin || !cgo

package secure

import "errors"

type Keychain struct{}

var errPlatform = errors.New("macOS Keychain requires a macOS build with CGO enabled; no plaintext fallback")

func (Keychain) Get(string) ([]byte, error)  { return nil, errPlatform }
func (Keychain) Set(string, []byte) error    { return errPlatform }
func (Keychain) Create(string, []byte) error { return errPlatform }
func (Keychain) Delete(string) error         { return errPlatform }
func (Keychain) OnlyInstalledBinary(string) (bool, error) {
	return false, errPlatform
}
