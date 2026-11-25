package activities

import (
	"context"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

type Compaction struct {
	Activities  int `json:"activities"`
	LiveRemoved int `json:"live_removed"`
	BytesBefore int `json:"bytes_before"`
	BytesAfter  int `json:"bytes_after"`
}

// Compact removes only phone estimates from activities that ended over 30 days ago.
func (s Store) Compact(ctx context.Context, now time.Time) (Compaction, error) {
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return Compaction{}, err
	}
	defer unlock()

	book, size, err := s.read()
	if err != nil {
		return Compaction{}, err
	}
	result := Compaction{Activities: len(book.Activities), BytesBefore: size, BytesAfter: size}
	cutoff := now.Add(-30 * 24 * time.Hour)
	for i := range book.Activities {
		row := &book.Activities[i]
		if row.End.Before(cutoff) && len(row.Live) > 0 {
			row.Live = nil
			result.LiveRemoved++
		}
	}
	if result.LiveRemoved == 0 {
		if size > MaxFileBytes {
			return Compaction{}, ErrCapacity
		}
		return result, nil
	}
	result.BytesAfter, err = s.write(book)
	if err != nil {
		return Compaction{}, err
	}
	return result, nil
}
