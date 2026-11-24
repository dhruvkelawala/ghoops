package health_test

import (
	"encoding/json"
	"errors"
	"fmt"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/health"
)

func TestCollectionErrorCodeRejectsForeignMessagesAndCanonicalizesAPIStatus(t *testing.T) {
	for _, tc := range []struct {
		err  error
		code string
	}{
		{nil, "request_failed"},
		{errors.New("sleep duration exceeds session"), "request_failed"},
		{errors.New("invalid numeric health field"), "request_failed"},
		{errors.New("invalid_sleep_summary synthetic-private-token 12345"), "request_failed"},
		{fmt.Errorf("synthetic-private-wrapper: %w", errors.New("invalid Google Health page")), "request_failed"},
		{(*health.APIError)(nil), "request_failed"},
		{&health.APIError{Status: 400, Code: "synthetic-private-token"}, "invalid_request_or_account_unlinked"},
		{&health.APIError{Status: 401, Code: "synthetic-private-token"}, "unauthorized"},
		{&health.APIError{Status: 403, Code: "synthetic-private-token"}, "permission_denied"},
		{&health.APIError{Status: 404, Code: "synthetic-private-token"}, "not_found"},
		{&health.APIError{Status: 429, Code: "synthetic-private-token"}, "rate_limited"},
		{&health.APIError{Status: 501, Code: "synthetic-private-token"}, "unsupported"},
		{&health.APIError{Status: 500, Code: "synthetic-private-token"}, "provider_error"},
	} {
		if got := health.CollectionErrorCode(tc.err); got != tc.code {
			t.Fatalf("got %q, want %q", got, tc.code)
		}
	}
}

func TestShortAwakeningMissingTypeHasSafeDiagnostic(t *testing.T) {
	_, err := health.Decode(health.Record{Type: "sleep", Raw: json.RawMessage(`{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"shortAwakenings":[{"startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:01:00Z"}]}}`)})
	if got := health.CollectionErrorCode(err); got != "short_awakening_missing_type" {
		t.Fatalf("missing type diagnosis = %q", got)
	}
}

func TestShortAwakeningDiagnosticsSeparateInvalidFields(t *testing.T) {
	for _, tc := range []struct{ awake, code string }{
		{`{"type":"NOT_A_STAGE","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:01:00Z"}`, "short_awakening_invalid_type"},
		{`{"type":"SLEEP_STAGE_TYPE_UNSPECIFIED","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T11:01:00Z"}`, "short_awakening_unspecified_type"},
		{`{"type":"AWAKE","startTime":"2026-10-12T11:00:00Z"}`, "short_awakening_missing_time"},
		{`{"type":"AWAKE","startTime":"2026-10-12T11:00:00Z","endTime":"2026-10-12T10:59:00Z"}`, "short_awakening_invalid_time_order"},
		{`{"type":"AWAKE","startTime":"2026-10-12T09:00:00Z","endTime":"2026-10-12T09:01:00Z"}`, "short_awakening_outside_session"},
	} {
		raw := `{"sleep":{"interval":{"startTime":"2026-10-12T10:00:00Z","endTime":"2026-10-12T12:00:00Z"},"shortAwakenings":[` + tc.awake + `]}}`
		_, err := health.Decode(health.Record{Type: "sleep", Raw: json.RawMessage(raw)})
		if got := health.CollectionErrorCode(err); got != tc.code {
			t.Fatalf("diagnosis = %q, want %q", got, tc.code)
		}
	}
}

func TestDecodeCollectionErrorCodes(t *testing.T) {
	for _, tc := range []struct{ kind, raw, code string }{
		{"sleep", `{}`, "missing_observation_or_type"},
		{"steps", `{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T10:00:00Z"}}}`, "invalid_health_interval"},
		{"daily-resting-heart-rate", `{"dailyRestingHeartRate":{"date":{"year":2026,"month":13,"day":12},"beatsPerMinute":"62"}}`, "invalid_health_date"},
		{"heart-rate", `{"heartRate":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"beatsPerMinute":"301"}}`, "invalid_heart_rate_measurement"},
		{"steps", `{"steps":{"interval":{"startTime":"2026-10-12T12:00:00Z","endTime":"2026-10-12T12:01:00Z"},"count":"1000001"}}`, "invalid_step_count"},
		{"heart-rate-variability", `{"heartRateVariability":{"sampleTime":{"physicalTime":"2026-10-12T12:00:00Z"},"rootMeanSquareOfSuccessiveDifferencesMilliseconds":201}}`, "invalid_sampled_rmssd_measurement"},
		{"daily-resting-heart-rate", `{"dailyRestingHeartRate":{"date":{"year":2026,"month":10,"day":12}}}`, "missing_resting_heart_rate_measurement"},
		{"sleep", `{"sleep":{"interval":{"startTime":"synthetic-private-time"}}}`, "invalid_data_point"},
	} {
		t.Run(tc.code, func(t *testing.T) {
			_, err := health.Decode(health.Record{Type: tc.kind, Raw: json.RawMessage(tc.raw)})
			if err == nil {
				t.Fatal("invalid fixture accepted")
			}
			if got := health.CollectionErrorCode(fmt.Errorf("synthetic-private-wrapper: %w", err)); got != tc.code {
				t.Fatalf("got %q, want %q", got, tc.code)
			}
		})
	}
}
