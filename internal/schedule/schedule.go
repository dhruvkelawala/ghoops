package schedule

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"text/template"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

type Agent struct {
	Label     string `json:"label"`
	Installed bool   `json:"installed"`
	Loaded    bool   `json:"loaded"`
	Path      string `json:"path"`
}
type Manager struct {
	Home string
	Run  func(context.Context, ...string) error
}

var labels = []string{"io.ghealth.collect", "io.ghealth.serve"}

func (m Manager) command(ctx context.Context, args ...string) error {
	if m.Run != nil {
		return m.Run(ctx, args...)
	}
	if err := exec.CommandContext(ctx, "/bin/launchctl", args...).Run(); err != nil {
		return errors.New("launchctl operation failed")
	}
	return nil
}
func (m Manager) domain() string { return "gui/" + strconv.Itoa(os.Getuid()) }
func (m Manager) Status(ctx context.Context) []Agent {
	out := []Agent{}
	for _, label := range labels {
		path := filepath.Join(m.Home, "Library", "LaunchAgents", label+".plist")
		info, err := os.Lstat(path)
		installed := err == nil && info.Mode().IsRegular()
		out = append(out, Agent{Label: label, Installed: installed, Loaded: m.command(ctx, "print", m.domain()+"/"+label) == nil, Path: path})
	}
	return out
}
func (m Manager) Install(ctx context.Context) error {
	state := filepath.Join(m.Home, ".local", "share", "ghealth")
	if err := secure.PrivateDir(state); err != nil {
		return err
	}
	logDir := filepath.Join(state, "logs")
	if err := secure.PrivateDir(logDir); err != nil {
		return err
	}
	for _, name := range []string{"collect.log", "serve.log"} {
		f, err := secure.OpenPrivate(filepath.Join(logDir, name), os.O_CREATE|os.O_APPEND|os.O_WRONLY)
		if err != nil {
			return err
		}
		if err = f.Close(); err != nil {
			return err
		}
	}
	agents := m.Status(ctx)
	dir := filepath.Join(m.Home, "Library", "LaunchAgents")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return errors.New("cannot create LaunchAgents directory")
	}
	info, err := os.Lstat(dir)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("invalid LaunchAgents directory")
	}
	for _, agent := range agents {
		body, err := Render(m.Home, agent.Label)
		if err != nil {
			return err
		}
		if agent.Loaded {
			if err = m.command(ctx, "bootout", m.domain()+"/"+agent.Label); err != nil {
				return err
			}
		}
		f, err := os.CreateTemp(dir, ".ghealth-*.plist")
		if err != nil {
			return errors.New("cannot create LaunchAgent")
		}
		temp := f.Name()
		if _, err = f.Write(body); err == nil {
			err = f.Sync()
		}
		closeErr := f.Close()
		if err == nil {
			err = closeErr
		}
		if err == nil {
			err = os.Rename(temp, agent.Path)
		}
		os.Remove(temp)
		if err != nil {
			return errors.New("cannot save LaunchAgent")
		}
		if err = m.command(ctx, "bootstrap", m.domain(), agent.Path); err != nil {
			return err
		}
	}
	return nil
}
func (m Manager) Uninstall(ctx context.Context) error {
	for _, agent := range m.Status(ctx) {
		if agent.Loaded {
			if err := m.command(ctx, "bootout", m.domain()+"/"+agent.Label); err != nil {
				return err
			}
		}
		if err := os.Remove(agent.Path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return errors.New("cannot remove LaunchAgent")
		}
	}
	return nil
}
func Render(home, label string) ([]byte, error) {
	if label != "io.ghealth.collect" && label != "io.ghealth.serve" {
		return nil, errors.New("unknown LaunchAgent")
	}
	escape := func(s string) string { var b bytes.Buffer; xml.EscapeText(&b, []byte(s)); return b.String() }
	t, err := template.New("agent").Funcs(template.FuncMap{"xml": escape}).Parse(plist)
	if err != nil {
		return nil, err
	}
	var b bytes.Buffer
	err = t.Execute(&b, struct {
		Label, Binary, Log string
		Collect            bool
	}{label, filepath.Join(home, ".local", "bin", "ghealth"), filepath.Join(home, ".local", "share", "ghealth", "logs", label[len("io.ghealth."):]+".log"), label == "io.ghealth.collect"})
	return b.Bytes(), err
}

const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>{{xml .Label}}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{{xml .Binary}}</string>
{{if .Collect}}    <string>collect</string>
    <string>--json</string>
    <string>--quiet</string>
{{else}}    <string>serve</string>
{{end}}  </array>
  <key>RunAtLoad</key><true/>
{{if .Collect}}  <key>StartInterval</key><integer>1800</integer>
{{else}}  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
{{end}}  <key>StandardOutPath</key><string>{{xml .Log}}</string>
  <key>StandardErrorPath</key><string>{{xml .Log}}</string>
</dict>
</plist>
`

func TrimLogs(stateDir string) error {
	for _, name := range []string{"collect.log", "serve.log"} {
		path := filepath.Join(stateDir, "logs", name)
		f, err := secure.OpenPrivate(path, os.O_WRONLY)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return errors.New("cannot open private log")
		}
		info, err := f.Stat()
		if err == nil && info.Size() > 1<<20 {
			err = f.Truncate(0)
		}
		closeErr := f.Close()
		if err != nil {
			return errors.New("cannot trim log")
		}
		if closeErr != nil {
			return errors.New("cannot close log")
		}
	}
	return nil
}
