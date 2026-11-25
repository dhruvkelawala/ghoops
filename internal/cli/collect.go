package cli

import (
	"context"
	"errors"
	"flag"
	"fmt"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/collect"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/schedule"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) collectV2(ctx context.Context, args []string) error {
	f := flags("collect")
	rangeFlags := addRange(f, 3)
	quiet := f.Bool("quiet", false, "")
	if err := parse(f, args); err != nil {
		return err
	}
	if err := schedule.TrimLogs(a.dir); err != nil {
		return err
	}
	options := collect.Options{Now: a.options.Now}
	explicit := false
	f.Visit(func(f *flag.Flag) {
		if f.Name != "quiet" {
			explicit = true
		}
	})
	if explicit {
		var err error
		options.From, options.Until, err = a.dateRange(f, rangeFlags)
		if err != nil {
			return err
		}
	}
	if !*quiet {
		options.Progress = func(stream, status string, records int) {
			fmt.Fprintf(a.err, "%s %s %d records\n", stream, status, records)
		}
	}
	client, ok := a.fetcher.(*health.Client)
	if !ok {
		return errors.New("collector client unavailable")
	}
	result, err := collect.Run(ctx, store2.Store{Dir: a.dir, Vault: a.store.Vault}, client, a.auth, options)
	if errors.Is(err, auth.ErrAccountChanged) {
		failure := v2report.NewError("collect_failed")
		failure.Message = auth.ErrAccountChanged.Error()
		return failure
	}
	if result.Kind != "" {
		if emitErr := a.emit(result); emitErr != nil {
			return emitErr
		}
	}
	return err
}
