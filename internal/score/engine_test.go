package score_test

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func fixtureState(t *testing.T, name string) store2.State2 {
	t.Helper()
	b, err := os.ReadFile("../../fixtures/v2/inputs/store_" + name + ".json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(b, &state); err != nil {
		t.Fatal(err)
	}
	return state
}
func engine(t *testing.T, state store2.State2, now string, cfg config.Values) *score.Engine {
	t.Helper()
	at, err := time.Parse(time.RFC3339, now)
	if err != nil {
		t.Fatal(err)
	}
	e, err := score.New(state, at, cfg)
	if err != nil {
		t.Fatal(err)
	}
	return e
}
func removeDate(state *store2.State2, id, date string) {
	kept := []health.Record{}
	for _, r := range state.Records {
		if r.Type != id || r.Date != date {
			kept = append(kept, r)
		}
	}
	state.Records = kept
}
func rewrite(state *store2.State2, id, date, old, value string) {
	for i, r := range state.Records {
		if r.Type == id && r.Date == date {
			state.Records[i].Raw = json.RawMessage(strings.ReplaceAll(string(r.Raw), old, value))
		}
	}
}

func TestEngineScoreObjectsMatchDayGoldens(t *testing.T) {
	for _, name := range []string{"full", "no_sleep", "calibrating", "new_user"} {
		t.Run(name, func(t *testing.T) {
			e := engine(t, fixtureState(t, name), "2026-03-10T14:30:00Z", config.Defaults())
			b, err := os.ReadFile("../../fixtures/v2/day_" + name + ".json")
			if err != nil {
				t.Fatal(err)
			}
			var golden map[string]json.RawMessage
			_ = json.Unmarshal(b, &golden)
			for key, value := range map[string]any{"cycle": e.Cycle("2026-03-10"), "recovery": e.Recovery("2026-03-10"), "strain": e.Strain("2026-03-10"), "sleep": e.Sleep("2026-03-10"), "vitals": e.Vitals("2026-03-10"), "activity": e.Activity("2026-03-10"), "workouts": e.Workouts("2026-03-10", false), "vo2_max": e.VO2("2026-03-10"), "health_flags": e.Flags("2026-03-10", e.Vitals("2026-03-10")), "freshness": e.Freshness()} {
				t.Run(key, func(t *testing.T) { testutil.CompareJSON(t, value, golden[key], false) })
			}
		})
	}
}

func TestVitalsRequireConsecutiveNights(t *testing.T) {
	for _, mode := range []string{"same_two", "one_night", "gap", "conflict"} {
		t.Run(mode, func(t *testing.T) {
			state := fixtureState(t, "full")
			for _, date := range []string{"2026-03-09", "2026-03-10"} {
				if date == "2026-03-09" && mode == "one_night" {
					continue
				}
				for _, id := range []string{"daily-resting-heart-rate", "daily-respiratory-rate"} {
					var row health.Record
					for _, r := range state.Records {
						if r.Type == id && r.Date == date {
							row = r
							break
						}
					}
					removeDate(&state, id, date)
					if date == "2026-03-09" && mode == "gap" {
						continue
					}
					var raw map[string]any
					_ = json.Unmarshal(row.Raw, &raw)
					if id == "daily-resting-heart-rate" {
						raw["dailyRestingHeartRate"].(map[string]any)["beatsPerMinute"] = "100"
					} else {
						raw["dailyRespiratoryRate"].(map[string]any)["breathsPerMinute"] = 30
					}
					row.Raw, _ = json.Marshal(raw)
					state.Records = append(state.Records, row)
					if date == "2026-03-09" && mode == "conflict" && id == "daily-resting-heart-rate" {
						raw["dailyRestingHeartRate"].(map[string]any)["beatsPerMinute"] = "101"
						row.Raw, _ = json.Marshal(raw)
						state.Records = append(state.Records, row)
					}
				}
			}
			e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
			v := e.Vitals("2026-03-10")
			body, _ := json.Marshal(v)
			var got struct {
				State      string   `json:"monitor_state"`
				Persistent []string `json:"persistent"`
			}
			_ = json.Unmarshal(body, &got)
			want := "outside"
			if mode == "same_two" {
				want = "attention"
			}
			if got.State != want || got.Persistent == nil {
				t.Fatalf("state %q, persistent %v; want %q and an array", got.State, got.Persistent, want)
			}
			flag := false
			for _, f := range e.Flags("2026-03-10", v) {
				flag = flag || f.Code == "vitals_outside_range"
			}
			if flag != (mode == "same_two") {
				t.Fatalf("attention flag %v", flag)
			}
		})
	}
}

