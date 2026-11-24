package v2report

import (
	"math"
	"sort"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/score"
)

type WeekWindow struct {
	From string `json:"from"`
	To   string `json:"to"`
}
type WeekUsual struct {
	From string `json:"from"`
	To   string `json:"to"`
	Min  int    `json:"min_days"`
}
type WeekMetric struct {
	Value    *float64 `json:"value"`
	Days     int      `json:"available_days"`
	LastWeek *float64 `json:"last_week"`
	Change   *float64 `json:"change"`
	Usual    *float64 `json:"usual"`
}
type WeekMetrics struct {
	Recovery    WeekMetric `json:"recovery"`
	Strain      WeekMetric `json:"strain"`
	Performance WeekMetric `json:"sleep_performance"`
	Asleep      WeekMetric `json:"asleep_minutes"`
	Consistency WeekMetric `json:"sleep_consistency"`
	HRV         WeekMetric `json:"hrv_rmssd_ms"`
	RHR         WeekMetric `json:"resting_hr_bpm"`
	Zones13     WeekMetric `json:"zones_1_3_minutes"`
	Zones45     WeekMetric `json:"zones_4_5_minutes"`
	Strength    WeekMetric `json:"strength_minutes"`
	Steps       WeekMetric `json:"steps"`
}
type WeekSport struct {
	Type     string `json:"exercise_type"`
	Name     string `json:"display_name"`
	Category string `json:"category"`
	Count    int    `json:"count"`
}
type WeekWorkouts struct {
	Total    int         `json:"total"`
	LastWeek int         `json:"last_week_total"`
	Detected int         `json:"detected_efforts"`
	BySport  []WeekSport `json:"by_sport"`
}
type WeekSleepTarget struct {
	Status     string `json:"status"`
	MinMinutes int    `json:"min_minutes"`
	Nights     int    `json:"nights"`
	Met        int    `json:"met_nights"`
	Missing    int    `json:"missing_nights"`
}
type WeekActivityTarget struct {
	Status  string `json:"status"`
	Minutes int    `json:"minutes"`
	Weight  int    `json:"vigorous_weight"`
	Credit  *int   `json:"credit_minutes"`
	Missing int    `json:"missing_days"`
}
type WeekStrengthTarget struct {
	Status  string `json:"status"`
	Days    int    `json:"days"`
	Met     int    `json:"met_days"`
	Missing int    `json:"missing_days"`
}
type WeekTargets struct {
	Sleep    WeekSleepTarget    `json:"sleep"`
	Activity WeekActivityTarget `json:"activity"`
	Strength WeekStrengthTarget `json:"strength"`
}
type Week struct {
	Envelope
	Freshness score.Freshness `json:"freshness"`
	Date      string          `json:"date"`
	From      string          `json:"from"`
	To        string          `json:"to"`
	WeekEnd   string          `json:"week_end"`
	Days      int             `json:"days_counted"`
	Complete  bool            `json:"complete"`
	LastWeek  WeekWindow      `json:"last_week"`
	Usual     WeekUsual       `json:"usual"`
	Metrics   WeekMetrics     `json:"metrics"`
	Workouts  WeekWorkouts    `json:"workouts"`
	Targets   WeekTargets     `json:"targets"`
}

