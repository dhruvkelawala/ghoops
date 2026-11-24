package activities

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestEditRoundTripReplayNormalizationAndEncryption(t *testing.T) {
	s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	note, sport := "  Synthetic note, 6 rounds. \n", "BOXING"
	start, end := now.Add(-2*time.Hour), now.Add(-time.Hour)
	e := Edit{ID: "7300000000000000101", ExerciseType: &sport, Start: &start, End: &end, Notes: &note, MergeWith: []string{"7300000000000000102"}}
	stored, err := s.PutEdit(context.Background(), e, now)
	if err != nil || stored == nil || *stored.Notes != "Synthetic note, 6 rounds." {
		t.Fatalf("trimmed edit: %v", err)
	}
	replay, err := s.PutEdit(context.Background(), e, now.Add(time.Minute))
	if err != nil || !reflect.DeepEqual(stored, replay) {
		t.Fatal("replay changed edit or timestamp", err)
	}
	reopened := Store{Dir: s.Dir, Vault: s.Vault}
	edits, err := reopened.Edits()
	if err != nil || len(edits) != 1 || !reflect.DeepEqual(edits[0], *stored) {
		t.Fatal("edit round trip", err)
	}
	raw, err := os.ReadFile(filepath.Join(s.Dir, "activities-v2.enc"))
	if err != nil || bytes.Contains(raw, []byte("Synthetic note")) || bytes.Contains(raw, []byte("BOXING")) {
		t.Fatal("plaintext on disk", err)
	}
	aead, err := s.aead(false)
	if err != nil {
		t.Fatal(err)
	}
	const header = "ghealth-cache-v2\n"
	plain, err := aead.Open(nil, raw[len(header):len(header)+aead.NonceSize()], raw[len(header)+aead.NonceSize():], []byte(header+secure.Service(s.Dir)))
	if err != nil {
		t.Fatal(err)
	}
	var wire struct{ Version int }
	if json.Unmarshal(plain, &wire) != nil || wire.Version != 1 {
		t.Fatal("storage version changed")
	}
	empty, err := s.PutEdit(context.Background(), Edit{ID: e.ID}, now)
	if err != nil || empty != nil {
		t.Fatal("empty override was stored", err)
	}
	edits, err = s.Edits()
	if err != nil || len(edits) != 0 {
		t.Fatal("normalisation retained override", err)
	}
	if err = s.DeleteEdit(context.Background(), e.ID, now); !errors.Is(err, ErrNotFound) {
		t.Fatal("delete missing edit", err)
	}
}

