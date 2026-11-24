package score

import (
	"encoding/json"
	"math"
	"sort"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/store2"
)

type MinuteInput struct {
	Rest     float64   `json:"resting_hr"`
	Max      float64   `json:"max_hr"`
	Averages []float64 `json:"minute_avg_bpm"`
	Expected int       `json:"expected_minutes"`
}
type MinuteScore struct {
	Trimp    float64  `json:"trimp"`
	Strain   *float64 `json:"strain"`
	Band     *string  `json:"band"`
	Coverage *float64 `json:"hr_coverage"`
	Zones    Zones    `json:"zones_minutes"`
}

func TrimpToStrain(trimp float64) float64 {
	return round(math.Min(21, 21*math.Log1p(trimp/StrainK)/math.Log1p(StrainTrimpCap/StrainK)), 1)
}
func ComputeMinutes(in MinuteInput, profile string) MinuteScore {
	out := MinuteScore{}
	a, b := trimpCoefficients(profile)
	for _, avg := range in.Averages {
		hrr := (avg - in.Rest) / (in.Max - in.Rest)
		switch {
		case hrr < HRRFloor:
			out.Zones.Below++
		case hrr < Zone2HRR:
			out.Zones.Z1++
		case hrr < Zone3HRR:
			out.Zones.Z2++
		case hrr < Zone4HRR:
			out.Zones.Z3++
		case hrr < Zone5HRR:
			out.Zones.Z4++
		default:
			out.Zones.Z5++
		}
		if hrr >= HRRFloor {
			h := math.Min(hrr, 1)
			out.Trimp += h * a * math.Exp(b*h)
		}
	}
	if len(in.Averages) > 0 {
		out.Strain = ptr(TrimpToStrain(out.Trimp))
		out.Band = strainBand(*out.Strain)
	}
	out.Trimp = round(out.Trimp, 1)
	if in.Expected > 0 {
		out.Coverage = ptr(round(float64(len(in.Averages))/float64(in.Expected), 2))
	}
	return out
}

func (e *Engine) rates(date string) (*float64, *string, *float64, *string) {
	rest, _ := e.metric(date, "daily-resting-heart-rate")
	source := ptr("daily_resting_heart_rate")
	if rest == nil {
		sample := stats(e.baseline(date, "daily-resting-heart-rate"), SDFloorRestingHR, false)
		source = nil
		if sample.n > 0 {
			rest, source = ptr(math.Round(sample.mean)), ptr("baseline_mean")
		}
	}
	if e.Config.MaxHR != nil {
		return rest, source, ptr(float64(*e.Config.MaxHR)), ptr("override")
	}
	var maximum *float64
	var maxSource *string
	var profile struct {
		Age *int `json:"age"`
	}
	if e.State.User["profile"].Status == "ok" && json.Unmarshal(e.State.User["profile"].Body, &profile) == nil && profile.Age != nil {
		maximum, maxSource = ptr(math.Round(208-.7*float64(*profile.Age))), ptr("age_predicted_profile")
	}
	if maximum == nil {
		for k := 0; k <= 30 && maximum == nil; k++ {
			for _, p := range e.points["daily-heart-rate-zones"][e.add(date, -k)] {
				if p.point.Zones == nil {
					continue
				}
				for _, zone := range p.point.Zones.Zones {
					if zone.Type == "PEAK" && zone.Max != nil && *zone.Max >= 150 && *zone.Max <= 220 {
						maximum, maxSource = ptr(float64(*zone.Max)), ptr("fitbit_zone_peak")
						break
					}
				}
			}
		}
	}
	if maximum != nil {
		from := e.add(date, -365)
		for _, w := range e.workoutPeaks() {
			if w.date >= from && w.date <= date && w.peak >= 120 && w.peak <= 220 && w.peak > *maximum {
				maximum, maxSource = ptr(w.peak), ptr("observed")
			}
		}
	}
	return rest, source, maximum, maxSource
}

type workoutPeak struct {
	date string
	peak float64
}

