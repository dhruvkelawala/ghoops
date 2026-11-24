package cli

import (
	"errors"
	"os"
	"path/filepath"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func configFile() (config.File, error) {
	home, err := os.UserHomeDir()
	return config.File{Path: filepath.Join(home, ".config", "ghealth", "config.json")}, err
}

func (a *app) configure(args []string) error {
	file, err := configFile()
	if err != nil {
		return err
	}
	var values config.Values
	switch {
	case len(args) == 1 && args[0] == "show":
		values, err = file.Load()
	case len(args) == 3 && args[0] == "set":
		values, err = file.Set(args[1], args[2])
	case len(args) == 2 && args[0] == "unset":
		values, err = file.Unset(args[1])
	default:
		return usageError{"expected config show, set KEY VALUE, or unset KEY"}
	}
	if errors.Is(err, config.ErrInvalid) {
		return usageError{"invalid configuration key or value"}
	}
	if err != nil {
		return err
	}
	return a.emit(v2report.Config{Envelope: v2report.CommandEnvelope("config", a.now), Values: values, Defaults: config.Defaults(), Path: file.Path})
}
