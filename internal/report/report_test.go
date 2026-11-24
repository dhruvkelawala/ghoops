package report_test

import (
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/report"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func fixture(t *testing.T) (cache.State, time.Time, time.Time, time.Time) {
	t.Helper()
	loc, _ := time.LoadLocation("Europe/London")
	from, _ := time.ParseInLocation("2006-01-02", "2026-10-12", loc)
	now := from.Add(16 * time.Hour)
	s := cache.Empty()
	s.Timezone = loc.String()
	for _, k := range health.Kinds {
		streams := []string{"raw"}
		if k.Reconcile {
			streams = append(streams, "reconciled")
		}
		for _, stream := range streams {
			s.Coverage = append(s.Coverage, cache.Coverage{Type: k.ID, Stream: stream, Date: "2026-10-12", Status: "ok", SuccessAt: &now})
		}
	}
	return s, from, from.AddDate(0, 0, 1), now
}

func TestMissingZeroStaleAndDailyConflicts(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = append(s.Records, testutil.Record(t, "steps", "reconciled", "2026-10-12", `{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":"0"}}`))
	d := report.Days(s, from, until, now).Days[0]
	if d.Steps.Value == nil || *d.Steps.Value != 0 || d.Steps.Status != "available" || d.HRV.Value != nil || d.HRV.Status != "missing" {
		t.Fatal("missing fabricated as zero", d.Steps, d.HRV)
	}
	d = report.Days(s, from, until, now.Add(25*time.Hour)).Days[0]
	if !d.Steps.Stale {
		t.Fatal("stale records not marked")
	}
	for _, v := range []string{"42", "44"} {
		s.Records = append(s.Records, testutil.Record(t, "daily-heart-rate-variability", "raw", "2026-10-12", `{"dailyHeartRateVariability":{"date":{"year":2026,"month":10,"day":12},"averageHeartRateVariabilityMilliseconds":`+v+`}}`))
	}
	d = report.Days(s, from, until, now).Days[0]
	if d.HRV.Status != "conflict" || d.HRV.Value != nil {
		t.Fatal("conflicting sources averaged")
	}
}

func TestSleepDurationStagesAwakeningAndNoTimeInBedInference(t *testing.T) {
	s, from, until, now := fixture(t)
	raw := `{"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"},"stages":[{"type":"LIGHT","startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"}],"shortAwakenings":[{"type":"AWAKE","startTime":"2026-10-11T23:00:00Z","endTime":"2026-10-11T23:05:00Z"}],"metadata":{"processed":false}}}`
	s.Records = append(s.Records, testutil.Record(t, "sleep", "reconciled", "2026-10-12", raw))
	d := report.Days(s, from, until, now).Days[0]
	if d.Sleep.Duration.Value == nil || *d.Sleep.Duration.Value != 115 || *d.Sleep.Stages["AWAKE"].Value != 5 || *d.Sleep.Stages["LIGHT"].Value != 115 || len(d.Sleep.Duration.Warnings) == 0 {
		t.Fatal("awake overlay counted as sleep", d.Sleep)
	}
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"}}}`)}
	d = report.Days(s, from, until, now).Days[0]
	if d.Sleep.Duration.Value != nil {
		t.Fatal("time in bed reported as asleep")
	}
}

func TestWorkoutDedupeSourceAndLiftingAreIndependent(t *testing.T) {
	s, from, until, now := fixture(t)
	for _, row := range []string{`{"name":"synthetic-one","dataSource":{"device":{"formFactor":"WATCH"},"recordingMethod":"ACTIVELY_MEASURED"},"exercise":{"exerciseType":"WORKOUT","interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T13:00:00Z"}}}`, `{"name":"synthetic-two","dataSource":{"application":{"packageName":"synthetic.lifting"},"recordingMethod":"MANUAL"},"exercise":{"exerciseType":"STRENGTH_TRAINING","activeDuration":"3000s","interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T13:00:00Z"}}}`} {
		s.Records = append(s.Records, testutil.Record(t, "exercise", "raw", "2026-10-12", row))
	}
	d := report.Days(s, from, until, now).Days[0]
	if len(d.Exercise.Workouts) != 1 {
		t.Fatal("duplicate workouts", d.Exercise)
	}
	w := d.Exercise.Workouts[0]
	if !w.Lifting || w.Wearable == nil || !*w.Wearable || len(w.Sources) != 2 || w.MergedRecords != 2 || w.ActiveMinutes == nil || *w.ActiveMinutes != 50 {
		t.Fatal("classification", w)
	}
}

