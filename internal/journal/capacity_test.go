package journal_test

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestWriterRefusesOversizedFile(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	store := journal.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	if _, err := store.SetBehaviours(t.Context(), []string{"alcohol"}, now); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(store.Dir, journal.FileName)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.SetBehaviours(t.Context(), []string{strings.Repeat("x", 17<<20)}, now); !errors.Is(err, journal.ErrCapacity) {
		t.Fatal("expected the journal file limit", err)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("the rejected write changed the file", err)
	}
	book, err := store.Load()
	if err != nil || len(book.Behaviours) != 1 || book.Behaviours[0] != "alcohol" {
		t.Fatal("the previous journal could not be read", err)
	}
}

func TestReadsOversizedLegacyJournal(t *testing.T) {
	dir := testutil.Dir(t)
	vault := &testutil.Vault{}
	key := strings.Repeat("x", 17<<20)
	testutil.WriteLegacyV2File(t, dir, journal.FileName, vault, struct {
		Version int `json:"version"`
		journal.Book
	}{1, journal.Book{Entries: []journal.Entry{{Date: "2026-03-09", Answers: map[string]bool{key: true}}}}})

	book, err := (journal.Store{Dir: dir, Vault: vault}).Load()
	if err != nil || len(book.Entries) != 1 || !book.Entries[0].Answers[key] {
		t.Fatal("oversized legacy journal could not be read", err)
	}
}
