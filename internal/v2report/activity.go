package v2report

import (
	"errors"

	"github.com/dhruvkelawala/ghoops/internal/activities"
)

func ActivityError(err error) *Error {
	var field *activities.ValidationError
	switch {
	case errors.As(err, &field):
		e := NewError("invalid_request")
		e.Message = field.Error()
		return e
	case errors.Is(err, activities.ErrConflict):
		return NewError("conflict")
	case errors.Is(err, activities.ErrNotFound):
		return NewError("not_found")
	case errors.Is(err, activities.ErrCapacity):
		return NewError("storage_full")
	default:
		return StoreError(err)
	}
}
