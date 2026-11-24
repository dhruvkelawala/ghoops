package score

import (
	"math"
	"sort"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/health"
)

type SleepNeedInput struct {
	Base           int      `json:"baseline_need_minutes"`
	PreviousStrain *float64 `json:"previous_cycle_strain"`
	Prior          []*int   `json:"prior_nights_asleep_minutes"`
	Naps           []int    `json:"nap_asleep_minutes"`
	Asleep         *int     `json:"main_asleep_minutes"`
}

func ComputeSleepNeed(in SleepNeedInput) (SleepNeed, Rating) {
	n := SleepNeed{Base: in.Base, PreviousStrain: in.PreviousStrain}
	if in.PreviousStrain != nil {
		n.StrainExtra = int(math.Min(StrainExtraMax, math.Round(StrainExtraPerPoint*math.Max(0, *in.PreviousStrain-StrainExtraFrom))))
	}
	debt := 0
	for i, v := range in.Prior {
		if i >= DebtNights {
			break
		}
		if v != nil {
			debt += max(0, in.Base-*v)
			n.Nights++
		}
	}
	n.DebtExtra = int(math.Min(DebtMax, math.Round(DebtFactor*float64(debt))))
	for _, v := range in.Naps {
		n.NapCredit += v
	}
	n.NapCredit = min(NapCreditMax, n.NapCredit)
	n.Total = int(clamp(float64(n.Base+n.StrainExtra+n.DebtExtra-n.NapCredit), NeedMin, NeedMax))
	rating := Rating{Status: "unavailable", Reason: ptr("no_sleep")}
	if in.Asleep != nil {
		value := math.Min(100, math.Round(100*float64(*in.Asleep)/float64(n.Total)))
		rating = Rating{Value: &value, Band: band(value, SleepPerformanceHighMin, SleepPerformanceMediumMin), Status: "ok"}
	}
	return n, rating
}

type Night struct {
	Bed  float64
	Wake float64
}

func ComputeConsistency(nights []Night) Consistency {
	c := Consistency{Rating: Rating{Status: "unavailable", Reason: ptr("insufficient_nights")}, Nights: len(nights)}
	if len(nights) < ConsistencyMinNights {
		return c
	}
	beds, wakes := []float64{}, []float64{}
	for _, n := range nights {
		beds = append(beds, n.Bed)
		wakes = append(wakes, n.Wake)
	}
	bed, wake := clockSD(beds), clockSD(wakes)
	value := math.Round(clamp(100*(1-(bed+wake)/2/ConsistencyZeroSD), 0, 100))
	c.Rating = Rating{Value: &value, Band: band(value, ConsistencyHighMin, ConsistencyMediumMin), Status: "ok"}
	c.BedSD, c.WakeSD = ptr(round(bed, 1)), ptr(round(wake, 1))
	return c
}

// clockSD is the sample standard deviation of times of day (minutes after
// midnight) around their circular centre: the smallest over the ways to cut
// the 24-hour clock between two neighbouring times (scores.md §4.6).
func clockSD(times []float64) float64 {
	sorted := make([]float64, len(times))
	for i, t := range times {
		sorted[i] = math.Mod(math.Mod(t, 1440)+1440, 1440)
	}
	sort.Float64s(sorted)
	best := math.Inf(1)
	for cut := range sorted {
		unwrapped := append(append([]float64{}, sorted[cut:]...), sorted[:cut]...)
		for i := len(sorted) - cut; i < len(unwrapped); i++ {
			unwrapped[i] += 1440
		}
		best = math.Min(best, stats(unwrapped, 0, false).sd)
	}
	return best
}

// Sleep is the sleep summary of the night ending on date, with the composite in composite mode.
func (e *Engine) Sleep(date string) SleepSummary {
	out := e.sleepSummary(date)
	if e.Config.CompositeSleep() {
		composite := ComputeSleepComposite(out.Performance, out.Consistency.Value, out.Efficiency)
		out.PerformanceComposite = &composite
	}
	return out
}

