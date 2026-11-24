package score_test

import (
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/score"
)

func TestWeekTargetStatusTable(t *testing.T) {
	for _, tc := range []struct {
		name                   string
		count, missing, target int
		complete               bool
		want                   string
	}{
		{"reached mid-week", 5, 0, 5, false, "met"},
		{"reached with a missing night", 5, 2, 5, true, "met"},
		{"short mid-week", 1, 0, 5, false, "open"},
		{"short mid-week even if out of reach", 0, 0, 5, false, "open"},
		{"short and the missing night could not help", 3, 1, 5, true, "not_met"},
		{"short with nothing missing", 4, 0, 5, true, "not_met"},
		{"short but the missing night could have met it", 4, 1, 5, true, "no_data"},
		{"a week with no data", 0, 7, 5, true, "no_data"},
	} {
		if got := score.WeekCountStatus(tc.count, tc.missing, tc.target, tc.complete); got != tc.want {
			t.Errorf("%s: got %s, want %s", tc.name, got, tc.want)
		}
	}
	minutes := func(n int) *int { return &n }
	for _, tc := range []struct {
		name            string
		credit          *int
		missing, target int
		complete        bool
		want            string
	}{
		{"reached mid-week", minutes(150), 0, 150, false, "met"},
		{"reached with missing days", minutes(222), 3, 150, true, "met"},
		{"short mid-week", minutes(10), 0, 150, false, "open"},
		{"short with every day known", minutes(149), 0, 150, true, "not_met"},
		{"short with one day missing", minutes(149), 1, 150, true, "no_data"},
		{"a week with no zones", nil, 7, 150, true, "no_data"},
	} {
		if got := score.WeekMinutesStatus(tc.credit, tc.missing, tc.target, tc.complete); got != tc.want {
			t.Errorf("%s: got %s, want %s", tc.name, got, tc.want)
		}
	}
}
