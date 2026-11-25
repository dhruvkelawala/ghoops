package cli

import (
	"context"
	"flag"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) sleepCommand(ctx context.Context, args []string) error {
	if len(args) == 0 || (args[0] != "edit" && args[0] != "restore" && args[0] != "edits") {
		return a.readV2(ctx, "sleep", args)
	}
	f := flags("sleep " + args[0])
	date, start, end := "", "", ""
	days := 30
	if args[0] == "edits" {
		f.IntVar(&days, "days", 30, "")
	} else {
		f.StringVar(&date, "date", "", "")
	}
	if args[0] == "edit" {
		f.StringVar(&start, "start", "", "")
		f.StringVar(&end, "end", "", "")
	}
	if err := parse(f, args[1:]); err != nil {
		return err
	}
	store := activities.Store{Dir: a.dir, Vault: a.store.Vault}
	response := func(edit *activities.SleepEdit) error {
		return a.emit(v2report.SleepEditResponse{Envelope: v2report.CommandEnvelope("sleep_edit", a.now), Date: date, SleepEdit: edit})
	}
	if args[0] == "restore" {
		if err := store.DeleteSleepEdit(ctx, date, a.now); err != nil {
			return v2report.EditError(err)
		}
		return response(nil)
	}
	state, err := (store2.Store{Dir: a.dir, Vault: a.store.Vault}).Load()
	if err != nil {
		return v2report.NewError("store_unavailable")
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
			return v2report.NewError("store_unavailable")
		}
		type row struct {
			activities.SleepEdit
			Applies bool `json:"applies"`
		}
		rows := []row{}
		for _, edit := range book.SleepEdits {
			if !edit.UpdatedAt.Before(a.now.AddDate(0, 0, -days)) {
				rows = append(rows, row{edit, engine.SleepEditApplies(edit)})
			}
		}
		return a.emit(struct {
			v2report.Envelope
			SleepEdits []row `json:"sleep_edits"`
		}{v2report.CommandEnvelope("sleep_edits", a.now), rows})
	}
	given := map[string]bool{}
	f.Visit(func(f *flag.Flag) { given[f.Name] = true })
	stored, err := store.PutSleepEdit(ctx, date, a.now, activities.EditPrecondition{}, func(book activities.Book) (*activities.SleepEdit, error) {
		engine.Activities, engine.Edits, engine.SleepEdits, engine.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
		night := engine.SleepDetail(date)
		if night.Session == nil {
			return nil, activities.ErrNotFound
		}
		edit := activities.SleepEdit{Date: date, Start: night.Session.Start, End: night.Session.End}
		for _, field := range []struct {
			name, value string
			target      *time.Time
		}{{"start", start, &edit.Start}, {"end", end, &edit.End}} {
			if !given[field.name] {
				continue
			}
			value, err := time.Parse(time.RFC3339, field.value)
			if err != nil {
				return nil, &activities.EditValidationError{Field: field.name}
			}
			*field.target = value
		}
		return engine.ValidateSleepEdit(edit)
	})
	if err != nil {
		return v2report.EditError(err)
	}
	return response(stored)
}
