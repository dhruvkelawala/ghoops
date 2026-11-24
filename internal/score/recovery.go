package score

import "math"

type TemperatureInput struct {
	Nightly  *float64 `json:"nightly_c"`
	Baseline *float64 `json:"baseline_c"`
	SD       *float64 `json:"stddev_30d_c"`
}
type RecoveryInput struct {
	HRV             *float64          `json:"hrv_ms"`
	HRVBaseline     []float64         `json:"hrv_baseline_ms"`
	RHR             *float64          `json:"rhr_bpm"`
	RHRBaseline     []float64         `json:"rhr_baseline_bpm"`
	RR              *float64          `json:"rr_bpm"`
	RRBaseline      []float64         `json:"rr_baseline_bpm"`
	Temperature     *TemperatureInput `json:"skin_temp"`
	Sleep           *float64          `json:"sleep_performance"`
	SleepProcessing bool
	HRVConflict     bool
	RHRConflict     bool
	Today           bool
}

func ComputeRecovery(in RecoveryInput) Recovery {
	hrv, rhr, rr := stats(in.HRVBaseline, SDFloorLnRMSSD, true), stats(in.RHRBaseline, SDFloorRestingHR, false), stats(in.RRBaseline, SDFloorRespRate, false)
	out := Recovery{Rating: Rating{Status: "unavailable"}, Missing: []string{}, Calibrating: min(hrv.n, rhr.n) < CalibratedValues, Calibration: Calibration{BaselineMinValues, CalibratedValues, hrv.n, rhr.n}, Inputs: RecoveryInputs{HRV: rounded(in.HRV, 1), RHR: rounded(in.RHR, 0), RR: rounded(in.RR, 1), Sleep: in.Sleep}, Baseline: RecoveryBaselines{BaselineWindowDays, hrv.hrvOutput(), rhr.output(), rr.output()}}
	if in.Temperature != nil && in.Temperature.Nightly != nil && in.Temperature.Baseline != nil {
		out.Inputs.Temp = ptr(round(*in.Temperature.Nightly-*in.Temperature.Baseline, 2))
	}
	if in.Sleep == nil {
		out.Missing = append(out.Missing, "no_sleep")
	} else if in.SleepProcessing {
		out.Missing = append(out.Missing, "sleep_processing")
	}
	if in.HRVConflict {
		out.Missing = append(out.Missing, "hrv_conflict")
	} else if in.HRV == nil || *in.HRV <= 0 {
		out.Missing = append(out.Missing, "no_hrv")
	}
	if in.RHRConflict {
		out.Missing = append(out.Missing, "rhr_conflict")
	} else if in.RHR == nil {
		out.Missing = append(out.Missing, "no_resting_hr")
	}
	if min(hrv.n, rhr.n) < BaselineMinValues {
		out.Missing = append(out.Missing, "insufficient_baseline")
	}
	if len(out.Missing) > 0 {
		out.Reason = ptr(out.Missing[0])
		if in.Today {
			for _, reason := range out.Missing {
				switch reason {
				case "no_sleep", "sleep_processing", "no_hrv", "no_resting_hr":
					out.Status = "pending"
				}
			}
		}
		return out
	}
	hz, rz := z(math.Log(*in.HRV), hrv.mean, hrv.sd), z(*in.RHR, rhr.mean, rhr.sd)
	hs, rs := 100*cdf(hz), 100*cdf(-rz)
	w := RecoveryWeights{HRV: WeightHRV, RestingHR: WeightRestingHR, Sleep: WeightSleep}
	base := w.HRV*hs + w.RestingHR*rs + w.Sleep*(*in.Sleep)
	c := Components{HRVZ: round(hz, 2), HRVScore: round(hs, 1), RHRZ: round(rz, 2), RHRScore: round(rs, 1), Sleep: *in.Sleep, Base: round(base, 1), Weights: w, OptionalMissing: []string{}}
	rp, tp := 0.0, 0.0
	if in.RR != nil && rr.n >= BaselineMinValues {
		v := z(*in.RR, rr.mean, rr.sd)
		c.RRZ = ptr(round(v, 2))
		rp = clamp(PenaltySlope*(v-1), 0, PenaltyMax)
	} else {
		c.OptionalMissing = append(c.OptionalMissing, "respiratory_rate")
	}
	t := in.Temperature
	if t != nil && t.Nightly != nil && t.Baseline != nil && t.SD != nil {
		v := z(*t.Nightly, *t.Baseline, math.Max(*t.SD, SDFloorSkinTemp))
		c.TempZ = ptr(round(v, 2))
		tp = clamp(PenaltySlope*(v-1), 0, PenaltyMax)
	} else {
		c.OptionalMissing = append(c.OptionalMissing, "skin_temperature")
	}
	c.RRPenalty, c.TempPenalty = round(rp, 1), round(tp, 1)
	value := math.Round(clamp(base-rp-tp, 0, 100))
	out.Value = &value
	out.Band = band(value, RecoveryHighMin, RecoveryMediumMin)
	out.Status = "ok"
	out.Confidence = ptr("high")
	if out.Calibrating {
		out.Status = "calibrating"
		out.Confidence = ptr("medium")
	}
	if len(c.OptionalMissing) > 0 {
		out.Confidence = ptr("medium")
		if out.Calibrating {
			out.Confidence = ptr("low")
		}
	}
	out.Components = &c
	return out
}
