package v2report

import (
	"time"

	"github.com/dhruvkelawala/ghoops/internal/health"
)

type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	HTTP    *int   `json:"http_status"`
}

func (e *Error) Error() string { return e.Message }
func NewError(code string) *Error {
	status, message := 500, "An internal error occurred."
	switch code {
	case "invalid_request":
		status, message = 400, "Invalid request parameters."
	case "date_out_of_range":
		status, message = 400, "The requested date range is not available."
	case "unauthorized":
		status, message = 401, "A valid pairing token is required."
	case "not_found":
		status, message = 404, "The requested resource was not found."
	case "method_not_allowed":
		status, message = 405, "This method is not allowed for this resource."
	case "conflict":
		status, message = 409, "This activity ID already has a different body."
	case "payload_too_large":
		status, message = 413, "Request body exceeds 64 KiB."
	case "rate_limited":
		status, message = 429, "Too many failed authentication attempts."
	case "store_unavailable":
		status, message = 503, "The local store is unavailable."
	case "storage_full":
		status, message = 507, "Your Mac's activity file is full. Run ghoops activities compact."
	case "collect_in_progress":
		return &Error{Code: code, Message: "Another collection is in progress."}
	case "collect_failed":
		return &Error{Code: code, Message: "Collection was incomplete."}
	case "permission_missing":
		return &Error{Code: code, Message: "TCX export needs the location.readonly scope; run ghoops auth login"}
	default:
		code = "internal"
	}
	return &Error{Code: code, Message: message, HTTP: &status}
}

type ErrorBody struct {
	Envelope
	Error *Error `json:"error"`
}

func (e *Error) Body(now time.Time) ErrorBody {
	return ErrorBody{Envelope: CommandEnvelope("error", now), Error: e}
}
func CommandEnvelope(kind string, now time.Time) Envelope {
	return Envelope{Version: 2, Kind: kind, Source: health.Source, GeneratedAt: now.UTC(), Timezone: "Europe/London"}
}
