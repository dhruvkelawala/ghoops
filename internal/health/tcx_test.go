package health_test

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/health"
)

func TestTCXReadRoute(t *testing.T) {
	for _, partial := range []bool{false, true} {
		t.Run(fmt.Sprint(partial), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != "GET" || r.URL.Path != "/v4/users/me/dataTypes/exercise/dataPoints/synthetic-id:exportExerciseTcx" || r.URL.Query().Get("alt") != "media" || (r.URL.Query().Get("partialData") == "true") != partial {
					t.Errorf("unexpected TCX request %s", r.URL)
				}
				if !partial && r.URL.Query().Has("partialData") {
					t.Error("partial flag must be absent")
				}
				fmt.Fprint(w, "<TrainingCenterDatabase>synthetic</TrainingCenterDatabase>")
			}))
			defer server.Close()
			c := health.New(func(context.Context, string) (string, error) { return "synthetic-token", nil })
			c.BaseURL = server.URL
			data, err := c.ExportTCX(context.Background(), "synthetic-id", partial)
			if err != nil || string(data) != "<TrainingCenterDatabase>synthetic</TrainingCenterDatabase>" {
				t.Fatalf("%q %v", data, err)
			}
		})
	}
}
