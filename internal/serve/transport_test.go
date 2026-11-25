package serve_test

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/serve"
)

func TestRequestLogUsesRouteTemplates(t *testing.T) {
	s := newEditServer(t)
	for _, tc := range []struct {
		method, path, template string
		authorized             bool
		status                 int
	}{
		{http.MethodPut, "/v2/journal/2026-03-10", "/v2/journal/{date}", true, 200},
		{http.MethodGet, "/v2/x/y", "other", true, 404},
		{http.MethodPut, "/v2/journal/2026-03-10", "/v2/journal/{date}", false, 401},
	} {
		s.logs.Reset()
		body, media := "", ""
		if tc.method == http.MethodPut {
			body, media = `{"answers":{"alcohol":true}}`, "application/json"
		}
		w := s.request(tc.method, tc.path, body, media, tc.authorized)
		if w.Code != tc.status {
			t.Fatalf("status = %d, want %d", w.Code, tc.status)
		}
		var entry struct {
			Path   string
			Status int
		}
		if err := json.Unmarshal(s.logs.Bytes(), &entry); err != nil {
			t.Fatal(err)
		}
		if entry.Path != tc.template || entry.Status != tc.status {
			t.Errorf("log path %q status %d, want %q status %d", entry.Path, entry.Status, tc.template, tc.status)
		}
	}
}

func TestServerReadTimeoutClosesStalledBody(t *testing.T) {
	s := newEditServer(t)
	server := httptest.NewUnstartedServer(s.handler)
	server.Config = serve.Server(s.handler)
	if server.Config.ReadTimeout != 15*time.Second {
		t.Errorf("read timeout = %s, want 15s", server.Config.ReadTimeout)
	}
	server.Config.ReadTimeout = 150 * time.Millisecond
	server.Start()
	defer server.Close()

	conn, err := net.DialTimeout("tcp", server.Listener.Addr().String(), 3*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	_, err = fmt.Fprintf(conn, "PUT /v2/journal/2026-03-10 HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nContent-Length: 32\r\n\r\n{", s.token)
	if err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(conn)
	response, err := http.ReadResponse(reader, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.Copy(io.Discard, response.Body); err != nil {
		t.Fatal(err)
	}
	if err := response.Body.Close(); err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", response.StatusCode)
	}
	if _, err := reader.ReadByte(); err != io.EOF {
		t.Errorf("read after the response = %v, want EOF", err)
	}
}
