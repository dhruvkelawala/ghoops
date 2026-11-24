package serve_test

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"io"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGzipSnapshotNegotiationAndSmallMutation(t *testing.T) {
	s := newEditServer(t)
	identity := s.request("GET", "/v2/snapshot", "", "", true)
	if identity.Code != 200 || identity.Header().Get("Content-Encoding") != "" {
		t.Fatal("identity snapshot", identity.Code)
	}
	for _, tc := range []struct {
		encoding   string
		compressed bool
	}{
		{"gzip", true}, {"br, gzip;q=0.5", true}, {"gzip;q=0", false}, {"gzip;q=0.000", false},
		{"gzip;q=invalid", false}, {"gzip;q=2", false}, {"xgzip", false}, {"*", false}, {"GZIP; q=1", true},
	} {
		t.Run(tc.encoding, func(t *testing.T) {
			r := httptest.NewRequest("GET", "/v2/snapshot", nil)
			r.Header.Set("Authorization", "Bearer "+s.token)
			r.Header.Set("Accept-Encoding", tc.encoding)
			w := httptest.NewRecorder()
			s.handler.ServeHTTP(w, r)
			body := w.Body.Bytes()
			if tc.compressed {
				if w.Header().Get("Content-Encoding") != "gzip" || w.Header().Get("Vary") != "Accept-Encoding" {
					t.Fatal("gzip headers missing", w.Header())
				}
				reader, err := gzip.NewReader(bytes.NewReader(body))
				if err != nil {
					t.Fatal(err)
				}
				body, err = io.ReadAll(reader)
				reader.Close()
				if err != nil {
					t.Fatal(err)
				}
			} else if w.Header().Get("Content-Encoding") != "" {
				t.Fatal("unexpected compression")
			}
			if w.Code != 200 || !bytes.Equal(body, identity.Body.Bytes()) {
				t.Fatal("snapshot bytes changed", w.Code)
			}
		})
	}
	r := httptest.NewRequest("PUT", "/v2/edits/"+editTarget, strings.NewReader(editBody(t, "edit")))
	r.Header.Set("Authorization", "Bearer "+s.token)
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("Accept-Encoding", "gzip")
	w := httptest.NewRecorder()
	s.handler.ServeHTTP(w, r)
	if w.Code != 200 || w.Body.Len() >= 1024 || w.Header().Get("Content-Encoding") != "" {
		t.Fatal("small mutation must stay identity", w.Code, w.Body.Len())
	}
	for _, line := range strings.Split(strings.TrimSpace(s.logs.String()), "\n") {
		var fields map[string]json.RawMessage
		if err := json.Unmarshal([]byte(line), &fields); err != nil {
			t.Fatal(err)
		}
		if len(fields) != 5 {
			t.Fatal("log shape changed", len(fields))
		}
		for _, key := range []string{"time", "method", "path", "status", "duration_ms"} {
			if _, ok := fields[key]; !ok {
				t.Fatal("missing log field", key)
			}
		}
	}
}
