package activities

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

const (
	EditHorizonDays       = 30
	EditMaxShiftMinutes   = 180
	MergeMaxGapMinutes    = 15
	MaxMergeIDs           = 4
	NotesMaxRunes         = 500
	ActiveMinMinutes      = 1
	ActiveMaxMinutes      = 720
	HeartRateMaxSpanHours = 18
)

type Book struct {
	SleepEdits []SleepEdit `json:"sleep_edits"`
	Activities []Record    `json:"activities"`
	Edits      []Edit      `json:"edits"`
	Ratings    []Rating    `json:"ratings"`
}

type Edit struct {
	ID           string     `json:"id"`
	ExerciseType *string    `json:"exercise_type"`
	Start        *time.Time `json:"start"`
	End          *time.Time `json:"end"`
	Notes        *string    `json:"notes"`
	Hidden       bool       `json:"hidden"`
	MergeWith    []string   `json:"merge_with"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

type EditRequest struct {
	Edit         Edit
	Precondition EditPrecondition
}

type EditPrecondition struct {
	Present   bool
	UpdatedAt *time.Time
}

var ErrEditChanged = errors.New("This activity changed on your Mac.")

type EditValidationError struct{ Field string }

func (e *EditValidationError) Error() string { return "Invalid edit field: " + e.Field + "." }

func (s Store) PutEdit(ctx context.Context, edit Edit, now time.Time) (*Edit, error) {
	return s.UpdateEdit(ctx, now, EditPrecondition{}, func(Book) (Edit, error) { return edit, nil })
}

// UpdateEdit applies and validates a change against the book held under activities.lock.
func (s Store) UpdateEdit(ctx context.Context, now time.Time, precondition EditPrecondition, change func(Book) (Edit, error)) (*Edit, error) {
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
	edit, err = edit.Validate(now)
	if err != nil {
		return nil, err
	}

	index := -1
	for i, old := range book.Edits {
		if old.ID != edit.ID {
			continue
		}
		index = i
		edit.UpdatedAt = old.UpdatedAt
		if reflect.DeepEqual(old, edit) {
			return &old, nil
		}
		break
	}
	if index == -1 && edit.empty() {
		return nil, nil
	}
	if precondition.Present {
		matches := index == -1 && precondition.UpdatedAt == nil
		if index >= 0 && precondition.UpdatedAt != nil {
			matches = book.Edits[index].UpdatedAt.UTC().Truncate(time.Second).Equal(precondition.UpdatedAt.UTC().Truncate(time.Second))
		}
		if !matches {
			return nil, ErrEditChanged
		}
	}
	if index >= 0 {
		book.Edits = append(book.Edits[:index], book.Edits[index+1:]...)
	}
	var stored *Edit
	if !edit.empty() {
		edit.UpdatedAt = now.UTC()
		book.Edits = append(book.Edits, edit)
		stored = &edit
	}
	return stored, s.save(book, now)
}

func (s Store) DeleteEdit(ctx context.Context, id string, now time.Time) error {
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return err
	}
	for i, e := range book.Edits {
		if e.ID == id {
			book.Edits = append(book.Edits[:i], book.Edits[i+1:]...)
			return s.save(book, now)
		}
	}
	return ErrNotFound
}

func (s Store) Edits() ([]Edit, error) {
	book, err := s.Load()
	return book.Edits, err
}

func (e Edit) empty() bool {
	return e.ExerciseType == nil && e.Start == nil && e.End == nil && e.Notes == nil && !e.Hidden && len(e.MergeWith) == 0
}

func (e Edit) Validate(now time.Time) (Edit, error) {
	bad := func(field string) (Edit, error) { return Edit{}, &EditValidationError{field} }
	if e.ID == "" || strings.Contains(e.ID, "/") || strings.HasPrefix(e.ID, "effort-") {
		return bad("id")
	}
	if e.ExerciseType != nil {
		if _, ok := Sports[*e.ExerciseType]; !ok {
			return bad("exercise_type")
		}
	}
	if e.Start == nil && e.End != nil {
		return bad("start")
	}
	if e.Start != nil && e.End == nil {
		return bad("end")
	}
	if e.Start != nil {
		start, end := e.Start.UTC(), e.End.UTC()
		if start.IsZero() {
			return bad("start")
		}
		if !end.After(start) || end.After(now.Add(5*time.Minute)) {
			return bad("end")
		}
		e.Start, e.End = &start, &end
	}
	if e.Notes != nil {
		note := strings.TrimSpace(*e.Notes)
		if n := utf8.RuneCountInString(note); n < 1 || n > NotesMaxRunes {
			return bad("notes")
		}
		e.Notes = &note
	}
	if len(e.MergeWith) > MaxMergeIDs {
		return bad("merge_with")
	}
	for _, id := range e.MergeWith {
		if id == "" || id == e.ID || strings.Contains(id, "/") || strings.HasPrefix(id, "effort-") {
			return bad("merge_with")
		}
	}
	if e.MergeWith == nil {
		e.MergeWith = []string{}
	}
	return e, nil
}

func DecodeEdit(id string, raw []byte) (EditRequest, error) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return EditRequest{}, &EditValidationError{"body"}
	}
	edit := Edit{ID: id}
	for _, f := range []struct {
		key      string
		value    any
		nullable bool
	}{
		{"exercise_type", &edit.ExerciseType, true}, {"start", &edit.Start, true}, {"end", &edit.End, true},
		{"notes", &edit.Notes, true}, {"hidden", &edit.Hidden, false}, {"merge_with", &edit.MergeWith, false},
	} {
		value, ok := fields[f.key]
		if !ok || (!f.nullable && bytes.Equal(bytes.TrimSpace(value), []byte("null"))) || json.Unmarshal(value, f.value) != nil {
			return EditRequest{}, &EditValidationError{f.key}
		}
	}
	precondition := EditPrecondition{}
	if value, ok := fields["if_updated_at"]; ok {
		precondition.Present = true
		if json.Unmarshal(value, &precondition.UpdatedAt) != nil {
			return EditRequest{}, &EditValidationError{"if_updated_at"}
		}
	}
	return EditRequest{Edit: edit, Precondition: precondition}, nil
}
