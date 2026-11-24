package report_test

import (
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/report"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestNonAwakeShortSegmentsPrecludeEveryTimelineInference(t *testing.T) {
	for _, timeline := range []string{"AWAKE", "RESTLESS", "LIGHT"} {
		for _, short := range []string{"LIGHT", "DEEP", "REM", "ASLEEP", "RESTLESS"} {
			t.Run(timeline+"/"+short, func(t *testing.T) {
				s, from, until, now := fixture(t)
				point := `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"stages":[{"type":"` + timeline + `","startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"}],"shortAwakenings":[{"type":"` + short + `","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}]}}`
				s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", point)}
				sleep := report.Days(s, from, until, now).Days[0].Sleep
				if sleep.Duration.Value != nil || sleep.Duration.Status != "missing" {
					t.Fatal("ambiguous timeline inferred asleep duration", sleep.Duration)
				}
				for key, m := range sleep.Stages {
					if m.Value != nil || m.Status != "missing" {
						t.Fatal("ambiguous timeline inferred stage minutes", key, m)
					}
				}
			})
		}
	}
}

func TestNonAwakeShortSegmentsWarnWithoutDiscardingIndependentSummaries(t *testing.T) {
	const warning = "non-AWAKE short-awakening segments preclude sleep timeline interpretation"
	for _, tc := range []struct {
		name, summary string
		asleep, light float64
		stageStatus   string
	}{
		{"no measurements", `{}`, -1, -1, "missing"},
		{"observed asleep only", `{"minutesAsleep":"100"}`, 100, -1, "missing"},
		{"partial stage summary", `{"minutesAsleep":"100","stagesSummary":[{"type":"LIGHT","minutes":"60"}]}`, 100, 60, "partial"},
		{"complete stage summary", `{"stagesSummary":[{"type":"LIGHT","minutes":"100"},{"type":"AWAKE","minutes":"20"}]}`, 100, 100, "available"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s, from, until, now := fixture(t)
			point := `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"stages":[{"type":"LIGHT","startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"}],"shortAwakenings":[{"type":"LIGHT","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:05:00Z"}],"summary":` + tc.summary + `}}`
			s.Records = []health.Record{testutil.Record(t, "sleep", "reconciled", "2026-10-12", point)}
			result := report.Days(s, from, until, now)
			sleep := result.Days[0].Sleep
			if !strings.Contains(strings.Join(sleep.Duration.Warnings, ";"), warning) {
				t.Fatal("missing static timeline warning", sleep.Duration.Warnings)
			}
			if tc.asleep < 0 {
				if sleep.Duration.Value != nil || sleep.Duration.Status != "missing" {
					t.Fatal("time in bed became asleep duration", sleep.Duration)
				}
			} else if sleep.Duration.Value == nil || *sleep.Duration.Value != tc.asleep || sleep.Duration.Status != "available" || sleep.Duration.Stale {
				t.Fatal("independent asleep summary discarded", sleep.Duration)
			}
			if tc.light < 0 {
				for key, m := range sleep.Stages {
					if m.Value != nil {
						t.Fatal("ambiguous timeline substituted for absent stage summary", key, m)
					}
				}
			} else if m := sleep.Stages["LIGHT"]; m.Value == nil || *m.Value != tc.light || m.Status != tc.stageStatus || m.Stale {
				t.Fatal("independent stage summary discarded", m)
			}
			var text strings.Builder
			report.Text(&text, result, false)
			if !strings.Contains(text.String(), warning) {
				t.Fatal("text report omitted timeline warning")
			}
		})
	}
}