// Week sums up the Monday-to-Sunday London week that contains date (week-review-spec.md §3).
func (b *Builder) Week(date string) Week {
	e := b.engine
	day := e.Date(date)
	monday := day.AddDate(0, 0, -((int(day.Weekday()) + 6) % 7))
	sunday := monday.AddDate(0, 0, 6)
	to := min(sunday.Format(dateLayout), e.DefaultDate())
	out := Week{
		Envelope: b.envelope("week"), Freshness: e.Freshness(), Date: date,
		From: monday.Format(dateLayout), To: to, WeekEnd: sunday.Format(dateLayout),
		Complete: sunday.Format(dateLayout) < e.DefaultDate(),
		Usual:    WeekUsual{From: monday.AddDate(0, 0, -28).Format(dateLayout), To: monday.AddDate(0, 0, -1).Format(dateLayout), Min: score.ComparisonMinDays},
	}
	current := dates(monday, to)
	out.Days = len(current)
	last := dates(monday.AddDate(0, 0, -7), e.Date(to).AddDate(0, 0, -7).Format(dateLayout))
	out.LastWeek = WeekWindow{From: last[0], To: last[len(last)-1]}

	rows, sports := []DayRow{}, map[string]*WeekSport{}
	for _, date := range current {
		d := b.dayValues(date)
		rows = append(rows, b.rowOf(d))
		for _, w := range d.Workouts {
			if w.Kind != "recorded" && w.Kind != "goop" {
				out.Workouts.Detected++
				continue
			}
			out.Workouts.Total++
			if w.Type == nil || w.Name == nil {
				continue
			}
			key := *w.Type
			if sports[key] == nil {
				sports[key] = &WeekSport{Type: key, Name: *w.Name, Category: w.Category}
			}
			sports[key].Count++
		}
	}
	out.Workouts.BySport = []WeekSport{}
	for _, sport := range sports {
		out.Workouts.BySport = append(out.Workouts.BySport, *sport)
	}
	sort.Slice(out.Workouts.BySport, func(i, j int) bool {
		a, c := out.Workouts.BySport[i], out.Workouts.BySport[j]
		return a.Count > c.Count || a.Count == c.Count && a.Name < c.Name
	})
	lastRows := []DayRow{}
	for _, date := range last {
		lastRows = append(lastRows, b.row(date))
		out.Workouts.LastWeek += lastRows[len(lastRows)-1].Workouts
	}
	usualRows := []DayRow{}
	for _, date := range dates(monday.AddDate(0, 0, -28), out.Usual.To) {
		usualRows = append(usualRows, b.row(date))
	}

	m := &out.Metrics
	for _, metric := range []struct {
		into  *WeekMetric
		get   func(DayRow) *float64
		total bool
	}{
		{&m.Recovery, func(r DayRow) *float64 { return r.Recovery }, false},
		{&m.Strain, func(r DayRow) *float64 { return r.Strain }, false},
		{&m.Performance, func(r DayRow) *float64 { return r.Performance }, false},
		{&m.Asleep, func(r DayRow) *float64 { return floatValue(r.Asleep) }, false},
		{&m.Consistency, func(r DayRow) *float64 { return floatValue(r.Consistency) }, false},
		{&m.HRV, func(r DayRow) *float64 { return r.HRV }, false},
		{&m.RHR, func(r DayRow) *float64 { return r.RHR }, false},
		{&m.Zones13, func(r DayRow) *float64 { return floatValue(r.Zones13) }, true},
		{&m.Zones45, func(r DayRow) *float64 { return floatValue(r.Zones45) }, true},
		{&m.Strength, func(r DayRow) *float64 { return floatValue(r.Strength) }, true},
		{&m.Steps, func(r DayRow) *float64 { return r.Steps }, true},
	} {
		*metric.into = weekMetric(rows, lastRows, usualRows, metric.get, metric.total, out.Days)
	}

	goals := e.Config.Week
	sleep := WeekSleepTarget{MinMinutes: goals.SleepMinutes, Nights: goals.SleepNights}
	activity := WeekActivityTarget{Minutes: goals.ActivityMinutes, Weight: score.WeekVigorousWeight}
	strength := WeekStrengthTarget{Days: goals.StrengthDays}
	for _, r := range rows {
		switch {
		case r.Asleep == nil:
			sleep.Missing++
		case *r.Asleep >= goals.SleepMinutes:
			sleep.Met++
		}
		if r.Zones13 == nil || r.Zones45 == nil {
			activity.Missing++
		} else {
			activity.Credit = ptr(valueOr(activity.Credit) + *r.Zones13 + score.WeekVigorousWeight**r.Zones45)
		}
		switch {
		case r.Strength == nil:
			strength.Missing++
		case *r.Strength > 0:
			strength.Met++
		}
	}
	sleep.Status = score.WeekCountStatus(sleep.Met, sleep.Missing, sleep.Nights, out.Complete)
	activity.Status = score.WeekMinutesStatus(activity.Credit, activity.Missing, activity.Minutes, out.Complete)
	strength.Status = score.WeekCountStatus(strength.Met, strength.Missing, strength.Days, out.Complete)
	out.Targets = WeekTargets{Sleep: sleep, Activity: activity, Strength: strength}
	return out
}

