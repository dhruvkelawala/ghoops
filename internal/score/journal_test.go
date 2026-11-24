package score_test

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestJournalImpactVectors(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/scores/journal.json")
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Cases []struct {
			Name  string
			Input struct {
				Key     string
				Yes, No []float64
			}
			Expected json.RawMessage
		}
	}
	if err = json.Unmarshal(raw, &file); err != nil || len(file.Cases) == 0 {
		t.Fatal("cannot read vectors", err)
	}
	for _, c := range file.Cases {
		t.Run(c.Name, func(t *testing.T) {
			testutil.CompareJSON(t, score.ComputeJournalImpact(c.Input.Key, c.Input.Yes, c.Input.No), c.Expected, false)
		})
	}
	if got := score.ConstantsFor("banister_b192").Journal; got.WindowDays != score.JournalWindowDays || got.MinAnswers != score.JournalMinAnswers {
		t.Fatal("score_constants.journal must report the constants the engine uses", got)
	}
}
