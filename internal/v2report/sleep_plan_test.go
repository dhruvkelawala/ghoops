package v2report_test

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestSleepPlanDayAndSnapshotCycleContract(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	b, err := v2report.New(state, fixtureTime("2026-03-10T14:30:00Z"), config.Defaults(), v2report.Options{})
	if err != nil {
		t.Fatal(err)
	}
	if b.Day("2026-03-09").SleepPlan != nil {
		t.Fatal("closed day has a sleep plan")
	}
	plan := b.Snapshot().Day.SleepPlan
	if plan == nil || plan.Need != 483 || plan.Nights != 12 || plan.Efficiency == nil || *plan.Efficiency != 92.5 || plan.Latency != nil || len(plan.Goals) != 3 || plan.Goals[0].InBed != 522 {
		t.Fatal("snapshot's open cycle plan differs", plan)
	}
}
