package v2report_test

import (
	"encoding/json"
	"fmt"
	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"net/url"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestComparisonContract(t *testing.T) {
	b, err := v2report.New(store2.Empty(), time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC), config.Defaults(), v2report.Options{})
	if err != nil {
		t.Fatal(err)
	}
	body, err := b.Build("day", url.Values{"date": {"2026-03-10"}})
	if err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	var day struct {
		Comparison struct {
			Window  int    `json:"window_days"`
			From    string `json:"from"`
			To      string `json:"to"`
			Metrics map[string]struct {
				Mean  *float64 `json:"mean"`
				Count int      `json:"available_days"`
			} `json:"metrics"`
		} `json:"comparison"`
	}
	if err = json.Unmarshal(raw, &day); err != nil {
		t.Fatal(err)
	}
	c := day.Comparison
	if c.Window != 30 || c.From != "2026-02-08" || c.To != "2026-03-09" || len(c.Metrics) != 15 {
		t.Fatal("comparison window or metrics missing")
	}
	for key, metric := range c.Metrics {
		if metric.Mean != nil || metric.Count != 0 {
			t.Fatalf("empty comparison %s is not null", key)
		}
	}
}

func TestComparisonMinimumAndStrength(t *testing.T) {
	for _, count := range []int{6, 7} {
		state := store2.Empty()
		for k := 0; k <= count; k++ {
			date := time.Date(2026, 3, 10-k, 0, 0, 0, 0, time.UTC)
			value := 50
			if k == 0 {
				value = 999
			}
			state.Records = append(state.Records, testutil.Record(t, "daily-resting-heart-rate", "raw", date.Format("2006-01-02"), fmt.Sprintf(`{"dailyRestingHeartRate":{"date":{"year":2026,"month":3,"day":%d},"beatsPerMinute":%d}}`, 10-k, value)))
		}
		b, err := v2report.New(state, time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC), config.Defaults(), v2report.Options{})
		if err != nil {
			t.Fatal(err)
		}
		day := b.Day("2026-03-10")
		metric := day.Comparison.Metrics.RHR
		if metric.Days != count || (metric.Mean != nil) != (count == 7) {
			t.Fatal("comparison minimum or count mismatch")
		}
		if count == 7 && *metric.Mean != 50 {
			t.Fatal("today entered prior comparison")
		}
	}
	for _, tc := range []struct {
		status   string
		workouts bool
		want     *int
	}{
		{"", false, nil}, {"permission_missing", false, nil}, {"unavailable", false, nil}, {"ok", false, intPtr(0)}, {"", true, intPtr(61)},
	} {
		state := store2.Empty()
		if tc.status != "" {
			state.Coverage = append(state.Coverage, cache.Coverage{Date: "2026-03-10", Type: "exercise", Stream: "list", Status: tc.status})
		}
		if tc.workouts {
			for i, interval := range [][2]string{{"12:00:00", "12:30:15"}, {"13:00:00", "13:30:15"}} {
				state.Records = append(state.Records, testutil.Record(t, "exercise", "raw", "2026-03-10", fmt.Sprintf(`{"name":"users/synthetic/dataTypes/exercise/dataPoints/%d","exercise":{"exerciseType":"WEIGHTLIFTING","interval":{"startTime":"2026-03-10T%sZ","endTime":"2026-03-10T%sZ"}}}`, i, interval[0], interval[1])))
			}
		}
		b, err := v2report.New(state, time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC), config.Defaults(), v2report.Options{})
		if err != nil {
			t.Fatal(err)
		}
		day := b.Day("2026-03-10")
		if (day.Strength == nil) != (tc.want == nil) || tc.want != nil && *day.Strength != *tc.want {
			t.Fatal("strength coverage or sum mismatch")
		}
		row := b.Days("2026-03-10", "2026-03-10").Days[0]
		if !reflect.DeepEqual(row.Strength, day.Strength) {
			t.Fatal("row strength differs from day")
		}
	}
}

func TestSnapshotRowAdditionsAndBudget(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	b, err := v2report.New(state, time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC), config.Defaults(), v2report.Options{})
	if err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	body, err := b.Build("snapshot", url.Values{})
	if err != nil {
		t.Fatal(err)
	}
	// The race detector on a shared, busy Mac makes wall time meaningless; the plain test pass checks the budget.
	if !raceEnabled && time.Since(start) >= 2*time.Second {
		t.Fatal("snapshot exceeded 2-second budget")
	}
	snapshot := body.(v2report.Snapshot)
	for _, row := range snapshot.Days.Days {
		day := b.Day(row.Date)
		if !reflect.DeepEqual(row.Consistency, intFromScore(day.Sleep.Consistency.Value)) || !reflect.DeepEqual(row.Strength, day.Strength) {
			t.Fatal("row does not match day")
		}
		if zones := day.Strain.Zones; zones != nil {
			if row.Zones13 == nil || *row.Zones13 != zones.Z1+zones.Z2+zones.Z3 || row.Zones45 == nil || *row.Zones45 != zones.Z4+zones.Z5 {
				t.Fatal("zone sums differ")
			}
		} else if row.Zones13 != nil || row.Zones45 != nil {
			t.Fatal("missing zones became zero")
		}
		deep, rem := day.Sleep.Stages["deep"].Minutes, day.Sleep.Stages["rem"].Minutes
		if deep != nil && rem != nil {
			if row.Restorative == nil || *row.Restorative != *deep+*rem {
				t.Fatal("restorative duration differs")
			}
		} else if row.Restorative != nil {
			t.Fatal("missing stages became zero")
		}
	}
}
func intPtr(v int) *int { return &v }
func intFromScore(v *float64) *int {
	if v == nil {
		return nil
	}
	return intPtr(int(*v))
}