// workoutPeaks returns, once per engine, the second-highest minute maximum of each
// recorded workout with at least two covered minutes (scores.md §3.3).
func (e *Engine) workoutPeaks() []workoutPeak {
	if e.peaks != nil {
		return e.peaks
	}
	e.peaks = []workoutPeak{}
	for day, rows := range e.points["exercise"] {
		for _, p := range rows {
			if p.point.Exercise == nil {
				continue
			}
			x := p.point.Exercise
			minutes, _ := e.window(x.Interval.Start.Truncate(time.Minute), x.Interval.End)
			if len(minutes) < 2 {
				continue
			}
			first, second := math.Inf(-1), math.Inf(-1)
			for _, m := range minutes {
				if m.Max > first {
					first, second = m.Max, first
				} else if m.Max > second {
					second = m.Max
				}
			}
			e.peaks = append(e.peaks, workoutPeak{day, second})
		}
	}
	return e.peaks
}
func (e *Engine) window(start, end time.Time) ([]store2.Minute, int) {
	first := start.Truncate(time.Minute)
	if first.Before(start) {
		first = first.Add(time.Minute)
	}
	expected := 0
	if end.After(first) {
		expected = int(math.Ceil(end.Sub(first).Minutes()))
	}
	i := sort.Search(len(e.minutes), func(i int) bool { return e.minutes[i].Start >= first.Unix() })
	out := []store2.Minute{}
	for ; i < len(e.minutes); i++ {
		m := e.minutes[i]
		if !time.Unix(m.Start, 0).Before(end) {
			break
		}
		out = append(out, m)
	}
	return out, expected
}
func (e *Engine) Strain(date string) Strain {
	c := e.Cycle(date)
	rest, rs, maximum, ms := e.rates(date)
	out := Strain{Rating: Rating{Status: "unavailable"}, Rest: rest, RestSource: rs, Max: maximum, MaxSource: ms}
	if c.Status == "not_started" {
		out.Status, out.Reason = "pending", ptr("cycle_not_started")
		return out
	}
	if rest == nil {
		out.Reason = ptr("resting_hr_unknown")
		return out
	}
	if maximum == nil || *maximum <= *rest {
		out.Reason = ptr("max_hr_unknown")
		return out
	}
	end := e.Now
	if c.End != nil {
		end = *c.End
	} else if e.device.Sync != nil && e.device.Sync.Before(end) {
		end = *e.device.Sync
	}
	minutes, expected := e.window(c.Start, end)
	out.Until = &end
	out.Covered = ptr(len(minutes))
	out.Expected = &expected
	if expected > 0 {
		out.Coverage = ptr(round(float64(len(minutes))/float64(expected), 2))
	}
	if len(minutes) == 0 {
		out.Reason = ptr("no_heart_rate")
		return out
	}
	out.Status = "ok"
	if c.Status == "open" {
		out.Status = "in_progress"
	}
	score, avg, peak := e.scoreWindow(minutes, expected, *rest, *maximum)
	out.Value, out.Band, out.Trimp, out.Zones = score.Strain, score.Band, ptr(score.Trimp), &score.Zones
	out.Avg, out.Peak = avg, peak
	if score.Coverage != nil {
		out.Confidence = confidence(float64(len(minutes)) / float64(expected))
	}
	return out
}
func (e *Engine) scoreWindow(minutes []store2.Minute, expected int, rest, maximum float64) (MinuteScore, *float64, *float64) {
	in := MinuteInput{Rest: rest, Max: maximum, Expected: expected}
	for _, m := range minutes {
		in.Averages = append(in.Averages, m.Avg)
	}
	score := ComputeMinutes(in, e.Config.TrimpProfile)
	avg, peak := minuteStats(minutes)
	return score, avg, peak
}

func minuteStats(minutes []store2.Minute) (*float64, *float64) {
	if len(minutes) == 0 {
		return nil, nil
	}
	sum, peak := 0.0, 0.0
	for _, m := range minutes {
		sum += m.Avg
		peak = math.Max(peak, m.Max)
	}
	return ptr(math.Round(sum / float64(len(minutes)))), ptr(math.Round(peak))
}
