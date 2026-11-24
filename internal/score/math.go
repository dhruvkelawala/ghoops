package score

import "math"

func ptr[T any](v T) *T { return &v }
func round(v float64, places int) float64 {
	scale := math.Pow10(places)
	return math.Round(v*scale) / scale
}
func rounded(v *float64, places int) *float64 {
	if v == nil {
		return nil
	}
	return ptr(round(*v, places))
}
func clamp(v, low, high float64) float64 { return math.Max(low, math.Min(high, v)) }
func text(v string) *string {
	if v == "" {
		return nil
	}
	return &v
}
func band(v, high, medium float64) *string {
	if v >= high {
		return ptr("high")
	}
	if v >= medium {
		return ptr("medium")
	}
	return ptr("low")
}
func strainBand(v float64) *string {
	if v < StrainModerateMin {
		return ptr("light")
	}
	if v < StrainStrenuousMin {
		return ptr("moderate")
	}
	if v < StrainAllOutMin {
		return ptr("strenuous")
	}
	return ptr("all_out")
}
func confidence(v float64) *string {
	if v >= CoverageHigh {
		return ptr("high")
	}
	if v >= CoverageMedium {
		return ptr("medium")
	}
	return ptr("low")
}
func cdf(v float64) float64         { return .5 * (1 + math.Erf(v/math.Sqrt2)) }
func z(v, mean, sd float64) float64 { return clamp((v-mean)/sd, -ZClamp, ZClamp) }

type sample struct {
	n        int
	mean, sd float64
	floor    bool
}

func stats(values []float64, floor float64, log bool) sample {
	s := sample{n: len(values)}
	if s.n == 0 {
		return s
	}
	for _, v := range values {
		if log {
			v = math.Log(v)
		}
		s.mean += v
	}
	s.mean /= float64(s.n)
	if s.n < 2 {
		return s
	}
	for _, v := range values {
		if log {
			v = math.Log(v)
		}
		s.sd += (v - s.mean) * (v - s.mean)
	}
	s.sd = math.Sqrt(s.sd / float64(s.n-1))
	s.floor = s.sd < floor
	s.sd = math.Max(s.sd, floor)
	return s
}
func (s sample) output() Baseline {
	b := Baseline{N: s.n}
	if s.n > 0 {
		b.Mean = ptr(round(s.mean, 2))
	}
	if s.n > 1 {
		b.SD = ptr(round(s.sd, 2))
		b.Floor = ptr(s.floor)
	}
	return b
}
func (s sample) hrvOutput() HRVBaseline {
	b := HRVBaseline{N: s.n}
	if s.n > 0 {
		b.Mean = ptr(round(s.mean, 4))
		b.MeanMS = ptr(round(math.Exp(s.mean), 1))
	}
	if s.n > 1 {
		b.SD = ptr(round(s.sd, 4))
		b.Floor = ptr(s.floor)
	}
	return b
}