func TestHRVMethodsStaySeparateAndTrendsUseObservedDays(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = append(s.Records, testutil.Record(t, "heart-rate-variability", "raw", "2026-10-12", `{"heartRateVariability":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"standardDeviationMilliseconds":60}}`))
	r := report.Days(s, from, until.AddDate(0, 0, 1), now)
	if r.Days[0].HRV.Value != nil || r.Days[0].SampleHRV.Value != nil || r.Days[0].SampleSDNN.Value == nil || *r.Days[0].SampleSDNN.Value != 60 || r.Trends["hrv_rmssd_ms"].Mean != nil {
		t.Fatal("HRV methods conflated")
	}
	var out strings.Builder
	report.Text(&out, r, true)
	if strings.Contains(strings.ToLower(out.String()), "score") {
		t.Fatal("invented score")
	}
}

func TestOverlappingSleepAndUnknownStagesCannotCreateTotals(t *testing.T) {
	s, from, until, now := fixture(t)
	row := testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"},"summary":{"minutesAsleep":"120","stagesSummary":[{"type":"LIGHT","minutes":"120"}]}}}`)
	s.Records = []health.Record{row, row}
	d := report.Days(s, from, until, now).Days[0]
	if d.Sleep.Duration.Status != "conflict" || d.Sleep.Duration.Value != nil || d.Sleep.Stages["LIGHT"].Value != nil {
		t.Fatal("overlapping sleep double counted")
	}
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"},"stages":[{"type":"SLEEP_STAGE_TYPE_UNSPECIFIED","startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"}]}}`)}
	d = report.Days(s, from, until, now).Days[0]
	if d.Sleep.Duration.Value != nil || len(d.Sleep.Duration.Warnings) == 0 {
		t.Fatal("unknown stages became observed zero")
	}
}

func TestInvalidCachedIntegerMeasurementsAreNotAvailable(t *testing.T) {
	for _, tc := range []struct {
		id, stream, raw string
		metric          func(report.Daily) report.Metric
	}{
		{"heart-rate", "reconciled", `{"heartRate":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"beatsPerMinute":"301"}}`, func(d report.Daily) report.Metric { return d.HR.Mean }},
		{"heart-rate", "reconciled", `{"heartRate":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"beatsPerMinute":"0"}}`, func(d report.Daily) report.Metric { return d.HR.Min }},
		{"steps", "reconciled", `{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":"1000001"}}`, func(d report.Daily) report.Metric { return d.Steps }},
		{"steps", "reconciled", `{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":1.5}}`, func(d report.Daily) report.Metric { return d.Steps }},
		{"daily-resting-heart-rate", "raw", `{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12},"beatsPerMinute":62.5}}`, func(d report.Daily) report.Metric { return d.RHR }},
	} {
		t.Run(tc.id+"/"+tc.raw, func(t *testing.T) {
			s, from, until, now := fixture(t)
			s.Records = []health.Record{testutil.Record(t, tc.id, tc.stream, "2026-10-12", tc.raw)}
			m := tc.metric(report.Days(s, from, until, now).Days[0])
			if m.Value != nil || m.Status == "available" {
				t.Fatal("cached invalid measurement published", m)
			}
		})
	}
}

