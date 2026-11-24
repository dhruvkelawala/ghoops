package journal_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestSharedRequestCases(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/journal/requests/cases.json")
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		DefaultDate string `json:"default_date"`
		HorizonDays int    `json:"horizon_days"`
		Cases       []struct {
			Name, Date, Body string
			Status           int
			Field            *string
		}
	}
	if err = json.Unmarshal(raw, &file); err != nil || len(file.Cases) == 0 {
		t.Fatal("cannot read cases", err)
	}
	for _, c := range file.Cases {
		t.Run(c.Name, func(t *testing.T) {
			if !journal.DateAllowed(c.Date, file.DefaultDate, file.HorizonDays) {
				if c.Status != 404 {
					t.Fatalf("date refused, want %d", c.Status)
				}
				return
			}
			_, _, err := journal.DecodePut([]byte(c.Body))
			var field *journal.ValidationError
			switch {
			case c.Status == 200 && err != nil:
				t.Fatalf("refused: %v", err)
			case c.Status == 400 && (!errors.As(err, &field) || c.Field == nil || field.Field != *c.Field):
				t.Fatalf("want field %v, got %v", c.Field, err)
			case c.Status != 200 && c.Status != 400:
				t.Fatalf("date allowed, want %d", c.Status)
			}
		})
	}
}

func TestStoreEncryptsAnswersAndDropsOldEntries(t *testing.T) {
	dir := testutil.Dir(t)
	store := journal.Store{Dir: dir, Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	answers := map[string]bool{}
	for _, behaviour := range journal.Catalogue {
		answers[behaviour.Key] = true
	}
	put := func(date string, answers map[string]bool) *journal.Entry {
		t.Helper()
		entry, err := store.Put(t.Context(), date, now, journal.Precondition{}, func(map[string]bool) (map[string]bool, error) { return answers, nil })
		if err != nil {
			t.Fatal(err)
		}
		return entry
	}
	put("2026-03-09", answers)
	if _, err := store.SetBehaviours(t.Context(), []string{"sauna", "alcohol"}, now); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(filepath.Join(dir, journal.FileName))
	if err != nil {
		t.Fatal(err)
	}
	for _, behaviour := range journal.Catalogue {
		if bytes.Contains(raw, []byte(behaviour.Key)) {
			t.Fatalf("%s is readable on disk", behaviour.Key)
		}
	}
	book, err := store.Load()
	if err != nil || !reflect.DeepEqual(book.Entry("2026-03-09").Answers, answers) {
		t.Fatal("answers did not round trip", err)
	}
	if got := book.Enabled(); len(got) != 2 || got[0].Key != "alcohol" || got[1].Key != "sauna" {
		t.Fatalf("enabled set is not in catalogue order: %+v", got)
	}
	put("2025-02-03", map[string]bool{"alcohol": false})
	put("2025-02-02", map[string]bool{"alcohol": false})
	book, _ = store.Load()
	if book.Entry("2025-02-02") != nil || book.Entry("2025-02-03") == nil {
		t.Fatal("retention must keep 400 days and drop older entries")
	}
	if put("2026-03-09", map[string]bool{}) != nil {
		t.Fatal("empty answers must remove the entry")
	}
	if book, _ = store.Load(); book.Entry("2026-03-09") != nil {
		t.Fatal("removed entry still stored")
	}
	if book, _ = store.SetBehaviours(t.Context(), nil, now); len(book.Enabled()) != 5 {
		t.Fatal("reset must restore the five defaults")
	}
}

func TestPutPreconditionAndReplay(t *testing.T) {
	store := journal.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 10, 7, 42, 9, 500, time.UTC)
	set := func(condition journal.Precondition, answers map[string]bool) (*journal.Entry, error) {
		return store.Put(t.Context(), "2026-03-09", now, condition, func(map[string]bool) (map[string]bool, error) { return answers, nil })
	}
	noEntry := journal.Precondition{Present: true}
	first, err := set(noEntry, map[string]bool{"alcohol": true})
	if err != nil || !first.UpdatedAt.Equal(now.Truncate(time.Second)) {
		t.Fatal("first answer refused", err)
	}
	now = now.Add(time.Hour)
	if replay, err := set(noEntry, map[string]bool{"alcohol": true}); err != nil || !replay.UpdatedAt.Equal(first.UpdatedAt) {
		t.Fatal("a replay must answer with the stored entry", err)
	}
	if _, err = set(noEntry, map[string]bool{"alcohol": false}); !errors.Is(err, journal.ErrChanged) {
		t.Fatal("a stale precondition must conflict", err)
	}
	stale := first.UpdatedAt.Add(-time.Minute)
	if _, err = set(journal.Precondition{Present: true, UpdatedAt: &stale}, map[string]bool{"alcohol": false}); !errors.Is(err, journal.ErrChanged) {
		t.Fatal("a different updated_at must conflict", err)
	}
	if second, err := set(journal.Precondition{Present: true, UpdatedAt: &first.UpdatedAt}, map[string]bool{"alcohol": false}); err != nil || second.Answers["alcohol"] {
		t.Fatal("a matching precondition must store", err)
	}
	if _, err = set(journal.Precondition{}, map[string]bool{"stress": true}); err != nil {
		t.Fatal("an absent precondition must store", err)
	}
}

func TestArguments(t *testing.T) {
	stored := map[string]bool{"alcohol": true, "stress": false}
	got, err := journal.ParseArguments(stored, []string{"alcohol=clear", "late_meal=yes", "stress=no"})
	if err != nil || !reflect.DeepEqual(got, map[string]bool{"late_meal": true, "stress": false}) || !stored["alcohol"] {
		t.Fatalf("got %v, %v", got, err)
	}
	for _, args := range [][]string{nil, {"alcohol"}, {"coffee=yes"}, {"alcohol=maybe"}} {
		if _, err := journal.ParseArguments(stored, args); err == nil || err.Error() != "Invalid journal field: answers." {
			t.Fatalf("%v accepted: %v", args, err)
		}
	}
	if keys, err := journal.ParseBehaviours("stress,alcohol"); err != nil || !reflect.DeepEqual(keys, []string{"alcohol", "stress"}) {
		t.Fatal(keys, err)
	}
	for _, list := range []string{"", "alcohol,alcohol", "coffee", "alcohol,"} {
		if _, err := journal.ParseBehaviours(list); err == nil || err.Error() != "Invalid journal field: behaviours." {
			t.Fatalf("%q accepted", list)
		}
	}
}
