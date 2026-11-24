package config_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestConfigurationDefaultsValidationAndPrivatePersistence(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	f := config.File{Path: filepath.Join(testutil.Dir(t), "ghealth", "config.json")}
	v, err := f.Load()
	if err != nil || !reflect.DeepEqual(v, config.Defaults()) {
		t.Fatal(v, err)
	}
	if _, err := os.Stat(filepath.Dir(f.Path)); !os.IsNotExist(err) {
		t.Fatal("default read created directory")
	}
	for _, tc := range []struct {
		key, value string
		valid      bool
	}{
		{"unknown", "1", false}, {"max_hr_override_bpm", "119", false}, {"max_hr_override_bpm", "231", false}, {"max_hr_override_bpm", "150.1", false},
		{"strain_intent", "push", false}, {"strain_intent", "null", false}, {"wake_target", "25:00", false}, {"wake_target", "7:5", false}, {"wake_target", "07:05\n", false},
		{"sleep_score_mode", "hourly", false}, {"sleep_score_mode", "", false}, {"sleep_score_mode", "null", false}, {"sleep_score_mode", "Composite", false},
		{"sleep_score_mode", "composite", true}, {"sleep_score_mode", "sufficiency", true},
		{"strain_intent", "restore", true}, {"strain_intent", "overreach", true}, {"strain_intent", "maintain", true}, {"wake_target", "00:00", true}, {"wake_target", "23:59", true}, {"wake_target", "06:45", true}, {"wake_target", "null", true}, {"wake_target", "06:45", true},
		{"sleep_base_need_minutes", "359", false}, {"sleep_base_need_minutes", "601", false}, {"trimp_profile", "unknown", false},
		{"max_hr_override_bpm", "120", true}, {"max_hr_override_bpm", "230", true}, {"sleep_base_need_minutes", "360", true}, {"sleep_base_need_minutes", "600", true}, {"trimp_profile", "banister_b167", true},
		{"week_sleep_minutes", "239", false}, {"week_sleep_minutes", "721", false}, {"week_sleep_minutes", "7h", false}, {"week_sleep_nights", "0", false}, {"week_sleep_nights", "8", false},
		{"week_activity_minutes", "0", false}, {"week_activity_minutes", "1001", false}, {"week_strength_days", "0", false}, {"week_strength_days", "8", false}, {"week_strength_days", "null", false},
		{"week_sleep_minutes", "240", true}, {"week_sleep_minutes", "720", true}, {"week_sleep_nights", "1", true}, {"week_sleep_nights", "7", true},
		{"week_activity_minutes", "1", true}, {"week_activity_minutes", "1000", true}, {"week_strength_days", "1", true}, {"week_strength_days", "7", true},
	} {
		before, _ := os.ReadFile(f.Path)
		v, err := f.Set(tc.key, tc.value)
		if (err == nil) != tc.valid {
			t.Fatal(tc, err)
		}
		if !tc.valid {
			after, _ := os.ReadFile(f.Path)
			if string(before) != string(after) {
				t.Fatal("invalid set changed file")
			}
			continue
		}
		got, err := f.Load()
		if err != nil || !reflect.DeepEqual(got, v) {
			t.Fatal("persistence", got, err)
		}
	}
	for _, key := range []string{"max_hr_override_bpm", "sleep_base_need_minutes", "trimp_profile", "strain_intent", "wake_target", "sleep_score_mode", "week_sleep_minutes", "week_sleep_nights", "week_activity_minutes", "week_strength_days"} {
		if _, err := f.Unset(key); err != nil {
			t.Fatal(err)
		}
	}
	v, err = f.Load()
	if err != nil || !reflect.DeepEqual(v, config.Defaults()) {
		t.Fatal("unset", v, err)
	}
	if _, err = f.Unset("unknown"); err == nil {
		t.Fatal("unknown unset accepted")
	}
	for path, mode := range map[string]os.FileMode{f.Path: 0600, filepath.Dir(f.Path): 0700} {
		info, err := os.Stat(path)
		if err != nil || info.Mode().Perm() != mode {
			t.Fatal("private mode", err)
		}
	}
}

