package schedule_test

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/schedule"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestLaunchAgentXMLContract(t *testing.T) {
	for _, name := range []string{"collect", "serve"} {
		got, err := schedule.Render("/Users/synthetic", "io.ghealth."+name)
		if err != nil {
			t.Fatal(err)
		}
		want, err := os.ReadFile("testdata/" + name + ".plist")
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, want) {
			t.Fatalf("%s XML mismatch\n%s", name, got)
		}
	}
}
func TestScheduleLifecycleAndPrivateLogs(t *testing.T) {
	home := testutil.Dir(t)
	loaded := map[string]bool{}
	manager := schedule.Manager{Home: home, Run: func(ctx context.Context, args ...string) error {
		switch args[0] {
		case "print":
			if loaded[args[1][strings.LastIndex(args[1], "/")+1:]] {
				return nil
			}
			return errors.New("not loaded")
		case "bootstrap":
			raw, err := os.ReadFile(args[2])
			if err != nil || !bytes.Contains(raw, []byte(filepath.Join(home, ".local", "bin", "ghealth"))) {
				t.Fatal("bootstrap cannot read installed plist")
			}
			loaded[strings.TrimSuffix(filepath.Base(args[2]), ".plist")] = true
		case "bootout":
			delete(loaded, args[1][strings.LastIndex(args[1], "/")+1:])
		default:
			t.Fatal("unexpected launchctl operation")
		}
		return nil
	}}
	ctx := context.Background()
	if err := manager.Install(ctx); err != nil {
		t.Fatal(err)
	}
	for _, agent := range manager.Status(ctx) {
		if !agent.Loaded || !agent.Installed {
			t.Fatal(agent)
		}
	}
	logs := filepath.Join(home, ".local", "share", "ghealth", "logs")
	for _, path := range []string{logs, filepath.Join(logs, "collect.log"), filepath.Join(logs, "serve.log")} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		want := os.FileMode(0600)
		if info.IsDir() {
			want = 0700
		}
		if info.Mode().Perm() != want {
			t.Fatal("private modes")
		}
	}
	if err := manager.Install(ctx); err != nil {
		t.Fatal("reinstall", err)
	}
	f, err := os.OpenFile(filepath.Join(logs, "serve.log"), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err = f.Write(make([]byte, (1<<20)+1)); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(logs, "collect.log"), []byte("small"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = schedule.TrimLogs(filepath.Dir(logs)); err != nil {
		t.Fatal(err)
	}
	if _, err = f.Write([]byte("continued")); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Join(logs, "serve.log"))
	if string(raw) != "continued" {
		t.Fatal("open writer did not continue after truncation")
	}
	raw, _ = os.ReadFile(filepath.Join(logs, "collect.log"))
	if string(raw) != "small" {
		t.Fatal("small log truncated")
	}
	if err = manager.Uninstall(ctx); err != nil {
		t.Fatal(err)
	}
	for _, agent := range manager.Status(ctx) {
		if agent.Loaded || agent.Installed {
			t.Fatal(agent)
		}
	}
}
