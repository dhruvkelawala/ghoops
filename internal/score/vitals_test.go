package score

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestVitalVectors(t *testing.T) {
	var file struct {
		Version string `json:"score_version"`
		Cases   []struct {
			Name  string
			Input struct {
				Tonight   vitalNightVector
				LastNight *vitalNightVector `json:"last_night"`
			}
			Expected json.RawMessage
		}
	}
	raw, err := os.ReadFile("../../fixtures/v2/scores/vitals.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &file); err != nil {
		t.Fatal(err)
	}
	if file.Version != Version {
		t.Fatalf("vector version %q, engine %q", file.Version, Version)
	}
	input := func(r vitalNightVector) NightInput {
		metric := func(v *float64, baseline []float64) VitalInput {
			status := "missing"
			if v != nil {
				status = "available"
			}
			return VitalInput{v, status, baseline}
		}
		return NightInput{HRV: metric(r.HRV, r.HRVBaseline), RHR: metric(r.RHR, r.RHRBaseline), RR: metric(r.RR, r.RRBaseline), SpO2: metric(r.SpO2, r.SpO2Baseline), Temp: r.Temperature, TempStatus: "missing"}
	}
	for _, tc := range file.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			before := []Vitals{}
			if tc.Input.LastNight != nil {
				before = append(before, night(input(*tc.Input.LastNight)))
			}
			v := withAttention(night(input(tc.Input.Tonight)), before)
			ranges := map[string]any{}
			positions := map[string]*string{}
			for key, m := range v.Metrics {
				ranges[key] = nil
				if m.Low != nil && m.High != nil {
					ranges[key] = [2]float64{*m.Low, *m.High}
				}
				positions[key] = m.Position
			}
			flags := []map[string]string{}
			for _, f := range vitalFlags(v, tc.Input.Tonight.SpO2, tc.Input.Tonight.SpO2Baseline) {
				flags = append(flags, map[string]string{"code": f.Code, "message": f.Message})
			}
			testutil.CompareJSON(t, map[string]any{"ranges": ranges, "positions": positions, "outside_range": v.Outside, "adverse": v.Adverse, "persistent": v.Persistent, "metrics_with_range": v.WithRange, "monitor_state": v.State, "flags": flags}, tc.Expected, false)
		})
	}
}

type vitalNightVector struct {
	RecoveryInput
	SpO2         *float64  `json:"spo2_pct"`
	SpO2Baseline []float64 `json:"spo2_baseline_pct"`
}