func TestInvalidCachedDataTakesPrecedenceOverValidValuesAndConflicts(t *testing.T) {
	for _, tc := range []struct {
		name, id, stream string
		raw              []string
		metric           func(report.Daily) report.Metric
	}{
		{"conflicting daily values", "daily-resting-heart-rate", "raw", []string{
			`{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12},"beatsPerMinute":62.5}}`,
			`{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12},"beatsPerMinute":"60"}}`,
			`{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12},"beatsPerMinute":"61"}}`,
		}, func(d report.Daily) report.Metric { return d.RHR }},
		{"agreeing daily values", "daily-resting-heart-rate", "raw", []string{
			`{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12},"beatsPerMinute":62.5}}`,
			`{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12},"beatsPerMinute":"60"}}`,
		}, func(d report.Daily) report.Metric { return d.RHR }},
		{"valid sample mean", "heart-rate", "reconciled", []string{
			`{"heartRate":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"beatsPerMinute":62.5}}`,
			`{"heartRate":{"sampleTime":{"physicalTime":"2026-10-12T12:01:00Z"},"beatsPerMinute":"60"}}`,
		}, func(d report.Daily) report.Metric { return d.HR.Mean }},
		{"cross-day step conflict", "steps", "reconciled", []string{
			`{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":1.5}}`,
			`{"steps":{"interval":{"startTime":"2026-10-12T23:00:00Z","endTime":"2026-10-13T01:00:00Z"},"count":"60"}}`,
		}, func(d report.Daily) report.Metric { return d.Steps }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, reverse := range []bool{false, true} {
				s, from, until, now := fixture(t)
				for _, raw := range tc.raw {
					s.Records = append(s.Records, testutil.Record(t, tc.id, tc.stream, "2026-10-12", raw))
				}
				if reverse {
					for i, j := 0, len(s.Records)-1; i < j; i, j = i+1, j-1 {
						s.Records[i], s.Records[j] = s.Records[j], s.Records[i]
					}
				}
				summary := report.Days(s, from, until, now)
				m := tc.metric(summary.Days[0])
				if m.Status != "invalid_data" || m.Value != nil {
					t.Fatal("invalid_data replaced or numeric value leaked", m)
				}
				for _, trend := range summary.Trends {
					if trend.AvailableDays != 0 || trend.Mean != nil {
						t.Fatal("invalid data entered trend", trend)
					}
				}
			}
		})
	}
}

func TestInvalidCachedSleepTakesPrecedenceOverOverlapConflictsAndStageValues(t *testing.T) {
	for name, overlap := range map[string]bool{"with overlap": true, "without overlap": false} {
		t.Run(name, func(t *testing.T) {
			s, from, until, now := fixture(t)
			invalid := testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"summary":{"minutesAsleep":"120","stagesSummary":[{"type":"AWAKE","minutes":"120"}]}}}`)
			valid := testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"summary":{"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"100"},{"type":"AWAKE","minutes":"20"}]}}}`)
			s.Records = []health.Record{invalid, valid}
			if overlap {
				s.Records = append(s.Records, valid)
			}
			summary := report.Days(s, from, until, now)
			sleep := summary.Days[0].Sleep
			if sleep.Duration.Status != "invalid_data" || sleep.Duration.Value != nil {
				t.Fatal("invalid sleep status replaced", sleep.Duration)
			}
			for key, m := range sleep.Stages {
				if m.Status != "invalid_data" || m.Value != nil {
					t.Fatal("invalid sleep stage status replaced or value leaked", key, m)
				}
			}
			if summary.Trends["sleep_minutes"].AvailableDays != 0 || summary.Trends["sleep_minutes"].Mean != nil {
				t.Fatal("invalid sleep entered trend")
			}
		})
	}
}

func TestCachedSampledRMSSDBoundsDoNotInventDailyBounds(t *testing.T) {
	for _, value := range []string{`0`, `201`} {
		t.Run(value, func(t *testing.T) {
			s, from, until, now := fixture(t)
			s.Records = []health.Record{
				testutil.Record(t, "heart-rate-variability", "raw", "2026-10-12", `{"heartRateVariability":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"rootMeanSquareOfSuccessiveDifferencesMilliseconds":`+value+`}}`),
				testutil.Record(t, "daily-heart-rate-variability", "raw", "2026-10-12", `{"dailyHeartRateVariability":{"date":{"year":2026,"month":10,"day":12},"averageHeartRateVariabilityMilliseconds":201}}`),
			}
			d := report.Days(s, from, until, now).Days[0]
			if d.SampleHRV.Value != nil || d.SampleHRV.Status == "available" {
				t.Fatal("invalid sampled RMSSD published")
			}
			if d.HRV.Value == nil || *d.HRV.Value != 201 || d.HRV.Status != "available" {
				t.Fatal("invented daily HRV bound", d.HRV)
			}
		})
	}
}

