package cli

import (
	"encoding/json"
	"errors"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/collect"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

type commandErrorBody = v2report.ErrorBody

func (a *app) failV2(err error) int {
	var response *v2report.Error
	if errors.Is(err, secure.ErrKeychainAccess) {
		response = v2report.StoreError(err)
	} else if !errors.As(err, &response) {
		code := "internal"
		var usage usageError
		switch {
		case errors.As(err, &usage):
			code = "invalid_request"
		case errors.Is(err, store2.ErrCollectInProgress):
			code = "collect_in_progress"
		case errors.Is(err, collect.ErrFailed), errors.Is(err, collect.ErrPartial):
			code = "collect_failed"
		}
		response = v2report.NewError(code)
	}
	now := a.now
	if now.IsZero() {
		now = time.Now()
	}
	_ = json.NewEncoder(a.err).Encode(response.Body(now))
	if response.HTTP != nil && (*response.HTTP == 400 || *response.HTTP == 404 || *response.HTTP == 409 || *response.HTTP == 413) {
		return 2
	}
	return 1
}
