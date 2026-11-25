package v2report

import (
	"errors"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/score"
)

type EditResponse struct {
	Envelope
	ID   string           `json:"id"`
	Edit *activities.Edit `json:"edit"`
}

func EditError(err error) *Error {
	var field *activities.EditValidationError
	var conflict *score.EditConflictError
	switch {
	case errors.As(err, &field):
		e := NewError("invalid_request")
		e.Message = field.Error()
		return e
	case errors.Is(err, activities.ErrEditChanged), errors.Is(err, activities.ErrSleepChanged):
		e := NewError("conflict")
		e.Message = err.Error()
		return e
	case errors.As(err, &conflict):
		e := NewError("conflict")
		e.Message = conflict.Error()
		return e
	case errors.Is(err, activities.ErrNotFound):
		return NewError("not_found")
	case errors.Is(err, activities.ErrCapacity):
		return NewError("storage_full")
	default:
		return NewError("store_unavailable")
	}
}

type RatingResponse struct {
	Envelope
	ID     string             `json:"id"`
	Rating *activities.Rating `json:"rating"`
}

type SleepEditResponse struct {
	Envelope
	Date      string                `json:"date"`
	SleepEdit *activities.SleepEdit `json:"sleep_edit"`
}
