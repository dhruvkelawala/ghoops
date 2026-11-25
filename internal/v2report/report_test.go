package v2report_test

import (
	"encoding/json"
	"flag"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/score"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/testutil/scorefixture"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

var updateGoldens = flag.Bool("update-goldens", false, "write fixture response goldens")

const fixtureProfileID = "ghoops-fixture-profile"

var goldenResponses = []struct{ file, input, kind, query string }{
	{"sleep_unstaged", "sleep_unstaged", "sleep", "date=2026-03-10"},
	{"day_unstaged", "sleep_unstaged", "day", "date=2026-03-10"},
	{"days_unstaged", "sleep_unstaged", "days", "from=2026-03-04&to=2026-03-10"},
	{"day_full", "full", "day", "date=2026-03-10"},
	{"day_strain_sparse", "full", "day", "date=2026-03-10"},
	{"day_full_config", "full", "day", "date=2026-03-10"},
	{"day_no_sleep", "no_sleep", "day", "date=2026-03-10"},
	{"day_calibrating", "calibrating", "day", "date=2026-03-10"},
	{"day_new_user", "new_user", "day", "date=2026-03-10"},
	{"sleep_full", "full", "sleep", "date=2026-03-10"},
	{"sleep_no_sleep", "no_sleep", "sleep", "date=2026-03-10"},
	{"workouts_full", "full", "workouts", "from=2026-03-09&to=2026-03-10"},
	{"names/workouts", "one_name", "workouts", "from=2026-03-10&to=2026-03-10"},
	{"names/workouts_edited", "one_name", "workouts", "from=2026-03-10&to=2026-03-10"},
	{"parity/workouts", "parity", "workouts", "from=2026-03-09&to=2026-03-10"},
	{"parity/snapshot", "parity", "snapshot", ""},
	{"parity/heart_rate_effort", "parity", "heart_rate", "start=2026-03-09T16:40:00Z&end=2026-03-09T23:25:00Z"},
	{"days_full", "full", "days", "from=2026-03-04&to=2026-03-10"},
	{"status_full", "full", "status", ""},
	{"status_new_user", "new_user", "status", ""},
	{"brief_full", "full", "brief", "date=2026-03-10"},
	{"brief_full_values", "full", "brief", "date=2026-03-10&include_values=true"},
	{"brief_full_evening", "full", "brief", "date=2026-03-10&part=evening"},
	{"brief_full_evening_values", "full", "brief", "date=2026-03-10&part=evening&include_values=true"},
	{"parity/brief_0309", "parity", "brief", "date=2026-03-09"},
	{"composite/day_full", "full", "day", "date=2026-03-10"},
	{"composite/sleep_full", "full", "sleep", "date=2026-03-10"},
	{"composite/days_full", "full", "days", "from=2026-03-04&to=2026-03-10"},
	{"composite/snapshot", "full", "snapshot", ""},
	{"composite/brief_full_values", "full", "brief", "date=2026-03-10&include_values=true"},
	{"week_full", "full", "week", "date=2026-03-08"},
	{"week_current", "full", "week", ""},
	{"week_config", "full", "week", "date=2026-03-08"},
	{"brief_week", "full", "brief", "date=2026-03-08&part=week"},
	{"brief_week_values", "full", "brief", "date=2026-03-08&part=week&include_values=true"},
}

func TestGoldenResponses(t *testing.T) {
	for _, tc := range goldenResponses {
		t.Run(tc.file, func(t *testing.T) {
			raw, err := os.ReadFile("../../fixtures/v2/inputs/store_" + tc.input + ".json")
			if err != nil {
				t.Fatal(err)
			}
			var state store2.State2
			if err = json.Unmarshal(raw, &state); err != nil {
				t.Fatal(err)
			}
			auth := v2report.Auth{Authorized: true, State: "authorized", Refreshable: true, Missing: []string{}}
			if tc.input == "new_user" {
				auth.Missing = []string{"https://www.googleapis.com/auth/googlehealth.profile.readonly", "https://www.googleapis.com/auth/googlehealth.settings.readonly", "https://www.googleapis.com/auth/googlehealth.irn.readonly", "https://www.googleapis.com/auth/googlehealth.location.readonly"}
				auth.Partial = true
			}
			now, _ := time.Parse(time.RFC3339, "2026-03-10T14:30:00Z")
			if tc.file == "day_strain_sparse" {
				state, err = scorefixture.SparseStrain(state)
				if err != nil {
					t.Fatal(err)
				}
				now = now.AddDate(0, 0, 1)
			}
			cfg := config.Defaults()
			if strings.HasPrefix(tc.file, "composite/") {
				cfg.SleepScoreMode = config.SleepScoreComposite
			}
			if tc.file == "day_full_config" {
				cfg.StrainIntent = "restore"
				wake := "06:45"
				cfg.WakeTarget = &wake
			}
			if tc.file == "week_config" {
				cfg.Week.SleepNights = 4
			}
			options := v2report.Options{Auth: auth, ScheduleInstalled: true, Server: v2report.Server{Version: "0.2.0", Revision: "synthetic", ProfileID: fixturePointer(fixtureProfileID)}}
			if tc.file == "names/workouts_edited" {
				e, err := score.New(state, now, cfg)
				if err != nil {
					t.Fatal(err)
				}
				for _, w := range e.Workouts("2026-03-10", false) {
					end := w.End.Add(time.Minute)
					options.Edits = append(options.Edits, activities.Edit{ID: w.ID, Start: &w.Start, End: &end, UpdatedAt: now})
				}
			}
			b, err := v2report.New(state, now, cfg, options)
			if err != nil {
				t.Fatal(err)
			}
			params, _ := url.ParseQuery(tc.query)
			got, err := b.Build(tc.kind, params)
			if err != nil {
				t.Fatal(err)
			}
			path := "../../fixtures/v2/" + tc.file + ".json"
			if *updateGoldens {
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				raw, err := json.MarshalIndent(got, "", "  ")
				if err != nil {
					t.Fatal(err)
				}
				old, err := os.ReadFile(path)
				if err != nil && !os.IsNotExist(err) {
					t.Fatal(err)
				}
				var before, after any
				if len(old) > 0 {
					if err = json.Unmarshal(old, &before); err != nil {
						t.Fatal(err)
					}
				}
				if err = json.Unmarshal(raw, &after); err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(before, after) {
					if err = os.WriteFile(path, append(raw, '\n'), 0644); err != nil {
						t.Fatal(err)
					}
				}
			}
			want, err := os.ReadFile("../../fixtures/v2/" + tc.file + ".json")
			if err != nil {
				t.Fatal(err)
			}
			testutil.CompareJSON(t, got, want, false)
		})
	}
}

func TestFixtureBodiesPreserveEveryKey(t *testing.T) {
	for _, dir := range []string{"preview", "commands", "errors"} {
		files, err := filepath.Glob("../../fixtures/v2/" + dir + "/*.json")
		if err != nil {
			t.Fatal(err)
		}
		for _, path := range files {
			t.Run(path, func(t *testing.T) {
				raw, err := os.ReadFile(path)
				if err != nil {
					t.Fatal(err)
				}
				var header struct {
					Kind string `json:"kind"`
				}
				if err = json.Unmarshal(raw, &header); err != nil {
					t.Fatal(err)
				}
				var body any
				switch header.Kind {
				case "day":
					body = &v2report.Day{}
				case "sleep":
					body = &v2report.Sleep{}
				case "days":
					body = &v2report.Days{}
				case "workouts":
					body = &v2report.Workouts{}
				case "status":
					body = &v2report.Status{}
				case "snapshot":
					body = &v2report.Snapshot{}
				case "brief":
					body = &v2report.Brief{}
				case "collect":
					body = &v2report.Collect{}
				case "config":
					body = &v2report.Config{}
				case "pair":
					body = &v2report.Pair{}
				case "pair_redeem":
					body = &v2report.PairRedeem{}
				case "pair_status":
					body = &v2report.PairStatus{}
				case "pair_devices":
					body = &v2report.PairDevices{}
				case "schedule":
					body = &v2report.Schedule{}
				case "export":
					body = &v2report.Export{}
				case "error":
					body = &v2report.ErrorBody{}
				case "week":
					body = &v2report.Week{}
				default:
					t.Fatalf("unhandled kind %q", header.Kind)
				}
				if err = json.Unmarshal(raw, body); err != nil {
					t.Fatal(err)
				}
				testutil.CompareJSON(t, body, raw, true)
			})
		}
	}
}

func TestRequestValidation(t *testing.T) {
	now, _ := time.Parse(time.RFC3339, "2026-03-10T14:30:00Z")
	b, err := v2report.New(store2.State2{}, now, config.Defaults(), v2report.Options{})
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ kind, query, code string }{
		{"day", "date=2026-02-30", "invalid_request"},
		{"day", "date=2026-03-11", "date_out_of_range"},
		{"day", "date=2026-03-09&date=2026-03-10", "invalid_request"},
		{"status", "unknown=true", "invalid_request"},
		{"brief", "include_values=1", "invalid_request"},
		{"days", "from=2026-03-01", "invalid_request"},
		{"days", "days=1&from=2026-03-01&to=2026-03-10", "invalid_request"},
		{"days", "days=91", "date_out_of_range"},
		{"days", "from=2026-03-10&to=2026-03-01", "date_out_of_range"},
		{"status/", "", "not_found"},
		{"week", "date=2026-03-11", "date_out_of_range"},
		{"week", "date=2026-02-30", "invalid_request"},
		{"week", "end=2026-03-08", "invalid_request"},
	} {
		t.Run(tc.kind+"/"+tc.query, func(t *testing.T) {
			p, _ := url.ParseQuery(tc.query)
			_, err := b.Build(tc.kind, p)
			if e, ok := err.(*v2report.Error); !ok || e.Code != tc.code {
				t.Fatalf("error=%v, want %s", err, tc.code)
			}
		})
	}

	for _, tc := range []struct{ kind, query, word string }{
		{"day", "date=invalid", "date"},
		{"days", "from=invalid&to=2026-03-10", "from"},
		{"days", "from=2026-03-01&to=invalid", "to"},
		{"days", "days=invalid", "days"},
		{"brief", "include_values=invalid", "include_values"},
		{"brief", "part=noon", "part"},
		{"brief", "part=weekly", "part"},
		{"brief", "part=", "part"},
		{"brief", "part=morning&part=evening", "part"},
	} {
		params, _ := url.ParseQuery(tc.query)
		_, err := b.Build(tc.kind, params)
		e, ok := err.(*v2report.Error)
		if !ok || !strings.Contains(e.Message, tc.word) || strings.Contains(e.Message, "invalid") {
			t.Fatalf("parameter-specific error: %v", err)
		}
	}
	var day v2report.Day
	if err = json.NewDecoder(strings.NewReader(`{"schema_version":2,"future_field":true}`)).Decode(&day); err != nil {
		t.Fatal(err)
	}
}

