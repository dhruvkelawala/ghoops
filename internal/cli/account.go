package cli

import (
	"context"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

func (a *app) lockAccountChange(ctx context.Context) (func(), error) {
	unlockSync, err := secure.Lock(ctx, a.dir, "sync.lock")
	if err != nil {
		return nil, err
	}
	unlockCollect, err := (store2.Store{Dir: a.dir}).WaitLock(ctx)
	if err != nil {
		unlockSync()
		return nil, err
	}
	return func() {
		unlockCollect()
		unlockSync()
	}, nil
}

func (a *app) profileOwner() (string, error) {
	v1, err := a.store.Load()
	if err != nil {
		return "", err
	}
	v2, err := (store2.Store{Dir: a.dir, Vault: a.store.Vault}).Load()
	if err != nil {
		return "", err
	}
	if v1.Account == "" {
		return v2.Account, nil
	}
	if v2.Account != "" && v1.Account != v2.Account {
		return "", auth.ErrProfileOwner
	}
	return v1.Account, nil
}
