package score

import (
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
)

type EditConflictError struct{ Target bool }

func (e *EditConflictError) Error() string {
	if e.Target {
		return "This activity is merged into another."
	}
	return "A merged activity is already part of another."
}

func (e *Engine) ValidateEdit(edit activities.Edit) (activities.Edit, error) {
	edit, err := edit.Validate(e.Now)
	if err != nil {
		return edit, err
	}
	target, err := e.EditTarget(edit.ID)
	if err != nil {
		return edit, err
	}
	for _, old := range e.Edits {
		for _, id := range old.MergeWith {
			if id == edit.ID {
				return edit, &EditConflictError{Target: true}
			}
		}
	}
	originals := map[string]Workout{}
	for _, w := range e.baseWorkouts() {
		originals[w.ID] = w
	}
	effective := map[string]Workout{}
	for _, w := range e.effectiveWorkouts() {
		effective[w.ID] = w
	}
	start, end := target.Original.Start, target.Original.End
	if edit.Start != nil {
		start, end = *edit.Start, *edit.End
	}
	earliest, latest := target.Original.Start, target.Original.End
	windows := []Workout{target.Original}
	for _, id := range edit.MergeWith {
		for _, old := range e.Edits {
			if old.ID == id && len(old.MergeWith) > 0 {
				return edit, &EditConflictError{}
			}
			if old.ID != edit.ID {
				for _, absorbed := range old.MergeWith {
					if absorbed == id {
						return edit, &EditConflictError{}
					}
				}
			}
		}
		candidate, found := effective[id]
		retained := false
		if target.Current.Edit != nil {
			for _, oldID := range target.Current.Edit.MergeWith {
				retained = retained || oldID == id
			}
		}
		adjacent := target.Previous != nil && target.Previous.ID == id || target.Next != nil && target.Next.ID == id
		if !found || (!retained && !adjacent) || start.After(candidate.Start) || end.Before(candidate.End) {
			return edit, &activities.EditValidationError{Field: "merge_with"}
		}
		original := originals[id]
		windows = append(windows, original)
		if original.Start.Before(earliest) {
			earliest = original.Start
		}
		if original.End.After(latest) {
			latest = original.End
		}
	}
	if start.Before(earliest.Add(-activities.EditMaxShiftMinutes * time.Minute)) {
		return edit, &activities.EditValidationError{Field: "start"}
	}
	if end.After(latest.Add(activities.EditMaxShiftMinutes * time.Minute)) {
		return edit, &activities.EditValidationError{Field: "end"}
	}
	overlaps := false
	for _, w := range windows {
		overlaps = overlaps || start.Before(w.End) && end.After(w.Start)
	}
	if !overlaps {
		return edit, &activities.EditValidationError{Field: "start"}
	}
	active := end.Sub(start)
	for _, pause := range target.Original.Pauses {
		a, b := pause.Start, pause.End
		if a.Before(start) {
			a = start
		}
		if b.After(end) {
			b = end
		}
		if b.After(a) {
			active -= b.Sub(a)
		}
	}
	if active < activities.ActiveMinMinutes*time.Minute || active > activities.ActiveMaxMinutes*time.Minute {
		return edit, &activities.EditValidationError{Field: "active_duration"}
	}
	return edit, nil
}

func (e *Engine) EditApplies(id string) bool {
	for _, w := range e.baseWorkouts() {
		if w.ID == id {
			return true
		}
	}
	return false
}