func TestHRVTrendBaselineSkipsTheWeek(t *testing.T) {
	state := fixtureState(t, "full")
	week := 0
	for i, r := range state.Records {
		if r.Type != "daily-heart-rate-variability" {
			continue
		}
		value := 60.0
		if r.Date >= "2026-03-04" {
			value = 45
			week++
		}
		var p map[string]any
		_ = json.Unmarshal(r.Raw, &p)
		p["dailyHeartRateVariability"].(map[string]any)["averageHeartRateVariabilityMilliseconds"] = value
		state.Records[i].Raw, _ = json.Marshal(p)
	}
	trend := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults()).Vitals("2026-03-10").HRVTrend
	// A baseline that overlapped the week would hold 45 ms nights and give a lower, wider range.
	if trend.N == nil || *trend.N != 28 || trend.Low == nil || *trend.Low != 54.3 || *trend.High != 66.3 || trend.Nights != week || *trend.Value != 45 || *trend.Position != "below" {
		t.Fatalf("trend %+v, nights %d of %d", trend.Vital, trend.Nights, week)
	}
}
func TestRecoveryEdgeCases(t *testing.T) {
	for _, tc := range []struct {
		name           string
		change         func(*store2.State2)
		reason, status string
	}{
		{"processing", func(s *store2.State2) {
			rewrite(s, "sleep", "2026-03-10", `"processed":true`, `"processed":false`)
			rewrite(s, "sleep", "2026-03-10", `"processed": true`, `"processed": false`)
		}, "sleep_processing", "pending"},
		{"sleep_missing_hrv_present", func(s *store2.State2) { removeDate(s, "sleep", "2026-03-10") }, "no_sleep", "pending"},
		{"rhr_pending", func(s *store2.State2) { removeDate(s, "daily-resting-heart-rate", "2026-03-10") }, "no_resting_hr", "pending"},
		{"hrv_conflict", func(s *store2.State2) {
			for _, r := range s.Records {
				if r.Type == "daily-heart-rate-variability" && r.Date == "2026-03-10" {
					r.Raw = json.RawMessage(strings.ReplaceAll(string(r.Raw), "56.0", "57.0"))
					s.Records = append(s.Records, r)
					break
				}
			}
		}, "hrv_conflict", "unavailable"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			state := fixtureState(t, "full")
			tc.change(&state)
			e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
			r := e.Recovery("2026-03-10")
			if r.Value != nil || r.Reason == nil || *r.Reason != tc.reason || r.Status != tc.status {
				t.Fatalf("unexpected recovery: %+v", r)
			}
		})
	}
	for _, nonfinite := range []string{`"NaN"`, `"Infinity"`, `"-Infinity"`} {
		state := fixtureState(t, "full")
		rewrite(&state, "daily-sleep-temperature-derivations", "2026-03-10", `33.8`, nonfinite)
		e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
		r := e.Recovery("2026-03-10")
		if r.Value == nil || r.Components == nil || r.Components.TempZ != nil || r.Components.TempPenalty != 0 || len(r.Components.OptionalMissing) != 1 || r.Components.OptionalMissing[0] != "skin_temperature" {
			t.Fatal("temperature baseline quirk not applied", r)
		}
		v := e.Vitals("2026-03-10").Metrics["skin_temp_deviation"]
		if v.Position == nil || *v.Position != "no_baseline" {
			t.Fatal("no-baseline position missing")
		}
	}
	state := fixtureState(t, "full")
	kept := []health.Record{}
	for _, r := range state.Records {
		if r.Type != "daily-respiratory-rate" || r.Date >= "2026-03-04" {
			kept = append(kept, r)
		}
	}
	state.Records = kept
	e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
	if r := e.Recovery("2026-03-10"); r.Value == nil || r.Components.RRZ != nil || r.Components.OptionalMissing[0] != "respiratory_rate" {
		t.Fatal("short optional baseline changed required score")
	}
}

