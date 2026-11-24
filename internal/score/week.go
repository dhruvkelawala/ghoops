package score

// WeekVigorousWeight is how many zone minutes one minute in zones 4–5 earns towards the weekly target (week-review-spec.md D5).
const WeekVigorousWeight = 2

// WeekCountStatus judges a target counted in nights or days (week-review-spec.md §3.3).
// Missing nights or days count against not_met only when even all of them could not have reached the target.
func WeekCountStatus(count, missing, target int, complete bool) string {
	switch {
	case count >= target:
		return "met"
	case !complete:
		return "open"
	case count+missing < target:
		return "not_met"
	}
	return "no_data"
}

// WeekMinutesStatus judges the zone-minute target. A missing day could hold any number of minutes, so any missing day leaves a finished, unmet week at no_data.
func WeekMinutesStatus(credit *int, missing, target int, complete bool) string {
	switch {
	case credit != nil && *credit >= target:
		return "met"
	case !complete:
		return "open"
	case missing == 0:
		return "not_met"
	}
	return "no_data"
}
