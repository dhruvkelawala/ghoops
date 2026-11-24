package serve

import (
	"compress/gzip"
	"io"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func TestCompressionThresholdAndErrorBody(t *testing.T) {
	for _, size := range []int{1023, 1024, 4096} {
		t.Run(strconv.Itoa(size), func(t *testing.T) {
			body := strings.Repeat("e", size)
			recorder := httptest.NewRecorder()
			response := &bufferedResponse{ResponseWriter: recorder}
			response.WriteHeader(409)
			response.WriteHeader(200)
			response.Write([]byte(body))
			response.send([]string{"gzip"})
			if recorder.Code != 409 {
				t.Fatal("error status lost", recorder.Code)
			}
			got := recorder.Body.String()
			if size >= 1024 {
				if recorder.Header().Get("Content-Encoding") != "gzip" {
					t.Fatal("large error is identity")
				}
				reader, err := gzip.NewReader(recorder.Body)
				if err != nil {
					t.Fatal(err)
				}
				inflated, err := io.ReadAll(reader)
				reader.Close()
				if err != nil {
					t.Fatal(err)
				}
				got = string(inflated)
			} else if recorder.Header().Get("Content-Encoding") != "" {
				t.Fatal("small error compressed")
			}
			if got != body {
				t.Fatal("error bytes changed")
			}
		})
	}
}
