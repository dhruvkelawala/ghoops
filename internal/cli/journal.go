package cli

import (
	"context"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

// journalCommand runs `ghoops journal show|set|behaviours` (journal-spec §5).
func (a *app) journalCommand(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return usageError{"expected journal show, set or behaviours"}
	}
	store := journal.Store{Dir: a.dir, Vault: a.store.Vault}
	switch args[0] {
	case "show":
		return a.readV2(ctx, "journal", args[1:])
	case "behaviours":
		var book journal.Book
		var err error
		switch {
		case len(args) == 1:
			book, err = store.Load()
		case len(args) == 2 && args[1] == "reset":
			book, err = store.SetBehaviours(ctx, nil, a.now)
		case len(args) == 3 && args[1] == "set":
			keys, parseErr := journal.ParseBehaviours(args[2])
			if parseErr != nil {
				return v2report.JournalError(parseErr)
			}
			book, err = store.SetBehaviours(ctx, keys, a.now)
		default:
			return usageError{"expected journal behaviours [set KEY[,KEY...] | reset]"}
		}
		if err != nil {
			return v2report.NewError("store_unavailable")
		}
		return a.emit(v2report.JournalCatalogue(book, v2report.CommandEnvelope("journal_behaviours", a.now)))
	case "set":
		f := flags("journal set")
		date := f.String("date", "", "")
		if err := f.Parse(args[1:]); err != nil {
			return usageError{err.Error()}
		}
		builder, err := a.builder(ctx, false)
		if err != nil {
			return err
		}
		today := builder.DefaultDate()
		if *date == "" {
			day, _ := time.Parse("2006-01-02", today)
			*date = day.AddDate(0, 0, -1).Format("2006-01-02")
		}
		if !journal.DateAllowed(*date, today, activities.EditHorizonDays) {
			return v2report.NewError("not_found")
		}
		entry, err := store.Put(ctx, *date, a.now, journal.Precondition{}, func(stored map[string]bool) (map[string]bool, error) {
			return journal.ParseArguments(stored, f.Args())
		})
		if err != nil {
			return v2report.JournalError(err)
		}
		return a.emit(v2report.JournalEntryResponse{Envelope: v2report.CommandEnvelope("journal_entry", a.now), Date: *date, Entry: entry})
	}
	return usageError{"expected journal show, set or behaviours"}
}
