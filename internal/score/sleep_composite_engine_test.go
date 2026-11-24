package score_test

import (
	"math"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
)

// Two late bedtimes in the week before D lower consistency, so the composite falls below hours
// vs. needed, and in composite mode Recovery takes the composite as its sleep input
// (composite-sleep-spec §9). Default mode on the same nights keeps hours vs. needed.
func TestCompositeModeFeedsRecovery(t *testing.T) {
	const now, day = "2026-03-10T14:30:00Z", "2026-03-10"
	state := fixtureState(t, "full")
	plain := engine(t, state, now, config.Defaults())
	edits := []activities.SleepEdit{}
	for _, date := range []string{"2026-03-06", "2026-03-08"} {
		session := plain.SleepDetail(date).Session
		if session == nil {
			t.Fatalf("store_full has no main sleep on %s", date)
		}
		edits = append(edits, activities.SleepEdit{Date: date, Start: session.Start.Add(4 * time.Hour), End: session.End, UpdatedAt: session.End})
	}
	composite := config.Defaults()
	composite.SleepScoreMode = config.SleepScoreComposite
	modes := map[string]*score.Engine{}
	for name, cfg := range map[string]config.Values{"default": config.Defaults(), "composite": composite} {
		e := engine(t, state, now, cfg)
		e.SleepEdits = edits
		modes[name] = e
	}

	before := plain.Sleep(day).Consistency.Value
	sleep := modes["composite"].Sleep(day)
	if sleep.PerformanceComposite == nil || sleep.Performance.Value == nil || before == nil || sleep.Consistency.Value == nil {
		t.Fatal("missing sleep values")
	}
	value := *sleep.PerformanceComposite.Value
	if *sleep.Consistency.Value >= *before || value >= *sleep.Performance.Value {
		t.Fatalf("consistency %v (was %v), composite %v, hours vs. needed %v", *sleep.Consistency.Value, *before, value, *sleep.Performance.Value)
	}
	want := score.ComputeSleepComposite(sleep.Performance, sleep.Consistency.Value, sleep.Efficiency)
	if *want.Value != value {
		t.Fatalf("engine composite %v, formula %v", value, *want.Value)
	}

	withComposite, withHours := modes["composite"].Recovery(day), modes["default"].Recovery(day)
	if withComposite.Components == nil || withHours.Components == nil {
		t.Fatal("recovery not computed")
	}
	if withComposite.Components.Sleep != value || *withComposite.Inputs.Sleep != value {
		t.Fatalf("recovery sleep input %v / %v, want the composite %v", withComposite.Components.Sleep, *withComposite.Inputs.Sleep, value)
	}
	if withHours.Components.Sleep != *sleep.Performance.Value || modes["default"].Sleep(day).PerformanceComposite != nil {
		t.Fatalf("default mode sleep input %v, want hours vs. needed %v", withHours.Components.Sleep, *sleep.Performance.Value)
	}
	shift := withHours.Components.Base - withComposite.Components.Base
	if expected := score.WeightSleep * (*sleep.Performance.Value - value); math.Abs(shift-expected) > 0.1 || *withComposite.Value >= *withHours.Value {
		t.Fatalf("recovery %v → %v, base shift %v, want %v", *withHours.Value, *withComposite.Value, shift, expected)
	}
	t.Logf("consistency %v → %v; hours vs. needed %v, composite %v; recovery %v → %v", *before, *sleep.Consistency.Value, *sleep.Performance.Value, value, *withHours.Value, *withComposite.Value)
	if score.VersionFor(composite) != score.Version+"+"+score.CompositeRevision || score.VersionFor(config.Defaults()) != score.Version {
		t.Fatal("score version does not follow the mode")
	}
}
