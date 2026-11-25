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

// rating serves PUT and DELETE /v2/ratings/<id> (effort-rating-spec.md §4.4).
func (h *Handler) rating(w http.ResponseWriter, r *http.Request, now time.Time) int {
	fail := func(e *v2report.Error) int {
		w.WriteHeader(*e.HTTP)
		json.NewEncoder(w).Encode(e.Body(now))
		return *e.HTTP
	}
	id := strings.TrimPrefix(r.URL.Path, "/v2/ratings/")
	if r.URL.Path == "/v2/ratings" || id == "" {
		return fail(v2report.NewError("not_found"))
	}
	if r.Method != http.MethodPut && r.Method != http.MethodDelete {
		w.Header().Set("Allow", "PUT, DELETE")
		return fail(v2report.NewError("method_not_allowed"))
	}
	if r.URL.RawQuery != "" || r.URL.ForceQuery {
		return fail(v2report.NewError("invalid_request"))
	}
	if err := activities.ValidateRatingID(id); err != nil {
		return fail(v2report.EditError(err))
	}
	store := h.activityStore()
	var stored *activities.Rating
	var err error
	if r.Method == http.MethodDelete {
		if r.ContentLength != 0 || len(r.TransferEncoding) > 0 {
			return fail(v2report.NewError("invalid_request"))
		}
		err = store.DeleteRating(r.Context(), id, now)
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
		rpe, decodeErr := activities.DecodeRating(raw)
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
		stored, err = store.PutRating(r.Context(), id, rpe, now, func(book activities.Book) error {
			engine.Activities, engine.Edits, engine.SleepEdits, engine.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
			_, err := engine.EditTarget(id)
			return err
		})
	}
	if err != nil {
		return fail(v2report.EditError(err))
	}
	json.NewEncoder(w).Encode(v2report.RatingResponse{Envelope: v2report.CommandEnvelope("rating", now), ID: id, Rating: stored})
	return http.StatusOK
}
