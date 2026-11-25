package cli

import (
	"context"
	"flag"
	"net/url"
	"os"
	"path/filepath"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) readV2(ctx context.Context, kind string, args []string) error {
	params, err := readParameters(kind, args)
	if err != nil {
		return err
	}
	builder, err := a.builder(ctx, kind == "journal" || kind == "snapshot")
	if err != nil {
		return err
	}
	body, err := builder.Build(kind, params)
	if err != nil {
		return err
	}
	return a.emit(body)
}

// builder loads the store, config, activities and, when asked, the journal for a v2 body.
func (a *app) builder(ctx context.Context, withJournal bool) (*v2report.Builder, error) {
	state, profileID, err := (store2.Store{Dir: a.dir, Vault: a.store.Vault}).LoadWithProfile()
	if err != nil {
		return nil, v2report.NewError("store_unavailable")
	}
	file, err := configFile(a.dir)
	if err != nil {
		return nil, err
	}
	cfg, err := file.Load()
	if err != nil {
		return nil, err
	}
	options := a.reportOptions(ctx)
	options.Server.ProfileID = profileID
	book, err := (activities.Store{Dir: a.dir, Vault: a.store.Vault}).Load()
	options.Activities, options.Edits, options.SleepEdits, options.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
	if err != nil {
		return nil, v2report.NewError("store_unavailable")
	}
	if withJournal {
		if options.Journal, err = (journal.Store{Dir: a.dir, Vault: a.store.Vault}).Load(); err != nil {
			return nil, v2report.NewError("store_unavailable")
		}
	}
	return v2report.New(state, a.now, cfg, options)
}
func readParameters(kind string, args []string) (url.Values, error) {
	f := flags(kind)
	switch kind {
	case "heart_rate":
		f.String("date", "", "")
		f.String("start", "", "")
		f.String("end", "", "")
	case "day", "sleep", "week":
		f.String("date", "", "")
	case "brief":
		f.String("date", "", "")
		f.Bool("include-values", false, "")
		f.String("part", "morning", "")
	case "days", "workouts":
		addRange(f, 30)
	case "journal":
		f.String("days", "", "")
	}
	if err := parse(f, args); err != nil {
		return nil, err
	}
	params := url.Values{}
	f.Visit(func(flag *flag.Flag) {
		name := flag.Name
		if name == "include-values" {
			name = "include_values"
		}
		params.Set(name, flag.Value.String())
	})
	return params, nil
}
func (a *app) reportOptions(ctx context.Context) v2report.Options {
	status, err := a.auth.Status(ctx)
	auth := v2report.Auth{Authorized: status.Authorized, State: status.State, Refreshable: status.Refreshable, Missing: status.MissingScopes, Partial: status.PartialPermissions}
	if err != nil {
		auth.State = "unavailable"
	}
	home, _ := os.UserHomeDir()
	installed := a.dir == defaultStateDir(home)
	if installed {
		for _, label := range []string{"io.ghealth.collect", "io.ghealth.serve"} {
			info, err := os.Stat(filepath.Join(home, "Library", "LaunchAgents", label+".plist"))
			installed = installed && err == nil && info.Mode().IsRegular()
		}
	}
	return v2report.Options{Auth: auth, ScheduleInstalled: installed, Server: v2report.Server{Version: a.options.Version, Revision: a.options.Revision}}
}
