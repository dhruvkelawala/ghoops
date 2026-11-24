package activities

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestEditPreconditionGuardsConcurrentStoreWrites(t *testing.T) {
	s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	ctx := context.Background()
	edit := Edit{ID: "recorded", Hidden: true}
	put := func(condition EditPrecondition, hidden bool, at time.Time) (*Edit, error) {
		return s.UpdateEdit(ctx, at, condition, func(Book) (Edit, error) {
			edit.Hidden = hidden
			return edit, nil
		})
	}
	first, err := put(EditPrecondition{Present: true}, true, now)
	if err != nil || first == nil {
		t.Fatal("null with none", err)
	}
	old := now.Add(-time.Second)
	replay, err := put(EditPrecondition{Present: true, UpdatedAt: &old}, true, now.Add(time.Second))
	if err != nil || replay == nil || !replay.UpdatedAt.Equal(first.UpdatedAt) {
		t.Fatal("replay must beat stale condition", err)
	}
	if _, err = put(EditPrecondition{Present: true}, false, now); !errors.Is(err, ErrEditChanged) {
		t.Fatal("null overwrote edit", err)
	}
	fractional := now.Add(900 * time.Millisecond)
	if removed, err := put(EditPrecondition{Present: true, UpdatedAt: &fractional}, false, now); err != nil || removed != nil {
		t.Fatal("same second must match", err)
	}
	if _, err = put(EditPrecondition{Present: true, UpdatedAt: &now}, true, now); !errors.Is(err, ErrEditChanged) {
		t.Fatal("time with no edit must refuse", err)
	}
	if _, err = put(EditPrecondition{}, true, now); err != nil {
		t.Fatal("absent precondition changed", err)
	}
	var writers sync.WaitGroup
	results := make(chan error, 2)
	for _, note := range []string{"writer one", "writer two"} {
		writers.Go(func() {
			_, err := s.UpdateEdit(ctx, now.Add(time.Second), EditPrecondition{Present: true, UpdatedAt: &now}, func(Book) (Edit, error) { return Edit{ID: "recorded", Hidden: true, Notes: &note}, nil })
			results <- err
		})
	}
	writers.Wait()
	close(results)
	accepted, refused := 0, 0
	for err := range results {
		if err == nil {
			accepted++
		} else if errors.Is(err, ErrEditChanged) {
			refused++
		} else {
			t.Fatal(err)
		}
	}
	if accepted != 1 || refused != 1 {
		t.Fatal("competing writes", accepted, refused)
	}
	edits, err := s.Edits()
	if err != nil || len(edits) != 1 || !edits[0].UpdatedAt.Equal(now.Add(time.Second)) {
		t.Fatal("winner not retained", err)
	}
}
