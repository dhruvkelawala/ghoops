package cli

import (
	"errors"
	"fmt"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

func (a *app) doctorKeychain() error {
	read := a.options.ReadKeychainACL
	if read == nil {
		read = secure.Keychain{}.OnlyInstalledBinary
	}
	items := []struct {
		item        secure.KeychainItem
		name, label string
	}{
		{secure.CacheKeyItem, "cache_key", "Cache key"},
		{secure.OAuthSessionItem, "oauth_session", "OAuth session"},
		{secure.ServeTokenItem, "serve_token", "Serve token"},
		{secure.ServeDevicesItem, "serve_devices", "Serve devices"},
	}
	type status struct {
		Exists              bool `json:"exists"`
		OnlyInstalledBinary bool `json:"only_installed_binary"`
	}
	report := make(map[string]status, len(items))
	for _, item := range items {
		only, err := read(item.item.Service(a.dir))
		switch {
		case errors.Is(err, secure.ErrNotFound):
			report[item.name] = status{}
		case err != nil:
			return fmt.Errorf("%s: %w", item.label, err)
		default:
			report[item.name] = status{Exists: true, OnlyInstalledBinary: only}
		}
	}
	if a.json {
		return a.emit(struct {
			SchemaVersion int               `json:"schema_version"`
			Items         map[string]status `json:"items"`
		}{1, report})
	}
	for _, item := range items {
		result := report[item.name]
		if _, err := fmt.Fprintf(a.out, "%s: exists=%t only_installed_binary=%t\n",
			item.label, result.Exists, result.OnlyInstalledBinary); err != nil {
			return err
		}
	}
	return nil
}
