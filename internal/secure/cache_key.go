package secure

import (
	"context"
	"crypto/rand"
	"errors"
)

func CacheKey(dir string, vault Vault, create bool) ([]byte, error) {
	item := CacheKeyItem.Service(dir)
	key, err := vault.Get(item)
	if errors.Is(err, ErrNotFound) && create {
		unlock, lockErr := Lock(context.Background(), dir, "cache-key.lock")
		if lockErr != nil {
			return nil, lockErr
		}
		defer unlock()
		key, err = vault.Get(item)
		if errors.Is(err, ErrNotFound) {
			key = make([]byte, 32)
			if _, err = rand.Read(key); err != nil {
				return nil, errors.New("cannot generate encryption key")
			}
			err = vault.Create(item, key)
			if errors.Is(err, ErrExists) {
				key, err = vault.Get(item)
			}
		}
	}
	if errors.Is(err, ErrNotFound) {
		return nil, errors.New("cache encryption key missing; encrypted records cannot be opened")
	}
	if err != nil {
		return nil, err
	}
	if len(key) != 32 {
		return nil, errors.New("invalid cache encryption key")
	}
	return key, nil
}
