package activities

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func anyID(Book) error { return nil }

func TestRatingDecodeAcceptsWholeNumbersInRange(t *testing.T) {
	for body, want := range map[string]int{`{"rpe":0}`: 0, `{"rpe":7}`: 7, `{"rpe":7.0}`: 7, `{"rpe":10,"note":"ignored"}`: 10} {
		if got, err := DecodeRating([]byte(body)); err != nil || got != want {
			t.Fatalf("%s: got %d, %v", body, got, err)
		}
	}
	for body, field := range map[string]string{`[]`: "body", `null`: "body", `{}`: "rpe", `{"rpe":null}`: "rpe", `{"rpe":7.5}`: "rpe", `{"rpe":"7"}`: "rpe", `{"rpe":-1}`: "rpe", `{"rpe":11}`: "rpe", `{"rpe":true}`: "rpe"} {
		_, err := DecodeRating([]byte(body))
		var invalid *EditValidationError
		if !errors.As(err, &invalid) || invalid.Field != field {
			t.Fatalf("%s: want field %s, got %v", body, field, err)
		}
	}
	for _, id := range []string{"", "a/b", "effort-2026-03-11T18:04:00Z"} {
		if ValidateRatingID(id) == nil {
			t.Fatalf("id %q accepted", id)
		}
	}
}

func TestRatingReplayWritesOnceAndDeleteIsPermanent(t *testing.T) {
	s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	ctx, now := context.Background(), time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	first, err := s.PutRating(ctx, "7300000000000000101", 7, now, anyID)
	if err != nil || first.RPE != 7 || !first.UpdatedAt.Equal(now) {
		t.Fatal("first rating", err)
	}
	file := filepath.Join(s.Dir, "activities-v2.enc")
	before, err := os.Stat(file)
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(20 * time.Millisecond)
	replay, err := s.PutRating(ctx, "7300000000000000101", 7, now.Add(time.Hour), anyID)
	after, _ := os.Stat(file)
	if err != nil || !replay.UpdatedAt.Equal(now) || !after.ModTime().Equal(before.ModTime()) {
		t.Fatal("replay rewrote the rating", err)
	}
	changed, err := s.PutRating(ctx, "7300000000000000101", 5, now.Add(time.Hour), anyID)
	if err != nil || changed.RPE != 5 || !changed.UpdatedAt.Equal(now.Add(time.Hour)) {
		t.Fatal("change", err)
	}
	refused := errors.New("not found")
	if _, err = s.PutRating(ctx, "7300000000000000102", 3, now, func(Book) error { return refused }); err != refused {
		t.Fatal("lookup error ignored", err)
	}
	book, err := s.Load()
	if err != nil || len(book.Ratings) != 1 || book.Ratings[0].RPE != 5 {
		t.Fatal("one rating stored", err)
	}
	if err = s.DeleteRating(ctx, "7300000000000000101", now); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteRating(ctx, "7300000000000000101", now); !errors.Is(err, ErrNotFound) {
		t.Fatal("second delete", err)
	}
}

func TestRatingSurvivesOtherWritesRetentionAndCascade(t *testing.T) {
	s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	ctx, now := context.Background(), time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	a := Upload{ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING", DisplayName: "Boxing", Start: now.Add(-time.Hour), End: now}
	if _, _, err := s.Put(ctx, a, now); err != nil {
		t.Fatal(err)
	}
	for id, at := range map[string]time.Time{"goop-" + a.ID: now, "old": now.AddDate(0, 0, -401), "edge": now.AddDate(0, 0, -400), "7300000000000000101": now} {
		if _, err := s.PutRating(ctx, id, 6, at, anyID); err != nil {
			t.Fatal(err)
		}
	}
	b := Upload{ID: "3f0c0000-0000-4000-8000-000000000002", ExerciseType: "WALKING", DisplayName: "Walking", Start: now.Add(-3 * time.Hour), End: now.Add(-2 * time.Hour)}
	if _, _, err := s.Put(ctx, b, now); err != nil {
		t.Fatal(err)
	}
	note := "Synthetic note"
	if _, err := s.PutEdit(ctx, Edit{ID: "7300000000000000101", Notes: &note}, now); err != nil {
		t.Fatal(err)
	}
	if _, err := s.PutSleepEdit(ctx, "2026-03-12", now, EditPrecondition{}, func(Book) (*SleepEdit, error) {
		return &SleepEdit{Start: now.Add(-20 * time.Hour), End: now.Add(-12 * time.Hour)}, nil
	}); err != nil {
		t.Fatal(err)
	}
	ids := func() map[string]bool {
		book, err := s.Load()
		if err != nil {
			t.Fatal(err)
		}
		out := map[string]bool{}
		for _, r := range book.Ratings {
			out[r.ID] = true
		}
		return out
	}
	got := ids()
	if len(got) != 3 || !got["goop-"+a.ID] || !got["edge"] || !got["7300000000000000101"] || got["old"] {
		t.Fatalf("ratings after other writes and retention: %v", got)
	}
	if err := s.Delete(ctx, a.ID, now); err != nil {
		t.Fatal(err)
	}
	if got = ids(); got["goop-"+a.ID] || len(got) != 2 {
		t.Fatalf("permanent delete kept the rating: %v", got)
	}
}