func TestConfigurationFixtureAndUnknownFileKey(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	b, err := os.ReadFile("../../fixtures/v2/commands/config_show.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Values   config.Values `json:"values"`
		Defaults config.Values `json:"defaults"`
	}
	if err = json.Unmarshal(b, &fixture); err != nil || fixture.Values.Validate() != nil || !reflect.DeepEqual(fixture.Defaults, config.Defaults()) {
		t.Fatal("config fixture", err)
	}
	f := config.File{Path: filepath.Join(t.TempDir(), "config.json")}
	for _, body := range []string{`{"unknown":1}`, `null`, `{} {}`, `{"sleep_base_need_minutes":null}`, `{"sport_aliases":null}`, `{"strain_intent":null}`, `{"strain_intent":"push"}`, `{"wake_target":"7:5"}`, `{"wake_target":"25:00"}`, `{"sleep_score_mode":null}`, `{"sleep_score_mode":""}`, `{"sleep_score_mode":"hourly"}`, `{"week_targets":null}`, `{"week_targets":{"sleep_nights":0}}`, `{"week_targets":{"unknown":1}}`} {
		if err = os.WriteFile(f.Path, []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err = f.Load(); err == nil {
			t.Fatalf("invalid file accepted: %s", body)
		}
	}
}

func TestSportAliasValidationPersistenceAndMissingUnset(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	f := config.File{Path: filepath.Join(os.Getenv("HOME"), "config.json")}
	for _, tc := range []struct{ key, value string }{
		{"sport_alias.", "BOXING"}, {"sport_alias.kickboxing", "BOXING"}, {"sport_alias.1KICKBOXING", "BOXING"},
		{"sport_alias." + strings.Repeat("A", 41), "BOXING"}, {"sport_alias.KICK-BOXING", "BOXING"},
		{"sport_alias.KICKBOXING", "unknown"}, {"sport_alias.KICKBOXING", "KICKBOXING"},
	} {
		before, _ := os.ReadFile(f.Path)
		if _, err := f.Set(tc.key, tc.value); !errors.Is(err, config.ErrInvalid) {
			t.Fatalf("accepted %s", tc.key)
		}
		after, _ := os.ReadFile(f.Path)
		if !bytes.Equal(before, after) {
			t.Fatal("invalid alias wrote config")
		}
	}
	if _, err := f.Unset("sport_alias.MISSING"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(f.Path); !os.IsNotExist(err) {
		t.Fatal("missing unset wrote config")
	}
	v, err := f.Set("sport_alias.KICKBOXING", "BOXING")
	if err != nil || v.SportAliases["KICKBOXING"] != "BOXING" {
		t.Fatal("set", err)
	}
	v, err = f.Load()
	if err != nil || v.SportAliases["KICKBOXING"] != "BOXING" {
		t.Fatal("load", err)
	}
	for i := 0; i < 19; i++ {
		if _, err = f.Set(fmt.Sprintf("sport_alias.SOURCE_%d", i), "BOXING"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = f.Set("sport_alias.OVER_LIMIT", "BOXING"); !errors.Is(err, config.ErrInvalid) {
		t.Fatal("accepted 21 aliases")
	}
	if _, err = f.Set("sport_alias.KICKBOXING", "RUNNING"); err != nil {
		t.Fatal("update at limit", err)
	}
	v, err = f.Unset("sport_alias.KICKBOXING")
	if err != nil || len(v.SportAliases) != 19 {
		t.Fatal("unset", err)
	}
	if _, err = f.Unset("sport_alias.bad"); !errors.Is(err, config.ErrInvalid) {
		t.Fatal("accepted invalid unset")
	}
}

func TestConfigurationOldFileUsesParityDefaults(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	f := config.File{Path: filepath.Join(os.Getenv("HOME"), "config.json")}
	if err := os.WriteFile(f.Path, []byte(`{"max_hr_override_bpm":null,"sleep_base_need_minutes":450,"trimp_profile":"banister_b192","sport_aliases":{}}`), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := f.Load()
	if err != nil || got.StrainIntent != "maintain" || got.WakeTarget != nil || got.Week != config.Defaults().Week {
		t.Fatal("old config parity defaults", got, err)
	}
}

// The default mode is stored and echoed as nothing, so default files and bodies keep their bytes.
func TestSleepScoreModeDefaultIsNeverWritten(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	f := config.File{Path: filepath.Join(os.Getenv("HOME"), "config.json")}
	if b, _ := json.Marshal(config.Defaults()); bytes.Contains(b, []byte("sleep_score_mode")) {
		t.Fatal("defaults echo the mode", string(b))
	}
	file := func() string { b, _ := os.ReadFile(f.Path); return string(b) }
	v, err := f.Set("sleep_score_mode", "composite")
	if err != nil || !v.CompositeSleep() || !strings.Contains(file(), `"sleep_score_mode":"composite"`) {
		t.Fatal("composite not written", err, file())
	}
	for _, step := range []func() (config.Values, error){
		func() (config.Values, error) { return f.Set("sleep_score_mode", "sufficiency") },
		func() (config.Values, error) {
			f.Set("sleep_score_mode", "composite")
			return f.Unset("sleep_score_mode")
		},
	} {
		v, err = step()
		if err != nil || v.CompositeSleep() || v.SleepScoreMode != "" || strings.Contains(file(), "sleep_score_mode") {
			t.Fatal("default mode written", err, file())
		}
	}
	if err = os.WriteFile(f.Path, []byte(`{"sleep_score_mode":"sufficiency"}`), 0600); err != nil {
		t.Fatal(err)
	}
	v, err = f.Load()
	if err != nil || v.SleepScoreMode != "" || !reflect.DeepEqual(v, config.Defaults()) {
		t.Fatal("explicit sufficiency is the default", v, err)
	}
}

func TestWeekTargetsDefaultsAndPartialFile(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	want := config.WeekTargets{SleepMinutes: 420, SleepNights: 5, ActivityMinutes: 150, StrengthDays: 2}
	if config.Defaults().Week != want {
		t.Fatal("week defaults", config.Defaults().Week)
	}
	f := config.File{Path: filepath.Join(os.Getenv("HOME"), "config.json")}
	if err := os.WriteFile(f.Path, []byte(`{"week_targets":{"sleep_nights":4}}`), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := f.Load()
	want.SleepNights = 4
	if err != nil || got.Week != want {
		t.Fatal("partial week targets", got.Week, err)
	}
	b, err := json.Marshal(got.Score)
	if err != nil || bytes.Contains(b, []byte("week")) {
		t.Fatal("score settings carry week targets", string(b), err)
	}
}
