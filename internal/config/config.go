package config

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/secure"
)

var ErrInvalid = errors.New("invalid configuration")

// Sleep score modes (scores.md §0.1). The default, sufficiency, is stored and echoed as "".
const (
	SleepScoreSufficiency = "sufficiency"
	SleepScoreComposite   = "composite"
)

type Values struct {
	Score
	Week WeekTargets `json:"week_targets"`
}

// Score holds the settings that change scores; read bodies echo it as score_config.
type Score struct {
	MaxHR         *int              `json:"max_hr_override_bpm"`
	SleepBaseNeed int               `json:"sleep_base_need_minutes"`
	TrimpProfile  string            `json:"trimp_profile"`
	SportAliases  map[string]string `json:"sport_aliases"`
	StrainIntent  string            `json:"strain_intent"`
	WakeTarget    *string           `json:"wake_target"`
	// SleepScoreMode is "" for the default sufficiency mode, so default bodies stay byte-identical.
	SleepScoreMode string `json:"sleep_score_mode,omitempty"`
}

// CompositeSleep reports whether Sleep Performance uses the composite (scores.md §4.5a).
func (v Values) CompositeSleep() bool { return v.SleepScoreMode == SleepScoreComposite }

type WeekTargets struct {
	SleepMinutes    int `json:"sleep_minutes"`
	SleepNights     int `json:"sleep_nights"`
	ActivityMinutes int `json:"activity_minutes"`
	StrengthDays    int `json:"strength_days"`
}

var weekKeys = map[string]struct {
	min, max, fallback int
	field              func(*WeekTargets) *int
}{
	"week_sleep_minutes":    {240, 720, 420, func(w *WeekTargets) *int { return &w.SleepMinutes }},
	"week_sleep_nights":     {1, 7, 5, func(w *WeekTargets) *int { return &w.SleepNights }},
	"week_activity_minutes": {1, 1000, 150, func(w *WeekTargets) *int { return &w.ActivityMinutes }},
	"week_strength_days":    {1, 7, 2, func(w *WeekTargets) *int { return &w.StrengthDays }},
}

func Defaults() Values {
	values := Values{Score: Score{SleepBaseNeed: 450, TrimpProfile: "banister_b192", SportAliases: map[string]string{}, StrainIntent: "maintain"}}
	for _, key := range weekKeys {
		*key.field(&values.Week) = key.fallback
	}
	return values
}

type File struct{ Path string }

func (f File) Load() (Values, error) {
	values := Defaults()
	file, err := secure.OpenPrivate(f.Path, os.O_RDONLY)
	if errors.Is(err, os.ErrNotExist) {
		return values, nil
	}
	if err != nil {
		return values, errors.New("cannot open configuration")
	}
	defer file.Close()
	b, err := io.ReadAll(io.LimitReader(file, 65537))
	if err != nil || len(b) > 65536 {
		return values, errors.New("cannot read configuration")
	}
	decoder := json.NewDecoder(bytes.NewReader(b))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&values) != nil || decoder.Decode(new(any)) != io.EOF {
		return values, ErrInvalid
	}
	if bytes.Equal(bytes.TrimSpace(b), []byte("null")) {
		return values, ErrInvalid
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(b, &fields) != nil {
		return values, ErrInvalid
	}
	for _, key := range []string{"sleep_base_need_minutes", "trimp_profile", "sport_aliases", "strain_intent", "sleep_score_mode", "week_targets"} {
		if bytes.Equal(bytes.TrimSpace(fields[key]), []byte("null")) {
			return values, ErrInvalid
		}
	}
	if _, present := fields["sleep_score_mode"]; present {
		if values.SleepScoreMode == "" {
			return values, ErrInvalid
		}
		if values.SleepScoreMode == SleepScoreSufficiency {
			values.SleepScoreMode = ""
		}
	}
	return values, values.Validate()
}

var aliasSource = regexp.MustCompile(`^[A-Z][A-Z0-9_]{0,39}$`)
var wakeTime = regexp.MustCompile(`^([01][0-9]|2[0-3]):[0-5][0-9]$`)

