package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func TestDefaultAndAlternateProfilesKeepSeparateSettings(t *testing.T) {
	home := testutil.Dir(t)
	t.Setenv("HOME", home)
	defaultConfig := filepath.Join(home, ".config", "ghealth", "config.json")
	legacy := []byte(`{"sleep_base_need_minutes":495,"strain_intent":"restore","wake_target":"06:45"}`)
	if err := os.MkdirAll(filepath.Dir(defaultConfig), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(defaultConfig, legacy, 0600); err != nil {
		t.Fatal(err)
	}
	other := testutil.Dir(t)
	options := Options{Vault: &testutil.Vault{}}
	readConfig := func(args ...string) v2report.Config {
		t.Helper()
		var out, stderr bytes.Buffer
		if code := Run(context.Background(), args, nil, &out, &stderr, options); code != 0 {
			t.Fatalf("config: exit %d: %s", code, stderr.String())
		}
		var body v2report.Config
		if err := json.Unmarshal(out.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		return body
	}

	separate := readConfig("config", "show", "--state-dir", other)
	otherPath := filepath.Join(other, "config.json")
	if separate.Path != otherPath || separate.Values.SleepBaseNeed != 450 || separate.Values.WakeTarget != nil {
		t.Fatal("alternate profile did not start from defaults")
	}
	separate = readConfig("config", "set", "sleep_base_need_minutes", "510", "--state-dir", other)
	if separate.Path != otherPath || separate.Values.SleepBaseNeed != 510 {
		t.Fatal("alternate config set did not write the selected profile")
	}
	if loaded, err := (config.File{Path: otherPath}).Load(); err != nil || loaded.SleepBaseNeed != 510 {
		t.Fatalf("alternate config readback: %v", err)
	}
	for _, args := range [][]string{
		{"config", "show"},
		{"config", "show", "--state-dir", filepath.Join(home, ".local", "share", "ghealth")},
	} {
		current := readConfig(args...)
		if current.Path != defaultConfig || current.Values.SleepBaseNeed != 495 || current.Values.StrainIntent != "restore" ||
			current.Values.WakeTarget == nil || *current.Values.WakeTarget != "06:45" {
			t.Fatal("default profile did not read its existing settings")
		}
	}
	if raw, err := os.ReadFile(defaultConfig); err != nil || !bytes.Equal(raw, legacy) {
		t.Fatalf("existing config changed: %v", err)
	}

	for _, tc := range []struct {
		args []string
		want int
	}{
		{[]string{"status"}, 495},
		{[]string{"status", "--state-dir", other}, 510},
	} {
		var out, stderr bytes.Buffer
		if code := Run(context.Background(), tc.args, nil, &out, &stderr, options); code != 0 {
			t.Fatalf("status: exit %d: %s", code, stderr.String())
		}
		var body struct {
			ScoreConfig config.Score `json:"score_config"`
		}
		if err := json.Unmarshal(out.Bytes(), &body); err != nil || body.ScoreConfig.SleepBaseNeed != tc.want {
			t.Fatalf("report did not use its profile's settings: %v", err)
		}
	}
}

func TestScheduleChangesRequireDefaultProfile(t *testing.T) {
	home := testutil.Dir(t)
	t.Setenv("HOME", home)
	other := testutil.Dir(t)
	calls := 0
	options := Options{Vault: &testutil.Vault{}, Launchctl: func(context.Context, ...string) error {
		calls++
		return nil
	}}
	for _, command := range []string{"install", "uninstall"} {
		var out, stderr bytes.Buffer
		args := []string{"schedule", command, "--state-dir", other}
		exit := Run(context.Background(), args, nil, &out, &stderr, options)
		if exit != 2 || !strings.Contains(stderr.String(), "schedule manages only the default profile") || calls != 0 {
			t.Fatalf("%s: want usage error before launchctl, got exit %d and %d calls", command, exit, calls)
		}
	}
	var out, stderr bytes.Buffer
	if exit := Run(context.Background(), []string{"schedule", "status", "--state-dir", other}, nil, &out, &stderr, options); exit != 0 {
		t.Fatalf("schedule status: exit %d: %s", exit, stderr.String())
	}
	var body v2report.Schedule
	if err := json.Unmarshal(out.Bytes(), &body); err != nil || body.Profile != "default" || len(body.Agents) != 2 {
		t.Fatalf("schedule status did not identify the managed profile: %v", err)
	}
}

func TestConfigCommandsPersistAndRejectInvalidUsage(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	for _, tc := range []struct {
		args []string
		exit int
		want int
	}{
		{[]string{"config", "show", "--json"}, 0, 450},
		{[]string{"config", "set", "sleep_base_need_minutes", "480", "--json"}, 0, 480},
		{[]string{"config", "show"}, 0, 480},
		{[]string{"config", "unset", "sleep_base_need_minutes"}, 0, 450},
		{[]string{"config", "set", "unknown", "1"}, 2, 0},
		{[]string{"config", "show", "--unexpected"}, 2, 0},
	} {
		var out, stderr bytes.Buffer
		exit := Run(context.Background(), tc.args, nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
		if exit != tc.exit {
			t.Fatalf("%v exit %d %s", tc.args, exit, stderr.String())
		}
		if exit != 0 {
			var body commandErrorBody
			if json.Unmarshal(stderr.Bytes(), &body) != nil || body.Version != 2 || body.Error.Code != "invalid_request" {
				t.Fatal(stderr.String())
			}
			continue
		}
		var body struct {
			Kind   string        `json:"kind"`
			Values config.Values `json:"values"`
		}
		if json.Unmarshal(out.Bytes(), &body) != nil || body.Kind != "config" || body.Values.SleepBaseNeed != tc.want {
			t.Fatal(out.String())
		}
	}
}

func TestConfigSportAliasCommands(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	for _, tc := range []struct {
		args    []string
		exit    int
		aliases int
	}{
		{[]string{"show"}, 0, 0}, {[]string{"set", "sport_alias.KICKBOXING", "BOXING"}, 0, 1},
		{[]string{"show"}, 0, 1}, {[]string{"set", "sport_alias.KICKBOXING", "unknown"}, 2, 0},
		{[]string{"unset", "sport_alias.KICKBOXING"}, 0, 0}, {[]string{"unset", "sport_alias.KICKBOXING"}, 0, 0},
	} {
		var out, stderr bytes.Buffer
		code := Run(context.Background(), append([]string{"config"}, tc.args...), nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
		if code != tc.exit {
			t.Fatalf("config %v: exit %d", tc.args, code)
		}
		if code == 0 {
			var body struct{ Values config.Values }
			if json.Unmarshal(out.Bytes(), &body) != nil || body.Values.SportAliases == nil || len(body.Values.SportAliases) != tc.aliases {
				t.Fatal("wrong alias response")
			}
		}
	}
}

func TestConfigParityKeys(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	for _, tc := range []struct {
		args         []string
		exit         int
		intent, wake string
	}{
		{[]string{"show"}, 0, "maintain", ""},
		{[]string{"set", "strain_intent", "restore"}, 0, "restore", ""},
		{[]string{"set", "wake_target", "06:45"}, 0, "restore", "06:45"},
		{[]string{"show"}, 0, "restore", "06:45"},
		{[]string{"set", "wake_target", "25:00"}, 2, "", ""},
		{[]string{"set", "wake_target", "7:5"}, 2, "", ""},
		{[]string{"set", "strain_intent", "push"}, 2, "", ""},
		{[]string{"set", "wake_target", "null"}, 0, "restore", ""},
		{[]string{"unset", "strain_intent"}, 0, "maintain", ""},
		{[]string{"set", "wake_target", "06:45"}, 0, "maintain", "06:45"},
		{[]string{"unset", "wake_target"}, 0, "maintain", ""},
	} {
		var out, stderr bytes.Buffer
		exit := Run(context.Background(), append([]string{"config"}, tc.args...), nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
		if exit != tc.exit {
			t.Fatalf("config %v: exit %d %s", tc.args, exit, stderr.String())
		}
		if exit != 0 {
			var body commandErrorBody
			if json.Unmarshal(stderr.Bytes(), &body) != nil || body.Error.Code != "invalid_request" {
				t.Fatal("wrong config usage error", stderr.String())
			}
			continue
		}
		var body struct{ Values, Defaults config.Values }
		if json.Unmarshal(out.Bytes(), &body) != nil || body.Values.StrainIntent != tc.intent || body.Defaults.StrainIntent != "maintain" || body.Defaults.WakeTarget != nil {
			t.Fatal("wrong config response", out.String())
		}
		wake := ""
		if body.Values.WakeTarget != nil {
			wake = *body.Values.WakeTarget
		}
		if wake != tc.wake {
			t.Fatalf("wake = %q, want %q", wake, tc.wake)
		}
	}
}

// The default sleep score mode is never echoed, so `config show` stays byte-identical
// until the owner opts in, and unsetting restores the same bytes (scores.md §0.1).
func TestConfigSleepScoreMode(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	generated := regexp.MustCompile(`"generated_at":"[^"]*",`)
	run := func(args ...string) (int, string, string) {
		var out, stderr bytes.Buffer
		exit := Run(context.Background(), append([]string{"config"}, args...), nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
		return exit, generated.ReplaceAllString(out.String(), ""), stderr.String()
	}
	_, before, _ := run("show")
	if strings.Contains(before, "sleep_score_mode") {
		t.Fatal("default mode echoed", before)
	}
	for _, tc := range []struct {
		args      []string
		exit      int
		composite bool
	}{
		{[]string{"set", "sleep_score_mode", "composite"}, 0, true},
		{[]string{"set", "sleep_score_mode", "hourly"}, 2, false},
		{[]string{"set", "sleep_score_mode", ""}, 2, false},
		{[]string{"set", "sleep_score_mode", "null"}, 2, false},
		{[]string{"show"}, 0, true},
		{[]string{"set", "sleep_score_mode", "sufficiency"}, 0, false},
		{[]string{"set", "sleep_score_mode", "composite"}, 0, true},
		{[]string{"unset", "sleep_score_mode"}, 0, false},
	} {
		exit, out, stderr := run(tc.args...)
		if exit != tc.exit {
			t.Fatalf("config %v: exit %d %s", tc.args, exit, stderr)
		}
		if exit != 0 {
			var body commandErrorBody
			if json.Unmarshal([]byte(stderr), &body) != nil || body.Error.Code != "invalid_request" {
				t.Fatal("wrong config usage error", stderr)
			}
			continue
		}
		var body struct{ Values, Defaults config.Values }
		if json.Unmarshal([]byte(out), &body) != nil || body.Values.CompositeSleep() != tc.composite || body.Defaults.SleepScoreMode != "" {
			t.Fatal("wrong config response", tc.args, out)
		}
		if !tc.composite && strings.Contains(out, "sleep_score_mode") {
			t.Fatal("default mode echoed", tc.args, out)
		}
	}
	if _, after, _ := run("show"); after != before {
		t.Fatalf("unset did not restore the default body:\n%s\n%s", before, after)
	}
}

func TestConfigWeekTargetKeys(t *testing.T) {
	t.Setenv("HOME", testutil.Dir(t))
	for _, tc := range []struct {
		args   []string
		exit   int
		nights int
	}{
		{[]string{"show"}, 0, 5},
		{[]string{"set", "week_sleep_nights", "4"}, 0, 4},
		{[]string{"set", "week_sleep_nights", "8"}, 2, 0},
		{[]string{"show"}, 0, 4},
		{[]string{"unset", "week_sleep_nights"}, 0, 5},
	} {
		var out, stderr bytes.Buffer
		exit := Run(context.Background(), append([]string{"config"}, tc.args...), nil, &out, &stderr, Options{Vault: &testutil.Vault{}})
		if exit != tc.exit {
			t.Fatalf("config %v: exit %d %s", tc.args, exit, stderr.String())
		}
		if exit != 0 {
			continue
		}
		var body struct {
			Values, Defaults struct {
				Week map[string]int `json:"week_targets"`
			}
		}
		if json.Unmarshal(out.Bytes(), &body) != nil || body.Values.Week["sleep_nights"] != tc.nights || body.Defaults.Week["sleep_nights"] != 5 || len(body.Values.Week) != 4 {
			t.Fatal("wrong week targets", out.String())
		}
	}
}
