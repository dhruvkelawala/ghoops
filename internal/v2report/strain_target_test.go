package v2report_test

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestStrainTargetConfigVersionAndClosedDay(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		intent    string
		low, high float64
		position  string
	}{
		{"maintain", 13.3, 16.3, "below"},
		{"restore", 10.3, 13.3, "within"},
	} {
		cfg := config.Defaults()
		cfg.StrainIntent = tc.intent
		b, err := v2report.New(state, fixtureTime("2026-03-10T14:30:00Z"), cfg, v2report.Options{})
		if err != nil {
			t.Fatal(err)
		}
		d := b.Day("2026-03-10")
		target := d.StrainTarget
		if target.Low == nil || *target.Low != tc.low || target.High == nil || *target.High != tc.high || target.Position == nil || *target.Position != tc.position || target.Intent != tc.intent {
			t.Fatal("day target differs from contract", target)
		}
		past := b.Day("2026-03-09")
		if past.Cycle.Status != "closed" || past.StrainTarget.Status != "ok" || past.StrainTarget.Low == nil || past.StrainTarget.Intent != tc.intent {
			t.Fatal("past target missing", past.StrainTarget)
		}
		snapshot := b.Snapshot()
		for _, envelope := range []v2report.Envelope{d.Envelope, snapshot.Envelope, snapshot.Day.Envelope, snapshot.Days.Envelope, snapshot.Sleep.Envelope, snapshot.Status.Envelope, snapshot.Workouts.Envelope, b.Brief(d.Date, false, "morning").Envelope} {
			if envelope.ScoreVersion != "2.4.1" {
				t.Fatalf("%s version %q", envelope.Kind, envelope.ScoreVersion)
			}
			if envelope.Kind != "brief" && (envelope.Config == nil || envelope.Config.StrainIntent != tc.intent) {
				t.Fatal("score config not echoed")
			}
		}
	}
}
