package score_test

import (
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
)

func TestEditLimitCases(t *testing.T) {
	var vectors struct {
		Cases []struct {
			Name, State string
			Start, End  time.Time
			MergeWith   []string `json:"merge_with"`
			Accepted    bool
			Field       *string
		}
	}
	raw, err := os.ReadFile("../../fixtures/v2/edits/limit_cases.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &vectors); err != nil {
		t.Fatal(err)
	}
	for _, tc := range vectors.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			e := engine(t, fixtureState(t, "edit"), "2026-03-12T20:30:00Z", config.Defaults())
			raw, err := os.ReadFile("../../fixtures/v2/edits/book_" + tc.State + ".json")
			if err != nil {
				t.Fatal(err)
			}
			var book activities.Book
			if err = json.Unmarshal(raw, &book); err != nil {
				t.Fatal(err)
			}
			e.Activities, e.Edits = book.Activities, book.Edits
			_, err = e.ValidateEdit(activities.Edit{ID: bandOne, Start: &tc.Start, End: &tc.End, MergeWith: tc.MergeWith})
			if (err == nil) != tc.Accepted {
				t.Fatalf("accepted=%t: %v", tc.Accepted, err)
			}
			if tc.Field != nil {
				var invalid *activities.EditValidationError
				if !errors.As(err, &invalid) || invalid.Field != *tc.Field {
					t.Fatalf("want field %s: %v", *tc.Field, err)
				}
			}
		})
	}
}
