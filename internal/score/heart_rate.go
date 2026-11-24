package score

import (
	"math"
	"time"
)

type HeartRateMinute struct {
	Time    time.Time `json:"t"`
	Average float64   `json:"avg_bpm"`
	Maximum int       `json:"max_bpm"`
}

type HeartRate struct {
	CycleDate   string            `json:"cycle_date"`
	Start       time.Time         `json:"start"`
	End         time.Time         `json:"end"`
	RestingHR   *int              `json:"resting_hr_bpm"`
	MaxHR       *int              `json:"max_hr_bpm"`
	MaxHRSource *string           `json:"max_hr_source"`
	RatesReason *string           `json:"rates_reason"`
	Minutes     []HeartRateMinute `json:"minutes"`
}

func (e *Engine) HeartRate(start, end time.Time) HeartRate {
	start, end = start.UTC().Truncate(time.Minute), end.UTC().Truncate(time.Minute)
	date := e.workoutDate(start)
	rest, _, maximum, source := e.rates(date)
	out := HeartRate{CycleDate: date, Start: start, End: end, MaxHRSource: source, Minutes: []HeartRateMinute{}}
	if rest != nil {
		out.RestingHR = ptr(int(math.Round(*rest)))
	}
	if maximum != nil {
		out.MaxHR = ptr(int(math.Round(*maximum)))
	}
	if rest == nil {
		out.RatesReason = ptr("resting_hr_unknown")
	} else if maximum == nil || *maximum <= *rest {
		out.RatesReason = ptr("max_hr_unknown")
	}
	minutes, _ := e.window(start, end)
	for _, m := range minutes {
		out.Minutes = append(out.Minutes, HeartRateMinute{Time: time.Unix(m.Start, 0).UTC(), Average: round(m.Avg, 2), Maximum: int(math.Round(m.Max))})
	}
	return out
}

func (e *Engine) HeartRateDay(date string) HeartRate {
	cycle := e.Cycle(date)
	end := cycle.Start
	if cycle.Status != "not_started" {
		end = e.Now
		if cycle.End != nil {
			end = *cycle.End
		} else if e.device.Sync != nil && e.device.Sync.Before(end) {
			end = *e.device.Sync
		}
		if end.Before(cycle.Start) {
			end = cycle.Start
		}
	}
	out := e.HeartRate(cycle.Start, end)
	out.CycleDate = date
	return out
}
