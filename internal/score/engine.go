package score

import (
	"encoding/json"
	"errors"
	"math"
	"sort"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

type observation struct {
	point health.Point
	raw   json.RawMessage
}
type Engine struct {
	Activities []activities.Record
	SleepEdits []activities.SleepEdit
	Edits      []activities.Edit
	Ratings    []activities.Rating
	State      store2.State2
	Now        time.Time
	Config     config.Values
	loc        *time.Location
	points     map[string]map[string][]observation
	minutes    []store2.Minute
	peaks      []workoutPeak
	workouts   []recordedWorkout
	main       map[string]*health.Sleep
	device     Device
	freshness  Freshness
}

func New(state store2.State2, now time.Time, cfg config.Values) (*Engine, error) {
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	loc, err := time.LoadLocation("Europe/London")
	if err != nil {
		return nil, err
	}
	e := &Engine{State: state, Now: now.UTC(), Config: cfg, loc: loc, points: map[string]map[string][]observation{}, main: map[string]*health.Sleep{}, minutes: []store2.Minute{}}
	for _, r := range state.Records {
		if r.Type == "sleep" && r.Stream != "reconciled" {
			continue
		}
		p, err := health.DecodeV2(r)
		if err != nil {
			return nil, errors.New("invalid stored health record")
		}
		if e.points[r.Type] == nil {
			e.points[r.Type] = map[string][]observation{}
		}
		e.points[r.Type][r.Date] = append(e.points[r.Type][r.Date], observation{p, r.Raw})
	}
	for date, points := range e.points["sleep"] {
		candidates := []*health.Sleep{}
		for _, p := range points {
			if p.point.Sleep != nil {
				candidates = append(candidates, p.point.Sleep)
			}
		}
		sort.SliceStable(candidates, func(i, j int) bool {
			a, b := candidates[i], candidates[j]
			if a.Metadata.Main != b.Metadata.Main {
				return a.Metadata.Main
			}
			if a.Metadata.Main {
				av, bv := asleep(a), asleep(b)
				an, bn := -1, -1
				if av != nil {
					an = *av
				}
				if bv != nil {
					bn = *bv
				}
				if an != bn {
					return an > bn
				}
			} else if a.Interval.End.Sub(a.Interval.Start) != b.Interval.End.Sub(b.Interval.Start) {
				return a.Interval.End.Sub(a.Interval.Start) > b.Interval.End.Sub(b.Interval.Start)
			}
			return a.Interval.Start.Before(b.Interval.Start)
		})
		if len(candidates) > 0 && (candidates[0].Metadata.Main || candidates[0].Interval.End.Sub(candidates[0].Interval.Start) >= 180*time.Minute) {
			e.main[date] = candidates[0]
		}
	}
	for _, day := range state.HRMinutes {
		e.minutes = append(e.minutes, day.Windows...)
	}
	sort.Slice(e.minutes, func(i, j int) bool { return e.minutes[i].Start < e.minutes[j].Start })
	e.device = e.readDevice()
	e.freshness = e.readFreshness()
	return e, nil
}

func (e *Engine) Date(s string) time.Time {
	d, _ := time.ParseInLocation("2006-01-02", s, e.loc)
	return d
}
func (e *Engine) Today() string { return e.Now.In(e.loc).Format("2006-01-02") }
func (e *Engine) add(date string, days int) string {
	return e.Date(date).AddDate(0, 0, days).Format("2006-01-02")
}
func (e *Engine) DefaultDate() string {
	today := e.Today()
	if e.Cycle(today).Status == "open" {
		return today
	}
	yesterday := e.add(today, -1)
	if e.Cycle(yesterday).Status == "open" {
		return yesterday
	}
	return today
}
func (e *Engine) Cycle(date string) Cycle {
	start, source := e.cycleStart(date)
	end, _ := e.cycleStart(e.add(date, 1))
	c := Cycle{Start: start, StartSource: source, Status: "closed", End: &end, EndSource: ptr("next_cycle_start")}
	if e.Now.Before(start) {
		c.Status, c.End, c.EndSource = "not_started", nil, nil
	} else if e.Now.Before(end) {
		c.Status, c.End, c.EndSource = "open", nil, ptr("now")
	}
	return c
}
func (e *Engine) cycleStart(date string) (time.Time, string) {
	if main := e.sleep(date); main != nil {
		return main.Interval.End.UTC(), "main_sleep_wake"
	}
	wakes := []float64{}
	for k := 1; k <= TypicalWakeDays; k++ {
		if s := e.sleep(e.add(date, -k)); s != nil {
			wakes = append(wakes, localMinutes(s.Interval.End, e.loc))
		}
	}
	m := TypicalWakeDefaultMinutes
	if len(wakes) >= TypicalWakeMinNights {
		sort.Float64s(wakes)
		mid := len(wakes) / 2
		median := wakes[mid]
		if len(wakes)%2 == 0 {
			median = (wakes[mid-1] + wakes[mid]) / 2
		}
		m = int(math.Floor(median))
	}
	d := e.Date(date)
	at := time.Date(d.Year(), d.Month(), d.Day(), m/60, m%60, 0, 0, e.loc)
	if at.In(e.loc).Hour() != m/60 || at.In(e.loc).Minute() != m%60 {
		at = time.Date(d.Year(), d.Month(), d.Day(), 2, 0, 0, 0, e.loc)
	}
	return at.UTC(), "typical_wake_fallback"
}
func localMinutes(at time.Time, loc *time.Location) float64 {
	at = at.In(loc)
	return float64(at.Hour()*60+at.Minute()) + float64(at.Second())/60 + float64(at.Nanosecond())/6e10
}
func number(n *health.Number) *float64 {
	if n == nil {
		return nil
	}
	return ptr(float64(*n))
}
func integer(n *health.Integer) *int {
	if n == nil {
		return nil
	}
	return ptr(int(*n))
}
func asleep(s *health.Sleep) *int {
	if s == nil {
		return nil
	}
	if s.Summary.MinutesAsleep != nil {
		return integer(s.Summary.MinutesAsleep)
	}
	if len(s.Summary.Stages) == 0 {
		return nil
	}
	total := 0
	for _, stage := range s.Summary.Stages {
		if stage.Minutes == nil {
			return nil
		}
		switch stage.Type {
		case "LIGHT", "DEEP", "REM", "ASLEEP":
			total += int(*stage.Minutes)
		}
	}
	return &total
}

func (e *Engine) metric(date, id string) (*float64, string) {
	found, conflict := e.metricValue(date, id)
	if conflict {
		return nil, "conflict"
	}
	if found != nil {
		return found, "available"
	}
	return nil, e.MissingStatus(date, id, "list")
}

// metricValue is the day's value, or conflict when stored values differ. It skips the coverage scan
// that only callers reporting a missing status need.
func (e *Engine) metricValue(date, id string) (*float64, bool) {
	var found *float64
	for _, p := range e.points[id][date] {
		var v *float64
		switch id {
		case "daily-heart-rate-variability":
			if p.point.DailyHRV != nil {
				v = number(p.point.DailyHRV.RMSSD)
				if v != nil && *v <= 0 {
					v = nil
				}
			}
		case "daily-resting-heart-rate":
			if p.point.RHR != nil && p.point.RHR.BPM != nil {
				v = ptr(float64(*p.point.RHR.BPM))
			}
		case "daily-respiratory-rate":
			if p.point.DailyRR != nil {
				v = number(p.point.DailyRR.BPM)
			}
		case "daily-oxygen-saturation":
			if p.point.Oxygen != nil {
				v = number(p.point.Oxygen.Average)
			}
		}
		if v != nil {
			if found != nil && *found != *v {
				return nil, true
			}
			found = v
		}
	}
	return found, false
}
func (e *Engine) MissingStatus(date, id, route string) string {
	for _, row := range e.State.Coverage {
		if row.Date == date && row.Type == id && row.Stream == route {
			switch row.Status {
			case "ok":
				return "missing"
			case "permission_missing":
				return "permission_missing"
			default:
				return "unavailable"
			}
		}
	}
	return "not_synced"
}
func (e *Engine) baseline(date, id string) []float64 {
	values := []float64{}
	for k := 1; k <= BaselineWindowDays && len(values) < BaselineMaxValues; k++ {
		if v, conflict := e.metricValue(e.add(date, -k), id); v != nil && !conflict {
			values = append(values, *v)
		}
	}
	return values
}
func (e *Engine) temperature(date string) *TemperatureInput {
	rows := e.points["daily-sleep-temperature-derivations"][date]
	if len(rows) != 1 || rows[0].point.Temperature == nil {
		return nil
	}
	t := rows[0].point.Temperature
	return &TemperatureInput{number(t.Nightly), number(t.Baseline), number(t.SD)}
}
func (e *Engine) Recovery(date string) Recovery {
	hrv, hs := e.metric(date, "daily-heart-rate-variability")
	rhr, rs := e.metric(date, "daily-resting-heart-rate")
	rr, _ := e.metric(date, "daily-respiratory-rate")
	summary := e.Sleep(date)
	sleep := summary.Performance.Value
	if summary.PerformanceComposite != nil {
		sleep = summary.PerformanceComposite.Value
	}
	in := RecoveryInput{HRV: hrv, HRVBaseline: e.baseline(date, "daily-heart-rate-variability"), RHR: rhr, RHRBaseline: e.baseline(date, "daily-resting-heart-rate"), RR: rr, RRBaseline: e.baseline(date, "daily-respiratory-rate"), Temperature: e.temperature(date), Sleep: sleep, HRVConflict: hs == "conflict", RHRConflict: rs == "conflict", Today: date == e.Today()}
	if main := e.main[date]; main != nil && main.Metadata.Processed != nil {
		in.SleepProcessing = !*main.Metadata.Processed
	}
	return ComputeRecovery(in)
}

func (e *Engine) Device() Device       { return e.device }
func (e *Engine) Freshness() Freshness { return e.freshness }
func (e *Engine) readDevice() Device {
	d := Device{Status: "error"}
	resource := e.State.User["paired_devices"]
	if resource.Status == "permission_missing" {
		d.Status = "scope_missing"
		return d
	}
	if resource.Status != "ok" {
		return d
	}
	d.Status = "no_tracker"
	var body struct {
		Devices []struct {
			Type          string     `json:"deviceType"`
			Name          *string    `json:"deviceVersion"`
			Battery       *int       `json:"batteryLevel"`
			BatteryStatus *string    `json:"batteryStatus"`
			Sync          *time.Time `json:"lastSyncTime"`
		} `json:"pairedDevices"`
	}
	if json.Unmarshal(resource.Body, &body) != nil {
		return Device{Status: "error"}
	}
	for _, device := range body.Devices {
		if device.Type == "TRACKER" && device.Sync != nil && (d.Sync == nil || device.Sync.After(*d.Sync)) {
			d = Device{"ok", device.Name, device.Battery, device.BatteryStatus, device.Sync}
		}
	}
	return d
}
func (e *Engine) readFreshness() Freshness {
	f := Freshness{LastStatus: "never", CollectorStale: true, DeviceSync: e.device.Sync, DeviceSource: e.device.Status}
	if e.device.Status == "ok" {
		f.DeviceSource = "paired_devices"
	}
	for _, run := range e.State.Runs {
		if run.CoreComplete && (f.Collected == nil || run.FinishedAt.After(*f.Collected)) {
			f.Collected = ptr(run.FinishedAt)
		}
	}
	if len(e.State.Runs) > 0 {
		f.LastStatus = e.State.Runs[len(e.State.Runs)-1].Status
	}
	if f.Collected != nil {
		age := int(math.Floor(e.Now.Sub(*f.Collected).Minutes()))
		f.CollectAge = &age
		f.CollectorStale = age > CollectorStaleMinutes
	}
	if f.DeviceSync != nil {
		age := int(math.Floor(e.Now.Sub(*f.DeviceSync).Minutes()))
		f.DeviceAge = &age
		f.DeviceStale = ptr(age > DeviceStaleMinutes)
	}
	return f
}
