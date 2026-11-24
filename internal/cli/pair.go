package cli

import (
	"context"
	"errors"
	"fmt"

	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) pair(ctx context.Context, args []string) error {
	tokens := pairing.Tokens{Dir: a.dir, Vault: a.store.Vault}
	if len(args) > 0 && args[0] == "revoke" {
		if err := parse(flags("pair revoke"), args[1:]); err != nil {
			return err
		}
		if err := tokens.Revoke(ctx); err != nil {
			return err
		}
		return a.emit(v2report.Pair{Envelope: v2report.CommandEnvelope("pair", a.now), Paired: false})
	}
	f := flags("pair")
	rotate := f.Bool("rotate", false, "")
	base := f.String("url", "", "")
	png := f.String("png", "", "")
	if err := parse(f, args); err != nil {
		return err
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
	token, err := tokens.Pair(ctx, *rotate, a.now)
	if err != nil {
		return err
	}
	link := pairing.Link(tailnet, token)
	var pngPath *string
	if !a.json || *png != "" {
		matrix, err := pairing.Matrix(link)
		if err != nil {
			return err
		}
		if *png != "" {
			if err = pairing.PNG(*png, matrix); err != nil {
				return err
			}
			pngPath = png
		}
		if !a.json {
			if err = pairing.Terminal(a.out, matrix); err != nil {
				return err
			}
		}
	}
	if a.json {
		return a.emit(v2report.Pair{Envelope: v2report.CommandEnvelope("pair", a.now), Paired: true, PairDetails: &v2report.PairDetails{URL: tailnet.URL, Name: tailnet.Name, Link: link, Created: token.Created, Configured: tailnet.Configured, PNG: pngPath}})
	}
	fmt.Fprintln(a.out, link)
	fmt.Fprintln(a.out, "Scan with the iPhone camera, or AirDrop/paste this link into the app.")
	if !tailnet.Configured {
		fmt.Fprintln(a.out, pairing.ServeCommand)
		return v2report.NewError("internal")
	}
	return nil
}
