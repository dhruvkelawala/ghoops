package cli

import (
	"context"
	"errors"
	"fmt"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

var keychainItems = []struct {
	item        secure.KeychainItem
	name, label string
	whatNext    string
}{
	{secure.CacheKeyItem, "cache_key", "Cache key", ""},
	{secure.OAuthSessionItem, "oauth_session", "OAuth session", "Log in again with ghoops auth login --client-file PATH."},
	{secure.ServeTokenItem, "serve_token", "Serve token", "Pair again with ghoops pair."},
	{secure.ServeDevicesItem, "serve_devices", "Serve devices", "Pair again with ghoops pair."},
}

type keychainStatus struct {
	Exists              bool `json:"exists"`
	OnlyInstalledBinary bool `json:"only_installed_binary"`
}

func (a *app) keychainReport() (map[string]keychainStatus, error) {
	read := a.options.ReadKeychainACL
	if read == nil {
		read = secure.Keychain{}.OnlyInstalledBinary
	}
	report := make(map[string]keychainStatus, len(keychainItems))
	for _, item := range keychainItems {
		only, err := read(item.item.Service(a.dir))
		switch {
		case errors.Is(err, secure.ErrNotFound):
			report[item.name] = keychainStatus{}
		case err != nil:
			return nil, fmt.Errorf("%s: %w", item.label, err)
		default:
			report[item.name] = keychainStatus{Exists: true, OnlyInstalledBinary: only}
		}
	}
	return report, nil
}

func (a *app) doctorKeychain() error {
	report, err := a.keychainReport()
	if err != nil {
		return err
	}
	if a.json {
		return a.emit(struct {
			SchemaVersion int                       `json:"schema_version"`
			Items         map[string]keychainStatus `json:"items"`
		}{1, report})
	}
	for _, item := range keychainItems {
		result := report[item.name]
		if _, err := fmt.Fprintf(a.out, "%s: exists=%t only_installed_binary=%t\n",
			item.label, result.Exists, result.OnlyInstalledBinary); err != nil {
			return err
		}
	}
	return nil
}

func (a *app) repairKeychain(ctx context.Context) error {
	unlock, err := a.lockAccountChange(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	for _, lock := range []string{"auth.lock", "pair.lock"} {
		unlock, err := secure.Lock(ctx, a.dir, lock)
		if err != nil {
			return err
		}
		defer unlock()
	}
	report, err := a.keychainReport()
	if err != nil {
		return err
	}
	if key := report["cache_key"]; key.Exists && !key.OnlyInstalledBinary {
		return errors.New("cache key has an unsafe Keychain access list and was left in place. Encrypted stores need the original key")
	}
	type repair struct {
		Item     string `json:"item"`
		NextStep string `json:"next_step"`
	}
	repaired := []repair{}
	var failures error
	for _, item := range keychainItems {
		if result := report[item.name]; item.whatNext == "" || !result.Exists || result.OnlyInstalledBinary {
			continue
		}
		err := a.store.Vault.Delete(item.item.Service(a.dir))
		if errors.Is(err, secure.ErrNotFound) {
			continue
		}
		if err != nil {
			failures = errors.Join(failures, fmt.Errorf("%s: %w", item.label, err))
			continue
		}
		repaired = append(repaired, repair{item.name, item.whatNext})
		if !a.json {
			_, err := fmt.Fprintf(a.out, "Removed %s. %s\n", item.label, item.whatNext)
			failures = errors.Join(failures, err)
		}
	}
	if a.json {
		return errors.Join(failures, a.emit(struct {
			SchemaVersion int      `json:"schema_version"`
			Repaired      []repair `json:"repaired"`
		}{1, repaired}))
	}
	if len(repaired) == 0 && failures == nil {
		_, failures = fmt.Fprintln(a.out, "No Keychain credentials needed repair.")
	}
	return failures
}
