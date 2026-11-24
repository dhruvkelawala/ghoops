package score

// Journal impact display constants (journal-spec §4, after WHOOP's Behavior Insights rule).
// No score uses them, so score_version does not change.
const (
	JournalWindowDays = 90
	JournalMinAnswers = 5
)

// JournalConstants is `score_constants.journal`.
type JournalConstants struct {
	WindowDays int `json:"window_days"`
	MinAnswers int `json:"min_answers"`
}

// JournalImpact is one behaviour's relation to the next morning's Recovery.
type JournalImpact struct {
	Key         string   `json:"key"`
	Status      string   `json:"status"`
	YesMornings int      `json:"yes_mornings"`
	NoMornings  int      `json:"no_mornings"`
	YesMean     *float64 `json:"yes_mean"`
	NoMean      *float64 `json:"no_mean"`
	Difference  *float64 `json:"difference"`
	Direction   *string  `json:"direction"`
}

// ComputeJournalImpact compares the reported Recovery after "yes" with that after "no" (journal-spec §4).
// Means, difference and direction stay null until both sides have JournalMinAnswers mornings.
func ComputeJournalImpact(key string, yes, no []float64) JournalImpact {
	out := JournalImpact{Key: key, Status: "insufficient", YesMornings: len(yes), NoMornings: len(no)}
	if len(yes) < JournalMinAnswers || len(no) < JournalMinAnswers {
		return out
	}
	mean := func(values []float64) float64 {
		sum := 0.0
		for _, v := range values {
			sum += v
		}
		return sum / float64(len(values))
	}
	y, n := mean(yes), mean(no)
	difference := round(y-n, 1)
	direction := "same"
	if difference > 0 {
		direction = "higher"
	} else if difference < 0 {
		direction = "lower"
	} else {
		difference = 0
	}
	out.Status = "ok"
	out.YesMean, out.NoMean = ptr(round(y, 1)), ptr(round(n, 1))
	out.Difference, out.Direction = &difference, &direction
	return out
}
