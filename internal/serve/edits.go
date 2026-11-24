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

func (h *Handler) edit(w http.ResponseWriter, r *http.Request, now time.Time) int {
	fail := func(e *v2report.Error) int {
		w.WriteHeader(*e.HTTP)
		json.NewEncoder(w).Encode(e.Body(now))
		return *e.HTTP
	}
	id := strings.TrimPrefix(r.URL.Path, "/v2/edits/")
	if r.URL.Path == "/v2/edits" || id == "" {
		return fail(v2report.NewError("not_found"))
	}
	if r.Method != http.MethodPut && r.Method != http.MethodDelete {
		w.Header().Set("Allow", "PUT, DELETE")
		return fail(v2report.NewError("method_not_allowed"))
	}
	if r.URL.RawQuery != "" || r.URL.ForceQuery {
		return fail(v2report.NewError("invalid_request"))
	}
	if _, err := (activities.Edit{ID: id}).Validate(now); err != nil {
		return fail(v2report.EditError(err))
	}
	store := h.activityStore()
	var stored *activities.Edit
	var err error
	if r.Method == http.MethodDelete {
		if r.ContentLength != 0 || len(r.TransferEncoding) > 0 {
			return fail(v2report.NewError("invalid_request"))
		}
		err = store.DeleteEdit(r.Context(), id, now)
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
		request, decodeErr := activities.DecodeEdit(id, raw)
		if decodeErr != nil {
			return fail(v2report.EditError(decodeErr))
		}
		state, loadErr := h.load()
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
		stored, err = store.UpdateEdit(r.Context(), now, request.Precondition, func(book activities.Book) (activities.Edit, error) {
			engine.Activities, engine.Edits, engine.SleepEdits, engine.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
			return engine.ValidateEdit(request.Edit)
		})
	}
	if err != nil {
		return fail(v2report.EditError(err))
	}
	json.NewEncoder(w).Encode(v2report.EditResponse{Envelope: v2report.CommandEnvelope("edit", now), ID: id, Edit: stored})
	return http.StatusOK
}
