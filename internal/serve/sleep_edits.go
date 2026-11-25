package serve

import (
	"encoding/json"
	"io"
	"mime"
	"net/http"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (h *Handler) sleepEdit(w http.ResponseWriter, r *http.Request, now time.Time) int {
	fail := func(e *v2report.Error) int {
		w.WriteHeader(*e.HTTP)
		json.NewEncoder(w).Encode(e.Body(now))
		return *e.HTTP
	}
	date := strings.TrimPrefix(r.URL.Path, "/v2/sleep-edits/")
	if r.URL.Path == "/v2/sleep-edits" || date == "" {
		return fail(v2report.NewError("not_found"))
	}
	if r.Method != http.MethodPut && r.Method != http.MethodDelete {
		w.Header().Set("Allow", "PUT, DELETE")
		return fail(v2report.NewError("method_not_allowed"))
	}
	if r.URL.RawQuery != "" || r.URL.ForceQuery {
		return fail(v2report.NewError("invalid_request"))
	}
	if d, err := time.Parse("2006-01-02", date); err != nil || d.Format("2006-01-02") != date {
		return fail(v2report.NewError("not_found"))
	}
	store := h.activityStore()
	var stored *activities.SleepEdit
	var err error
	if r.Method == http.MethodDelete {
		if r.ContentLength != 0 || len(r.TransferEncoding) > 0 {
			return fail(v2report.NewError("invalid_request"))
		}
		err = store.DeleteSleepEdit(r.Context(), date, now)
	} else {
		media, _, mediaErr := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if mediaErr != nil || media != "application/json" {
			return fail(v2report.NewError("invalid_request"))
		}
		raw, readErr := io.ReadAll(io.LimitReader(r.Body, (64<<10)+1))
		if readErr != nil {
			return fail(v2report.NewError("invalid_request"))
		}
		if len(raw) > 64<<10 {
			return fail(v2report.NewError("payload_too_large"))
		}
		request, decodeErr := activities.DecodeSleepEdit(date, raw)
		if decodeErr != nil {
			return fail(v2report.EditError(decodeErr))
		}
		state, _, loadErr := h.load()
		if loadErr != nil {
			return fail(v2report.NewError("store_unavailable"))
		}
		cfg, loadErr := h.settings.Config.Load()
		if loadErr != nil {
			return fail(v2report.NewError("store_unavailable"))
		}
		engine, loadErr := score.New(state, now, cfg)
		if loadErr != nil {
			return fail(v2report.NewError("store_unavailable"))
		}
		stored, err = store.PutSleepEdit(r.Context(), date, now, request.Precondition, func(book activities.Book) (*activities.SleepEdit, error) {
			engine.Activities, engine.Edits, engine.SleepEdits, engine.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
			return engine.ValidateSleepEdit(request.Edit)
		})
	}
	if err != nil {
		return fail(v2report.EditError(err))
	}
	json.NewEncoder(w).Encode(v2report.SleepEditResponse{Envelope: v2report.CommandEnvelope("sleep_edit", now), Date: date, SleepEdit: stored})
	return http.StatusOK
}
