package cli

import (
	"context"
	"encoding/json"
	"flag"
	"strconv"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

// rateActivity is `ghoops activity rate --id ID (--rpe N | --clear)`, the CLI side of /v2/ratings/<id>.
func (a *app) rateActivity(ctx context.Context, args []string) error {
	f := flags("activity rate")
	id := f.String("id", "", "")
	value := f.String("rpe", "", "")
	clear := f.Bool("clear", false, "")
	if err := parse(f, args); err != nil {
		return err
	}
	given := map[string]bool{}
	f.Visit(func(f *flag.Flag) { given[f.Name] = true })
	if given["rpe"] == *clear {
		return usageError{"activity rate needs exactly one of --rpe and --clear"}
	}
	if err := activities.ValidateRatingID(*id); err != nil {
		return v2report.EditError(err)
	}
	store := activities.Store{Dir: a.dir, Vault: a.store.Vault}
	if *clear {
		if err := store.DeleteRating(ctx, *id, a.now); err != nil {
			return v2report.EditError(err)
		}
		return a.emit(v2report.RatingResponse{Envelope: v2report.CommandEnvelope("rating", a.now), ID: *id})
	}
	n, err := strconv.Atoi(*value)
	if err != nil {
		return v2report.EditError(&activities.EditValidationError{Field: "rpe"})
	}
	raw, _ := json.Marshal(map[string]int{"rpe": n})
	rpe, err := activities.DecodeRating(raw)
	if err != nil {
		return v2report.EditError(err)
	}
	state, err := (store2.Store{Dir: a.dir, Vault: a.store.Vault}).Load()
	if err != nil {
		return v2report.NewError("store_unavailable")
	}
	file, err := configFile()
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
	stored, err := store.PutRating(ctx, *id, rpe, a.now, func(book activities.Book) error {
		engine.Activities, engine.Edits, engine.SleepEdits, engine.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
		_, err := engine.EditTarget(*id)
		return err
	})
	if err != nil {
		return v2report.EditError(err)
	}
	return a.emit(v2report.RatingResponse{Envelope: v2report.CommandEnvelope("rating", a.now), ID: *id, Rating: stored})
}
