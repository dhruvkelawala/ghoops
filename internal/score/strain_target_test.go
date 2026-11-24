package score_test

import (
	"reflect"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/score"
)

func TestStrainTargetGoldenVectorsAndVersion(t *testing.T) {
	var file struct {
		Version string `json:"score_version"`
		Cases   []struct {
			Name  string
			Input struct {
				Recovery   score.Recovery `json:"recovery"`
				Value      *float64       `json:"strain_value"`
				Confidence *string        `json:"strain_confidence"`
				Intent     string         `json:"intent"`
			}
			Expected score.StrainTarget
		}
	}
	vectorFile(t, "strain_target", &file)
	if score.Version != "2.4.1" || file.Version != score.Version {
		t.Fatalf("score version %q, vector %q", score.Version, file.Version)
	}
	for _, tc := range file.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			strain := score.Strain{Rating: score.Rating{Value: tc.Input.Value}, Confidence: tc.Input.Confidence}
			got := score.StrainTargetFor(tc.Input.Recovery, strain, tc.Input.Intent)
			if !reflect.DeepEqual(got, tc.Expected) {
				t.Fatalf("target = %+v, want %+v", got, tc.Expected)
			}
		})
	}
}