func TestEditReadsLegacyBookAndActivityOrigin(t *testing.T) {
	s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	if err := s.save(Book{Activities: []Record{}, Edits: []Edit{}}, now); err != nil {
		t.Fatal(err)
	}
	aead, err := s.aead(false)
	if err != nil {
		t.Fatal(err)
	}
	const header = "ghealth-cache-v2\n"
	nonce := make([]byte, aead.NonceSize())
	legacy := []byte(`{"version":1,"activities":[{"id":"3f0c0000-0000-4000-8000-000000000001","exercise_type":"BOXING","display_name":"Boxing","start":"2026-03-10T12:00:00Z","end":"2026-03-10T13:00:00Z","pauses":[],"created_at":"2026-03-10T14:30:00Z"}]}`)
	raw := append([]byte(header), nonce...)
	raw = aead.Seal(raw, nonce, legacy, []byte(header+secure.Service(s.Dir)))
	if err = os.WriteFile(filepath.Join(s.Dir, "activities-v2.enc"), raw, 0600); err != nil {
		t.Fatal(err)
	}
	book, err := s.Load()
	if err != nil || len(book.Edits) != 0 || len(book.Activities) != 1 || book.Activities[0].Origin != "live" || book.Activities[0].Notes != nil {
		t.Fatal("legacy book rejected", err)
	}
	row, created, err := s.Put(context.Background(), Upload{ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING", DisplayName: "Boxing", Start: time.Date(2026, 3, 10, 12, 0, 0, 0, time.UTC), End: time.Date(2026, 3, 10, 13, 0, 0, 0, time.UTC)}, now)
	if err != nil || created || row.Origin != "live" {
		t.Fatal("legacy upload replay conflicts", err)
	}
}

func TestEditRetentionAndPermanentActivityDeleteCascade(t *testing.T) {
	s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	ctx := context.Background()
	old := now.AddDate(0, 0, -401)
	edge := now.AddDate(0, 0, -400)
	for _, tc := range []struct {
		id string
		at time.Time
	}{{"old", old}, {"edge", edge}} {
		if _, err := s.PutEdit(ctx, Edit{ID: tc.id, Hidden: true}, tc.at); err != nil {
			t.Fatal(err)
		}
	}
	a := Upload{ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING", DisplayName: "Boxing", Start: now.Add(-time.Hour), End: now}
	if _, _, err := s.Put(ctx, a, now); err != nil {
		t.Fatal(err)
	}
	target := "goop-" + a.ID
	if _, err := s.PutEdit(ctx, Edit{ID: target, Hidden: true}, now); err != nil {
		t.Fatal(err)
	}
	note := "Synthetic survivor"
	if _, err := s.PutEdit(ctx, Edit{ID: "absorber", Notes: &note, MergeWith: []string{target}}, now); err != nil {
		t.Fatal(err)
	}
	if err := s.Delete(ctx, a.ID, now); err != nil {
		t.Fatal(err)
	}
	book, err := s.Load()
	if err != nil || len(book.Activities) != 0 || len(book.Edits) != 2 {
		t.Fatal("cascade or retention count", err)
	}
	for _, e := range book.Edits {
		if e.ID == target || e.ID == "old" || len(e.MergeWith) != 0 {
			t.Fatal("deleted reference or expired edit survived")
		}
	}
	if err = s.DeleteEdit(ctx, "edge", now); err != nil {
		t.Fatal(err)
	}
	edits, err := s.Edits()
	if err != nil || len(edits) != 1 || edits[0].ID != "absorber" {
		t.Fatal("restore removed wrong edit", err)
	}
}

func TestActivityAddedOriginNotesAndThirtyDayBound(t *testing.T) {
	now := time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	base := Upload{ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING", DisplayName: "Boxing", Origin: "added", Start: now.Add(-30 * 24 * time.Hour), End: now.Add(-30*24*time.Hour + time.Hour)}
	for _, tc := range []struct {
		name, field string
		change      func(*Upload)
	}{
		{"boundary", "", func(*Upload) {}},
		{"old", "start", func(a *Upload) { a.Start = a.Start.Add(-time.Second) }},
		{"origin", "origin", func(a *Upload) { a.Origin = "unknown" }},
		{"added-live", "live", func(a *Upload) { a.Live = json.RawMessage(`{}`) }},
		{"empty-note", "notes", func(a *Upload) { n := " \n"; a.Notes = &n }},
		{"long-note", "notes", func(a *Upload) { n := strings.Repeat("界", 501); a.Notes = &n }},
		{"unicode-note", "", func(a *Upload) { n := " \n" + strings.Repeat("界", 500) + " "; a.Notes = &n }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a := base
			tc.change(&a)
			s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			row, _, err := s.Put(context.Background(), a, now)
			if tc.field != "" {
				var bad *ValidationError
				if !errors.As(err, &bad) || bad.Field != tc.field {
					t.Fatalf("want field %s, got %v", tc.field, err)
				}
				return
			}
			if err != nil || row.Origin != "added" {
				t.Fatal("added rejected", err)
			}
			if row.Notes != nil && strings.TrimSpace(*row.Notes) != *row.Notes {
				t.Fatal("note not trimmed")
			}
			replay, created, err := s.Put(context.Background(), a, now)
			first, _ := json.Marshal(row)
			second, _ := json.Marshal(replay)
			if err != nil || created || !bytes.Equal(first, second) {
				t.Fatal("added replay changed response", err)
			}
		})
	}
}

func TestEditAndActivityConcurrentWritesKeepBothArrays(t *testing.T) {
	s := Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
	now := time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC)
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	wg.Go(func() {
		_, err := s.PutEdit(context.Background(), Edit{ID: "recorded", Hidden: true}, now)
		errs <- err
	})
	wg.Go(func() {
		_, _, err := s.Put(context.Background(), Upload{ID: "3f0c0000-0000-4000-8000-000000000001", ExerciseType: "BOXING", DisplayName: "Boxing", Start: now.Add(-time.Hour), End: now}, now)
		errs <- err
	})
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	book, err := s.Load()
	if err != nil || len(book.Activities) != 1 || len(book.Edits) != 1 {
		t.Fatal("lost concurrent write", err)
	}
}
