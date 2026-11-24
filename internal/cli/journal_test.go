package cli_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cli"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestJournalCommands(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	dir, vault := testutil.Dir(t), &testutil.Vault{}
	now := time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC)
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	if err = (store2.Store{Dir: dir, Vault: vault}).Save(state, now); err != nil {
		t.Fatal(err)
	}
	opts := cli.Options{Vault: vault, Now: func() time.Time { return now }}
	invoke := func(want int, args ...string) string {
		t.Helper()
		code, out, stderr := run(t, append([]string{"--state-dir", dir, "journal"}, args...), opts)
		if code != want {
			t.Fatalf("%v: want exit %d got %d: %s", args, want, code, stderr)
		}
		if want != 0 {
			return stderr
		}
		return out
	}
	type entry struct {
		Date    string          `json:"date"`
		Answers map[string]bool `json:"answers"`
	}
	var set struct {
		Kind  string `json:"kind"`
		Date  string `json:"date"`
		Entry *entry `json:"entry"`
	}
	if err = json.Unmarshal([]byte(invoke(0, "set", "alcohol=yes", "late_meal=no")), &set); err != nil || set.Kind != "journal_entry" || set.Date != "2026-03-09" || set.Entry == nil || !set.Entry.Answers["alcohol"] || set.Entry.Answers["late_meal"] {
		t.Fatalf("set without --date must answer for the day before today's Recovery: %+v %v", set, err)
	}
	invoke(0, "set", "--date", "2026-03-09", "late_meal=clear", "stress=yes")
	var show struct {
		Kind       string `json:"kind"`
		From, To   string
		Behaviours []struct{ Key string }
		Entries    []entry
	}
	if err = json.Unmarshal([]byte(invoke(0, "show")), &show); err != nil || show.Kind != "journal" || show.From != "2026-02-09" || show.To != "2026-03-10" || len(show.Behaviours) != 5 {
		t.Fatalf("show: %+v %v", show, err)
	}
	if len(show.Entries) != 1 || len(show.Entries[0].Answers) != 2 || !show.Entries[0].Answers["alcohol"] || !show.Entries[0].Answers["stress"] {
		t.Fatalf("show did not return the set answers: %+v", show.Entries)
	}
	enc, err := os.ReadFile(filepath.Join(dir, journal.FileName))
	if err != nil || bytes.Contains(enc, []byte("alcohol")) || bytes.Contains(enc, []byte("stress")) {
		t.Fatal("behaviour keys must not be readable in the store file", err)
	}
	invoke(0, "set", "--date", "2026-02-08", "alcohol=no")
	invoke(0, "set", "--date", "2026-03-10", "alcohol=no")
	for _, date := range []string{"2026-02-07", "2026-03-11", "2026-3-9"} {
		if !strings.Contains(invoke(2, "set", "--date", date, "alcohol=no"), `"not_found"`) {
			t.Fatalf("%s must be not_found", date)
		}
	}
	for _, args := range [][]string{{"set"}, {"set", "coffee=yes"}, {"set", "alcohol=maybe"}} {
		if !strings.Contains(invoke(2, args...), "Invalid journal field: answers.") {
			t.Fatalf("%v accepted", args)
		}
	}
	if !strings.Contains(invoke(0, "show", "--days", "90"), `"from":"2025-12-11"`) {
		t.Fatal("days 90 range")
	}
	invoke(2, "show", "--days", "0")
	invoke(2, "show", "--days", "91")
	invoke(2, "show", "--date", "2026-03-10")
	var catalogue struct {
		Kind       string `json:"kind"`
		Behaviours []struct {
			Key              string
			Enabled, Default bool
		}
	}
	if err = json.Unmarshal([]byte(invoke(0, "behaviours", "set", "sauna,alcohol")), &catalogue); err != nil || catalogue.Kind != "journal_behaviours" || len(catalogue.Behaviours) != len(journal.Catalogue) {
		t.Fatal("behaviours set", err)
	}
	for _, row := range catalogue.Behaviours {
		if row.Enabled != (row.Key == "alcohol" || row.Key == "sauna") {
			t.Fatalf("%s enabled=%v", row.Key, row.Enabled)
		}
	}
	if !strings.Contains(invoke(0, "show"), `"behaviours":[{"key":"alcohol","name":"Alcohol","question":"Did you drink any alcohol?"},{"key":"sauna"`) {
		t.Fatal("show must list the enabled set in catalogue order")
	}
	if !strings.Contains(invoke(2, "behaviours", "set", "coffee"), "Invalid journal field: behaviours.") {
		t.Fatal("unknown behaviour accepted")
	}
	invoke(2, "behaviours", "nonsense")
	if !strings.Contains(invoke(0, "behaviours", "reset"), `{"key":"stress","name":"Stress","question":"Did you feel stressed?","enabled":true,"default":true}`) {
		t.Fatal("reset must restore the defaults")
	}
	invoke(2)
	invoke(2, "impact")
}
