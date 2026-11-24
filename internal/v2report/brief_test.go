package v2report_test

import (
	"encoding/json"
	"net/url"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestBriefDisclosurePartAndReview(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err := json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	b, err := v2report.New(state, fixtureTime("2026-03-10T14:30:00Z"), config.Defaults(), v2report.Options{})
	if err != nil {
		t.Fatal(err)
	}
	for _, part := range []string{"", "morning", "evening"} {
		for _, values := range []bool{false, true} {
			query := url.Values{"date": {"2026-03-10"}, "include_values": {"false"}}
			if part != "" {
				query.Set("part", part)
			}
			if values {
				query.Set("include_values", "true")
			}
			body, err := b.Build("brief", query)
			if err != nil {
				t.Fatal(err)
			}
			raw, err := json.Marshal(body)
			if err != nil {
				t.Fatal(err)
			}
			var got map[string]any
			if err := json.Unmarshal(raw, &got); err != nil {
				t.Fatal(err)
			}
			if got["note"] != "ghoops estimates from documented formulas; not medical advice. Strain uses Banister's published heart-rate formula on a scale ghoops set from public examples; it is not WHOOP's Strain." {
				t.Fatal("brief estimate disclosure", got["note"])
			}
			wantPart := part
			if wantPart == "" {
				wantPart = "morning"
			}
			if got["part"] != wantPart {
				t.Fatalf("part=%v, want %s", got["part"], wantPart)
			}
			_, review := got["review"]
			if review != (part == "evening") {
				t.Fatal("review disclosure", string(raw))
			}
			if values {
				target := got["strain_target"].(map[string]any)
				plan := got["sleep_plan"].(map[string]any)
				if target["low"] != 13.3 || target["high"] != 16.3 || plan["need_minutes"] != float64(483) || plan["bedtime"] != "2026-03-10T22:25:00Z" {
					t.Fatal("brief values", string(raw))
				}
			} else {
				var inspect func(any)
				inspect = func(value any) {
					switch v := value.(type) {
					case map[string]any:
						for key, child := range v {
							switch key {
							case "low", "high", "need_minutes", "bedtime", "mean_7", "mean_30", "zones_1_3_minutes", "zones_4_5_minutes", "start", "end":
								t.Fatalf("status-only leaked %s", key)
							}
							inspect(child)
						}
					case []any:
						for _, child := range v {
							inspect(child)
						}
					}
				}
				inspect(got)
			}
			if review {
				r := got["review"].(map[string]any)
				if r["workouts"] != float64(1) || r["detected_efforts"] != float64(0) || !reflect.DeepEqual(r["new_flags"], []any{}) {
					t.Fatal("evening counts", r)
				}
				if values && (r["zones_1_3_minutes"] != float64(27) || r["zones_4_5_minutes"] != float64(33)) {
					t.Fatal("evening zones", r)
				}
			}
			keys := []string{"disclosure", "part", "date", "freshness", "recovery", "strain", "strain_target", "sleep", "sleep_plan", "trend", "vitals_adverse", "workouts", "health_flags"}
			if review {
				keys = append(keys, "review")
			}
			keys = append(keys, "note")
			at := -1
			for _, key := range keys {
				next := strings.Index(string(raw), `"`+key+`":`)
				if next <= at {
					t.Fatalf("field order at %s: %s", key, raw)
				}
				at = next
			}
			at = -1
			for _, key := range []string{"recovery", "hrv_rmssd_ms", "resting_hr_bpm", "sleep_performance", "asleep_minutes", "strain"} {
				next := strings.Index(string(raw)[strings.Index(string(raw), `"trend":`):], `"`+key+`":`)
				if next <= at {
					t.Fatalf("trend order at %s: %s", key, raw)
				}
				at = next
			}
		}
	}
}

func TestBriefReviewNewFlagsAgainstPreviousDay(t *testing.T) {
	for _, day := range []string{"2026-03-09", "2026-03-10"} {
		state := store2.State2{}
		state.Records = append(state.Records, testutil.Record(t, "irregular-rhythm-notification", "raw", day, `{"irregularRhythmNotification":{"interval":{"startTime":"`+day+`T01:00:00Z","endTime":"`+day+`T01:30:00Z"}}}`))
		b, err := v2report.New(state, time.Date(2026, 3, 10, 14, 30, 0, 0, time.UTC), config.Defaults(), v2report.Options{})
		if err != nil {
			t.Fatal(err)
		}
		body, err := b.Build("brief", url.Values{"date": {"2026-03-10"}, "part": {"evening"}})
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := json.Marshal(body)
		var got struct {
			Review struct {
				Flags []string `json:"new_flags"`
			} `json:"review"`
		}
		if err := json.Unmarshal(raw, &got); err != nil {
			t.Fatal(err)
		}
		want := []string{}
		if day == "2026-03-10" {
			want = append(want, "irn_alert_recorded")
		}
		if !reflect.DeepEqual(got.Review.Flags, want) {
			t.Fatalf("on %s flags=%v, want %v", day, got.Review.Flags, want)
		}
	}
}

func TestBriefWeekPartHidesValuesWithoutTheFlag(t *testing.T) {
	raw, err := os.ReadFile("../../fixtures/v2/inputs/store_full.json")
	if err != nil {
		t.Fatal(err)
	}
	var state store2.State2
	if err := json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	b, err := v2report.New(state, fixtureTime("2026-03-10T14:30:00Z"), config.Defaults(), v2report.Options{})
	if err != nil {
		t.Fatal(err)
	}
	valueKeys := []string{`"metrics"`, `"min_minutes"`, `"met_nights"`, `"missing_nights"`, `"credit_minutes"`, `"met_days"`, `"missing_days"`}
	for _, include := range []bool{false, true} {
		params := url.Values{"date": {"2026-03-08"}, "part": {"week"}}
		if include {
			params.Set("include_values", "true")
		}
		body, err := b.Build("brief", params)
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := json.Marshal(body.(v2report.Brief).Week)
		for _, key := range valueKeys {
			if strings.Contains(string(raw), key) != include {
				t.Errorf("include_values=%v: %s present=%v in %s", include, key, !include, raw)
			}
		}
		if brief := body.(v2report.Brief); brief.Review != nil || brief.Week.Targets.Sleep.Status != "no_data" {
			t.Fatalf("week part: review %v, sleep %s", brief.Review, brief.Week.Targets.Sleep.Status)
		}
	}
	for _, part := range []string{"morning", "evening"} {
		body, err := b.Build("brief", url.Values{"date": {"2026-03-10"}, "part": {part}})
		if err != nil || body.(v2report.Brief).Week != nil {
			t.Fatalf("%s brief carries a week: %v", part, err)
		}
	}
}
