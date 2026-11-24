package scorefixture

import (
	"errors"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/store2"
)

func SparseStrain(state store2.State2) (store2.State2, error) {
	noon := time.Date(2026, time.March, 10, 12, 0, 0, 0, time.UTC).Unix()
	for _, day := range state.HRMinutes {
		for _, minute := range day.Windows {
			if minute.Start == noon {
				state.HRMinutes = []store2.MinuteDay{{Date: day.Date, Windows: []store2.Minute{minute}}}
				return state, nil
			}
		}
	}
	return store2.State2{}, errors.New("full fixture has no March 10 noon heart-rate minute")
}
