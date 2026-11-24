package v2report

import (
	"encoding/json"
	"math"
	"net/url"
	"sort"
	"strconv"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/collect"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

type Options struct {
	Journal           journal.Book
	SleepEdits        []activities.SleepEdit
	Ratings           []activities.Rating
	Activities        []activities.Record
	Edits             []activities.Edit
	Auth              Auth
	ScheduleInstalled bool
	Server            Server
}
type Builder struct {
	engine     *score.Engine
	options    Options
	recoveries map[string]score.Recovery
}

// recovery memoises Recovery per date for one request, so the journal impact reuses the day rows' values.
func (b *Builder) recovery(date string) score.Recovery {
	if r, ok := b.recoveries[date]; ok {
		return r
	}
	r := b.engine.Recovery(date)
	b.recoveries[date] = r
	return r
}

func New(state store2.State2, now time.Time, cfg config.Values, options Options) (*Builder, error) {
	e, err := score.New(state, now, cfg)
	if err != nil {
		return nil, NewError("store_unavailable")
	}
	e.Activities = options.Activities
	e.Edits = options.Edits
	e.SleepEdits = options.SleepEdits
	e.Ratings = options.Ratings
	if options.Auth.Missing == nil {
		options.Auth.Missing = []string{}
	}
	return &Builder{engine: e, options: options, recoveries: map[string]score.Recovery{}}, nil
}

func (b *Builder) Build(kind string, params url.Values) (any, error) {
	allowed := map[string]bool{}
	switch kind {
	case "day", "sleep", "week":
		allowed["date"] = true
	case "heart_rate":
		allowed["date"], allowed["start"], allowed["end"] = true, true, true
	case "brief":
		allowed["date"], allowed["include_values"], allowed["part"] = true, true, true
	case "days", "workouts":
		allowed["days"], allowed["from"], allowed["to"] = true, true, true
	case "journal":
		allowed["days"] = true
	case "status", "snapshot":
	default:
		return nil, NewError("not_found")
	}
	for key, values := range params {
		if !allowed[key] || len(values) != 1 || values[0] == "" {
			if key == "part" && kind == "brief" {
				return nil, invalidParameter("part")
			}
			return nil, invalidParameter("query")
		}
	}
	if kind == "heart_rate" {
		return b.heartRate(params)
	}
	if kind == "journal" {
		return b.journal(params)
	}
	date := b.engine.DefaultDate()
	if value := params.Get("date"); value != "" {
		if _, err := b.date(value, "date"); err != nil {
			return nil, err
		}
		date = value
	}
	switch kind {
	case "day":
		return b.Day(date), nil
	case "sleep":
		return b.Sleep(date), nil
	case "week":
		return b.Week(date), nil
	case "status":
		return b.Status(), nil
	case "snapshot":
		return b.Snapshot(), nil
	case "brief":
		include := false
		if value := params.Get("include_values"); value != "" {
			if value != "true" && value != "false" {
				return nil, invalidParameter("include_values")
			}
			include = value == "true"
		}
		part := "morning"
		if value, ok := params["part"]; ok {
			part = value[0]
		}
		if part != "morning" && part != "evening" && part != "week" {
			return nil, invalidParameter("part")
		}
		return b.Brief(date, include, part), nil
	case "days", "workouts":
		defaultDays := 30
		if kind == "workouts" {
			defaultDays = 14
		}
		from, to, err := b.rangeDates(params, defaultDays)
		if err != nil {
			return nil, err
		}
		if kind == "days" {
			return b.Days(from, to), nil
		}
		return b.Workouts(from, to), nil
	}
	return nil, NewError("not_found")
}
func (b *Builder) date(value, parameter string) (time.Time, error) {
	date, err := time.Parse("2006-01-02", value)
	if err != nil || date.Format("2006-01-02") != value {
		return date, invalidParameter(parameter)
	}
	if value > b.engine.Today() {
		return date, NewError("date_out_of_range")
	}
	return b.engine.Date(value), nil
}
func (b *Builder) rangeDates(params url.Values, days int) (string, string, error) {
	_, hasDays := params["days"]
	_, hasFrom := params["from"]
	_, hasTo := params["to"]
	if hasDays && (hasFrom || hasTo) || hasFrom != hasTo {
		return "", "", invalidParameter("range")
	}
	if hasFrom {
		from, err := b.date(params.Get("from"), "from")
		if err != nil {
			return "", "", err
		}
		to, err := b.date(params.Get("to"), "to")
		if err != nil {
			return "", "", err
		}
		if from.After(to) || from.AddDate(0, 0, 89).Before(to) {
			return "", "", NewError("date_out_of_range")
		}
		return params.Get("from"), params.Get("to"), nil
	}
	if hasDays {
		n, err := strconv.Atoi(params.Get("days"))
		if err != nil {
			return "", "", invalidParameter("days")
		}
		days = n
	}
	if days < 1 || days > 90 {
		return "", "", NewError("date_out_of_range")
	}
	end := b.engine.DefaultDate()
	return b.engine.Date(end).AddDate(0, 0, 1-days).Format("2006-01-02"), end, nil
}
func (b *Builder) envelope(kind string) Envelope {
	e := CommandEnvelope(kind, b.engine.Now)
	e.ScoreVersion = score.VersionFor(b.engine.Config)
	if kind != "brief" && kind != "week" {
		e.Config = &b.engine.Config.Score
		c := score.ConstantsForConfig(b.engine.Config)
		e.Constants = &c
	}
	e.Synthetic = b.engine.State.Synthetic
	for _, r := range b.engine.State.Records {
		if r.Synthetic {
			e.Synthetic = true
			break
		}
	}
	return e
}
func (b *Builder) Day(date string) Day {
	out := b.dayValues(date)
	out.Comparison = b.comparison(date)
	return out
}
func (b *Builder) dayValues(date string) Day {
	e := b.engine
	cycle := e.Cycle(date)
	vitals := e.Vitals(date)
	workouts := e.Workouts(date, false)
	recovery, strain := b.recovery(date), e.Strain(date)
	return Day{
		Envelope: b.envelope("day"), Freshness: e.Freshness(),
		Date: date, Current: cycle.Status == "open", Cycle: cycle,
		Recovery: recovery, Strain: strain,
		StrainTarget: score.StrainTargetFor(recovery, strain, e.Config.StrainIntent),
		Sleep:        e.Sleep(date), SleepPlan: e.SleepPlan(date), Vitals: vitals, Activity: e.Activity(date),
		Workouts: workouts, Strength: b.strength(date, workouts),
		VO2: e.VO2(date), Flags: e.Flags(date, vitals),
	}
}
func (b *Builder) Sleep(date string) Sleep {
	return Sleep{Envelope: b.envelope("sleep"), Freshness: b.engine.Freshness(), Date: date, SleepDetail: b.engine.SleepDetail(date)}
}
func (b *Builder) Workouts(from, to string) Workouts {
	out := Workouts{Envelope: b.envelope("workouts"), Freshness: b.engine.Freshness(), From: from, To: to, Workouts: []score.Workout{}}
	for day := b.engine.Date(from); day.Format("2006-01-02") <= to; day = day.AddDate(0, 0, 1) {
		out.Workouts = append(out.Workouts, b.engine.Workouts(day.Format("2006-01-02"), true)...)
	}
	sort.SliceStable(out.Workouts, func(i, j int) bool { return out.Workouts[i].Start.Before(out.Workouts[j].Start) })
	return out
}
func (b *Builder) Days(from, to string) Days {
	out := Days{Envelope: b.envelope("days"), Freshness: b.engine.Freshness(), From: from, To: to, Days: []DayRow{}, Summary: map[string]Summary{}}
	for day := b.engine.Date(from); day.Format("2006-01-02") <= to; day = day.AddDate(0, 0, 1) {
		out.Days = append(out.Days, b.row(day.Format("2006-01-02")))
	}
	for _, key := range []string{"recovery", "strain", "sleep_performance", "asleep_minutes", "hrv_rmssd_ms", "resting_hr_bpm", "steps"} {
		summary := Summary{}
		sum := 0.0
		for _, row := range out.Days {
			var v *float64
			switch key {
			case "recovery":
				v = row.Recovery
			case "strain":
				v = row.Strain
			case "sleep_performance":
				v = row.Performance
			case "asleep_minutes":
				if row.Asleep != nil {
					v = ptr(float64(*row.Asleep))
				}
			case "hrv_rmssd_ms":
				v = row.HRV
			case "resting_hr_bpm":
				v = row.RHR
			case "steps":
				v = row.Steps
			}
			if v == nil {
				continue
			}
			sum += *v
			summary.Days++
			if summary.Min == nil || *v < *summary.Min {
				summary.Min = ptr(*v)
			}
			if summary.Max == nil || *v > *summary.Max {
				summary.Max = ptr(*v)
			}
		}
		if summary.Days > 0 {
			scale := 10.0
			if key == "steps" {
				scale = 1
			}
			summary.Mean = ptr(math.Round(sum/float64(summary.Days)*scale) / scale)
		}
		out.Summary[key] = summary
	}
	return out
}

func (b *Builder) Status() Status {
	e := b.engine
	date := e.DefaultDate()
	recovery := b.recovery(date)
	out := Status{Envelope: b.envelope("status"), Freshness: e.Freshness(), Date: date, Auth: b.options.Auth, Device: e.Device(), ProviderTimezone: e.ProviderTimezone(), Server: b.options.Server, EditLimits: activities.ReportedLimits(), User: map[string]UserResource{}, Store: StoreStatus{HRDays: len(e.State.HRMinutes)}, Calibration: Calibration{Status: "ready", Calibration: recovery.Calibration}, Collector: Collector{Installed: b.options.ScheduleInstalled, Interval: 30, Success: e.Freshness().Collected, Streams: []StreamStatus{}}}
	if recovery.Calibrating {
		out.Calibration.Status = "calibrating"
	}
	if min(recovery.Calibration.HRV, recovery.Calibration.RHR) < score.BaselineMinValues {
		out.Calibration.Status = "insufficient"
	}
	if n := len(e.State.Runs); n > 0 {
		run := e.State.Runs[n-1]
		if run.FailedStreams == nil {
			run.FailedStreams = []string{}
		}
		out.Collector.Last = &run
	}
	for _, stream := range collect.Streams() {
		s := StreamStatus{Stream: stream, Status: "never"}
		for _, row := range e.State.Coverage {
			if row.Type+"/"+row.Stream == stream && (s.Date == nil || row.Date > *s.Date) {
				s.Date = ptr(row.Date)
				s.Status = row.Status
				s.Success = row.SuccessAt
				s.Error = text(row.Error)
			}
		}
		out.Collector.Streams = append(out.Collector.Streams, s)
	}
	dateSeen := func(date string) {
		if out.Store.Oldest == nil || date < *out.Store.Oldest {
			out.Store.Oldest = ptr(date)
		}
		if out.Store.Newest == nil || date > *out.Store.Newest {
			out.Store.Newest = ptr(date)
		}
	}
	for _, r := range e.State.Records {
		dateSeen(r.Date)
	}
	for _, r := range e.State.HRMinutes {
		dateSeen(r.Date)
	}
	for _, r := range e.State.DailyRollups {
		dateSeen(r.Date)
	}
	for _, key := range []string{"profile", "settings", "paired_devices", "irn_profile"} {
		resource := e.State.User[key]
		status := resource.Status
		if status == "" {
			status = "never"
		}
		u := UserResource{Status: status, Fetched: resource.FetchedAt}
		if key == "irn_profile" {
			u.IRNProfile = &IRNProfile{}
			var body struct {
				Onboarded *bool `json:"onboardingStatus"`
				Enrolled  *bool `json:"enrollmentStatus"`
			}
			if status == "ok" && json.Unmarshal(resource.Body, &body) == nil {
				u.Onboarded, u.Enrolled = body.Onboarded, body.Enrolled
			}
		}
		out.User[key] = u
	}
	return out
}
func (b *Builder) Snapshot() Snapshot {
	date := b.engine.DefaultDate()
	from := b.engine.Date(date)
	return Snapshot{Envelope: b.envelope("snapshot"), Freshness: b.engine.Freshness(), Date: date, Status: b.Status(), Day: b.Day(date), Sleep: b.Sleep(date), Days: b.Days(from.AddDate(0, 0, -29).Format("2006-01-02"), date), Workouts: b.Workouts(from.AddDate(0, 0, -13).Format("2006-01-02"), date), Journal: b.Journal(JournalDefaultDays)}
}
func ptr[T any](v T) *T { return &v }
func text(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func invalidParameter(parameter string) *Error {
	e := NewError("invalid_request")
	switch parameter {
	case "date", "from", "to":
		e.Message = parameter + " must be a valid YYYY-MM-DD"
	case "days":
		e.Message = "days must be an integer"
	case "part":
		e.Message = "part must be morning or evening"
	case "include_values":
		e.Message = "include_values must be true or false"
	case "range":
		e.Message = "days cannot be combined with from/to; from and to must be supplied together"
	default:
		e.Message = "query must contain supported parameters, each once with a nonempty value"
	}
	return e
}

func (b *Builder) row(date string) DayRow { return b.rowOf(b.dayValues(date)) }
func (b *Builder) rowOf(d Day) DayRow {
	row := DayRow{Date: d.Date, CycleStatus: d.Cycle.Status, Recovery: d.Recovery.Value, RecoveryBand: d.Recovery.Band, RecoveryStatus: d.Recovery.Status, RecoveryReason: d.Recovery.Reason, Strain: d.Strain.Value, StrainBand: d.Strain.Band, StrainStatus: d.Strain.Status, Coverage: d.Strain.Coverage, Performance: d.Sleep.Performance.Value, PerformanceBand: d.Sleep.Performance.Band, Asleep: d.Sleep.Asleep, Need: d.Sleep.Need.Total, InBed: d.Sleep.InBed, Efficiency: d.Sleep.Efficiency, HRV: d.Vitals.Metrics["hrv_rmssd"].Value, RHR: d.Vitals.Metrics["resting_hr"].Value, RR: d.Vitals.Metrics["respiratory_rate"].Value, SpO2: d.Vitals.Metrics["spo2"].Value, Temperature: d.Vitals.Metrics["skin_temp_deviation"].Value, Steps: d.Activity["steps"].Value, AZM: d.Activity["active_zone_minutes"].Value, Calories: d.Activity["calories_kcal"].Value, Adverse: len(d.Vitals.Adverse)}
	for _, w := range d.Workouts {
		if w.Kind == "recorded" || w.Kind == "goop" {
			row.Workouts++
		} else {
			row.Detected++
		}
	}
	row.Strength = d.Strength
	row.Consistency = intValue(d.Sleep.Consistency.Value)
	if composite := d.Sleep.PerformanceComposite; composite != nil {
		row.PerformanceComposite = &composite.Value
	}
	if zones := d.Strain.Zones; zones != nil {
		row.Zones13, row.Zones45 = ptr(zones.Z1+zones.Z2+zones.Z3), ptr(zones.Z4+zones.Z5)
	}
	deep, rem := d.Sleep.Stages["deep"].Minutes, d.Sleep.Stages["rem"].Minutes
	if deep != nil && rem != nil {
		row.Restorative = ptr(*deep + *rem)
	}
	return row
}