func TestCycleFallbackUsesLondonWallClockAcrossDST(t *testing.T) {
	for _, tc := range []struct{ date, start string }{{"2026-03-29", "2026-03-29T06:00:00Z"}, {"2026-10-25", "2026-10-25T07:00:00Z"}} {
		e := engine(t, store2.Empty(), "2026-11-01T12:00:00Z", config.Defaults())
		c := e.Cycle(tc.date)
		if c.Start.Format(time.RFC3339) != tc.start || c.StartSource != "typical_wake_fallback" {
			t.Fatal(tc, c)
		}
	}
	state := store2.Empty()
	for _, day := range []int{26, 27, 28} {
		state.Records = append(state.Records, testutil.Record(t, "sleep", "reconciled", fmt.Sprintf("2026-03-%02d", day), fmt.Sprintf(`{"sleep":{"interval":{"startTime":"2026-03-%02dT21:00:00Z","endTime":"2026-03-%02dT01:30:00Z"},"metadata":{"mainSleep":true}}}`, day-1, day)))
	}
	e := engine(t, state, "2026-03-30T12:00:00Z", config.Defaults())
	if got := e.Cycle("2026-03-29").Start.Format(time.RFC3339); got != "2026-03-29T01:00:00Z" {
		t.Fatal("spring gap did not use 02:00 London", got)
	}
	e = engine(t, store2.Empty(), "2026-03-10T01:30:00Z", config.Defaults())
	if e.DefaultDate() != "2026-03-09" {
		t.Fatal("early morning lost previous open cycle")
	}
}

func TestBaselineSkipsConflictDatesAndStageZeroIsNull(t *testing.T) {
	state := fixtureState(t, "calibrating")
	for _, r := range state.Records {
		if r.Type == "daily-heart-rate-variability" && r.Date == "2026-03-09" {
			var p map[string]any
			_ = json.Unmarshal(r.Raw, &p)
			p["dailyHeartRateVariability"].(map[string]any)["averageHeartRateVariabilityMilliseconds"] = 100.0
			r.Raw, _ = json.Marshal(p)
			state.Records = append(state.Records, r)
			break
		}
	}
	e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
	if r := e.Recovery("2026-03-10"); r.Baseline.HRV.N != 7 || r.Baseline.RHR.N != 9 || r.Status != "calibrating" {
		t.Fatal("baseline conflict was averaged or retained", r.Baseline)
	}
	state = fixtureState(t, "full")
	for i, r := range state.Records {
		if r.Type == "respiratory-rate-sleep-summary" && r.Date == "2026-03-10" {
			var p map[string]any
			_ = json.Unmarshal(r.Raw, &p)
			p["respiratoryRateSleepSummary"].(map[string]any)["remSleepStats"] = map[string]any{"breathsPerMinute": 0}
			state.Records[i].Raw, _ = json.Marshal(p)
		}
	}
	e = engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
	detail := e.SleepDetail("2026-03-10")
	if detail.Respiratory == nil || detail.Respiratory.REM != nil || detail.Respiratory.Full == nil {
		t.Fatal("stage zero did not produce null", detail.Respiratory)
	}
}

func TestStrainMissingInputsAndStaleSync(t *testing.T) {
	state := fixtureState(t, "full")
	cfg := config.Defaults()
	maxHR := 120
	cfg.MaxHR = &maxHR
	for _, r := range state.Records {
		if r.Type == "daily-resting-heart-rate" && r.Date == "2026-03-10" {
			rewrite(&state, r.Type, r.Date, `"56"`, `"150"`)
			break
		}
	}
	e := engine(t, state, "2026-03-10T14:30:00Z", cfg)
	if s := e.Strain("2026-03-10"); s.Value != nil || s.Reason == nil || *s.Reason != "max_hr_unknown" {
		t.Fatal(s)
	}
	state = fixtureState(t, "full")
	resource := state.User["paired_devices"]
	resource.Body = json.RawMessage(strings.ReplaceAll(string(resource.Body), "14:08:00", "08:00:00"))
	state.User["paired_devices"] = resource
	e = engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
	s := e.Strain("2026-03-10")
	if s.Until == nil || s.Until.Format(time.RFC3339) != "2026-03-10T08:00:00Z" || s.Expected == nil || *s.Expected != 91 {
		t.Fatal("stale band inflated expected window", s)
	}
	state = store2.Empty()
	e = engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
	if s = e.Strain("2026-03-10"); s.Reason == nil || *s.Reason != "resting_hr_unknown" {
		t.Fatal(s)
	}
	state.Records = []health.Record{testutil.Record(t, "daily-resting-heart-rate", "raw", "2026-03-10", `{"dailyRestingHeartRate":{"date":{"year":2026,"month":3,"day":10},"beatsPerMinute":"56"}}`)}
	e = engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
	if s = e.Strain("2026-03-10"); s.Reason == nil || *s.Reason != "max_hr_unknown" {
		t.Fatal(s)
	}
}

