package score

import (
	"sort"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
)

type WorkoutOriginal struct {
	ID    string    `json:"id,omitempty"`
	Kind  string    `json:"kind,omitempty"`
	Type  *string   `json:"exercise_type"`
	Name  *string   `json:"display_name"`
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}

type WorkoutEdit struct {
	ExerciseType *string    `json:"exercise_type"`
	Start        *time.Time `json:"start"`
	End          *time.Time `json:"end"`
	Notes        *string    `json:"notes"`
	MergeWith    []string   `json:"merge_with"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

type EditTarget struct {
	Original Workout
	Current  Workout
	Previous *Workout
	Next     *Workout
}

func (e *Engine) EditTarget(id string) (*EditTarget, error) {
	var original *Workout
	first, last := e.add(e.DefaultDate(), 1-activities.EditHorizonDays), e.DefaultDate()
	for _, w := range e.baseWorkouts() {
		if w.ID == id && w.CycleDate >= first && w.CycleDate <= last {
			original = &w
			break
		}
	}
	if original == nil {
		return nil, activities.ErrNotFound
	}
	target := &EditTarget{Original: *original, Current: *original}
	for _, w := range e.effectiveWorkouts() {
		if w.ID == id {
			target.Current = w
			break
		}
	}
	for _, w := range e.Workouts(target.Current.CycleDate, false) {
		if w.ID == id {
			continue
		}
		if w.Start.Before(target.Current.Start) {
			if target.Current.Start.Sub(w.End) <= activities.MergeMaxGapMinutes*time.Minute && (target.Previous == nil || w.Start.After(target.Previous.Start)) {
				target.Previous = &w
			}
		} else if w.Start.Sub(target.Current.End) <= activities.MergeMaxGapMinutes*time.Minute && (target.Next == nil || w.Start.Before(target.Next.Start)) {
			target.Next = &w
		}
	}
	return target, nil
}

func (e *Engine) baseWorkouts() []Workout {
	out := []Workout{}
	for _, r := range e.recorded() {
		w := r.Workout
		w.Original = &WorkoutOriginal{Type: w.Type, Name: w.Name, Start: w.Start, End: w.End}
		w.Merged = []WorkoutOriginal{}
		w.Pauses = []activities.Pause{}
		if w.Type != nil {
			if alias, ok := e.Config.SportAliases[*w.Type]; ok {
				w.Type = ptr(alias)
				w.Name = ptr(activities.Sports[alias])
				w.Category = category(alias)
			}
		}
		out = append(out, w)
	}
	for _, a := range e.Activities {
		origin := a.Origin
		if origin == "" {
			origin = "live"
		}
		w := Workout{Kind: "goop", ID: "goop-" + a.ID, Type: ptr(a.ExerciseType), Name: workoutName(a.ExerciseType, a.DisplayName), Category: category(a.ExerciseType), CycleDate: e.workoutDate(a.Start), Start: a.Start, End: a.End, Source: "goop", Notes: a.Notes, Origin: &origin, Pauses: append([]activities.Pause{}, a.Pauses...), Merged: []WorkoutOriginal{}}
		w.Original = &WorkoutOriginal{Type: w.Type, Name: w.Name, Start: w.Start, End: w.End}
		w = e.windowFields(w)
		out = append(out, w)
	}
	return out
}

func (e *Engine) effectiveWorkouts() []Workout {
	out := e.baseWorkouts()
	index := map[string]int{}
	for i, w := range out {
		index[w.ID] = i
	}
	for _, edit := range e.Edits {
		i, ok := index[edit.ID]
		if !ok {
			continue
		}
		w := &out[i]
		ids := append([]string{}, edit.MergeWith...)
		w.Edit = &WorkoutEdit{ExerciseType: edit.ExerciseType, Start: edit.Start, End: edit.End, Notes: edit.Notes, MergeWith: ids, UpdatedAt: edit.UpdatedAt}
		w.Edited = edit.ExerciseType != nil || edit.Start != nil || len(edit.MergeWith) > 0
		if edit.ExerciseType != nil {
			w.Type = edit.ExerciseType
			w.Name = ptr(activities.Sports[*edit.ExerciseType])
			w.Category = category(*edit.ExerciseType)
		}
		if edit.Start != nil && edit.End != nil {
			w.Start, w.End = *edit.Start, *edit.End
		}
		if edit.Notes != nil {
			w.Notes = edit.Notes
		}
		w.hidden = edit.Hidden
		for _, id := range edit.MergeWith {
			if j, found := index[id]; found {
				out[j].absorbedBy = edit.ID
				original := *out[j].Original
				original.ID, original.Kind = out[j].ID, out[j].Kind
				w.Merged = append(w.Merged, original)
			}
		}
		sort.SliceStable(w.Merged, func(i, j int) bool { return w.Merged[i].Start.Before(w.Merged[j].Start) })
		*w = e.windowFields(*w)
		if w.Kind == "recorded" && (edit.Start != nil || len(edit.MergeWith) > 0) {
			w.Active = nil
		}
	}
	for _, rating := range e.Ratings {
		if i, ok := index[rating.ID]; ok {
			rpe := rating.RPE
			out[i].RPE = &rpe
		}
	}
	for i := range out {
		if out[i].absorbedBy != "" {
			out[i].hidden = true
		}
		if out[i].Kind != "recorded" {
			continue
		}
		for _, g := range out {
			if g.Kind == "goop" && out[i].absorbedBy != g.ID && g.absorbedBy != out[i].ID && goopHidesRecorded(out[i], g) {
				out[i].hidden = true
				break
			}
		}
	}
	return out
}

func (e *Engine) windowFields(w Workout) Workout {
	w.CycleDate = e.workoutDate(w.Start)
	w.Elapsed = round(w.End.Sub(w.Start).Minutes(), 1)
	pauses := []activities.Pause{}
	active := w.End.Sub(w.Start).Minutes()
	for _, p := range w.Pauses {
		if p.Start.Before(w.Start) {
			p.Start = w.Start
		}
		if p.End.After(w.End) {
			p.End = w.End
		}
		if p.End.After(p.Start) {
			pauses = append(pauses, p)
			active -= p.End.Sub(p.Start).Minutes()
		}
	}
	w.Pauses = pauses
	if w.Kind == "goop" {
		w.Active = ptr(round(active, 1))
	}
	return w
}

func (e *Engine) workoutDate(start time.Time) string {
	date := start.In(e.loc).Format("2006-01-02")
	cycle, _ := e.cycleStart(date)
	if start.Before(cycle) {
		date = e.add(date, -1)
	}
	return date
}