const dateLayout = "2006-01-02"

func dates(from time.Time, to string) []string {
	out := []string{}
	for day := from; day.Format(dateLayout) <= to; day = day.AddDate(0, 0, 1) {
		out = append(out, day.Format(dateLayout))
	}
	return out
}

func valueOr(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}

// weekMetric is one row of week-review-spec.md §3.2: a mean (1 dp) or a total (integer) of the week's row values.
func weekMetric(rows, last, usual []DayRow, get func(DayRow) *float64, total bool, days int) WeekMetric {
	sums := func(rows []DayRow) (sum float64, count int) {
		for _, r := range rows {
			if v := get(r); v != nil {
				sum += *v
				count++
			}
		}
		return sum, count
	}
	round := func(v float64) *float64 {
		if total {
			return ptr(math.Round(v))
		}
		return ptr(math.Round(v*10) / 10)
	}
	aggregate := func(rows []DayRow) (*float64, int) {
		sum, count := sums(rows)
		switch {
		case count == 0:
			return nil, 0
		case total:
			return round(sum), count
		}
		return round(sum / float64(count)), count
	}
	out := WeekMetric{}
	out.Value, out.Days = aggregate(rows)
	out.LastWeek, _ = aggregate(last)
	if out.Value != nil && out.LastWeek != nil {
		out.Change = ptr(math.Round((*out.Value-*out.LastWeek)*10) / 10)
	}
	if sum, count := sums(usual); count >= score.ComparisonMinDays {
		mean := sum / float64(count)
		if total {
			mean *= float64(days)
		}
		out.Usual = round(mean)
	}
	return out
}

// BriefWeek is the week in `brief --part week` (week-review-spec.md §4.3). Status-only mode keeps
// the dates, target statuses and workout counts; values mode adds the metrics and each target's counts.
type BriefWeek struct {
	From     string            `json:"from"`
	To       string            `json:"to"`
	Days     int               `json:"days_counted"`
	Complete bool              `json:"complete"`
	Targets  BriefWeekTargets  `json:"targets"`
	Workouts BriefWeekWorkouts `json:"workouts"`
	Metrics  *WeekMetrics      `json:"metrics,omitempty"`
}

// Each target's own status hides the embedded one, so status-only mode prints only `status`.
type BriefWeekTargets struct {
	Sleep struct {
		Status string `json:"status"`
		*WeekSleepTarget
	} `json:"sleep"`
	Activity struct {
		Status string `json:"status"`
		*WeekActivityTarget
	} `json:"activity"`
	Strength struct {
		Status string `json:"status"`
		*WeekStrengthTarget
	} `json:"strength"`
}
type BriefWeekSport struct {
	Type  string `json:"exercise_type"`
	Count int    `json:"count"`
}
type BriefWeekWorkouts struct {
	Total    int              `json:"total"`
	Detected int              `json:"detected_efforts"`
	BySport  []BriefWeekSport `json:"by_sport"`
}

func briefWeek(w Week, values bool) *BriefWeek {
	out := &BriefWeek{From: w.From, To: w.To, Days: w.Days, Complete: w.Complete, Workouts: BriefWeekWorkouts{Total: w.Workouts.Total, Detected: w.Workouts.Detected, BySport: []BriefWeekSport{}}}
	for _, sport := range w.Workouts.BySport {
		out.Workouts.BySport = append(out.Workouts.BySport, BriefWeekSport{sport.Type, sport.Count})
	}
	t := &out.Targets
	t.Sleep.Status, t.Activity.Status, t.Strength.Status = w.Targets.Sleep.Status, w.Targets.Activity.Status, w.Targets.Strength.Status
	if values {
		out.Metrics = &w.Metrics
		t.Sleep.WeekSleepTarget, t.Activity.WeekActivityTarget, t.Strength.WeekStrengthTarget = &w.Targets.Sleep, &w.Targets.Activity, &w.Targets.Strength
	}
	return out
}
