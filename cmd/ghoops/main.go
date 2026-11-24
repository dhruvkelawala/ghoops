package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"github.com/dhruvkelawala/ghoops/internal/cli"
)

var version = "dev"
var revision = "uncommitted"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	os.Exit(cli.Run(ctx, os.Args[1:], os.Stdin, os.Stdout, os.Stderr, cli.Options{Version: version, Revision: revision}))
}
