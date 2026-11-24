package score_test

import (
	"math"
	"reflect"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/score"
)

func TestSleepCompositeGoldenVectors(t *testing.T) {
	var file struct {
		Version string `json:"score_version"`
		Cases   []struct {
			Name  string
			Input struct {
				Performance score.Rating `json:"performance"`
				Consistency *float64     `json:"consistency"`
				Efficiency  *int         `json:"efficiency_pct"`
			}
			Expected score.SleepComposite
		}
	}
	vectorFile(t, "sleep_composite", &file)
	// Only the composite's own revision is pinned, so a Version bump elsewhere needs no change here.
	if !strings.HasSuffix(file.Version, "+"+score.CompositeRevision) {
		t.Fatalf("vector version %q, want the suffix +%s", file.Version, score.CompositeRevision)
	}
	if len(file.Cases) != 12 {
		t.Fatalf("%d cases, want the 12 of composite-sleep-spec §4.1", len(file.Cases))
	}
	for _, tc := range file.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			got := score.ComputeSleepComposite(tc.Input.Performance, tc.Input.Consistency, tc.Input.Efficiency)
			if !reflect.DeepEqual(got, tc.Expected) {
				t.Fatalf("composite = %+v %+v %+v, want %+v %+v %+v", got.Rating, got.Weights, got.Parts, tc.Expected.Rating, tc.Expected.Weights, tc.Expected.Parts)
			}
		})
	}
}

// The total is a sum of whole-percent weights times integer parts, so every half-way case
// must round up exactly as integer arithmetic does (scores.md §1.1, §4.5a).
func TestSleepCompositeRoundsHalfWayLikeIntegers(t *testing.T) {
	span := score.CompositeEfficiencyFull - score.CompositeEfficiencyZero
	percent := func(weight float64) int { return int(math.Round(weight * 100)) }
	ws, wc, we := percent(score.CompositeWeightSufficiency), percent(score.CompositeWeightConsistency), percent(score.CompositeWeightEfficiency)
	halfWay := 0
	for sufficiency := 0; sufficiency <= 100; sufficiency++ {
		for consistency := -1; consistency <= 100; consistency++ {
			for _, efficiency := range []int{-1, 62, 70, 71, 84, 88, 90, 97} {
				s, c, e := ws, wc, we
				total := 0
				var cons *float64
				if consistency < 0 {
					s, c = s+c, 0
				} else {
					cons = ptrTo(float64(consistency))
					total += c * consistency
				}
				var eff *int
				if efficiency < 0 {
					s, e = s+e, 0
				} else {
					if 100*(efficiency-score.CompositeEfficiencyZero)%span != 0 {
						t.Skip("efficiency part is not a whole number with these constants")
					}
					eff = &efficiency
					total += e * min(100, max(0, 100*(efficiency-score.CompositeEfficiencyZero)/span))
				}
				total += s * sufficiency
				if total%100 == 50 {
					halfWay++
				}
				got := score.ComputeSleepComposite(score.Rating{Value: ptrTo(float64(sufficiency)), Status: "ok"}, cons, eff)
				if want := float64((total + 50) / 100); *got.Value != want {
					t.Fatalf("S %d C %d E %d: %v, want %v", sufficiency, consistency, efficiency, *got.Value, want)
				}
			}
		}
	}
	if halfWay == 0 {
		t.Fatal("no half-way case exercised")
	}
}

func ptrTo[T any](v T) *T { return &v }
