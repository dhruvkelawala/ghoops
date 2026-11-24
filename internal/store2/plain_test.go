package store2

import (
	"encoding/json"
	"errors"
	"os"
)

func LoadPlainForTest(path string) (State2, error) {
	var state State2
	b, err := os.ReadFile(path)
	if err != nil {
		return state, err
	}
	if err := json.Unmarshal(b, &state); err != nil {
		return state, err
	}
	if state.Version != 2 || !state.Synthetic {
		return state, errors.New("plain test store must be a synthetic v2 fixture")
	}
	return state, nil
}
