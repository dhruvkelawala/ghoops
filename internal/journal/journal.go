// Package journal stores the owner's yes/no answers about each day (journal-spec.md).
package journal

import (
	"bytes"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"
)

// Behaviour is one catalogue entry (journal-spec §2).
type Behaviour struct {
	Key      string `json:"key"`
	Name     string `json:"name"`
	Question string `json:"question"`
	Default  bool   `json:"-"`
}

// Catalogue is the fixed list the Mac offers, in display order.
var Catalogue = []Behaviour{
	{"alcohol", "Alcohol", "Did you drink any alcohol?", true},
	{"late_caffeine", "Late caffeine", "Any caffeine after 14:00?", true},
	{"late_meal", "Late meal", "A large meal close to bedtime?", true},
	{"screen_in_bed", "Screen in bed", "Used a phone or screen in bed?", true},
	{"stress", "Stress", "Did you feel stressed?", true},
	{"sick", "Feeling ill", "Did you feel ill or run down?", false},
	{"travel", "Travel", "Did you travel?", false},
	{"sauna", "Sauna", "Did you use a sauna?", false},
	{"cold_exposure", "Cold exposure", "An ice bath or a cold shower?", false},
	{"melatonin", "Melatonin", "Did you take melatonin?", false},
}

// RetentionDays bounds how long entries are kept (journal-spec §5.1).
const RetentionDays = 400

func known(key string) bool {
	for _, b := range Catalogue {
		if b.Key == key {
			return true
		}
	}
	return false
}

// Entry is one journal date's answers.
type Entry struct {
	Date      string          `json:"date"`
	Answers   map[string]bool `json:"answers"`
	UpdatedAt time.Time       `json:"updated_at"`
}

// Book is the decrypted journal file. Behaviours nil means the defaults.
type Book struct {
	Behaviours []string `json:"behaviours"`
	Entries    []Entry  `json:"entries"`
}

// Enabled returns the enabled behaviours in catalogue order.
func (b Book) Enabled() []Behaviour {
	on := map[string]bool{}
	for _, key := range b.Behaviours {
		on[key] = true
	}
	out := []Behaviour{}
	for _, behaviour := range Catalogue {
		if b.Behaviours == nil && behaviour.Default || on[behaviour.Key] {
			out = append(out, behaviour)
		}
	}
	return out
}

// Entry returns the stored entry for date, or nil.
func (b Book) Entry(date string) *Entry {
	for i := range b.Entries {
		if b.Entries[i].Date == date {
			return &b.Entries[i]
		}
	}
	return nil
}

// ValidationError names the field a request got wrong.
type ValidationError struct{ Field string }

func (e *ValidationError) Error() string { return "Invalid journal field: " + e.Field + "." }

var (
	ErrNotFound = errors.New("journal date not found")
	ErrChanged  = errors.New("This day's journal changed on your Mac.")
)

// Precondition is the optional if_updated_at of a PUT: absent, null (no entry expected) or a time.
type Precondition struct {
	Present   bool
	UpdatedAt *time.Time
}

// DateAllowed applies journal-spec §3: default − horizon ≤ date ≤ default.
func DateAllowed(date, defaultDate string, horizonDays int) bool {
	d, err := time.Parse("2006-01-02", date)
	if err != nil || d.Format("2006-01-02") != date {
		return false
	}
	last, err := time.Parse("2006-01-02", defaultDate)
	if err != nil {
		return false
	}
	return !d.After(last) && !d.Before(last.AddDate(0, 0, -horizonDays))
}

// DecodePut reads a PUT body (journal-spec §6.2).
func DecodePut(raw []byte) (map[string]bool, Precondition, error) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(raw, &fields) != nil || fields == nil {
		return nil, Precondition{}, &ValidationError{"body"}
	}
	var values map[string]json.RawMessage
	if json.Unmarshal(fields["answers"], &values) != nil || values == nil {
		return nil, Precondition{}, &ValidationError{"answers"}
	}
	answers := map[string]bool{}
	for key, value := range values {
		value = bytes.TrimSpace(value)
		if !known(key) || !bytes.Equal(value, []byte("true")) && !bytes.Equal(value, []byte("false")) {
			return nil, Precondition{}, &ValidationError{"answers"}
		}
		answers[key] = bytes.Equal(value, []byte("true"))
	}
	var condition Precondition
	if raw, ok := fields["if_updated_at"]; ok {
		condition.Present = true
		if json.Unmarshal(raw, &condition.UpdatedAt) != nil {
			return nil, Precondition{}, &ValidationError{"if_updated_at"}
		}
	}
	return answers, condition, nil
}

// ParseArguments applies CLI KEY=yes|no|clear arguments to stored answers (journal-spec §5.3).
func ParseArguments(stored map[string]bool, args []string) (map[string]bool, error) {
	if len(args) == 0 {
		return nil, &ValidationError{"answers"}
	}
	answers := map[string]bool{}
	for key, value := range stored {
		answers[key] = value
	}
	for _, arg := range args {
		key, value, ok := strings.Cut(arg, "=")
		if !ok || !known(key) {
			return nil, &ValidationError{"answers"}
		}
		switch value {
		case "yes":
			answers[key] = true
		case "no":
			answers[key] = false
		case "clear":
			delete(answers, key)
		default:
			return nil, &ValidationError{"answers"}
		}
	}
	return answers, nil
}

// ParseBehaviours checks a comma-separated enabled set (journal-spec §5.4).
func ParseBehaviours(list string) ([]string, error) {
	seen := map[string]bool{}
	for _, key := range strings.Split(list, ",") {
		if !known(key) || seen[key] {
			return nil, &ValidationError{"behaviours"}
		}
		seen[key] = true
	}
	keys := []string{}
	for _, behaviour := range Catalogue {
		if seen[behaviour.Key] {
			keys = append(keys, behaviour.Key)
		}
	}
	return keys, nil
}

func sameAnswers(a, b map[string]bool) bool {
	if len(a) != len(b) {
		return false
	}
	for key, value := range a {
		if other, ok := b[key]; !ok || other != value {
			return false
		}
	}
	return true
}

func sortEntries(entries []Entry) {
	sort.Slice(entries, func(i, j int) bool { return entries[i].Date < entries[j].Date })
}
