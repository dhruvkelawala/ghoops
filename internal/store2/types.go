package store2

import (
	"encoding/json"
	"errors"
	"time"
	_ "time/tzdata"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
)

type State2 struct {
	Version      int                     `json:"schema_version"`
	Source       string                  `json:"source"`
	Account      string                  `json:"account"`
	Timezone     string                  `json:"timezone"`
	Records      []health.Record         `json:"records"`
	HRMinutes    []MinuteDay             `json:"hr_minutes"`
	DailyRollups []DailyRollup           `json:"daily_rollups"`
	User         map[string]UserResource `json:"user"`
	Coverage     []cache.Coverage        `json:"coverage"`
	Runs         []Run                   `json:"runs"`
	Synthetic    bool                    `json:"synthetic_fixture,omitempty"`
}

type MinuteDay struct {
	Date    string   `json:"date"`
	Windows []Minute `json:"windows"`
}

type Minute struct {
	Start         int64
	Min, Avg, Max float64
}

func (m Minute) MarshalJSON() ([]byte, error) {
	return json.Marshal([4]any{m.Start, m.Min, m.Avg, m.Max})
}

func (m *Minute) UnmarshalJSON(b []byte) error {
	var values []json.RawMessage
	if json.Unmarshal(b, &values) != nil || len(values) != 4 {
		return errors.New("invalid minute window")
	}
	for i, target := range []any{&m.Start, &m.Min, &m.Avg, &m.Max} {
		if string(values[i]) == "null" || json.Unmarshal(values[i], target) != nil {
			return errors.New("invalid minute window")
		}
	}
	return nil
}

type DailyRollup struct {
	Type  string          `json:"data_type"`
	Date  string          `json:"date"`
	Value json.RawMessage `json:"value"`
}

type UserResource struct {
	Status    string          `json:"status"`
	FetchedAt *time.Time      `json:"fetched_at"`
	Error     *string         `json:"error"`
	Body      json.RawMessage `json:"body"`
}

type Run struct {
	StartedAt     time.Time `json:"started_at"`
	FinishedAt    time.Time `json:"finished_at"`
	Pass          string    `json:"pass"`
	Status        string    `json:"status"`
	CoreComplete  bool      `json:"core_complete"`
	Requests      int       `json:"requests"`
	FailedStreams []string  `json:"failed_streams"`
}

func Empty() State2 {
	return State2{
		Version: 2, Source: health.Source, Timezone: "Europe/London",
		Records: []health.Record{}, HRMinutes: []MinuteDay{}, DailyRollups: []DailyRollup{},
		Coverage: []cache.Coverage{}, Runs: []Run{},
		User: map[string]UserResource{
			"profile": {Status: "never"}, "settings": {Status: "never"},
			"paired_devices": {Status: "never"}, "irn_profile": {Status: "never"},
		},
	}
}
