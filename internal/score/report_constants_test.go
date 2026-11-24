package score

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"testing"
	"time"
)

func TestReportedConstantsReproduceTheEngine(t *testing.T) {
	load := func(name string, out any) {
		t.Helper()
		raw, err := os.ReadFile("../../fixtures/v2/scores/" + name + ".json")
		if err != nil {
			t.Fatal(err)
		}
		if err = json.Unmarshal(raw, out); err != nil {
			t.Fatal(err)
		}
	}
	c := ConstantsFor("banister_b192")
	classify := func(value float64, edges Band3Edges) *string {
		if value >= float64(edges.High) {
			return ptr("high")
		}
		if value >= float64(edges.Medium) {
			return ptr("medium")
		}
		return ptr("low")
	}
	reference := func(in MinuteInput, model StrainModel) MinuteScore {
		var out MinuteScore
		floors := []float64{model.Zones.Z1, model.Zones.Z2, model.Zones.Z3, model.Zones.Z4, model.Zones.Z5}
		zones := []*int{&out.Zones.Below, &out.Zones.Z1, &out.Zones.Z2, &out.Zones.Z3, &out.Zones.Z4, &out.Zones.Z5}
		for _, bpm := range in.Averages {
			h := (bpm - in.Rest) / (in.Max - in.Rest)
			zone := 0
			for _, edge := range floors {
				if h >= edge {
					zone++
				}
			}
			*zones[zone]++
			if h >= floors[0] {
				h = math.Min(h, 1)
				out.Trimp += h * model.Trimp.A * math.Exp(model.Trimp.B*h)
			}
		}
		if len(in.Averages) > 0 {
			out.Strain = ptr(math.Round(math.Min(21, 21*math.Log1p(out.Trimp/model.Scale.K)/math.Log1p(model.Scale.TrimpCap/model.Scale.K))*10) / 10)
			name := "light"
			switch {
			case *out.Strain >= model.Bands.AllOut:
				name = "all_out"
			case *out.Strain >= model.Bands.Strenuous:
				name = "strenuous"
			case *out.Strain >= model.Bands.Moderate:
				name = "moderate"
			}
			out.Band = &name
		}
		out.Trimp = math.Round(out.Trimp*10) / 10
		return out
	}
	var strain struct {
		Cases []struct {
			Name     string
			Input    MinuteInput
			Expected MinuteScore
		}
	}
	load("strain", &strain)
	for _, tc := range strain.Cases {
		t.Run(tc.Name, func(t *testing.T) {
			got := reference(tc.Input, c.Strain)
			if got.Trimp != tc.Expected.Trimp || !reflect.DeepEqual(got.Strain, tc.Expected.Strain) || !reflect.DeepEqual(got.Band, tc.Expected.Band) || got.Zones != tc.Expected.Zones {
				t.Fatalf("reported model gives %+v, expected %+v", got, tc.Expected)
			}
			if tc.Name == "boxing_hour" {
				other := ConstantsFor("banister_b167")
				if other.Strain.Trimp != (TrimpCoefficients{A: 0.86, B: 1.67}) {
					t.Fatal(other.Strain.Trimp)
				}
				want, actual := reference(tc.Input, other.Strain), ComputeMinutes(tc.Input, "banister_b167")
				if want.Trimp != actual.Trimp || !reflect.DeepEqual(want.Strain, actual.Strain) || want.Zones != actual.Zones {
					t.Fatalf("alternate model: %+v != %+v", actual, want)
				}
			}
		})
	}
	var recovery struct{ Cases []struct{ Expected Recovery } }
	load("recovery", &recovery)
	for _, tc := range recovery.Cases {
		r := tc.Expected
		if r.Value != nil && !reflect.DeepEqual(r.Band, classify(*r.Value, c.Recovery.Bands)) {
			t.Fatal("recovery band differs")
		}
		if r.Components != nil && (r.Components.RRPenalty > c.Recovery.PenaltyMax || r.Components.TempPenalty > c.Recovery.PenaltyMax) {
			t.Fatal("penalty exceeds reported cap")
		}
	}
	var sleep struct {
		Need []struct {
			Expected struct {
				Value *float64 `json:"performance"`
				Band  *string
			}
		} `json:"sleep_need"`
		Consistency []struct{ Expected Rating }
	}
	load("sleep", &sleep)
	for _, tc := range sleep.Need {
		if tc.Expected.Value != nil && !reflect.DeepEqual(tc.Expected.Band, classify(*tc.Expected.Value, c.Sleep.Performance)) {
			t.Fatal("performance band differs")
		}
	}
	for _, tc := range sleep.Consistency {
		if tc.Expected.Value != nil && !reflect.DeepEqual(tc.Expected.Band, classify(*tc.Expected.Value, c.Sleep.Consistency)) {
			t.Fatal("consistency band differs")
		}
	}
	for _, ratio := range []float64{0.49, 0.50, 0.79, 0.80} {
		want := "low"
		if ratio >= c.Strain.Coverage.High {
			want = "high"
		} else if ratio >= c.Strain.Coverage.Medium {
			want = "medium"
		}
		if *confidence(ratio) != want {
			t.Fatalf("confidence at %v", ratio)
		}
	}
	for _, fewer := range []string{"none", "vital", "night"} {
		count, nights := c.Vitals.AttentionMinVitals, c.Vitals.AttentionNights
		if fewer == "vital" {
			count--
		}
		if fewer == "night" {
			nights--
		}
		keys := []string{"hrv_rmssd", "resting_hr", "respiratory_rate", "spo2", "skin_temp_deviation"}[:count]
		v := Vitals{WithRange: count, Outside: keys, Adverse: keys}
		before := make([]Vitals, max(0, nights-1))
		for i := range before {
			before[i] = v
		}
		want := "outside"
		if fewer == "none" {
			want = "attention"
		}
		if got := withAttention(v, before); got.State != want {
			t.Fatalf("reported attention boundary %s: %s", fewer, got.State)
		}
	}

	for _, fewer := range []string{"none", "night", "baseline"} {
		nights, values := c.HRVTrend.MinNights, c.HRVTrend.MinBaseline
		if fewer == "night" {
			nights--
		}
		if fewer == "baseline" {
			values--
		}
		baseline := make([]float64, values)
		for i := range baseline {
			baseline[i] = 50 + float64(i%5)
		}
		week := make([]float64, nights)
		for i := range week {
			week[i] = 30
		}
		got := hrvTrend(week, baseline)
		ranged := got.Position != nil && *got.Position == "below"
		if ranged != (fewer == "none") {
			t.Fatalf("reported HRV trend boundary %s: %+v", fewer, got)
		}
		if fewer == "night" {
			var mean, squares float64
			for _, v := range baseline {
				mean += math.Log(v) / float64(len(baseline))
			}
			for _, v := range baseline {
				squares += (math.Log(v) - mean) * (math.Log(v) - mean)
			}
			low := math.Round(math.Exp(mean-c.HRVTrend.BandSD*math.Max(math.Sqrt(squares/float64(len(baseline)-1)), SDFloorLnRMSSD))*10) / 10
			if got.Low == nil || *got.Low != low {
				t.Fatalf("reported band_sd does not give the engine's range: %v, want %v", got.Low, low)
			}
		}
	}

	start := time.Date(2026, 3, 10, 18, 0, 0, 0, time.UTC)
	a := Workout{Start: start, End: start.Add(time.Hour)}
	for _, seconds := range []int{0, -1} {
		overlap := time.Duration(c.Workouts.Recorded*3600)*time.Second + time.Duration(seconds)*time.Second
		b := Workout{Start: a.End.Add(-overlap), End: a.End.Add(time.Hour - overlap)}
		if goopHidesRecorded(a, b) != (seconds == 0) {
			t.Fatalf("recorded overlap boundary %v", seconds)
		}
	}
}

func TestEfficiencyBand(t *testing.T) {
	for _, tc := range []struct {
		pct  *int
		band *string
	}{{nil, nil}, {ptr(84), ptr("low")}, {ptr(85), ptr("medium")}, {ptr(89), ptr("medium")}, {ptr(90), ptr("high")}} {
		if !reflect.DeepEqual(EfficiencyBand(tc.pct), tc.band) {
			t.Fatalf("efficiency %v: %v", tc.pct, tc.band)
		}
	}
}
