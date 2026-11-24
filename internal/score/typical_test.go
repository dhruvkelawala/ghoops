package score

import (
	"math"
	"testing"
)

func TestPercentile(t *testing.T) {
	for _, tc := range []struct {
		values  []float64
		q, want float64
	}{
		{[]float64{5}, .25, 5}, {[]float64{10, 2}, .25, 4},
		{[]float64{7, 1, 4, 6, 2, 5, 3}, .25, 2.5},
		{[]float64{8, 7, 6, 5, 4, 3, 2, 1}, .75, 6.25},
		{[]float64{2, 2, 2, 4, 4, 4, 4}, .25, 2},
	} {
		if math.Abs(percentile(tc.values, tc.q)-tc.want) > 1e-9 {
			t.Fatal("linear percentile mismatch")
		}
	}
}
