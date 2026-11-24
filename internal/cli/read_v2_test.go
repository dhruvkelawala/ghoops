package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestV2ReadsStayOfflineAndFailClosed(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	dir := testutil.Dir(t)
	client := health.New(func(context.Context, string) (string, error) {
		t.Fatal("read requested network credentials")
		return "", nil
	})
	opts := Options{Vault: &testutil.Vault{}, Fetcher: client, Now: func() time.Time { return time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC) }}
	run := func(args ...string) (int, []byte, []byte) {
		var out, err bytes.Buffer
		code := Run(context.Background(), append([]string{"--state-dir", dir}, args...), nil, &out, &err, opts)
		return code, out.Bytes(), err.Bytes()
	}
	for _, kind := range []string{"day", "sleep", "days", "workouts", "status", "snapshot", "brief"} {
		code, out, stderr := run(kind)
		if code != 0 {
			t.Fatalf("%s %d %s", kind, code, stderr)
		}
		var body struct {
			Version int    `json:"schema_version"`
			Kind    string `json:"kind"`
		}
		if json.Unmarshal(out, &body) != nil || body.Version != 2 || body.Kind != kind {
			t.Fatal(string(out))
		}
	}
	code, out, stderr := run("day", "--date", "2026-03-11")
	if code != 2 || len(out) != 0 {
		t.Fatalf("date exit %d", code)
	}
	var e v2report.ErrorBody
	if json.Unmarshal(stderr, &e) != nil || e.Error.Code != "date_out_of_range" {
		t.Fatal(string(stderr))
	}
	if err := os.WriteFile(filepath.Join(dir, "records-v2.enc"), []byte("corrupt"), 0600); err != nil {
		t.Fatal(err)
	}
	code, out, stderr = run("snapshot")
	if code != 1 || len(out) != 0 {
		t.Fatalf("corrupt exit %d", code)
	}
	if json.Unmarshal(stderr, &e) != nil || e.Error.Code != "store_unavailable" {
		t.Fatal(string(stderr))
	}
}

func TestBriefPartCLI(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	dir := testutil.Dir(t)
	for _, part := range []string{"morning", "evening", "noon", ""} {
		var out, stderr bytes.Buffer
		code := Run(context.Background(), []string{"--state-dir", dir, "brief", "--part", part}, nil, &out, &stderr, Options{Vault: &testutil.Vault{}, Now: func() time.Time { return time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC) }})
		if part == "morning" || part == "evening" {
			var body struct{ Part string }
			if code != 0 || json.Unmarshal(out.Bytes(), &body) != nil || body.Part != part {
				t.Fatalf("part %q: code %d, %s %s", part, code, out.String(), stderr.String())
			}
		} else {
			var body v2report.ErrorBody
			if code != 2 || out.Len() != 0 || json.Unmarshal(stderr.Bytes(), &body) != nil || body.Error.Code != "invalid_request" || !strings.Contains(body.Error.Message, "part") {
				t.Fatalf("invalid part %q: %d %s", part, code, stderr.String())
			}
		}
	}
}

func TestTCXCreatesPrivateFileAndPreservesExistingFiles(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	dir := testutil.Dir(t)
	status := 200
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(status); w.Write([]byte("synthetic-tcx")) }))
	defer server.Close()
	client := health.New(func(context.Context, string) (string, error) { return "synthetic", nil })
	client.BaseURL = server.URL
	opts := Options{Vault: &testutil.Vault{}, Fetcher: client}
	run := func(path string) (int, []byte) {
		var out, stderr bytes.Buffer
		code := Run(context.Background(), []string{"--state-dir", dir, "workout", "export-tcx", "--id", "synthetic-id", "--output", path}, nil, &out, &stderr, opts)
		return code, stderr.Bytes()
	}
	path := filepath.Join(dir, "export.tcx")
	if code, stderr := run(path); code != 0 {
		t.Fatalf("%d %s", code, stderr)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("private export mode")
	}
	if code, _ := run(path); code != 1 {
		t.Fatalf("overwrite exit %d", code)
	}
	data, _ := os.ReadFile(path)
	if string(data) != "synthetic-tcx" {
		t.Fatal("existing export changed")
	}
	status = 403
	missing := filepath.Join(dir, "missing.tcx")
	code, stderr := run(missing)
	var e v2report.ErrorBody
	if code != 1 || json.Unmarshal(stderr, &e) != nil || e.Error.Code != "permission_missing" {
		t.Fatalf("%d %s", code, stderr)
	}
	if _, err = os.Stat(missing); !os.IsNotExist(err) {
		t.Fatal("failed export retained")
	}
}
