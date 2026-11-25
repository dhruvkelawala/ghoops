package serve

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (h *Handler) journalStore() journal.Store {
	return journal.Store{Dir: h.settings.Store.Dir, Vault: h.settings.Store.Vault}
}

// journalPut serves PUT /v2/journal/<date> (journal-spec §6.2).
func (h *Handler) journalPut(w http.ResponseWriter, r *http.Request, now time.Time) int {
	fail := func(e *v2report.Error) int {
		w.WriteHeader(*e.HTTP)
		json.NewEncoder(w).Encode(e.Body(now))
		return *e.HTTP
	}
	date := strings.TrimPrefix(r.URL.Path, "/v2/journal/")
	if date == "" || strings.Contains(date, "/") {
		return fail(v2report.NewError("not_found"))
	}
	if r.Method != http.MethodPut {
		w.Header().Set("Allow", "PUT")
		return fail(v2report.NewError("method_not_allowed"))
	}
	if r.URL.RawQuery != "" || r.URL.ForceQuery {
		return fail(v2report.NewError("invalid_request"))
	}
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/json" {
		return fail(v2report.NewError("invalid_request"))
	}
	raw, err := io.ReadAll(io.LimitReader(r.Body, (64<<10)+1))
	if err != nil {
		return fail(v2report.NewError("invalid_request"))
	}
	if len(raw) > 64<<10 {
		return fail(v2report.NewError("payload_too_large"))
	}
	answers, condition, err := journal.DecodePut(raw)
	if err != nil {
		return fail(v2report.JournalError(err))
	}
	state, _, err := h.load()
	if err != nil {
		return fail(v2report.NewError("store_unavailable"))
	}
	cfg, err := h.settings.Config.Load()
	if err != nil {
		return fail(v2report.NewError("store_unavailable"))
	}
	book, err := h.loadActivities()
	if err != nil {
		return fail(v2report.NewError("store_unavailable"))
	}
	builder, err := v2report.New(state, now, cfg, v2report.Options{Activities: book.Activities, Edits: book.Edits, SleepEdits: book.SleepEdits})
	if err != nil {
		return fail(v2report.NewError("store_unavailable"))
	}
	if !journal.DateAllowed(date, builder.DefaultDate(), activities.EditHorizonDays) {
		return fail(v2report.NewError("not_found"))
	}
	entry, err := h.journalStore().Put(r.Context(), date, now, condition, func(map[string]bool) (map[string]bool, error) { return answers, nil })
	if err != nil {
		return fail(v2report.JournalError(err))
	}
	json.NewEncoder(w).Encode(v2report.JournalEntryResponse{Envelope: v2report.CommandEnvelope("journal_entry", now), Date: date, Entry: entry})
	return http.StatusOK
}

// loadJournal reloads journal-v2.enc when its modification time or size changes (contract §7.4).
func (h *Handler) loadJournal() (journal.Book, error) {
	h.journalMu.Lock()
	defer h.journalMu.Unlock()
	var stamp time.Time
	var size int64
	info, err := os.Stat(filepath.Join(h.settings.Store.Dir, journal.FileName))
	if err == nil {
		stamp, size = info.ModTime(), info.Size()
	} else if !errors.Is(err, os.ErrNotExist) {
		return journal.Book{}, err
	}
	if !h.journalLoaded || !stamp.Equal(h.journalStamp) || size != h.journalSize {
		book, err := h.journalStore().Load()
		if err != nil {
			return journal.Book{}, err
		}
		h.journalBook, h.journalStamp, h.journalSize, h.journalLoaded = book, stamp, size, true
	}
	return h.journalBook, nil
}
