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
	manager := schedule.Manager{Home: home, Run: a.options.Launchctl}
	switch args[0] {
	case "install", "uninstall":
		if a.dir != defaultStateDir(home) {
			failure := v2report.NewError("invalid_request")
			failure.Message = "schedule manages only the default profile"
			return failure
		}
		if args[0] == "install" {
			err = manager.Install(ctx)
		} else {
			err = manager.Uninstall(ctx)
		}
	case "status":
	default:
		return usageError{"unknown schedule command"}
	}
	if err != nil {
		return err
	}
	return a.emit(v2report.Schedule{Envelope: v2report.CommandEnvelope("schedule", a.now), Profile: "default", Agents: manager.Status(ctx)})
}
