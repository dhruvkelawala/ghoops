package cli

import (
	"context"
	"flag"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) editActivity(ctx context.Context, args []string) error {
	f := flags("activity " + args[0])
	id, kind, start, end, notes, mergeIDs, with := "", "", "", "", "", "", ""
	bandWindow, clearNotes := false, false
	days := 30
	if args[0] == "edits" {
		f.IntVar(&days, "days", 30, "")
	} else {
		f.StringVar(&id, "id", "", "")
	}
	if args[0] == "edit" {
		f.StringVar(&kind, "type", "", "")
		f.StringVar(&start, "start", "", "")
		f.StringVar(&end, "end", "", "")
		f.StringVar(&notes, "notes", "", "")
		f.StringVar(&mergeIDs, "merge-with", "", "")
		f.BoolVar(&bandWindow, "band-window", false, "")
		f.BoolVar(&clearNotes, "clear-notes", false, "")
	}
	if args[0] == "merge" {
		f.StringVar(&with, "with", "", "")
	}
	if err := parse(f, args[1:]); err != nil {
		return err
	}
	store := activities.Store{Dir: a.dir, Vault: a.store.Vault}
	if args[0] == "restore" {
		if _, err := (activities.Edit{ID: id}).Validate(a.now); err != nil {
			return v2report.EditError(err)
		}
		if err := store.DeleteEdit(ctx, id, a.now); err != nil {
			return v2report.EditError(err)
		}
		return a.emit(v2report.EditResponse{Envelope: v2report.CommandEnvelope("edit", a.now), ID: id})
	}
	state, err := (store2.Store{Dir: a.dir, Vault: a.store.Vault}).Load()
	if err != nil {
		return v2report.StoreError(err)
	}
	file, err := configFile(a.dir)
	if err != nil {
		return err
	}
	cfg, err := file.Load()
	if err != nil {
		return v2report.NewError("store_unavailable")
	}
	engine, err := score.New(state, a.now, cfg)
	if err != nil {
		return v2report.NewError("store_unavailable")
	}
	if args[0] == "edits" {
		if days < 1 || days > 400 {
			return v2report.NewError("invalid_request")
		}
		book, err := store.Load()
		if err != nil {
			return v2report.StoreError(err)
		}
		engine.Activities, engine.Edits, engine.SleepEdits, engine.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
		type row struct {
			activities.Edit
			Applies bool `json:"applies"`
		}
		rows := []row{}
		for _, edit := range book.Edits {
			if !edit.UpdatedAt.Before(a.now.AddDate(0, 0, -days)) {
				rows = append(rows, row{edit, engine.EditApplies(edit.ID)})
			}
		}
		return a.emit(struct {
			v2report.Envelope
			Edits []row `json:"edits"`
		}{v2report.CommandEnvelope("edits", a.now), rows})
	}
	given := map[string]bool{}
	f.Visit(func(f *flag.Flag) { given[f.Name] = true })
	if given["start"] != given["end"] || bandWindow && (given["start"] || given["end"]) || clearNotes && given["notes"] {
		return v2report.NewError("invalid_request")
	}
	stored, err := store.UpdateEdit(ctx, a.now, activities.EditPrecondition{}, func(book activities.Book) (activities.Edit, error) {
		edit := activities.Edit{ID: id, MergeWith: []string{}}
		for _, old := range book.Edits {
			if old.ID == id {
				edit = old
				break
			}
		}
		engine.Activities, engine.Edits, engine.SleepEdits, engine.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
		switch args[0] {
		case "edit":
			if given["type"] {
				edit.ExerciseType = &kind
				if kind == "band" {
					edit.ExerciseType = nil
				}
			}
			if given["start"] {
				a, err := time.Parse(time.RFC3339, start)
				if err != nil {
					return edit, &activities.EditValidationError{Field: "start"}
				}
				b, err := time.Parse(time.RFC3339, end)
				if err != nil {
					return edit, &activities.EditValidationError{Field: "end"}
				}
				edit.Start, edit.End = &a, &b
			}
			if bandWindow {
				edit.Start, edit.End = nil, nil
			}
			if given["notes"] {
				edit.Notes = &notes
			}
			if clearNotes {
				edit.Notes = nil
			}
			if given["merge-with"] {
				edit.MergeWith = strings.Split(mergeIDs, ",")
				if mergeIDs == "" {
					edit.MergeWith = []string{}
				}
			}
		case "merge":
			target, err := engine.EditTarget(id)
			if err != nil {
				return edit, err
			}
			var candidate *score.Workout
			for _, w := range []*score.Workout{target.Previous, target.Next} {
				if w != nil && w.ID == with {
					candidate = w
				}
			}
			if candidate == nil {
				return edit, &activities.EditValidationError{Field: "merge_with"}
			}
			a, b := target.Current.Start, target.Current.End
			if candidate.Start.Before(a) {
				a = candidate.Start
			}
			if candidate.End.After(b) {
				b = candidate.End
			}
			edit.Start, edit.End = &a, &b
			if candidate.Kind != "detected" {
				edit.MergeWith = append(append([]string{}, edit.MergeWith...), candidate.ID)
			}
		case "hide", "unhide":
			edit.Hidden = args[0] == "hide"
		}
		return engine.ValidateEdit(edit)
	})
	if err != nil {
		return v2report.EditError(err)
	}
	return a.emit(v2report.EditResponse{Envelope: v2report.CommandEnvelope("edit", a.now), ID: id, Edit: stored})
}