func TestCachedImpossibleSleepIsInvalidRatherThanPartialOrAvailable(t *testing.T) {
	for _, summary := range []string{
		`"stagesSummary":[{"type":"LIGHT","minutes":"240"}]`,
		`"stagesSummary":[{"type":"LIGHT","minutes":"80"},{"type":"REM","minutes":"60"}]`,
		`"stagesSummary":[{"type":"LIGHT","minutes":"60.5"}]`,
		`"minutesAsleep":"121","stagesSummary":[{"type":"LIGHT","minutes":"60"}]`,
	} {
		t.Run(summary, func(t *testing.T) {
			s, from, until, now := fixture(t)
			s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"},"summary":{`+summary+`}}}`)}
			d := report.Days(s, from, until, now).Days[0]
			if d.Sleep.Duration.Value != nil || d.Sleep.Duration.Status != "invalid_data" {
				t.Fatal("invalid sleep not identified", d.Sleep.Duration)
			}
			for _, m := range d.Sleep.Stages {
				if m.Value != nil || m.Status != "invalid_data" {
					t.Fatal("impossible cached stage published", m)
				}
			}
		})
	}
}

func TestCachedAsleepAndStageSummaryContradictionsAreInvalid(t *testing.T) {
	for _, summary := range []string{
		`"minutesAsleep":"120","stagesSummary":[{"type":"AWAKE","minutes":"120"}]`,
		`"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"70"},{"type":"REM","minutes":"31"}]`,
		`"minutesAsleep":"100","stagesSummary":[{"type":"RESTLESS","minutes":"21"}]`,
	} {
		t.Run(summary, func(t *testing.T) {
			s, from, until, now := fixture(t)
			s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"summary":{`+summary+`}}}`)}
			sleep := report.Days(s, from, until, now).Days[0].Sleep
			if sleep.Duration.Status != "invalid_data" || sleep.Duration.Value != nil {
				t.Fatal("contradictory summary published", sleep.Duration)
			}
			for _, m := range sleep.Stages {
				if m.Status != "invalid_data" || m.Value != nil {
					t.Fatal("contradictory stages published", m)
				}
			}
		})
	}
}

func TestKnownAsleepWithPartialStagesDoesNotInventMissingStages(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"summary":{"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"60"},{"type":"AWAKE","minutes":"10"}]}}}`)}
	sleep := report.Days(s, from, until, now).Days[0].Sleep
	if sleep.Duration.Status != "available" || sleep.Duration.Value == nil || *sleep.Duration.Value != 100 {
		t.Fatal("valid asleep summary rejected", sleep.Duration)
	}
	for key, want := range map[string]float64{"LIGHT": 60, "AWAKE": 10} {
		m := sleep.Stages[key]
		if m.Status != "partial" || m.Value == nil || *m.Value != want {
			t.Fatal("partial stages lost", key, m)
		}
	}
	if sleep.Stages["REM"].Value != nil || sleep.Stages["DEEP"].Value != nil || sleep.Stages["ASLEEP"].Value != nil {
		t.Fatal("missing stages fabricated", sleep)
	}
}

func TestPartialSleepStagesDoNotBecomeCompleteSleepDuration(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"},"summary":{"stagesSummary":[{"type":"LIGHT","minutes":"60"}]}}}`)}
	d := report.Days(s, from, until, now).Days[0]
	m := d.Sleep.Stages["LIGHT"]
	if m.Value == nil || *m.Value != 60 || m.Status != "partial" {
		t.Fatal("legitimate partial stage lost or overstated", m)
	}
	if d.Sleep.Duration.Value != nil || d.Sleep.Duration.Status != "missing" || d.Sleep.Stages["REM"].Value != nil {
		t.Fatal("unobserved sleep fabricated", d.Sleep)
	}
}

func TestAlmostCompleteSleepStageSummaryDoesNotInferAsleep(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T11:00:00.300Z"},"summary":{"stagesSummary":[{"type":"LIGHT","minutes":"60"}]}}}`)}
	summary := report.Days(s, from, until, now)
	sleep := summary.Days[0].Sleep
	if sleep.Duration.Value != nil || sleep.Duration.Status != "missing" {
		t.Fatal("uncovered subsecond duration inferred as asleep", sleep.Duration)
	}
	if m := sleep.Stages["LIGHT"]; m.Value == nil || *m.Value != 60 || m.Status != "partial" || m.Records != 1 {
		t.Fatal("almost complete observed stage not partial", m)
	}
	if sleep.Stages["REM"].Value != nil || summary.Trends["sleep_minutes"].Mean != nil {
		t.Fatal("missing stage or asleep trend fabricated", summary)
	}
}

