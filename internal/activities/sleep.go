package activities

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

const SleepMinMinutes = 60

type SleepEdit struct {
	Date      string    `json:"date"`
	Start     time.Time `json:"start"`
	End       time.Time `json:"end"`
	UpdatedAt time.Time `json:"updated_at"`
}

type SleepEditRequest struct {
	Edit         SleepEdit
	Precondition EditPrecondition
}

var ErrSleepChanged = errors.New("This night changed on your Mac.")

func DecodeSleepEdit(date string, raw []byte) (SleepEditRequest, error) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return SleepEditRequest{}, &EditValidationError{Field: "body"}
	}
	request := SleepEditRequest{Edit: SleepEdit{Date: date}}
	for _, field := range []struct {
		key   string
		value *time.Time
	}{{"start", &request.Edit.Start}, {"end", &request.Edit.End}} {
		raw, ok := fields[field.key]
		if !ok || json.Unmarshal(raw, field.value) != nil || field.value.IsZero() || !field.value.Equal(field.value.Truncate(time.Minute)) {
			return SleepEditRequest{}, &EditValidationError{Field: field.key}
		}
		*field.value = field.value.UTC()
	}
	if raw, ok := fields["if_updated_at"]; ok {
		request.Precondition.Present = true
		if json.Unmarshal(raw, &request.Precondition.UpdatedAt) != nil {
			return SleepEditRequest{}, &EditValidationError{Field: "if_updated_at"}
		}
	}
	return request, nil
}

// PutSleepEdit validates and normalizes against the book held under activities.lock.
func (s Store) PutSleepEdit(ctx context.Context, date string, now time.Time, condition EditPrecondition, change func(Book) (*SleepEdit, error)) (*SleepEdit, error) {
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return nil, err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return nil, err
	}
	edit, err := change(book)
	if err != nil {
		return nil, err
	}
	index := -1
	for i, old := range book.SleepEdits {
		if old.Date != date {
			continue
		}
		index = i
		if edit != nil && old.Start.Equal(edit.Start) && old.End.Equal(edit.End) {
			return &old, nil
		}
		break
	}
	if index == -1 && edit == nil {
		return nil, nil
	}
	if condition.Present {
		matches := index == -1 && condition.UpdatedAt == nil
		if index >= 0 && condition.UpdatedAt != nil {
			matches = book.SleepEdits[index].UpdatedAt.Truncate(time.Second).Equal(condition.UpdatedAt.Truncate(time.Second))
		}
		if !matches {
			return nil, ErrSleepChanged
		}
	}
	if index >= 0 {
		book.SleepEdits = append(book.SleepEdits[:index], book.SleepEdits[index+1:]...)
	}
	if edit != nil {
		edit.Date, edit.Start, edit.End, edit.UpdatedAt = date, edit.Start.UTC(), edit.End.UTC(), now.UTC()
		book.SleepEdits = append(book.SleepEdits, *edit)
	}
	return edit, s.save(book, now)
}

func (s Store) DeleteSleepEdit(ctx context.Context, date string, now time.Time) error {
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return err
	}
	for i, edit := range book.SleepEdits {
		if edit.Date == date {
			book.SleepEdits = append(book.SleepEdits[:i], book.SleepEdits[i+1:]...)
			return s.save(book, now)
		}
	}
	return ErrNotFound
}
