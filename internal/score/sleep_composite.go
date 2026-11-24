package score

import (
	"math"

	"github.com/dhruvkelawala/ghoops/internal/config"
)

// VersionFor is the score_version of bodies built with cfg. Composite mode adds its revision,
// so default bodies keep Version (composite-sleep-spec D7).
func VersionFor(cfg config.Values) string {
	if cfg.CompositeSleep() {
		return Version + "+" + CompositeRevision
	}
	return Version
}

type CompositeWeights struct {
	Sufficiency float64 `json:"sufficiency"`
	Consistency float64 `json:"consistency"`
	Efficiency  float64 `json:"efficiency"`
}

// CompositeParts are the composite's inputs: hours vs. needed, consistency, and the 0 to 100 efficiency part.
type CompositeParts struct {
	Sufficiency float64  `json:"sufficiency"`
	Consistency *float64 `json:"consistency"`
	Efficiency  *float64 `json:"efficiency"`
}

type SleepComposite struct {
	Rating
	Weights *CompositeWeights `json:"weights"`
	Parts   *CompositeParts   `json:"parts"`
}

// ComputeSleepComposite blends the reported hours vs. needed, consistency and efficiency, so a
// reader can recompute it from JSON. A missing consistency or efficiency gives its weight to
// hours vs. needed.
func ComputeSleepComposite(performance Rating, consistency *float64, efficiency *int) SleepComposite {
	if performance.Value == nil {
		return SleepComposite{Rating: Rating{Status: performance.Status, Reason: performance.Reason}}
	}
	var part *float64
	if efficiency != nil {
		span := float64(CompositeEfficiencyFull - CompositeEfficiencyZero)
		part = ptr(clamp(100*float64(*efficiency-CompositeEfficiencyZero)/span, 0, 100))
	}
	// Whole-percent weights keep each product of integer parts an integer, so a half-way
	// total such as 98.5 rounds up exactly instead of drifting below .5 in floating point.
	sufficiency, regular, efficient := wholePercent(CompositeWeightSufficiency), wholePercent(CompositeWeightConsistency), wholePercent(CompositeWeightEfficiency)
	total := 0.0
	if consistency == nil {
		sufficiency, regular = sufficiency+regular, 0
	} else {
		total += regular * *consistency
	}
	if part == nil {
		sufficiency, efficient = sufficiency+efficient, 0
	} else {
		total += efficient * *part
	}
	total += sufficiency * *performance.Value
	value := math.Round(total / 100)
	return SleepComposite{
		Rating:  Rating{Value: &value, Band: band(value, SleepPerformanceHighMin, SleepPerformanceMediumMin), Status: "ok"},
		Weights: &CompositeWeights{Sufficiency: sufficiency / 100, Consistency: regular / 100, Efficiency: efficient / 100},
		Parts:   &CompositeParts{Sufficiency: *performance.Value, Consistency: consistency, Efficiency: rounded(part, 1)},
	}
}

func wholePercent(weight float64) float64 { return math.Round(weight * 100) }
