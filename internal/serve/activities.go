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
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (h *Handler) activityStore() activities.Store {
	return activities.Store{Dir: h.settings.Store.Dir, Vault: h.settings.Store.Vault}
}
func (h *Handler) activity(w http.ResponseWriter, r *http.Request, now time.Time) int {
	fail := func(code string, err error) int {
		e := v2report.NewError(code)
		var field *activities.ValidationError
		if errors.As(err, &field) {
			e.Message = field.Error()
		}
		w.WriteHeader(*e.HTTP)
		json.NewEncoder(w).Encode(e.Body(now))
		return *e.HTTP
	}
	if r.Method != http.MethodPost && r.URL.Path == "/v2/activities" {
		w.Header().Set("Allow", "POST")
		return fail("method_not_allowed", nil)
	}
	if strings.HasPrefix(r.URL.Path, "/v2/activities/") && r.Method != http.MethodDelete {
		w.Header().Set("Allow", "DELETE")
		return fail("method_not_allowed", nil)
	}
	if r.URL.RawQuery != "" || r.URL.ForceQuery {
		return fail("invalid_request", nil)
	}
	store := h.activityStore()
	if r.URL.Path == "/v2/activities" && r.Method == http.MethodPost {
		media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if err != nil || media != "application/json" {
			return fail("invalid_request", nil)
		}
		b, err := io.ReadAll(io.LimitReader(r.Body, 64<<10+1))
		if err != nil {
			return fail("invalid_request", nil)
		}
		if len(b) > 64<<10 {
			return fail("payload_too_large", nil)
		}
		a, err := activities.DecodeUpload(b)
		if err != nil {
			return fail("invalid_request", err)
		}
		row, created, err := store.Put(r.Context(), a, now)
		if errors.Is(err, activities.ErrConflict) {
			return fail("conflict", nil)
		}
		var invalid *activities.ValidationError
		if errors.As(err, &invalid) {
			return fail("invalid_request", err)
		}
		if err != nil {
			return fail("store_unavailable", nil)
		}
		status := 200
		if created {
			status = 201
		}
		w.WriteHeader(status)
		json.NewEncoder(w).Encode(struct {
			v2report.Envelope
			Activity activities.Record `json:"activity"`
		}{v2report.CommandEnvelope("activity", now), row})
		return status
	}
	id := strings.TrimPrefix(r.URL.Path, "/v2/activities/")
	if r.Method == http.MethodDelete && id != r.URL.Path && id != "" && !strings.Contains(id, "/") {
		if r.ContentLength != 0 || len(r.TransferEncoding) > 0 {
			return fail("invalid_request", nil)
		}
		err := store.Delete(r.Context(), id, now)
		if errors.Is(err, activities.ErrNotFound) {
			return fail("not_found", nil)
		}
		if err != nil {
			return fail("store_unavailable", nil)
		}
		json.NewEncoder(w).Encode(struct {
			v2report.Envelope
			ID string `json:"id"`
		}{v2report.CommandEnvelope("activity_deleted", now), id})
		return 200
	}
	return fail("method_not_allowed", nil)
}

func (h *Handler) loadActivities() (activities.Book, error) {
	h.activityMu.Lock()
	defer h.activityMu.Unlock()
	var stamp time.Time
	var size int64
	info, err := os.Stat(filepath.Join(h.settings.Store.Dir, "activities-v2.enc"))
	if err == nil {
		stamp, size = info.ModTime(), info.Size()
	} else if !errors.Is(err, os.ErrNotExist) {
		return activities.Book{}, err
	}
	if !h.activityLoaded || !stamp.Equal(h.activityStamp) || size != h.activitySize {
		rows, err := h.activityStore().Load()
		if err != nil {
			return activities.Book{}, err
		}
		h.activityBook, h.activityStamp, h.activitySize, h.activityLoaded = rows, stamp, size, true
	}
	return h.activityBook, nil
}
