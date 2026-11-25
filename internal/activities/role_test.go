package activities_test

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

const activityFile = "activities-v2.enc"

func TestLegacyActivitiesKeepAllDataWhenSaved(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	old := activities.Record{
		Upload: activities.Upload{
			ID: "00000000-0000-4000-8000-000000000001", ExerciseType: "WALKING",
			DisplayName: "Walk", Start: now.Add(-time.Hour), End: now.Add(-30 * time.Minute),
			Origin: "live", Pauses: []activities.Pause{},
		},
		CreatedAt: now,
	}
	edit := activities.Edit{ID: "recorded-1", Hidden: true, MergeWith: []string{}, UpdatedAt: now}
	sleep := activities.SleepEdit{Date: "2026-03-10", Start: now.Add(-16 * time.Hour), End: now.Add(-8 * time.Hour), UpdatedAt: now}
	rating := activities.Rating{ID: "recorded-2", RPE: 6, UpdatedAt: now}
	for era, name := range []string{"activities", "edits", "sleep edits", "ratings"} {
		t.Run(name, func(t *testing.T) {
			store := activities.Store{Dir: testutil.Dir(t), Vault: &testutil.Vault{}}
			want := activities.Book{
				Activities: []activities.Record{old}, Edits: []activities.Edit{},
				SleepEdits: []activities.SleepEdit{}, Ratings: []activities.Rating{},
			}
			legacy := map[string]any{"version": 1, "activities": want.Activities}
			if era >= 1 {
				want.Edits = append(want.Edits, edit)
				legacy["edits"] = want.Edits
			}
			if era >= 2 {
				want.SleepEdits = append(want.SleepEdits, sleep)
				legacy["sleep_edits"] = want.SleepEdits
			}
			if era >= 3 {
				want.Ratings = append(want.Ratings, rating)
				legacy["ratings"] = want.Ratings
			}
			key := testutil.WriteLegacyV2File(t, store.Dir, activityFile, store.Vault, legacy)
			if got, err := store.Load(); err != nil || !reflect.DeepEqual(got, want) {
				t.Fatal("legacy activities did not load with their original data", err)
			}
			upload := activities.Upload{
				ID: "00000000-0000-4000-8000-000000000002", ExerciseType: "RUNNING",
				DisplayName: "Run", Start: now.Add(-20 * time.Minute), End: now,
				Origin: "added", Pauses: []activities.Pause{},
			}
			if _, created, err := store.Put(t.Context(), upload, now); err != nil || !created {
				t.Fatal("activity save failed", err)
			}
			testutil.CheckV2FileRole(t, store.Dir, activityFile, "activities", key)
			want.Activities = append(want.Activities, activities.Record{Upload: upload, CreatedAt: now})
			if got, err := store.Load(); err != nil || !reflect.DeepEqual(got, want) {
				t.Fatal("activities did not reopen with the old and new data", err)
			}
		})
	}
}

func TestJournalFileRefusedAsActivities(t *testing.T) {
	for _, legacy := range []bool{true, false} {
		name := "role-bound"
		if legacy {
			name = "legacy"
		}
		t.Run(name, func(t *testing.T) {
			dir, vault := testutil.Dir(t), &testutil.Vault{}
			store := journal.Store{Dir: dir, Vault: vault}
			if legacy {
				body := map[string]any{"version": 1, "entries": []journal.Entry{}, "behaviours": []string{"alcohol"}}
				testutil.WriteLegacyV2File(t, dir, journal.FileName, vault, body)
			} else if _, err := store.SetBehaviours(t.Context(), []string{"alcohol"}, time.Now()); err != nil {
				t.Fatal(err)
			}
			if _, err := store.Load(); err != nil {
				t.Fatal("journal did not open in its own slot", err)
			}
			moveStoreFile(t, dir, journal.FileName, activityFile)
			if _, err := (activities.Store{Dir: dir, Vault: vault}).Load(); err == nil {
				t.Fatal("journal opened as activities")
			}
		})
	}
}

func TestActivitiesFileRefusedAsJournal(t *testing.T) {
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	for _, legacy := range []bool{true, false} {
		name := "role-bound"
		if legacy {
			name = "legacy"
		}
		t.Run(name, func(t *testing.T) {
			dir, vault := testutil.Dir(t), &testutil.Vault{}
			store := activities.Store{Dir: dir, Vault: vault}
			if legacy {
				body := map[string]any{"version": 1, "activities": []activities.Record{}}
				testutil.WriteLegacyV2File(t, dir, activityFile, vault, body)
			} else {
				upload := activities.Upload{
					ID: "00000000-0000-4000-8000-000000000001", ExerciseType: "WALKING",
					DisplayName: "Walk", Start: now.Add(-time.Hour), End: now,
				}
				if _, _, err := store.Put(t.Context(), upload, now); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := store.Load(); err != nil {
				t.Fatal("activities did not open in their own slot", err)
			}
			moveStoreFile(t, dir, activityFile, journal.FileName)
			if _, err := (journal.Store{Dir: dir, Vault: vault}).Load(); err == nil {
				t.Fatal("activities opened as journal")
			}
		})
	}
}

func moveStoreFile(t *testing.T, dir, from, to string) {
	t.Helper()
	if err := os.Rename(filepath.Join(dir, from), filepath.Join(dir, to)); err != nil {
		t.Fatal(err)
	}
}