func TestExactCompleteSleepStageSummaryInfersAsleep(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00.300Z","endTime":"2026-10-12T11:01:00.300Z"},"summary":{"stagesSummary":[{"type":"LIGHT","minutes":"60"},{"type":"AWAKE","minutes":"1"},{"type":"DEEP","minutes":"0"}]}}}`)}
	summary := report.Days(s, from, until, now)
	sleep := summary.Days[0].Sleep
	if sleep.Duration.Value == nil || *sleep.Duration.Value != 60 || sleep.Duration.Status != "available" {
		t.Fatal("exact complete stage summary lost asleep duration", sleep.Duration)
	}
	for key, want := range map[string]float64{"LIGHT": 60, "AWAKE": 1, "DEEP": 0} {
		m := sleep.Stages[key]
		if m.Value == nil || *m.Value != want || m.Status != "available" || m.Records != 1 {
			t.Fatal("exact complete observed stage lost", key, m)
		}
	}
	if sleep.Stages["REM"].Value != nil || summary.Trends["sleep_minutes"].Mean == nil || *summary.Trends["sleep_minutes"].Mean != 60 {
		t.Fatal("missing stage fabricated or complete asleep trend lost", summary)
	}
}

func TestKnownSleepStagesSurviveMissingStageMinutes(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"summary":{"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"60"},{"type":"REM"},{"type":"DEEP","minutes":"0"}]}}}`)}
	sleep := report.Days(s, from, until, now).Days[0].Sleep
	for key, want := range map[string]float64{"LIGHT": 60, "DEEP": 0} {
		m := sleep.Stages[key]
		if m.Value == nil || *m.Value != want || m.Status != "partial" || m.Records != 1 {
			t.Fatal("observed stage discarded because another stage has no minutes", key, m)
		}
	}
	if sleep.Duration.Value == nil || *sleep.Duration.Value != 100 || sleep.Duration.Status != "available" {
		t.Fatal("observed asleep summary lost", sleep.Duration)
	}
	if sleep.Stages["REM"].Value != nil || sleep.Stages["AWAKE"].Value != nil || sleep.Stages["ASLEEP"].Value != nil {
		t.Fatal("unmeasured stages fabricated", sleep)
	}
}

func TestMissingStageMinutesPreventAsleepInferenceEvenWhenKnownTotalMatches(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"summary":{"stagesSummary":[{"type":"REM"},{"type":"LIGHT","minutes":"120"}]}}}`)}
	sleep := report.Days(s, from, until, now).Days[0].Sleep
	if sleep.Duration.Value != nil || sleep.Duration.Status != "missing" || sleep.Stages["REM"].Value != nil {
		t.Fatal("absent stage minutes treated as observed zero", sleep)
	}
	if m := sleep.Stages["LIGHT"]; m.Value == nil || *m.Value != 120 || m.Status != "partial" {
		t.Fatal("known stage total matching elapsed time falsely complete", m)
	}
}

func TestOmittedStepCountIsObservedZeroButEmptyStreamIsMissing(t *testing.T) {
	for _, tc := range []struct {
		name, end, status string
		wantZero          bool
	}{
		{"stationary interval", "2026-10-12T12:01:00Z", "available", true},
		{"stationary cross-day interval", "2026-10-13T00:01:00Z", "conflict", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, from, until, now := fixture(t)
			if d := report.Days(s, from, until, now).Days[0]; d.Steps.Value != nil || d.Steps.Status != "missing" {
				t.Fatal("empty stream fabricated steps", d.Steps)
			}
			s.Records = []health.Record{testutil.Record(t, "steps", "reconciled", "2026-10-12", `{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"`+tc.end+`"}}}`)}
			d := report.Days(s, from, until, now).Days[0]
			if d.Steps.Status != tc.status {
				t.Fatal("wrong true-zero status", d.Steps)
			}
			if tc.wantZero {
				if d.Steps.Value == nil || *d.Steps.Value != 0 || d.Steps.Records != 1 {
					t.Fatal("stationary interval not observed zero", d.Steps)
				}
			} else if d.Steps.Value != nil {
				t.Fatal("cross-day count allocated", d.Steps)
			}
		})
	}
}

func TestInvalidCachedShortAwakeningsCannotPublishSleep(t *testing.T) {
	for _, awake := range []string{
		`{"type":"AWAKE","startTime":"2026-10-12T09:00:00Z","endTime":"2026-10-12T09:05:00Z"}`,
		`{"type":"AWAKE","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T10:30:00Z"}`,
		`{"type":"NOT_A_STAGE","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}`,
	} {
		t.Run(awake, func(t *testing.T) {
			s, from, until, now := fixture(t)
			s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"stages":[{"type":"LIGHT","startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"}],"shortAwakenings":[`+awake+`]}}`)}
			sleep := report.Days(s, from, until, now).Days[0].Sleep
			if sleep.Duration.Status != "invalid_data" || sleep.Duration.Value != nil {
				t.Fatal("invalid awakening published", sleep.Duration)
			}
			for _, m := range sleep.Stages {
				if m.Status != "invalid_data" || m.Value != nil {
					t.Fatal("invalid awakening published stages", m)
				}
			}
		})
	}
}

func TestValidAwakeningsCrossStagesAndDeduplicateOverlappingEvents(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"stages":[{"type":"LIGHT","startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T11:00:00Z"},{"type":"REM","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T12:00:00Z"}],"shortAwakenings":[{"type":"AWAKE","startTime":"2026-10-12T11:03:00Z","endTime":"2026-10-12T11:10:00Z"},{"type":"AWAKE","startTime":"2026-10-12T10:55:00Z","endTime":"2026-10-12T11:05:00Z"},{"type":"AWAKE","startTime":"2026-10-12T10:55:00Z","endTime":"2026-10-12T11:05:00Z"}]}}`)}
	sleep := report.Days(s, from, until, now).Days[0].Sleep
	for key, want := range map[string]float64{"AWAKE": 15, "LIGHT": 55, "REM": 50} {
		m := sleep.Stages[key]
		if m.Status != "available" || m.Value == nil || *m.Value != want {
			t.Fatal("awakening overlay changed", key, m)
		}
	}
	if sleep.Duration.Status != "available" || sleep.Duration.Value == nil || *sleep.Duration.Value != 105 {
		t.Fatal("awakening duration changed", sleep.Duration)
	}
}