func TestDayStrainContainsEveryWorkoutStrain(t *testing.T) {
	for _, profile := range []string{"banister_b192", "banister_b167"} {
		t.Run(profile, func(t *testing.T) {
			rng := rand.New(rand.NewSource(42))
			maximum := 190
			cfg := config.Defaults()
			cfg.MaxHR, cfg.TrimpProfile = &maximum, profile
			belowCeiling := 0
			for trial := 0; trial < 30; trial++ {
				state := store2.Empty()
				state.Records = []health.Record{
					testutil.Record(t, "daily-resting-heart-rate", "raw", "2026-03-10", `{"dailyRestingHeartRate":{"date":{"year":2026,"month":3,"day":10},"beatsPerMinute":"56"}}`),
					testutil.Record(t, "exercise", "raw", "2026-03-10", `{"name":"users/synthetic/dataTypes/exercise/dataPoints/1","exercise":{"exerciseType":"BOXING","interval":{"startTime":"2026-03-10T23:30:00Z","endTime":"2026-03-11T00:30:00Z"}}}`),
				}
				start, _ := time.Parse(time.RFC3339, "2026-03-10T07:00:00Z")
				day := store2.MinuteDay{Date: "2026-03-10"}
				for k := 0; k < 1440; k++ {
					if rng.Intn(5) == 0 {
						continue
					}
					v := float64(60 + rng.Intn(35))
					if k >= 990 && k < 1050 || k >= 360 && k < 360+trial {
						v = float64(100 + rng.Intn(105))
					}
					day.Windows = append(day.Windows, store2.Minute{Start: start.Add(time.Duration(k) * time.Minute).Unix(), Min: v - 2, Avg: v, Max: v + 2})
				}
				state.HRMinutes = []store2.MinuteDay{day}
				e := engine(t, state, "2026-03-12T12:00:00Z", cfg)
				dayScore := e.Strain("2026-03-10")
				workouts := e.Workouts("2026-03-10", false)
				if len(workouts) == 0 || dayScore.Value == nil {
					t.Fatal("property generated no scored workout")
				}
				if *dayScore.Value < 21 {
					belowCeiling++
				}
				for _, w := range workouts {
					if w.CycleDate != "2026-03-10" || w.Strain == nil || *w.Strain > *dayScore.Value {
						t.Fatal("workout exceeded containing cycle", w.Strain, dayScore.Value)
					}
				}
			}
			if belowCeiling != 30 {
				t.Fatalf("only %d trials exercised the scale below its ceiling", belowCeiling)
			}
		})
	}
}

func TestObservedMaximumUsesSecondPeakOfWorkoutsInTheYearBefore(t *testing.T) {
	state := fixtureState(t, "full")
	boxing, _ := time.Parse(time.RFC3339, "2026-03-10T12:00:00Z")
	for d := range state.HRMinutes {
		for i, m := range state.HRMinutes[d].Windows {
			switch m.Start {
			case boxing.Add(10 * time.Minute).Unix():
				state.HRMinutes[d].Windows[i].Max = 215
			case boxing.Add(20 * time.Minute).Unix():
				state.HRMinutes[d].Windows[i].Max = 198
			}
		}
	}
	e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
	for _, c := range []struct {
		date, source string
		max          float64
	}{
		{"2026-03-10", "observed", 198},
		{"2026-03-09", "age_predicted_profile", 187},
		{"2027-03-10", "observed", 198},
		{"2027-03-11", "age_predicted_profile", 187},
	} {
		s := e.Strain(c.date)
		if s.Max == nil || *s.Max != c.max || s.MaxSource == nil || *s.MaxSource != c.source {
			t.Errorf("%s: max %v from %v, want %v from %s", c.date, s.Max, s.MaxSource, c.max, c.source)
		}
	}
}

func TestSleepEditMovesRecordedWorkoutAfterWorkoutsWereRead(t *testing.T) {
	e := engine(t, fixtureState(t, "full"), "2026-03-10T14:30:00Z", config.Defaults())
	cycle := func() string {
		for _, date := range []string{"2026-03-09", "2026-03-10"} {
			for _, w := range e.Workouts(date, false) {
				if w.ID == "7000000000000000002" {
					return date
				}
			}
		}
		return ""
	}
	if got := cycle(); got != "2026-03-10" {
		t.Fatalf("kickboxing in cycle %q before the edit", got)
	}
	start, _ := time.Parse(time.RFC3339, "2026-03-09T23:15:00Z")
	end, _ := time.Parse(time.RFC3339, "2026-03-10T12:30:00Z")
	e.SleepEdits = []activities.SleepEdit{{Date: "2026-03-10", Start: start, End: end}}
	if got := cycle(); got != "2026-03-09" {
		t.Fatalf("kickboxing in cycle %q after the wake moved past its start", got)
	}
}
