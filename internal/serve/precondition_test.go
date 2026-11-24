package serve_test

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestEditHTTPIfUpdatedAt(t *testing.T) {
	s := newEditServer(t)
	body := editBody(t, "edit")
	var fields map[string]any
	if err := json.Unmarshal([]byte(body), &fields); err != nil {
		t.Fatal(err)
	}
	put := func(note string, condition any, present bool, status int) map[string]any {
		t.Helper()
		fields["notes"] = note
		if present {
			fields["if_updated_at"] = condition
		} else {
			delete(fields, "if_updated_at")
		}
		raw, err := json.Marshal(fields)
		if err != nil {
			t.Fatal(err)
		}
		w := s.request("PUT", "/v2/edits/"+editTarget, string(raw), "application/json", true)
		if w.Code != status {
			t.Fatalf("want %d got %d: %s", status, w.Code, w.Body)
		}
		var response map[string]any
		if err = json.Unmarshal(w.Body.Bytes(), &response); err != nil {
			t.Fatal(err)
		}
		if status == 409 && response["error"].(map[string]any)["message"] != "This activity changed on your Mac." {
			t.Fatal("wrong conflict message")
		}
		return response
	}
	first := put("first note", nil, true, 200)["edit"].(map[string]any)["updated_at"].(string)
	s.now = s.now.Add(2 * time.Second)
	second := put("second note", first, true, 200)["edit"].(map[string]any)["updated_at"].(string)
	put("stale note", first, true, 409)
	put("null note", nil, true, 409)
	replay := put("second note", first, true, 200)["edit"].(map[string]any)["updated_at"].(string)
	if replay != second {
		t.Fatal("replay changed timestamp")
	}
	s.now = s.now.Add(2 * time.Second)
	fractional := strings.TrimSuffix(second, "Z") + ".900Z"
	put("fractional match", fractional, true, 200)
	put("old phone", nil, false, 200)
	put("invalid time", "bad", true, 400)
	book, err := s.store.Load()
	if err != nil || len(book.Edits) != 1 || *book.Edits[0].Notes != "old phone" {
		t.Fatal("refused write changed book", err)
	}
}