func (e *Engine) sleepSummary(date string) SleepSummary {
	main := e.sleep(date)
	values := sleepWindow(main)
	out := SleepSummary{Naps: []Nap{}, Asleep: values.Asleep, StageTypical: e.stageTypical(date)}
	previous := e.Strain(e.add(date, -1)).Value
	in := SleepNeedInput{Base: e.Config.SleepBaseNeed, PreviousStrain: previous, Asleep: out.Asleep}
	for k := 1; k <= DebtNights; k++ {
		in.Prior = append(in.Prior, sleepAsleep(e.sleep(e.add(date, -k))))
	}
	if main != nil {
		start, _ := e.cycleStart(e.add(date, -1))
		for day, rows := range e.points["sleep"] {
			for _, p := range rows {
				s := p.point.Sleep
				if s == nil || s == e.main[day] || s.Interval.End.Before(start) || !s.Interval.End.Before(main.Interval.Start) {
					continue
				}
				if v := sleepAsleep(s); v != nil {
					in.Naps = append(in.Naps, *v)
				}
			}
		}
	}
	out.Need, out.Performance = ComputeSleepNeed(in)
	if out.Performance.Value == nil && date == e.Today() {
		out.Performance.Status = "pending"
	}
	nights := []Night{}
	for k := ConsistencyNights - 1; k >= 0; k-- {
		if s := e.sleep(e.add(date, -k)); s != nil {
			nights = append(nights, Night{localMinutes(s.Interval.Start, e.loc), localMinutes(s.Interval.End, e.loc)})
		}
	}
	out.Consistency = ComputeConsistency(nights)
	for _, p := range e.points["sleep"][date] {
		s := p.point.Sleep
		if s != nil && s != e.main[date] {
			out.Naps = append(out.Naps, Nap{s.Interval.Start, s.Interval.End, sleepAsleep(s)})
		}
	}
	sort.Slice(out.Naps, func(i, j int) bool { return out.Naps[i].Start.Before(out.Naps[j].Start) })
	if main == nil {
		return out
	}
	out.Bedtime, out.Wake = ptr(main.Interval.Start), ptr(main.Interval.End)
	out.InBed = &values.InBed
	out.Efficiency = values.Efficiency
	out.EfficiencyBand = EfficiencyBand(out.Efficiency)
	out.Latency, out.Stages = values.Latency, values.Stages
	d := Disturbances{Awake: values.Awake}
	for _, short := range main.ShortAwakenings {
		if short.Start.Before(main.Interval.End) && short.End.After(main.Interval.Start) {
			d.Short++
		}
	}
	d.Total = d.Awake + d.Short
	out.Disturbances = &d
	return out
}

