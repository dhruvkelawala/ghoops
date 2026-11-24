package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"regexp"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

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
