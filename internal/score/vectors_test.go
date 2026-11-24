package score_test

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func vectorFile(t *testing.T, name string, target any) {
	t.Helper()
	b, err := os.ReadFile("../../fixtures/v2/scores/" + name + ".json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(b, target); err != nil {
		t.Fatal(err)
	}
}
func TestRecoveryGoldenVectors(t *testing.T) {
	var file struct {
		Cases []struct {
			Name     string
			Input    score.RecoveryInput
			Expected json.RawMessage
		}
	}
	vectorFile(t, "recovery", &file)
	for _, tc := range file.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			got := score.ComputeRecovery(tc.Input)
			b, _ := json.Marshal(got)
			var body map[string]any
			_ = json.Unmarshal(b, &body)
			if got.Components != nil {
				c := body["components"].(map[string]any)
				c["hrv_ln"] = math.Round(math.Log(*got.Inputs.HRV)*1e4) / 1e4
				c["hrv_baseline_ln_mean"] = got.Baseline.HRV.Mean
				c["hrv_baseline_ln_sd"] = got.Baseline.HRV.SD
				c["resting_hr_baseline_mean"] = got.Baseline.RHR.Mean
				c["resting_hr_baseline_sd"] = got.Baseline.RHR.SD
			}
			testutil.CompareJSON(t, body, tc.Expected, true)
		})
	}
}
func TestRecoveryReportsTheWeightsItUsed(t *testing.T) {
	var file struct {
		Cases []struct {
			Name     string
			Input    score.RecoveryInput
			Expected struct{ Components *score.Components }
		}
	}
	vectorFile(t, "recovery", &file)
	for _, tc := range file.Cases {
		if tc.Expected.Components == nil {
			continue
		}
		t.Run(tc.Name, func(t *testing.T) {
			c := score.ComputeRecovery(tc.Input).Components
			if c == nil {
				t.Fatal("missing components")
			}
			w := c.Weights
			if math.Abs(w.HRV+w.RestingHR+w.Sleep-1) > 1e-9 {
				t.Fatalf("reported weights do not sum to 1: %+v", w)
			}
			base := w.HRV*c.HRVScore + w.RestingHR*c.RHRScore + w.Sleep*c.Sleep
			if math.Abs(base-c.Base) > 0.1 {
				t.Fatalf("reported weights give %v, weighted_base is %v", base, c.Base)
			}
		})
	}
}
func TestStrainGoldenVectors(t *testing.T) {
	var file struct {
		Cases []struct {
			Name     string
			Input    score.MinuteInput
			Expected json.RawMessage
		}
		Scale      []struct{ Trimp, Strain float64 } `json:"trimp_to_strain"`
		References []struct {
			Name  string
			Input struct {
				Rest      float64 `json:"resting_hr"`
				Max       float64 `json:"max_hr"`
				Profile   string  `json:"trimp_profile"`
				HeartRate []struct {
					Minutes int
					Average float64 `json:"avg_bpm"`
				} `json:"heart_rate_profile"`
			}
			Expected struct{ Trimp, Strain float64 }
		} `json:"reference_sessions"`
	}
	vectorFile(t, "strain", &file)
	for _, tc := range file.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			testutil.CompareJSON(t, score.ComputeMinutes(tc.Input, "banister_b192"), tc.Expected, true)
		})
	}
	if len(file.References) == 0 {
		t.Fatal("missing current-scale reference sessions")
	}
	for _, tc := range file.References {
		t.Run(tc.Name, func(t *testing.T) {
			in := score.MinuteInput{Rest: tc.Input.Rest, Max: tc.Input.Max}
			for _, part := range tc.Input.HeartRate {
				in.Averages = append(in.Averages, steadyMinutes(part.Minutes, part.Average)...)
			}
			in.Expected = len(in.Averages)
			got := score.ComputeMinutes(in, tc.Input.Profile)
			if got.Strain == nil {
				t.Fatal("reference session has no strain")
			}
			if *got.Strain != tc.Expected.Strain || got.Trimp != tc.Expected.Trimp {
				t.Fatalf("current scale changed: TRIMP %g, Strain %g; want %+v", got.Trimp, *got.Strain, tc.Expected)
			}
		})
	}
	for _, tc := range file.Scale {
		if got := score.TrimpToStrain(tc.Trimp); math.Abs(got-tc.Strain) > .1+1e-9 {
			t.Fatalf("TRIMP %v: got %v want %v", tc.Trimp, got, tc.Strain)
		}
	}
}
func TestSleepGoldenVectors(t *testing.T) {
	var file struct {
		Need []struct {
			Name     string
			Input    score.SleepNeedInput
			Expected json.RawMessage
		} `json:"sleep_need"`
		Consistency []struct {
			Name  string
			Input struct {
				Nights []struct {
					Bed  string `json:"bed_local"`
					Wake string `json:"wake_local"`
				}
			}
			Expected json.RawMessage
		}
	}
	vectorFile(t, "sleep", &file)
	for _, tc := range file.Need {
		t.Run(tc.Name, func(t *testing.T) {
			n, r := score.ComputeSleepNeed(tc.Input)
			b, _ := json.Marshal(n)
			var body map[string]any
			_ = json.Unmarshal(b, &body)
			body["performance"], body["band"] = r.Value, r.Band
			testutil.CompareJSON(t, body, tc.Expected, true)
		})
	}
	for _, tc := range file.Consistency {
		t.Run(tc.Name, func(t *testing.T) {
			nights := []score.Night{}
			for _, n := range tc.Input.Nights {
				minutes := func(s string) float64 {
					var h, m int
					_, err := fmt.Sscanf(s, "%d:%d", &h, &m)
					if err != nil {
						t.Fatal(err)
					}
					return float64(60*h + m)
				}
				nights = append(nights, score.Night{Bed: minutes(n.Bed), Wake: minutes(n.Wake)})
			}
			testutil.CompareJSON(t, score.ComputeConsistency(nights), tc.Expected, false)
		})
	}
}
