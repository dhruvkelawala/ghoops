package serve

import (
	"bytes"
	"compress/gzip"
	"net/http"
	"strconv"
	"strings"
)

type bufferedResponse struct {
	http.ResponseWriter
	body   bytes.Buffer
	status int
}

func (w *bufferedResponse) WriteHeader(status int) {
	if w.status == 0 {
		w.status = status
	}
}

func (w *bufferedResponse) Write(body []byte) (int, error) {
	w.WriteHeader(http.StatusOK)
	return w.body.Write(body)
}

func (w *bufferedResponse) send(encoding []string) {
	body := w.body.Bytes()
	if len(body) >= 1024 && acceptsGzip(encoding) {
		var compressed bytes.Buffer
		writer := gzip.NewWriter(&compressed)
		_, err := writer.Write(body)
		closeErr := writer.Close()
		if err == nil && closeErr == nil {
			body = compressed.Bytes()
			w.Header().Set("Content-Encoding", "gzip")
			w.Header().Add("Vary", "Accept-Encoding")
			w.Header().Del("Content-Length")
		}
	}
	if w.status == 0 {
		w.status = http.StatusOK
	}
	w.ResponseWriter.WriteHeader(w.status)
	w.ResponseWriter.Write(body)
}

func acceptsGzip(headers []string) bool {
	for _, header := range headers {
		for _, entry := range strings.Split(header, ",") {
			parts := strings.Split(entry, ";")
			if !strings.EqualFold(strings.TrimSpace(parts[0]), "gzip") {
				continue
			}
			quality := 1.0
			for _, parameter := range parts[1:] {
				key, value, ok := strings.Cut(strings.TrimSpace(parameter), "=")
				if strings.EqualFold(strings.TrimSpace(key), "q") {
					if !ok {
						quality = 0
						break
					}
					parsed, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
					if err != nil {
						quality = 0
						break
					}
					quality = parsed
				}
			}
			if quality > 0 && quality <= 1 {
				return true
			}
		}
	}
	return false
}
