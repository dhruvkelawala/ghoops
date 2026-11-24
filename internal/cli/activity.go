package cli

import (
	"context"
	"crypto/rand"
	"errors"
	"flag"
	"fmt"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) activity(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return v2report.NewError("invalid_request")
	}
	switch args[0] {
	case "edit", "merge", "hide", "unhide", "restore", "edits":
		return a.editActivity(ctx, args)
	case "rate":
		return a.rateActivity(ctx, args[1:])
	}
	store := activities.Store{Dir: a.dir, Vault: a.store.Vault}
	f := flags("activity " + args[0])
	days := f.Int("days", 30, "")
	kind := f.String("type", "", "")
	start := f.String("start", "", "")
	end := f.String("end", "", "")
	name := f.String("name", "", "")
	origin := f.String("origin", "live", "")
	notes := f.String("notes", "", "")
	id := f.String("id", "", "")
	if err := parse(f, args[1:]); err != nil {
		return err
	}
	var result any
	var err error
	switch args[0] {
	case "list":
		if *days < 1 || *days > 400 {
			return v2report.NewError("invalid_request")
		}
		rows, e := store.List()
		err = e
		kept := []activities.Record{}
		for _, r := range rows {
			if !r.Start.Before(a.now.AddDate(0, 0, -*days)) {
				kept = append(kept, r)
			}
		}
		result = struct {
			v2report.Envelope
			Activities []activities.Record `json:"activities"`
		}{v2report.CommandEnvelope("activity", a.now), kept}
	case "add":
		if *origin == "" {
			return &v2report.Error{Code: "invalid_request", Message: "Invalid activity field: origin.", HTTP: intPointer(400)}
		}
		from, e1 := time.Parse(time.RFC3339, *start)
		until, e2 := time.Parse(time.RFC3339, *end)
		if e1 != nil || e2 != nil {
			return &v2report.Error{Code: "invalid_request", Message: "Invalid activity field: start or end.", HTTP: intPointer(400)}
		}
		if *name == "" {
			*name = activities.Sports[*kind]
		}
		b := make([]byte, 16)
		if _, err = rand.Read(b); err != nil {
			return err
		}
		b[6] = (b[6] & 15) | 64
		b[8] = (b[8] & 63) | 128
		uuid := fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:])
		var note *string
		f.Visit(func(flag *flag.Flag) {
			if flag.Name == "notes" {
				note = notes
			}
		})
		row, _, e := store.Put(ctx, activities.Upload{ID: uuid, ExerciseType: *kind, DisplayName: *name, Start: from, End: until, Pauses: []activities.Pause{}, Origin: *origin, Notes: note}, a.now)
		err = e
		result = struct {
			v2report.Envelope
			Activity activities.Record `json:"activity"`
		}{v2report.CommandEnvelope("activity", a.now), row}
	case "delete":
		if *id == "" {
			return v2report.NewError("invalid_request")
		}
		err = store.Delete(ctx, strings.TrimPrefix(*id, "goop-"), a.now)
		result = struct {
			v2report.Envelope
			ID string `json:"id"`
		}{v2report.CommandEnvelope("activity_deleted", a.now), *id}
	default:
		return v2report.NewError("not_found")
	}
	var invalid *activities.ValidationError
	if errors.As(err, &invalid) {
		return &v2report.Error{Code: "invalid_request", Message: invalid.Error(), HTTP: intPointer(400)}
	}
	if errors.Is(err, activities.ErrNotFound) {
		return v2report.NewError("not_found")
	}
	if err != nil {
		return v2report.NewError("store_unavailable")
	}
	return a.emit(result)
}
func intPointer(n int) *int { return &n }
