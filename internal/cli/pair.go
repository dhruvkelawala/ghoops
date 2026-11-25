package cli

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) pair(ctx context.Context, args []string, input io.Reader) error {
	devices := pairing.Devices{Dir: a.dir, Vault: a.store.Vault}
	if len(args) > 0 && args[0] == "devices" {
		if err := parse(flags("pair devices"), args[1:]); err != nil {
			return err
		}
		return a.pairedDevices(ctx, devices)
	}
	if len(args) > 0 && args[0] == "revoke" {
		id := ""
		if len(args) > 1 {
			id = args[1]
			if id == "" || id[0] == '-' || len(args) != 2 {
				return usageError{"pair revoke accepts one device ID"}
			}
		}
		if err := devices.Revoke(ctx, id); err != nil {
			if errors.Is(err, pairing.ErrDeviceNotFound) {
				e := v2report.NewError("not_found")
				e.Message = "Paired device not found."
				return e
			}
			return err
		}
		return a.emit(v2report.Pair{Envelope: v2report.CommandEnvelope("pair", a.now), Paired: false})
	}
	f := flags("pair")
	f.Bool("rotate", false, "")
	base := f.String("url", "", "")
	png := f.String("png", "", "")
	if err := parse(f, args); err != nil {
		return err
	}
	var rotate bool
	f.Visit(func(option *flag.Flag) { rotate = rotate || option.Name == "rotate" })
	if rotate || a.json {
		e := v2report.NewError("invalid_request")
		e.Message = "pair uses the terminal and cannot be combined with --json"
		if rotate {
			e.Message = "Revoke a device with ghoops pair revoke <device>, then run ghoops pair."
		}
		return e
	}
	tailnet, err := pairing.Discover(ctx, *base)
	if errors.Is(err, pairing.ErrInvalidURL) {
		e := v2report.NewError("invalid_request")
		e.Message = "url must use https:// and a valid host without credentials, query or fragment"
		return e
	}
	if err != nil {
		return err
	}
	if !tailnet.Configured && *base == "" {
		fmt.Fprintln(a.out, pairing.ServeCommand)
		return v2report.NewError("internal")
	}
	return a.enrol(ctx, input, devices, tailnet.URL, *png)
}

func (a *app) pairedDevices(ctx context.Context, devices pairing.Devices) error {
	records, legacy, err := devices.List(ctx, a.now)
	if err != nil {
		return err
	}
	rows := make([]v2report.PairedDevice, 0, len(records)+1)
	for _, device := range records {
		rows = append(rows, v2report.PairedDevice{ID: device.ID, Name: device.Name, State: device.State, Created: device.Created, Approved: device.Approved})
	}
	if legacy.Value != "" {
		rows = append(rows, v2report.PairedDevice{ID: "legacy", Name: "Pairing link", State: "active", Created: legacy.Created})
	}
	if a.json {
		return a.emit(v2report.PairDevices{Envelope: v2report.CommandEnvelope("pair_devices", a.now), Devices: rows})
	}
	for _, device := range rows {
		approved := "—"
		if device.Approved != nil {
			approved = device.Approved.Format(time.RFC3339)
		}
		if _, err := fmt.Fprintf(a.out, "%s\t%s\t%s\t%s\t%s\n", device.ID, device.Name, device.State, device.Created.Format(time.RFC3339), approved); err != nil {
			return err
		}
	}
	return nil
}
