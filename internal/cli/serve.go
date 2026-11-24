package cli

import (
	"context"
	"fmt"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/serve"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

func (a *app) serve(ctx context.Context, args []string) error {
	f := flags("serve")
	port := f.Int("port", 8787, "")
	if err := parse(f, args); err != nil {
		return err
	}
	if *port < 1024 || *port > 65535 {
		return usageError{"port must be 1024 to 65535"}
	}
	file, err := configFile()
	if err != nil {
		return err
	}
	handler, err := serve.New(serve.Settings{Store: store2.Store{Dir: a.dir, Vault: a.store.Vault}, Config: file, Tokens: pairing.Tokens{Dir: a.dir, Vault: a.store.Vault}, Options: a.reportOptions, Now: time.Now, Log: a.err})
	if err != nil {
		return err
	}
	return handler.Run(ctx, fmt.Sprintf("127.0.0.1:%d", *port))
}
