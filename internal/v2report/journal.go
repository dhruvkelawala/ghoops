package v2report

import (
	"errors"
	"net/url"
	"strconv"

	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/score"
)

// JournalBehaviour is an enabled behaviour in the journal body (journal-spec §6.1).
type JournalBehaviour struct {
	Key      string `json:"key"`
	Name     string `json:"name"`
	Question string `json:"question"`
}

// Journal is the `journal` body: `ghoops journal show` and `GET /v2/journal`.
type Journal struct {
	Envelope
	DefaultDate string             `json:"default_date"`
	From        string             `json:"from"`
	To          string             `json:"to"`
	Behaviours  []JournalBehaviour `json:"behaviours"`
	Entries     []journal.Entry    `json:"entries"`
	Impact      JournalImpact      `json:"impact"`
}

// JournalImpact is `journal.impact` (journal-spec §4, §6.3): one row per enabled behaviour.
type JournalImpact struct {
	From       string                `json:"from"`
	To         string                `json:"to"`
	Behaviours []score.JournalImpact `json:"behaviours"`
}

// JournalEntryResponse answers `journal set` and `PUT /v2/journal/<date>`.
type JournalEntryResponse struct {
	Envelope
	Date  string         `json:"date"`
	Entry *journal.Entry `json:"entry"`
}

// JournalCatalogueRow is one row of `journal behaviours`.
type JournalCatalogueRow struct {
	Key      string `json:"key"`
	Name     string `json:"name"`
	Question string `json:"question"`
	Enabled  bool   `json:"enabled"`
	Default  bool   `json:"default"`
}

// JournalBehaviours is the `journal_behaviours` body.
type JournalBehaviours struct {
	Envelope
	Behaviours []JournalCatalogueRow `json:"behaviours"`
}

// JournalDays is the default and largest `days` of the journal body.
const (
	JournalDefaultDays = 30
	JournalMaxDays     = 90
)

func (b *Builder) journal(params url.Values) (Journal, error) {
	days := JournalDefaultDays
	if value := params.Get("days"); value != "" {
		n, err := strconv.Atoi(value)
		if err != nil || n < 1 {
			return Journal{}, invalidParameter("days")
		}
		if n > JournalMaxDays {
			return Journal{}, NewError("date_out_of_range")
		}
		days = n
	}
	return b.Journal(days), nil
}

// Journal builds the journal body for the days ending on the default date.
func (b *Builder) Journal(days int) Journal {
	to := b.engine.DefaultDate()
	from := b.engine.Date(to).AddDate(0, 0, 1-days).Format("2006-01-02")
	envelope := b.envelope("journal")
	envelope.Config, envelope.Constants = nil, nil
	body := Journal{Envelope: envelope, DefaultDate: to, From: from, To: to, Behaviours: []JournalBehaviour{}, Entries: []journal.Entry{}}
	for _, behaviour := range b.options.Journal.Enabled() {
		body.Behaviours = append(body.Behaviours, JournalBehaviour{behaviour.Key, behaviour.Name, behaviour.Question})
	}
	for _, entry := range b.options.Journal.Entries {
		if from <= entry.Date && entry.Date <= to {
			body.Entries = append(body.Entries, entry)
		}
	}
	body.Impact = b.journalImpact(to)
	return body
}

// journalImpact pairs each answer for journal date E with the reported Recovery of E + 1,
// computing Recovery only for answered dates.
func (b *Builder) journalImpact(to string) JournalImpact {
	end := b.engine.Date(to)
	from := end.AddDate(0, 0, 1-score.JournalWindowDays).Format("2006-01-02")
	impact := JournalImpact{From: from, To: to, Behaviours: []score.JournalImpact{}}
	for _, behaviour := range b.options.Journal.Enabled() {
		var yes, no []float64
		for _, entry := range b.options.Journal.Entries {
			answer, ok := entry.Answers[behaviour.Key]
			morning := b.engine.Date(entry.Date).AddDate(0, 0, 1).Format("2006-01-02")
			if !ok || morning < from || morning > to {
				continue
			}
			value := b.recovery(morning).Value
			if value == nil {
				continue
			}
			if answer {
				yes = append(yes, *value)
			} else {
				no = append(no, *value)
			}
		}
		impact.Behaviours = append(impact.Behaviours, score.ComputeJournalImpact(behaviour.Key, yes, no))
	}
	return impact
}

// DefaultDate is the ghoops day the builder's engine reports (scores.md §3.1).
func (b *Builder) DefaultDate() string { return b.engine.DefaultDate() }

// JournalCatalogue lists every catalogue behaviour with its state.
func JournalCatalogue(book journal.Book, envelope Envelope) JournalBehaviours {
	on := map[string]bool{}
	for _, behaviour := range book.Enabled() {
		on[behaviour.Key] = true
	}
	rows := []JournalCatalogueRow{}
	for _, behaviour := range journal.Catalogue {
		rows = append(rows, JournalCatalogueRow{behaviour.Key, behaviour.Name, behaviour.Question, on[behaviour.Key], behaviour.Default})
	}
	return JournalBehaviours{Envelope: envelope, Behaviours: rows}
}

// JournalError maps journal store errors to contract errors.
func JournalError(err error) *Error {
	var field *journal.ValidationError
	switch {
	case errors.As(err, &field):
		e := NewError("invalid_request")
		e.Message = field.Error()
		return e
	case errors.Is(err, journal.ErrChanged):
		e := NewError("conflict")
		e.Message = err.Error()
		return e
	case errors.Is(err, journal.ErrNotFound):
		return NewError("not_found")
	case errors.Is(err, journal.ErrCapacity):
		return NewError("storage_full")
	default:
		return NewError("store_unavailable")
	}
}
