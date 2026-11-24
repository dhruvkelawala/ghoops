package activities

import (
	"bytes"
	"context"
	"encoding/json"
	"math"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

// Ratings use Foster's modified CR-10 scale: whole numbers 0 to 10 (effort-rating-spec.md §4.3).
const (
	RPEScale = "cr10"
	RPEMin   = 0
	RPEMax   = 10
)

// Rating is how hard the owner says one workout felt. It feeds no score.
type Rating struct {
	ID        string    `json:"id"`
	RPE       int       `json:"rpe"`
	UpdatedAt time.Time `json:"updated_at"`
}

// ValidateRatingID applies the edit id rules: no empty id, no "/", no detected effort.
func ValidateRatingID(id string) error {
	_, err := Edit{ID: id}.Validate(time.Time{})
	return err
}

// DecodeRating reads a PUT body. Unknown keys are ignored; rpe must be a whole number in range.
func DecodeRating(raw []byte) (int, error) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return 0, &EditValidationError{"body"}
	}
	value, ok := fields["rpe"]
	if !ok {
		return 0, &EditValidationError{"rpe"}
	}
	decoder := json.NewDecoder(bytes.NewReader(value))
	decoder.UseNumber()
	var decoded any
	if decoder.Decode(&decoded) != nil {
		return 0, &EditValidationError{"rpe"}
	}
	number, ok := decoded.(json.Number)
	if !ok {
		return 0, &EditValidationError{"rpe"}
	}
	f, err := number.Float64()
	if err != nil || f != math.Trunc(f) || f < RPEMin || f > RPEMax {
		return 0, &EditValidationError{"rpe"}
	}
	return int(f), nil
}

// PutRating stores a rating under activities.lock after found accepts the id against the locked book.
// The same value again returns the stored rating without a write.
func (s Store) PutRating(ctx context.Context, id string, rpe int, now time.Time, found func(Book) error) (*Rating, error) {
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return nil, err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return nil, err
	}
	if err := found(book); err != nil {
		return nil, err
	}
	for i, old := range book.Ratings {
		if old.ID != id {
			continue
		}
		if old.RPE == rpe {
			return &old, nil
		}
		book.Ratings = append(book.Ratings[:i], book.Ratings[i+1:]...)
		break
	}
	rating := Rating{ID: id, RPE: rpe, UpdatedAt: now.UTC()}
	book.Ratings = append(book.Ratings, rating)
	return &rating, s.save(book, now)
}

func (s Store) DeleteRating(ctx context.Context, id string, now time.Time) error {
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return err
	}
	for i, rating := range book.Ratings {
		if rating.ID == id {
			book.Ratings = append(book.Ratings[:i], book.Ratings[i+1:]...)
			return s.save(book, now)
		}
	}
	return ErrNotFound
}
