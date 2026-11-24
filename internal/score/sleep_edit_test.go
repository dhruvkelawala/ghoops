package score

import (
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestSleepEditRangeStopsAtNowAndLondonMidnight(t *testing.T) {
	state := store2.Empty()
	state.Records = append(state.Records, testutil.Record(t, "sleep", "reconciled", "2026-03-10", `{"sleep":{"interval":{"startTime":"2026-03-10T18:00:00Z","endTime":"2026-03-10T23:00:00Z"},"metadata":{"mainSleep":true},"stages":[{"startTime":"2026-03-10T18:00:00Z","endTime":"2026-03-10T23:00:00Z","type":"ASLEEP"}]}}`))
	for _, tc := range []struct{ now, end string }{
		{"2026-03-10T23:30:00Z", "2026-03-10T23:30:00Z"},
		{"2026-03-11T12:00:00Z", "2026-03-11T00:00:00Z"},
	} {
		now, _ := time.Parse(time.RFC3339, tc.now)
		e, err := New(state, now, config.Defaults())
		if err != nil {
			t.Fatal(err)
		}
		r := e.SleepDetail("2026-03-10").Session.EditRange
		if r == nil || r.LatestEnd.Format(time.RFC3339) != tc.end {
			t.Fatalf("range at %s: %v", tc.now, r)
		}
	}
}