func TestImpossibleCachedSleepTimelineCannotPublishStages(t *testing.T) {
	s, from, until, now := fixture(t)
	s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", `{"sleep":{"interval":{"startTime":"2026-10-11T22:00:00Z","endTime":"2026-10-12T00:00:00Z"},"stages":[{"type":"LIGHT","startTime":"2026-10-11T21:00:00Z","endTime":"2026-10-12T00:00:00Z"}]}}`)}
	d := report.Days(s, from, until, now).Days[0]
	if d.Sleep.Duration.Status != "invalid_data" || d.Sleep.Duration.Value != nil || d.Sleep.Stages["LIGHT"].Value != nil {
		t.Fatal("impossible timeline not identified", d.Sleep)
	}
}

func TestCachedMeasurementsRequireValidObservationAndRequestedType(t *testing.T) {
	for _, tc := range []struct{ id, raw string }{
		{"steps", `{"steps":{"interval":{"startTime":"2026-10-12T12:01:00Z","endTime":"2026-10-12T12:00:00Z"}}}`},
		{"heart-rate", `{"heartRate":{"beatsPerMinute":"62"}}`},
		{"steps", `{"heartRate":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"beatsPerMinute":"62"}}`},
	} {
		t.Run(tc.id+"/"+tc.raw, func(t *testing.T) {
			s, from, until, now := fixture(t)
			s.Records = []health.Record{testutil.Record(t, tc.id, "reconciled", "2026-10-12", tc.raw)}
			d := report.Days(s, from, until, now).Days[0]
			m := d.Steps
			if tc.id == "heart-rate" {
				m = d.HR.Mean
			}
			if m.Value != nil || m.Status != "invalid_data" {
				t.Fatal("invalid cached observation not excluded", m)
			}
		})
	}
}

func TestGenericWorkoutDoesNotBridgeIncompatibleExerciseTypes(t *testing.T) {
	s, from, until, now := fixture(t)
	for _, kind := range []string{"RUNNING", "WORKOUT", "STRENGTH_TRAINING"} {
		s.Records = append(s.Records, testutil.Record(t, "exercise", "raw", "2026-10-12", `{"exercise":{"exerciseType":"`+kind+`","interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T13:00:00Z"}}}`))
	}
	d := report.Days(s, from, until, now).Days[0]
	if len(d.Exercise.Workouts) != 2 || d.Exercise.Workouts[0].Lifting {
		t.Fatal("generic record merged different specific workouts")
	}
}
