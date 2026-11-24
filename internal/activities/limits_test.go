package activities

import (
	"errors"
	"fmt"
	"testing"
	"time"
)

func TestMergeIDsAtTheReportedLimit(t *testing.T) {
	limit := ReportedLimits().MergeMaxIDs
	for _, count := range []int{limit, limit + 1} {
		ids := make([]string, count)
		for i := range ids {
			ids[i] = fmt.Sprintf("neighbor-%d", i)
		}
		_, err := (Edit{ID: "x", MergeWith: ids}).Validate(time.Date(2026, 3, 12, 20, 30, 0, 0, time.UTC))
		if count == limit && err != nil {
			t.Fatal(err)
		}
		var invalid *EditValidationError
		if count > limit && (!errors.As(err, &invalid) || invalid.Field != "merge_with") {
			t.Fatalf("one past reported merge limit: %v", err)
		}
	}
}
