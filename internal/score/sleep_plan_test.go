package score_test

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestSleepPlanGoldenVectors(t *testing.T) {
	var vectors struct {
		Goals []struct {
			Name  string
			Input struct {
				Need       int       `json:"need_minutes"`
				Efficiency float64   `json:"efficiency_pct_used"`
				Wake       time.Time `json:"wake_target"`
			}
			Expected json.RawMessage
		}
		Need []struct {
			Name     string
			Input    struct{ Nap bool }
			Expected json.RawMessage
		}
		Nights []struct {
			Name  string
			Input struct {
				Wake *string `json:"wake_target"`
			}
			Expected json.RawMessage
		}
	}
	vectorFile(t, "sleep_plan", &vectors)
	for _, tc := range vectors.Goals {
		t.Run(tc.Name, func(t *testing.T) {
			in := tc.Input
			testutil.CompareJSON(t, score.SleepPlanGoals(in.Need, in.Efficiency, in.Wake), tc.Expected, false)
		})
	}
	for _, tc := range vectors.Need {
		t.Run(tc.Name, func(t *testing.T) {
			state := fixtureState(t, "full")
			if tc.Input.Nap {
				state.Records = append(state.Records, planNap(t, "2026-03-10T12:30:00Z", "2026-03-10T13:10:00Z", 40))
			}
			plan := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults()).SleepPlan("2026-03-10")
			testutil.CompareJSON(t, plan, tc.Expected, true)
		})
	}
	for _, tc := range vectors.Nights {
		t.Run(tc.Name, func(t *testing.T) {
			state := fixtureState(t, "full")
			kept := []health.Record{}
			for _, r := range state.Records {
				if r.Type != "sleep" || r.Date >= "2026-03-09" {
					kept = append(kept, r)
				}
			}
			state.Records = kept
			cfg := config.Defaults()
			cfg.WakeTarget = tc.Input.Wake
			plan := engine(t, state, "2026-03-10T14:30:00Z", cfg).SleepPlan("2026-03-10")
			testutil.CompareJSON(t, plan, tc.Expected, true)
		})
	}
}

func TestSleepPlanCycleNapAndMissingStrain(t *testing.T) {
	for _, tc := range []struct {
		name, start, end string
		credit           int
	}{
		{"before_cycle", "2026-03-10T05:00:00Z", "2026-03-10T05:40:00Z", 0},
		{"at_cycle_start", "2026-03-10T05:49:00Z", "2026-03-10T06:29:00Z", 40},
		{"at_now", "2026-03-10T13:50:00Z", "2026-03-10T14:30:00Z", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			state := fixtureState(t, "full")
			state.Records = append(state.Records, planNap(t, tc.start, tc.end, 40))
			e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
			plan := e.SleepPlan("2026-03-10")
			if plan.Parts.NapCredit != tc.credit || plan.Need != 483-tc.credit {
				t.Fatalf("nap credit/need = %d/%d, want %d/%d", plan.Parts.NapCredit, plan.Need, tc.credit, 483-tc.credit)
			}
			if e.SleepPlan("2026-03-09") != nil || e.SleepPlan("2026-03-11") != nil {
				t.Fatal("closed or not-started cycle has a plan")
			}
		})
	}
	state := fixtureState(t, "full")
	state.HRMinutes = nil
	plan := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults()).SleepPlan("2026-03-10")
	if plan.Parts.CycleStrain != nil || plan.Parts.StrainExtra != 0 || plan.Parts.NapCredit != 0 || plan.Need != 472 {
		t.Fatal("null strain or main sleep treated as a nap", plan)
	}
}

func TestSleepPlanWakeAcrossSpringGapAndMissingLatency(t *testing.T) {
	state := store2.Empty()
	for _, day := range []int{26, 27, 28} {
		state.Records = append(state.Records, testutil.Record(t, "sleep", "reconciled", fmt.Sprintf("2026-03-%02d", day), fmt.Sprintf(`{"sleep":{"interval":{"startTime":"2026-03-%02dT17:30:00Z","endTime":"2026-03-%02dT01:30:30Z"},"summary":{"minutesAsleep":480},"metadata":{"mainSleep":true}}}`, day-1, day)))
	}
	gap := "01:30"
	for _, wake := range []*string{nil, &gap} {
		cfg := config.Defaults()
		cfg.WakeTarget = wake
		plan := engine(t, state, "2026-03-28T14:30:00Z", cfg).SleepPlan("2026-03-28")
		if plan.Wake == nil || plan.Wake.Format(time.RFC3339) != "2026-03-29T01:00:00Z" || plan.Latency != nil || len(plan.Goals) != 3 || plan.Goals[0].InBed != plan.Need {
			t.Fatal("spring gap or missing latency", plan)
		}
	}
}

// A night with no sleep says nothing about how long sleep takes, so it never
// becomes a planner night, and a zero efficiency never divides a goal.
func TestSleepPlanSkipsZeroEfficiencyNights(t *testing.T) {
	for _, tc := range []struct {
		asleep []int
		nights int
		status string
	}{
		{[]int{480, 480, 480, 0}, 3, "ok"},
		{[]int{480, 0, 0, 0}, 1, "unavailable"},
	} {
		state := store2.Empty()
		for i, minutes := range tc.asleep {
			day := 25 + i
			state.Records = append(state.Records, testutil.Record(t, "sleep", "reconciled", fmt.Sprintf("2026-03-%02d", day), fmt.Sprintf(`{"sleep":{"interval":{"startTime":"2026-03-%02dT23:00:00Z","endTime":"2026-03-%02dT07:00:00Z"},"summary":{"minutesAsleep":%d},"metadata":{"mainSleep":true}}}`, day-1, day, minutes)))
		}
		plan := engine(t, state, "2026-03-28T14:30:00Z", config.Defaults()).SleepPlan("2026-03-28")
		if plan.Nights != tc.nights || plan.Status != tc.status {
			t.Fatalf("%v: nights %d status %s", tc.asleep, plan.Nights, plan.Status)
		}
		if tc.status == "ok" && (*plan.Efficiency != 100 || plan.Goals[0].InBed != plan.Need) {
			t.Fatalf("%v: efficiency %v goals %+v", tc.asleep, *plan.Efficiency, plan.Goals)
		}
		if tc.status != "ok" && len(plan.Goals) != 0 {
			t.Fatalf("%v: goals %+v", tc.asleep, plan.Goals)
		}
	}
}

func planNap(t *testing.T, start, end string, minutes int) health.Record {
	t.Helper()
	return testutil.Record(t, "sleep", "reconciled", "2026-03-10", fmt.Sprintf(`{"sleep":{"interval":{"startTime":%q,"endTime":%q},"summary":{"minutesAsleep":%d},"metadata":{"mainSleep":false}}}`, start, end, minutes))
}
