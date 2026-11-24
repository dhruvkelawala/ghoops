package score_test

import (
	"fmt"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"testing"
	"time"
)

func TestStageTypicalEligibility(t *testing.T) {
	for _, n := range []int{6, 7} {
		state := store2.Empty()
		end := time.Date(2026, 3, 10, 0, 0, 0, 0, time.UTC)
		for k := 0; k <= 32; k++ {
			date := end.AddDate(0, 0, -k)
			kind := "STAGES"
			if k > n && k <= 30 {
				kind = "CLASSIC"
			}
			value := k * 10
			if k == 0 {
				value = 400
			}
			state.Records = append(state.Records, testutil.Record(t, "sleep", "reconciled", date.Format("2006-01-02"), fmt.Sprintf(`{"sleep":{"type":%q,"metadata":{"mainSleep":true},"interval":{"startTime":%q,"endTime":%q},"summary":{"stagesSummary":[{"type":"LIGHT","minutes":%d},{"type":"DEEP","minutes":10},{"type":"REM","minutes":20}]}}}`, kind, date.Add(-time.Hour*8).Format(time.RFC3339), date.Format(time.RFC3339), value)))
		}
		e := engine(t, state, "2026-03-10T14:30:00Z", config.Defaults())
		typical := e.Sleep("2026-03-10").StageTypical
		if typical.Nights != n || typical.Light.Nights != n || typical.Awake.Nights != 0 || typical.Awake.Low != nil {
			t.Fatal("eligibility or stage counts mismatch")
		}
		if n == 6 && (typical.Light.Low != nil || typical.Restorative.High != nil) {
			t.Fatal("range appeared before minimum")
		}
		if n == 7 && (typical.Light.Low == nil || *typical.Light.Low != 25 || *typical.Light.High != 55 || *typical.Restorative.Low != 30) {
			t.Fatal("prior nights or quantiles mismatch")
		}
	}
}
