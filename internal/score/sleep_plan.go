package score

import (
	"math"
	"time"
)

const (
	PlanNights    = 14
	PlanMinNights = 3
)

var PlanGoals = [...]int{100, 85, 70}

type SleepPlan struct {
	Status     string        `json:"status"`
	Reason     *string       `json:"reason"`
	Need       int           `json:"need_minutes"`
	Parts      SleepPlanNeed `json:"need_parts"`
	Wake       *time.Time    `json:"wake_target"`
	WakeSource string        `json:"wake_source"`
	Efficiency *float64      `json:"efficiency_pct_used"`
	Latency    *int          `json:"latency_minutes_used"` // always null: the efficiency already holds time to fall asleep
	Nights     int           `json:"nights_used"`
	Needed     int           `json:"nights_needed"`
	Window     int           `json:"window_nights"`
	Goals      []SleepGoal   `json:"goals"`
}

type SleepPlanNeed struct {
	Base        int      `json:"baseline_minutes"`
	StrainExtra int      `json:"strain_extra_minutes"`
	DebtExtra   int      `json:"debt_extra_minutes"`
	NapCredit   int      `json:"nap_credit_minutes"`
	CycleStrain *float64 `json:"cycle_strain"`
	Nights      int      `json:"debt_nights_used"`
}

type SleepGoal struct {
	Percent int       `json:"pct"`
	InBed   int       `json:"in_bed_minutes"`
	Bedtime time.Time `json:"bedtime"`
}

func (e *Engine) SleepPlan(date string) *SleepPlan {
	cycle := e.Cycle(date)
	if cycle.Status != "open" {
		return nil
	}
	in := SleepNeedInput{Base: e.Config.SleepBaseNeed, PreviousStrain: e.Strain(date).Value}
	for k := 0; k < DebtNights; k++ {
		in.Prior = append(in.Prior, sleepAsleep(e.sleep(e.add(date, -k))))
	}
	for day, rows := range e.points["sleep"] {
		for _, p := range rows {
			s := p.point.Sleep
			if s != nil && s != e.main[day] && !s.Interval.End.Before(cycle.Start) && s.Interval.End.Before(e.Now) {
				if v := sleepAsleep(s); v != nil {
					in.Naps = append(in.Naps, *v)
				}
			}
		}
	}
	need, _ := ComputeSleepNeed(in)
	plan := &SleepPlan{
		Needed: PlanMinNights, Window: PlanNights,
		Status: "unavailable", Reason: ptr("insufficient_nights"), Need: need.Total,
		Parts:      SleepPlanNeed{need.Base, need.StrainExtra, need.DebtExtra, need.NapCredit, in.PreviousStrain, need.Nights},
		WakeSource: "typical", Goals: []SleepGoal{},
	}
	if e.Config.WakeTarget != nil {
		plan.WakeSource = "config"
		wake, _ := time.Parse("15:04", *e.Config.WakeTarget)
		plan.Wake = ptr(e.planWake(date, wake.Hour()*60+wake.Minute()))
	}
	efficiencies, wakes := []float64{}, []float64{}
	for k := 0; k < PlanNights; k++ {
		s := e.sleep(e.add(date, -k))
		if efficiency := sleepWindow(s).Efficiency; efficiency != nil && *efficiency > 0 {
			efficiencies = append(efficiencies, float64(*efficiency))
			wakes = append(wakes, localMinutes(s.Interval.End, e.loc))
		}
	}
	plan.Nights = len(efficiencies)
	if plan.Nights < PlanMinNights {
		return plan
	}
	plan.Status, plan.Reason = "ok", nil
	plan.Efficiency = ptr(percentile(efficiencies, .5))
	if plan.Wake == nil {
		plan.Wake = ptr(e.planWake(date, int(math.Floor(percentile(wakes, .5)))))
	}
	plan.Goals = SleepPlanGoals(plan.Need, *plan.Efficiency, *plan.Wake)
	return plan
}

// SleepPlanGoals divides each goal's sleep by the whole-window efficiency
// (asleep over time in bed), which already holds the time to fall asleep and
// the usual time awake (scores.md §4.11).
func SleepPlanGoals(need int, efficiency float64, wake time.Time) []SleepGoal {
	goals := make([]SleepGoal, 0, len(PlanGoals))
	if efficiency <= 0 {
		return goals
	}
	for _, pct := range PlanGoals {
		inBed := int(math.Round(float64(need*pct) / efficiency))
		goals = append(goals, SleepGoal{pct, inBed, wake.Add(-time.Duration(inBed) * time.Minute)})
	}
	return goals
}

func (e *Engine) planWake(date string, minutes int) time.Time {
	d := e.Date(date).AddDate(0, 0, 1)
	at := time.Date(d.Year(), d.Month(), d.Day(), minutes/60, minutes%60, 0, 0, e.loc)
	if at.Hour() != minutes/60 || at.Minute() != minutes%60 {
		at = time.Date(d.Year(), d.Month(), d.Day(), 2, 0, 0, 0, e.loc)
	}
	return at.UTC()
}
