package testutil

import (
	"bytes"
	"encoding/json"
	"math"
	"strconv"
	"strings"
	"testing"
)

func CompareJSON(t *testing.T, got any, want []byte, subset bool) {
	t.Helper()
	actual, err := json.Marshal(got)
	if err != nil {
		t.Fatal(err)
	}
	decode := func(b []byte) any {
		d := json.NewDecoder(bytes.NewReader(b))
		d.UseNumber()
		var v any
		if err := d.Decode(&v); err != nil {
			t.Fatal(err)
		}
		return v
	}
	compareJSON(t, "$", decode(actual), decode(want), subset)
}
func compareJSON(t *testing.T, path string, got, want any, subset bool) {
	t.Helper()
	switch w := want.(type) {
	case map[string]any:
		g, ok := got.(map[string]any)
		if !ok {
			t.Errorf("%s: expected object, got %v", path, got)
			return
		}
		if !subset && len(g) != len(w) {
			t.Errorf("%s: key count got %d want %d", path, len(g), len(w))
		}
		for key, value := range w {
			actual, ok := g[key]
			if !ok {
				t.Errorf("%s.%s: missing key", path, key)
				continue
			}
			compareJSON(t, path+"."+key, actual, value, subset)
		}
	case []any:
		g, ok := got.([]any)
		if !ok || len(g) != len(w) {
			t.Errorf("%s: array length/type differs", path)
			return
		}
		for i, v := range w {
			compareJSON(t, path+"["+strconv.Itoa(i)+"]", g[i], v, subset)
		}
	case json.Number:
		g, ok := got.(json.Number)
		if !ok {
			t.Errorf("%s: expected number, got %v", path, got)
			return
		}
		a, _ := g.Float64()
		b, _ := w.Float64()
		tolerance := 0.0
		s := w.String()
		if i := strings.IndexByte(s, '.'); i >= 0 {
			tolerance = math.Pow10(-(len(s) - i - 1))
		}
		if math.Abs(a-b) > tolerance+1e-9 {
			t.Errorf("%s: got %s want %s", path, g, w)
		}
	default:
		if got != want {
			t.Errorf("%s: got %v want %v", path, got, want)
		}
	}
}
