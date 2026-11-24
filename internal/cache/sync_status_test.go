package cache_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestSyncPreconditionFailureCannotClaimComplete(t *testing.T) {
	from := time.Date(2026, 10, 12, 0, 0, 0, 0, time.UTC)
	for _, fail := range []string{"account-error", "empty-account", "account-mismatch", "cancelled"} {
		t.Run(fail, func(t *testing.T) {
			store := cache.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			resolve := resolveSyntheticAccount("synthetic-user")
			switch fail {
			case "account-error":
				resolve = func(context.Context) (string, error) { return "", errors.New("synthetic permission failure") }
			case "empty-account":
				resolve = resolveSyntheticAccount("")
			case "account-mismatch":
				old := cache.Empty()
				old.Account, old.Timezone = "synthetic-other", "UTC"
				if err := store.Save(old); err != nil {
					t.Fatal(err)
				}
			case "cancelled":
				cancel()
			}
			result, err := cache.Sync(ctx, store, movedRecordFetcher{}, resolve, from, from.AddDate(0, 0, 1))
			if err == nil || result.Complete {
				t.Fatal("failed collection falsely advertised complete", result, err)
			}
		})
	}
}
