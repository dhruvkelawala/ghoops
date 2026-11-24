package cli

import (
	"context"
	"errors"
	"os"
	"strings"

	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) workout(ctx context.Context, args []string) error {
	if len(args) == 0 || args[0] != "export-tcx" {
		return v2report.NewError("not_found")
	}
	f := flags("workout export-tcx")
	id := f.String("id", "", "")
	path := f.String("output", "", "")
	partial := f.Bool("partial", false, "")
	if err := parse(f, args[1:]); err != nil {
		return err
	}
	if *id == "" || *id == "." || *id == ".." || strings.ContainsAny(*id, "/\\?#\x00\r\n") || *path == "" {
		return usageError{"export-tcx requires --id and --output"}
	}
	out, err := secure.OpenPrivate(*path, os.O_CREATE|os.O_EXCL|os.O_WRONLY)
	if err != nil {
		return errors.New("cannot create private export file; path must not already exist")
	}
	saved := false
	defer func() {
		out.Close()
		if !saved {
			os.Remove(*path)
		}
	}()
	client, ok := a.fetcher.(*health.Client)
	if !ok {
		return v2report.NewError("internal")
	}
	data, err := client.ExportTCX(ctx, *id, *partial)
	if err != nil {
		var api *health.APIError
		if errors.As(err, &api) && api.Status == 403 {
			return v2report.NewError("permission_missing")
		}
		return err
	}
	if _, err = out.Write(data); err != nil {
		return err
	}
	if err = out.Sync(); err != nil {
		return err
	}
	if err = out.Close(); err != nil {
		return err
	}
	saved = true
	return a.emit(v2report.Export{Envelope: v2report.CommandEnvelope("export", a.now), Exported: "tcx", ID: *id, Path: *path, Bytes: len(data), Plaintext: true})
}
