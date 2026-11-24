package v2report_test

import (
	"encoding/json"
	"net/url"
	"os"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func journalBuilder(t *testing.T, bookName string) *v2report.Builder {
	t.Helper()
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err = json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	var book journal.Book
	if bookName != "" {
		if raw, err = os.ReadFile("../../fixtures/v2/journal/book_" + bookName + ".json"); err != nil {
			t.Fatal(err)
		}
		if err = json.Unmarshal(raw, &book); err != nil {
			t.Fatal(err)
		}
	}
	b, err := v2report.New(state, fixtureTime("2026-03-10T14:30:00Z"), config.Defaults(), v2report.Options{Journal: book, Auth: v2report.Auth{Authorized: true, State: "authorized", Refreshable: true, Missing: []string{}}, ScheduleInstalled: true, Server: v2report.Server{Version: "0.2.0", Revision: "synthetic"}})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestJournalGoldens(t *testing.T) {
	for _, tc := range []struct{ golden, book string }{{"journal_basic", "basic"}, {"journal_empty", ""}} {
		t.Run(tc.golden, func(t *testing.T) {
			got, err := journalBuilder(t, tc.book).Build("journal", url.Values{})
			if err != nil {
				t.Fatal(err)
			}
			path := "../../fixtures/v2/journal/" + tc.golden + ".json"
			if *updateGoldens {
				raw, err := json.MarshalIndent(got, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				if err = os.WriteFile(path, append(raw, '\n'), 0644); err != nil {
					t.Fatal(err)
				}
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			testutil.CompareJSON(t, got, want, false)
		})
	}
}

func TestJournalNeverReachesAgentBodies(t *testing.T) {
	with, without := journalBuilder(t, "basic"), journalBuilder(t, "")
	for _, kind := range []string{"day", "days", "brief", "status", "sleep", "workouts"} {
		a, err := with.Build(kind, url.Values{})
		if err != nil {
			t.Fatal(err)
		}
		b, _ := without.Build(kind, url.Values{})
		x, _ := json.Marshal(a)
		y, _ := json.Marshal(b)
		if string(x) != string(y) {
			t.Fatalf("%s changes when a journal exists", kind)
		}
	}
}
