package activities

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestSleepEditRetentionAndConcurrentPrecondition(t *testing.T) {
	store := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	put := func(date string, end time.Time, at time.Time, condition EditPrecondition) (*SleepEdit, error) {
		return store.PutSleepEdit(t.Context(), date, at, condition, func(Book) (*SleepEdit, error) {
			return &SleepEdit{Date: date, Start: now.Add(-12 * time.Hour), End: end}, nil
		})
	}
	old := now.AddDate(0, 0, -401)
	if _, err := put("2025-02-01", now.Add(-7*time.Hour), old, EditPrecondition{}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.PutEdit(t.Context(), Edit{ID: "synthetic-activity", Hidden: true}, now); err != nil {
		t.Fatal(err)
	}
	book, err := store.Load()
	if err != nil || len(book.SleepEdits) != 0 || len(book.Edits) != 1 {
		t.Fatal("activity write did not retain activity edit and prune expired sleep", err)
	}
	if _, err = put("2026-03-10", now.Add(-7*time.Hour), now, EditPrecondition{Present: true}); err != nil {
		t.Fatal(err)
	}
	var writers sync.WaitGroup
	results := make(chan error, 2)
	for _, minutes := range []int{1, 2} {
		writers.Go(func() {
			_, err := put("2026-03-10", now.Add(-7*time.Hour).Add(time.Duration(minutes)*time.Minute), now.Add(time.Minute), EditPrecondition{Present: true, UpdatedAt: &now})
			results <- err
		})
	}
	writers.Wait()
	close(results)
	accepted, refused := 0, 0
	for err := range results {
		if err == nil {
			accepted++
		} else if errors.Is(err, ErrSleepChanged) {
			refused++
		} else {
			t.Fatal(err)
		}
	}
	if accepted != 1 || refused != 1 {
		t.Fatal("concurrent writers", accepted, refused)
	}
	book, err = store.Load()
	if err != nil || len(book.SleepEdits) != 1 || len(book.Edits) != 1 {
		t.Fatal("sleep write lost activity edits", err)
	}
	if err = store.DeleteSleepEdit(t.Context(), "2026-03-10", now); err != nil {
		t.Fatal(err)
	}
	book, err = store.Load()
	if err != nil || len(book.SleepEdits) != 0 || len(book.Edits) != 1 {
		t.Fatal("restore lost activity edits", err)
	}
}
