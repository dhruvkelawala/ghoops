package journal_test

import (
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestLegacyJournalKeepsEntriesWhenSaved(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	store := journal.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	want := journal.Book{Entries: []journal.Entry{{
		Date: "2026-03-09", Answers: map[string]bool{"alcohol": true}, UpdatedAt: now,
	}}}
	legacy := map[string]any{"version": 1, "entries": want.Entries, "behaviours": nil}
	key := testutil.WriteLegacyV2File(t, store.Dir, journal.FileName, store.Vault, legacy)
	if got, err := store.Load(); err != nil || !reflect.DeepEqual(got, want) {
		t.Fatal("legacy journal did not load with its original data", err)
	}
	want.Behaviours = []string{"alcohol"}
	if _, err := store.SetBehaviours(t.Context(), want.Behaviours, now); err != nil {
		t.Fatal(err)
	}
	testutil.CheckV2FileRole(t, store.Dir, journal.FileName, "journal", key)
	if got, err := store.Load(); err != nil || !reflect.DeepEqual(got, want) {
		t.Fatal("journal did not reopen with the old entries and the new setting", err)
	}
}

func TestLegacyJournalRequiresBothRoleKeys(t *testing.T) {
	for _, missing := range []string{"entries", "behaviours"} {
		t.Run(missing, func(t *testing.T) {
			store := journal.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			body := map[string]any{"version": 1, "entries": []journal.Entry{}, "behaviours": nil}
			delete(body, missing)
			testutil.WriteLegacyV2File(t, store.Dir, journal.FileName, store.Vault, body)
			if _, err := store.Load(); err == nil {
				t.Fatal("legacy journal opened with a missing role key")
			}
		})
	}
}
