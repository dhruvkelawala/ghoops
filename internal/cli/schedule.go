package cli

import (
	"context"
	"os"

	"github.com/dhruvkelawala/ghoops/internal/schedule"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) schedule(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return usageError{"schedule requires install, uninstall or status"}
	}
	if err := parse(flags("schedule"), args[1:]); err != nil {
		return err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	manager := schedule.Manager{Home: home}
	switch args[0] {
	case "install":
		err = manager.Install(ctx)
	case "uninstall":
		err = manager.Uninstall(ctx)
	case "status":
	default:
		return usageError{"unknown schedule command"}
	}
	if err != nil {
		return err
	}
	return a.emit(v2report.Schedule{Envelope: v2report.CommandEnvelope("schedule", a.now), Agents: manager.Status(ctx)})
}
