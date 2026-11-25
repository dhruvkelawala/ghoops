package serve

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (h *Handler) redeem(w http.ResponseWriter, r *http.Request, now time.Time) (v2report.PairRedeem, *v2report.Error) {
	var empty v2report.PairRedeem
	if r.Method != http.MethodPost {
		return empty, v2report.NewError("method_not_allowed")
	}
	media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || media != "application/json" || len(r.Header.Values("Authorization")) != 0 || r.URL.RawQuery != "" {
		return empty, v2report.NewError("invalid_request")
	}
	const limit = 1024
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, limit))
	var tooLarge *http.MaxBytesError
	if r.ContentLength > limit || errors.As(err, &tooLarge) {
		apiError := v2report.NewError("payload_too_large")
		apiError.Message = "Request body exceeds 1 KiB."
		return empty, apiError
	}
	var request struct {
		Code       string `json:"code"`
		DeviceName string `json:"device_name"`
	}
	if err != nil || json.Unmarshal(body, &request) != nil {
		return empty, v2report.NewError("invalid_request")
	}
	name := strings.TrimSpace(request.DeviceName)
	if name == "" {
		name = "iPhone"
	}
	if utf8.RuneCountInString(name) > 40 || strings.ContainsFunc(name, unicode.IsControl) {
		return empty, v2report.NewError("invalid_request")
	}
	h.authMu.Lock()
	err = h.loadCredentials(r.Context(), now)
	h.authMu.Unlock()
	if err != nil {
		return empty, v2report.NewError("store_unavailable")
	}
	device, err := h.devices.Redeem(r.Context(), request.Code, name, now)
	if errors.Is(err, pairing.ErrEnrolmentEnded) {
		h.authMu.Lock()
		code := h.countAuthFailure(now)
		h.authMu.Unlock()
		apiError := v2report.NewError(code)
		if code == "unauthorized" {
			apiError.Message = "Pairing code expired or already used."
		}
		return empty, apiError
	}
	if err != nil {
		return empty, v2report.NewError("store_unavailable")
	}
	h.authMu.Lock()
	h.readAt = time.Time{}
	h.authMu.Unlock()
	return v2report.PairRedeem{
		Envelope: v2report.CommandEnvelope("pair_redeem", now), DeviceID: device.DeviceID,
		Credential: device.Credential, VerificationCode: device.Verification, MacName: h.settings.MacName,
		ProfileID: device.ProfileID, ExpiresAt: device.Expires,
	}, nil
}
