package score_test

import (
	"math/rand"
	"slices"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/score"
)

func TestStrainProperties(t *testing.T) {
	for _, profile := range []string{"banister_b192", "banister_b167"} {
		t.Run(profile, func(t *testing.T) {
			reserve := []float64{0, .299999, .3, .300001, .499999, .5, .6, .7, .8, .9, 1, 1.2}
			durations := []int{1, 2, 5, 15, 40, 60, 120, 240, 720, 1440}
			t.Run("more_minutes_never_lower_strain", func(t *testing.T) {
				for _, h := range reserve {
					previous := 0.0
					for _, minutes := range durations {
						got := minuteStrain(t, steadyMinutes(minutes, 56+131*h), profile)
						if got < previous {
							t.Fatalf("reserve %g, minutes %d: strain %g fell below %g", h, minutes, got, previous)
						}
						previous = got
					}
				}
			})
			t.Run("higher_heart_rate_never_lowers_strain", func(t *testing.T) {
				rates := []float64{}
				for bpm := 40.0; bpm <= 220; bpm += .5 {
					rates = append(rates, bpm)
				}
				for _, h := range reserve {
					rates = append(rates, 56+131*h)
				}
				slices.Sort(rates)
				for _, minutes := range durations {
					previous := 0.0
					for _, bpm := range rates {
						got := minuteStrain(t, steadyMinutes(minutes, bpm), profile)
						if got < previous {
							t.Fatalf("minutes %d, heart rate %g: strain %g fell below %g", minutes, bpm, got, previous)
						}
						previous = got
					}
				}
			})
			t.Run("removing_minutes_never_raises_strain", func(t *testing.T) {
				rng := rand.New(rand.NewSource(27))
				for trial := 0; trial < 200; trial++ {
					averages := make([]float64, 2+rng.Intn(239))
					kept := []float64{}
					for i := range averages {
						averages[i] = 40 + rng.Float64()*180
						if i == 0 || i > 1 && rng.Intn(2) == 0 {
							kept = append(kept, averages[i])
						}
					}
					full := minuteStrain(t, averages, profile)
					got := score.ComputeMinutes(score.MinuteInput{Rest: 56, Max: 187, Averages: kept, Expected: len(averages)}, profile)
					if got.Strain == nil || *got.Strain > full {
						t.Fatalf("trial %d: strain %v after removal exceeded %g", trial, got.Strain, full)
					}
				}
			})
			t.Run("twenty_one_is_the_ceiling", func(t *testing.T) {
				for _, h := range reserve {
					for _, minutes := range durations {
						if got := minuteStrain(t, steadyMinutes(minutes, 56+131*h), profile); got > 21 {
							t.Fatalf("reserve %g, minutes %d: strain %g exceeded 21", h, minutes, got)
						}
					}
				}
				if got := minuteStrain(t, steadyMinutes(1440, 187), profile); got != 21 {
					t.Fatalf("saturated strain %g, want 21", got)
				}
			})
		})
	}
}

func minuteStrain(t *testing.T, averages []float64, profile string) float64 {
	t.Helper()
	got := score.ComputeMinutes(score.MinuteInput{Rest: 56, Max: 187, Averages: averages, Expected: len(averages)}, profile)
	if got.Strain == nil {
		t.Fatal("covered minutes have no strain")
	}
	return *got.Strain
}

func steadyMinutes(minutes int, bpm float64) []float64 {
	averages := make([]float64, minutes)
	for i := range averages {
		averages[i] = bpm
	}
	return averages
}