func (v Values) Validate() error {
	if v.StrainIntent != "restore" && v.StrainIntent != "maintain" && v.StrainIntent != "overreach" {
		return ErrInvalid
	}
	if v.WakeTarget != nil && !wakeTime.MatchString(*v.WakeTarget) {
		return ErrInvalid
	}
	if v.SleepScoreMode != "" && v.SleepScoreMode != SleepScoreComposite {
		return ErrInvalid
	}
	if len(v.SportAliases) > 20 {
		return ErrInvalid
	}
	for source, target := range v.SportAliases {
		if !aliasSource.MatchString(source) || activities.Sports[target] == "" || source == target {
			return ErrInvalid
		}
	}
	if v.MaxHR != nil && (*v.MaxHR < 120 || *v.MaxHR > 230) || v.SleepBaseNeed < 360 || v.SleepBaseNeed > 600 || v.TrimpProfile != "banister_b192" && v.TrimpProfile != "banister_b167" {
		return ErrInvalid
	}
	for _, key := range weekKeys {
		if n := *key.field(&v.Week); n < key.min || n > key.max {
			return ErrInvalid
		}
	}
	return nil
}

func (f File) Set(key, value string) (Values, error) {
	values, err := f.Load()
	if err != nil {
		return values, err
	}
	switch key {
	case "max_hr_override_bpm":
		if value == "null" {
			values.MaxHR = nil
		} else {
			n, err := strconv.Atoi(value)
			if err != nil {
				return values, ErrInvalid
			}
			values.MaxHR = &n
		}
	case "sleep_base_need_minutes":
		n, err := strconv.Atoi(value)
		if err != nil {
			return values, ErrInvalid
		}
		values.SleepBaseNeed = n
	case "trimp_profile":
		values.TrimpProfile = value
	case "strain_intent":
		values.StrainIntent = value
	case "wake_target":
		values.WakeTarget = nil
		if value != "null" {
			values.WakeTarget = &value
		}
	case "sleep_score_mode":
		switch value {
		case SleepScoreSufficiency:
			values.SleepScoreMode = ""
		case SleepScoreComposite:
			values.SleepScoreMode = value
		default:
			return values, ErrInvalid
		}
	case "week_sleep_minutes", "week_sleep_nights", "week_activity_minutes", "week_strength_days":
		n, err := strconv.Atoi(value)
		if err != nil {
			return values, ErrInvalid
		}
		*weekKeys[key].field(&values.Week) = n
	default:
		source, ok := strings.CutPrefix(key, "sport_alias.")
		if !ok {
			return values, ErrInvalid
		}
		values.SportAliases[source] = value
	}
	if err := values.Validate(); err != nil {
		return values, err
	}
	return values, f.save(values)
}

func (f File) Unset(key string) (Values, error) {
	if source, ok := strings.CutPrefix(key, "sport_alias."); ok {
		if !aliasSource.MatchString(source) {
			return Defaults(), ErrInvalid
		}
		values, err := f.Load()
		if err != nil {
			return values, err
		}
		if _, exists := values.SportAliases[source]; !exists {
			return values, nil
		}
		delete(values.SportAliases, source)
		return values, f.save(values)
	}
	switch key {
	case "max_hr_override_bpm":
		return f.Set(key, "null")
	case "sleep_base_need_minutes":
		return f.Set(key, "450")
	case "trimp_profile":
		return f.Set(key, "banister_b192")
	case "strain_intent":
		return f.Set(key, "maintain")
	case "wake_target":
		return f.Set(key, "null")
	case "sleep_score_mode":
		return f.Set(key, SleepScoreSufficiency)
	}
	if week, ok := weekKeys[key]; ok {
		return f.Set(key, strconv.Itoa(week.fallback))
	}
	return Defaults(), ErrInvalid
}

func (f File) save(values Values) error {
	dir := filepath.Dir(f.Path)
	if err := secure.PrivateDir(dir); err != nil {
		return err
	}
	if file, err := secure.OpenPrivate(f.Path, os.O_RDONLY); err == nil {
		file.Close()
	} else if !errors.Is(err, os.ErrNotExist) {
		return errors.New("cannot replace configuration")
	}
	b, err := json.Marshal(values)
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(dir, ".config-*")
	if err != nil {
		return errors.New("cannot write configuration")
	}
	defer os.Remove(file.Name())
	if _, err = file.Write(append(b, '\n')); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return errors.New("cannot write configuration")
	}
	if err = os.Rename(file.Name(), f.Path); err != nil {
		return errors.New("cannot replace configuration")
	}
	return nil
}