func (e *Engine) SleepDetail(date string) SleepDetail {
	out := SleepDetail{SleepSummary: e.Sleep(date), HR: []HRPoint{}, HRV: []HRVPoint{}}
	s := e.sleep(date)
	if s == nil {
		return out
	}
	google := e.main[date]
	out.Session = &SleepSession{Start: s.Interval.Start, End: s.Interval.End, Type: text(s.Type), Main: s.Metadata.Main, Processed: s.Metadata.Processed, StagesStatus: text(s.Metadata.StagesStatus), Awake: integer(s.Summary.MinutesAwake), AfterWake: integer(s.Summary.MinutesAfterWakeUp), InPeriod: integer(s.Summary.MinutesInSleepPeriod), Google: sleepInput(google).Google, EditRange: e.SleepEditRange(date)}
	if edit := e.sleepEdit(date); edit != nil {
		out.Session.Edit = &SleepEditWindow{edit.Start, edit.End, edit.UpdatedAt}
	}
	values := sleepWindow(s)
	h := Hypnogram{Start: s.Interval.Start, End: s.Interval.End, Segments: values.Segments, Short: []Segment{}, Unstaged: values.Unstaged, Outside: []Segment{}}
	if out.Session.Edit != nil {
		h.Outside = sleepOutside(google, s.Interval.Start, s.Interval.End)
	}
	for _, stage := range s.ShortAwakenings {
		if stage.Start.Before(s.Interval.End) && stage.End.After(s.Interval.Start) {
			h.Short = append(h.Short, Segment{later(stage.Start, s.Interval.Start), earlier(stage.End, s.Interval.End), strings.ToLower(stage.Type)})
		}
	}
	sort.Slice(h.Segments, func(i, j int) bool { return h.Segments[i].Start.Before(h.Segments[j].Start) })
	sort.Slice(h.Short, func(i, j int) bool { return h.Short[i].Start.Before(h.Short[j].Start) })
	out.Hypnogram = &h
	start := s.Interval.Start.Truncate(time.Minute)
	minutes, _ := e.window(start, s.Interval.End)
	for i := 0; i < len(minutes); {
		bucket := (minutes[i].Start - start.Unix()) / 300
		sum, count := 0.0, 0
		for i < len(minutes) && (minutes[i].Start-start.Unix())/300 == bucket {
			sum += minutes[i].Avg
			count++
			i++
		}
		out.HR = append(out.HR, HRPoint{start.Add(time.Duration(bucket) * 5 * time.Minute), int(math.Round(sum / float64(count)))})
	}
	for _, rows := range e.points["heart-rate-variability"] {
		for _, p := range rows {
			v := p.point.HRV
			if v != nil && v.RMSSD != nil && !v.Sample.Physical.Before(s.Interval.Start) && v.Sample.Physical.Before(s.Interval.End) {
				out.HRV = append(out.HRV, HRVPoint{v.Sample.Physical, round(float64(*v.RMSSD), 1)})
			}
		}
	}
	sort.Slice(out.HRV, func(i, j int) bool { return out.HRV[i].T.Before(out.HRV[j].T) })
	var selected *health.RespiratorySleepSummary
	distance := time.Duration(1<<63 - 1)
	for _, rows := range e.points["respiratory-rate-sleep-summary"] {
		for _, p := range rows {
			r := p.point.RespSummary
			if r == nil || r.Sample.Physical.Before(google.Interval.Start.Add(-time.Hour)) || r.Sample.Physical.After(google.Interval.End.Add(time.Hour)) {
				continue
			}
			d := r.Sample.Physical.Sub(google.Interval.End)
			if d < 0 {
				d = -d
			}
			if d < distance {
				selected, distance = r, d
			}
		}
	}
	if selected != nil {
		rate := func(s *health.RespiratoryStats) *float64 {
			if s == nil || s.BPM == nil || *s.BPM == 0 {
				return nil
			}
			return rounded(number(s.BPM), 1)
		}
		out.Respiratory = &RespiratoryRate{rate(selected.Full), rate(selected.Deep), rate(selected.Light), rate(selected.REM)}
	}
	return out
}

func (e *Engine) stageTypical(date string) StageTypical {
	out := StageTypical{Window: StageTypicalNights, Needed: StageTypicalMinNights, LowPct: int(math.Round(100 * StageTypicalLowQuantile)), HighPct: int(math.Round(100 * StageTypicalHighQuantile))}
	values := map[string][]float64{}
	for k := 1; k <= StageTypicalNights; k++ {
		night := e.sleep(e.add(date, -k))
		if night == nil || night.Type != "STAGES" {
			continue
		}
		out.Nights++
		stages := map[string]float64{}
		for key, stage := range sleepWindow(night).Stages {
			if key != "unstaged" && stage.Minutes != nil {
				stages[key] = float64(*stage.Minutes)
			}
		}
		deep, hasDeep := stages["deep"]
		rem, hasREM := stages["rem"]
		if hasDeep && hasREM {
			stages["restorative"] = deep + rem
		}
		for key, value := range stages {
			values[key] = append(values[key], value)
		}
	}
	makeRange := func(key string) StageRange {
		v := values[key]
		r := StageRange{Nights: len(v)}
		if len(v) >= StageTypicalMinNights {
			r.Low = ptr(int(math.Round(percentile(v, StageTypicalLowQuantile))))
			r.High = ptr(int(math.Round(percentile(v, StageTypicalHighQuantile))))
		}
		return r
	}
	out.Light, out.Deep, out.REM, out.Awake, out.Restorative = makeRange("light"), makeRange("deep"), makeRange("rem"), makeRange("awake"), makeRange("restorative")
	return out
}

func percentile(values []float64, q float64) float64 {
	sorted := append([]float64(nil), values...)
	sort.Float64s(sorted)
	pos := q * float64(len(sorted)-1)
	i := int(math.Floor(pos))
	if i+1 == len(sorted) {
		return sorted[i]
	}
	return sorted[i] + (pos-float64(i))*(sorted[i+1]-sorted[i])
}

func EfficiencyBand(pct *int) *string {
	if pct == nil {
		return nil
	}
	return band(float64(*pct), EfficiencyHighMin, EfficiencyMediumMin)
}
