package score

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestHRVTrendVectors(t *testing.T) {
	var file struct {
		Version string `json:"score_version"`
		Cases   []struct {
			Name  string
			Input struct {
				Week     []*float64 `json:"week_hrv_ms"`
				Baseline []float64  `json:"baseline_hrv_ms"`
			}
			Expected json.RawMessage
		}
	}
	raw, err := os.ReadFile("../../fixtures/v2/scores/hrv_trend.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &file); err != nil {
		t.Fatal(err)
	}
	if file.Version != Version {
		t.Fatalf("vector version %q, engine %q", file.Version, Version)
	}
	for _, tc := range file.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			week := []float64{}
			for _, v := range tc.Input.Week {
				if v != nil {
					week = append(week, *v)
				}
			}
			got := hrvTrend(week, tc.Input.Baseline)
			testutil.CompareJSON(t, map[string]any{"value": got.Value, "status": got.Status, "nights": got.Nights, "range_low": got.Low, "range_high": got.High, "baseline_values": got.N, "position": got.Position}, tc.Expected, false)
		})
	}
}