func TestScoreConstantsTravelWithScoreConfig(t *testing.T) {
	for _, profile := range []string{"banister_b192", "banister_b167"} {
		for _, tc := range goldenResponses {
			t.Run(profile+"/"+tc.file, func(t *testing.T) {
				raw, err := os.ReadFile("../../fixtures/v2/inputs/store_" + tc.input + ".json")
				if err != nil {
					t.Fatal(err)
				}
				var state store2.State2
				if err = json.Unmarshal(raw, &state); err != nil {
					t.Fatal(err)
				}
				cfg := config.Defaults()
				cfg.TrimpProfile = profile
				now, _ := time.Parse(time.RFC3339, "2026-03-10T14:30:00Z")
				b, err := v2report.New(state, now, cfg, v2report.Options{})
				if err != nil {
					t.Fatal(err)
				}
				query, _ := url.ParseQuery(tc.query)
				body, err := b.Build(tc.kind, query)
				if err != nil {
					t.Fatal(err)
				}
				raw, err = json.Marshal(body)
				if err != nil {
					t.Fatal(err)
				}
				var value any
				if err = json.Unmarshal(raw, &value); err != nil {
					t.Fatal(err)
				}
				expected, _ := json.Marshal(score.ConstantsFor(profile))
				var want any
				_ = json.Unmarshal(expected, &want)
				var walk func(any)
				walk = func(v any) {
					switch v := v.(type) {
					case map[string]any:
						_, hasConfig := v["score_config"]
						constants, hasConstants := v["score_constants"]
						if hasConfig != hasConstants {
							t.Fatal("score constants/config presence differs")
						}
						if hasConstants && !reflect.DeepEqual(constants, want) {
							t.Fatalf("constants differ: %v", constants)
						}
						for _, child := range v {
							walk(child)
						}
					case []any:
						for _, child := range v {
							walk(child)
						}
					}
				}
				walk(value)
			})
		}
	}
}
