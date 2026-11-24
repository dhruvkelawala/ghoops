package cli

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
	_ "time/tzdata"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/report"
	"github.com/dhruvkelawala/ghoops/internal/secure"
)

const help = `ghoops: local-first, read-only Google Health v4 collector

Usage: ghoops [--json] [--state-dir PATH] COMMAND

  help                         Show this help
  version                      Show version, revision and toolchain
  doctor [--offline]           Check local runtime, auth and cache readiness
  doctor --keychain-test       Scoped dummy test using fresh installed processes
  doctor --live [--days 7]     Sync and require real records for all core metrics
  auth login --client-file PATH [--no-browser]
                               Authorize through the loopback callback
  auth status                  Local credential status, without network access
  auth refresh                 Refresh and persist authorization, without a browser
  auth logout [--revoke]        Remove local tokens; optionally revoke at Google
  sync [--days 7 | --from YYYY-MM-DD --to YYYY-MM-DD]
                               Collect and encrypt records; --to is inclusive
  probe [--days 14]            Ask every readable API route for records; counts only
  today [--date YYYY-MM-DD]    Summarize local records, without network access
  summary [--days 7 | --from YYYY-MM-DD --to YYYY-MM-DD]
  trends [--days 14 | --from YYYY-MM-DD --to YYYY-MM-DD]
  data export [--days 7 | --from YYYY-MM-DD --to YYYY-MM-DD] [--output PATH]
                               Export raw and reconciled records as JSON

Version 2 (JSON, local reads never collect implicitly):
  collect [--days N | --from D --to D] [--quiet]
                               Collect and encrypt v2 streams
  day [--date D]              Read one cycle's scores and measurements
  sleep [--date D]            Read sleep detail and overnight series
  sleep edit --date D [--start T] [--end T]
  sleep restore --date D
  sleep edits [--days 30]
  days [--days 30 | --from D --to D]
                               Read up to 90 days of trends
  workouts [--days 14 | --from D --to D]
                               Read recorded workouts and detected efforts
  week [--date D]             Read the Monday-to-Sunday week and its targets
  heart-rate --date D | --start T --end T
                               Read covered minutes with cycle-specific rates
  activity add --type T --start T --end T [--origin added] [--notes S]
  activity edit --id ID [--type T|band] [--start T --end T|--band-window]
                [--notes S|--clear-notes] [--merge-with ID[,ID]]
  activity merge --id ID --with ID
  activity hide|unhide|restore --id ID
  activity edits [--days 30]
  activity rate --id ID --rpe 0-10 | --clear
  activity list [--days 30] | delete --id ID
  journal show [--days 30]    Read the private yes/no journal (never in brief)
  journal set [--date D] KEY=yes|no|clear ...
  journal behaviours [set KEY[,KEY...] | reset]
  status                      Read auth, collector, device and calibration status
  snapshot                    Read status, day, sleep, trends and workouts
  brief [--date D] [--include-values] [--part morning|evening|week]
                               Read a compact agent summary
  config show | set KEY VALUE | unset KEY
                               Read or change score configuration
  serve [--port 8787]          Serve read-only JSON on 127.0.0.1
  pair [--rotate] [--url URL] [--png PATH]
                               Print a private pairing link and QR
  pair revoke                 Revoke the active pairing token
  schedule install | uninstall | status
                               Manage collection and server LaunchAgents
  workout export-tcx --id ID --output PATH [--partial]
                               Export plaintext TCX to a new private file

Timezone: Europe/London. Default state: ~/.local/share/ghealth (0700).
JSON schema versions: 1 for original commands, 2 for v2 commands.
Missing values are null with explicit status.
Offline summaries never sync implicitly. Export contains private health data.
Exit codes: 0 success, 1 unavailable/incomplete, 2 invalid usage.
`

type Options struct {
	Version  string
	Revision string
	Vault    secure.Vault
	Auth     *auth.Manager
	Fetcher  cache.Fetcher
	Now      func() time.Time
}
type app struct {
	dir      string
	json     bool
	v2       bool
	out, err io.Writer
	options  Options
	auth     *auth.Manager
	store    cache.Store
	fetcher  cache.Fetcher
	loc      *time.Location
	now      time.Time
}
type usageError struct{ message string }

func (e usageError) Error() string { return e.message }

func Run(ctx context.Context, args []string, in io.Reader, out, stderr io.Writer, options Options) int {
	if len(args) > 0 && args[0] == "internal-keychain-probe" {
		if err := probe(args[1:], in); err != nil {
			fmt.Fprintln(stderr, "ghoops: scoped Keychain probe failed:", err)
			return 1
		}
		return 0
	}
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintln(stderr, "ghoops: cannot find home directory")
		return 1
	}
	a := app{dir: filepath.Join(home, ".local", "share", "ghealth"), out: out, err: stderr, options: options}
	filtered := []string{}
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "--json":
			a.json = true
		case arg == "--state-dir":
			if i+1 == len(args) {
				return a.fail(usageError{"--state-dir requires a path"})
			}
			i++
			a.dir = args[i]
		case strings.HasPrefix(arg, "--state-dir="):
			a.dir = strings.TrimPrefix(arg, "--state-dir=")
		default:
			filtered = append(filtered, arg)
		}
	}
	args = filtered
	if len(args) > 0 {
		switch args[0] {
		case "heart-rate", "activity", "journal", "schedule", "serve", "pair", "workout", "collect", "config", "day", "sleep", "days", "workouts", "status", "snapshot", "brief", "week":
			a.v2 = true
		}
	}
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		fmt.Fprint(out, help)
		return 0
	}
	if args[0] == "version" || args[0] == "--version" {
		a.emit(map[string]any{"schema_version": 1, "version": options.Version, "revision": options.Revision, "go_version": runtime.Version(), "os": runtime.GOOS, "arch": runtime.GOARCH})
		return 0
	}
	if len(args) > 1 && (args[len(args)-1] == "--help" || args[len(args)-1] == "-h") {
		fmt.Fprint(out, help)
		return 0
	}
	if a.dir == "" {
		return a.fail(usageError{"empty state directory"})
	}
	a.dir, err = filepath.Abs(a.dir)
	if err != nil {
		return a.fail(usageError{"invalid state directory"})
	}
	a.loc, err = time.LoadLocation("Europe/London")
	if err != nil {
		return a.fail(err)
	}
	a.now = time.Now()
	if options.Now != nil {
		a.now = options.Now()
	}
	vault := options.Vault
	if vault == nil {
		vault = secure.Keychain{}
	}
	a.auth = options.Auth
	if a.auth == nil {
		a.auth = auth.New(vault, a.dir)
	}
	a.store = cache.Store{Dir: a.dir, Vault: vault}
	a.fetcher = options.Fetcher
	if a.fetcher == nil {
		a.fetcher = health.New(a.auth.Access)
	}
	if args[0] != "serve" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, 10*time.Minute)
		defer cancel()
	}
	switch args[0] {
	case "schedule":
		err = a.schedule(ctx, args[1:])
	case "serve":
		err = a.serve(ctx, args[1:])
	case "pair":
		err = a.pair(ctx, args[1:])
	case "auth":
		err = a.authentication(ctx, args[1:])
	case "doctor":
		err = a.doctor(ctx, args[1:])
	case "sync":
		err = a.sync(ctx, args[1:])
	case "collect":
		err = a.collectV2(ctx, args[1:])
	case "activity":
		err = a.activity(ctx, args[1:])
	case "workout":
		err = a.workout(ctx, args[1:])
	case "config":
		err = a.configure(args[1:])
	case "heart-rate":
		err = a.readV2(ctx, "heart_rate", args[1:])
	case "sleep":
		err = a.sleepCommand(ctx, args[1:])
	case "journal":
		err = a.journalCommand(ctx, args[1:])
	case "day", "days", "workouts", "status", "snapshot", "brief", "week":
		err = a.readV2(ctx, args[0], args[1:])
	case "probe":
		err = a.apiProbe(ctx, args[1:])
	case "today", "summary", "trends":
		err = a.summary(args[0], args[1:])
	case "data":
		if len(args) < 2 || args[1] != "export" {
			err = usageError{"expected data export"}
		} else {
			err = a.export(args[2:])
		}
	default:
		err = usageError{"unknown command; run ghoops help"}
	}
	if err != nil {
		return a.fail(err)
	}
	return 0
}

func (a *app) fail(err error) int {
	if a.v2 {
		return a.failV2(err)
	}
	code := 1
	kind := "unavailable"
	var usage usageError
	if errors.As(err, &usage) {
		code = 2
		kind = "usage"
	}
	if a.json {
		_ = json.NewEncoder(a.err).Encode(map[string]any{"schema_version": 1, "error": kind, "message": err.Error()})
	} else {
		fmt.Fprintln(a.err, "ghoops:", err)
	}
	return code
}
func (a *app) emit(v any) error { return json.NewEncoder(a.out).Encode(v) }
func flags(name string) *flag.FlagSet {
	f := flag.NewFlagSet(name, flag.ContinueOnError)
	f.SetOutput(io.Discard)
	return f
}
func parse(f *flag.FlagSet, args []string) error {
	if err := f.Parse(args); err != nil {
		return usageError{err.Error()}
	}
	if f.NArg() != 0 {
		return usageError{"unexpected positional arguments"}
	}
	return nil
}

type rangeFlags struct {
	days     *int
	from, to *string
}

func addRange(f *flag.FlagSet, days int) rangeFlags {
	return rangeFlags{f.Int("days", days, "number of calendar days"), f.String("from", "", "first date"), f.String("to", "", "last date, inclusive")}
}
func (a *app) date(s string) (time.Time, error) {
	d, err := time.ParseInLocation("2006-01-02", s, a.loc)
	if err != nil {
		return d, usageError{"date must be a valid YYYY-MM-DD"}
	}
	return d, nil
}
func (a *app) dateRange(f *flag.FlagSet, r rangeFlags) (time.Time, time.Time, error) {
	today, _ := a.date(a.now.In(a.loc).Format("2006-01-02"))
	end := today.AddDate(0, 0, 1)
	from := end.AddDate(0, 0, -*r.days)
	if *r.days < 1 || *r.days > 90 {
		return from, end, usageError{"--days must be between 1 and 90"}
	}
	if *r.from != "" || *r.to != "" {
		if *r.from == "" || *r.to == "" {
			return from, end, usageError{"--from and --to must be supplied together"}
		}
		explicitDays := false
		f.Visit(func(flag *flag.Flag) {
			if flag.Name == "days" {
				explicitDays = true
			}
		})
		if explicitDays {
			return from, end, usageError{"use --days or --from/--to"}
		}
		var err error
		from, err = a.date(*r.from)
		if err != nil {
			return from, end, err
		}
		end, err = a.date(*r.to)
		if err != nil {
			return from, end, err
		}
		end = end.AddDate(0, 0, 1)
	}
	if !from.Before(end) || end.After(today.AddDate(0, 0, 1)) || from.AddDate(0, 0, 90).Before(end) {
		return from, end, usageError{"date range must be ordered, at most 90 days, and not in the future"}
	}
	return from, end, nil
}

func (a *app) authentication(ctx context.Context, args []string) error {
	if len(args) == 0 {
		return usageError{"expected auth login, status, refresh or logout"}
	}
	f := flags("auth " + args[0])
	switch args[0] {
	case "status":
		if err := parse(f, args[1:]); err != nil {
			return err
		}
		s, err := a.auth.Status(ctx)
		if err != nil {
			return err
		}
		return a.emit(s)
	case "refresh":
		if err := parse(f, args[1:]); err != nil {
			return err
		}
		if err := a.auth.Refresh(ctx); err != nil {
			return err
		}
		s, err := a.auth.Status(ctx)
		if err != nil {
			return err
		}
		return a.emit(s)
	case "login":
		path := f.String("client-file", "", "private Web OAuth client JSON")
		noBrowser := f.Bool("no-browser", false, "print consent URL without opening a browser")
		if err := parse(f, args[1:]); err != nil {
			return err
		}
		if *path == "" {
			return usageError{"auth login requires --client-file PATH"}
		}
		if a.json {
			return usageError{"auth login prints an interactive URL; omit --json"}
		}
		if _, err := secure.InstalledExecutable(); err != nil && a.options.Auth == nil {
			return err
		}
		client, err := auth.LoadClient(*path, a.auth.CallbackURL)
		if err != nil {
			return err
		}
		unlock, err := secure.Lock(ctx, a.dir, "sync.lock")
		if err != nil {
			return err
		}
		defer unlock()
		state, err := a.store.Load()
		if err != nil {
			return err
		}
		if err := a.auth.Login(ctx, client, state.Account, *noBrowser, a.out); err != nil {
			return err
		}
		fmt.Fprintln(a.out, "Authorized. Run ghoops sync to collect data.")
		return nil
	case "logout":
		revoke := f.Bool("revoke", false, "revoke authorization at Google")
		if err := parse(f, args[1:]); err != nil {
			return err
		}
		unlock, err := secure.Lock(ctx, a.dir, "sync.lock")
		if err != nil {
			return err
		}
		defer unlock()
		if err := a.auth.Logout(ctx, *revoke); err != nil {
			return err
		}
		return a.emit(map[string]any{"authorized": false, "revoked_at_google": *revoke, "encrypted_cache_retained": true})
	default:
		return usageError{"unknown auth command"}
	}
}

func (a *app) collect(ctx context.Context, from, until time.Time) (cache.SyncResult, error) {
	return cache.Sync(ctx, a.store, a.fetcher, func(ctx context.Context) (string, error) {
		if _, err := a.auth.Access(ctx, ""); err != nil {
			return "", err
		}
		return a.auth.Account(ctx)
	}, from, until)
}
func (a *app) sync(ctx context.Context, args []string) error {
	f := flags("sync")
	r := addRange(f, 7)
	if err := parse(f, args); err != nil {
		return err
	}
	from, until, err := a.dateRange(f, r)
	if err != nil {
		return err
	}
	result, err := a.collect(ctx, from, until)
	if result.Source != "" {
		if emitErr := a.emit(result); emitErr != nil {
			return emitErr
		}
	}
	return err
}
func (a *app) summary(command string, args []string) error {
	f := flags(command)
	defaults := 7
	if command == "trends" {
		defaults = 14
	}
	r := addRange(f, defaults)
	date := f.String("date", "", "single date for today")
	if err := parse(f, args); err != nil {
		return err
	}
	var from, until time.Time
	var err error
	if command == "today" {
		explicitRange := false
		f.Visit(func(v *flag.Flag) {
			if v.Name != "date" {
				explicitRange = true
			}
		})
		if explicitRange {
			return usageError{"today accepts --date, not a range"}
		}
		s := *date
		if s == "" {
			s = a.now.In(a.loc).Format("2006-01-02")
		}
		from, err = a.date(s)
		until = from.AddDate(0, 0, 1)
		if from.After(a.now) {
			return usageError{"date cannot be in the future"}
		}
	} else {
		if *date != "" {
			return usageError{"--date is only valid for today"}
		}
		from, until, err = a.dateRange(f, r)
	}
	if err != nil {
		return err
	}
	state, err := a.store.Load()
	if err != nil {
		return err
	}
	if state.Timezone != "" && state.Timezone != a.loc.String() {
		return errors.New("cache timezone differs from Europe/London")
	}
	s := report.Days(state, from, until, a.now)
	if a.json {
		return a.emit(s)
	}
	report.Text(a.out, s, command != "today")
	return nil
}
func (a *app) export(args []string) error {
	f := flags("data export")
	r := addRange(f, 7)
	path := f.String("output", "", "create a private export file, refuses overwrite")
	if err := parse(f, args); err != nil {
		return err
	}
	from, until, err := a.dateRange(f, r)
	if err != nil {
		return err
	}
	state, err := a.store.Load()
	if err != nil {
		return err
	}
	rows := []health.Record{}
	coverage := []cache.Coverage{}
	for _, record := range state.Records {
		if record.Date >= from.Format("2006-01-02") && record.Date < until.Format("2006-01-02") {
			rows = append(rows, record)
		}
	}
	for _, c := range state.Coverage {
		if c.Date >= from.Format("2006-01-02") && c.Date < until.Format("2006-01-02") {
			coverage = append(coverage, c)
		}
	}
	data := struct {
		Version  int              `json:"schema_version"`
		Source   string           `json:"source"`
		Timezone string           `json:"timezone"`
		From     string           `json:"from"`
		Until    string           `json:"until_exclusive"`
		Records  []health.Record  `json:"records"`
		Coverage []cache.Coverage `json:"coverage"`
	}{1, health.Source, a.loc.String(), from.Format("2006-01-02"), until.Format("2006-01-02"), rows, coverage}
	if *path == "" {
		return a.emit(data)
	}
	fout, err := secure.OpenPrivate(*path, os.O_CREATE|os.O_EXCL|os.O_WRONLY)
	if err != nil {
		return errors.New("cannot create private export file; path must not already exist")
	}
	if err := json.NewEncoder(fout).Encode(data); err != nil {
		fout.Close()
		os.Remove(*path)
		return errors.New("cannot write export")
	}
	if err := fout.Sync(); err != nil {
		fout.Close()
		return errors.New("cannot flush export")
	}
	if err := fout.Close(); err != nil {
		return errors.New("cannot close export")
	}
	return a.emit(map[string]any{"schema_version": 1, "exported_records": len(rows), "plaintext_export": true})
}

func (a *app) doctor(ctx context.Context, args []string) error {
	f := flags("doctor")
	offline := f.Bool("offline", false, "check runtime and cache presence without reading Keychain or health data")
	keychain := f.Bool("keychain-test", false, "scoped dummy fresh-process Keychain test")
	live := f.Bool("live", false, "sync and require all core metric records")
	days := f.Int("days", 7, "live date range")
	if err := parse(f, args); err != nil {
		return err
	}
	modes := 0
	for _, v := range []bool{*offline, *keychain, *live} {
		if v {
			modes++
		}
	}
	if modes > 1 {
		return usageError{"doctor modes are mutually exclusive"}
	}
	if *keychain {
		if err := keychainTest(ctx); err != nil {
			return err
		}
		return a.emit(map[string]any{"schema_version": 1, "keychain_test": "passed", "fresh_processes": 4, "scope": "random dummy item only", "approval_ui": false})
	}
	if *offline {
		_, installedErr := secure.InstalledExecutable()
		_, statErr := os.Lstat(filepath.Join(a.dir, "records.enc"))
		return a.emit(map[string]any{"schema_version": 1, "go_version": runtime.Version(), "os": runtime.GOOS, "installed_binary": installedErr == nil, "cache_present": statErr == nil, "credentials_checked": false, "health_records_checked": false, "timezone": a.loc.String(), "source": health.Source})
	}
	s, err := a.auth.Status(ctx)
	if err != nil {
		return err
	}
	if *live {
		if *days < 1 || *days > 90 {
			return usageError{"--days must be between 1 and 90"}
		}
		end, _ := a.date(a.now.In(a.loc).Format("2006-01-02"))
		end = end.AddDate(0, 0, 1)
		from := end.AddDate(0, 0, -*days)
		result, err := a.collect(ctx, from, end)
		if err != nil {
			if result.Source != "" {
				_ = a.emit(result)
			}
			return err
		}
		state, err := a.store.Load()
		if err != nil {
			return err
		}
		for _, record := range state.Records {
			if record.Synthetic {
				return errors.New("live verification rejected explicitly synthetic fixture records")
			}
		}
		summary := report.Days(state, from, end, time.Now())
		counts := map[string]int{"sleep": 0, "hrv": 0, "resting_heart_rate": 0, "steps": 0, "heart_rate": 0, "exercise": 0}
		for _, d := range summary.Days {
			for key, m := range map[string]report.Metric{"sleep": d.Sleep.Duration, "hrv": d.HRV, "resting_heart_rate": d.RHR, "steps": d.Steps, "heart_rate": d.HR.Mean, "exercise": d.Exercise.Coverage} {
				if m.Status == "available" && m.Value != nil && !m.Stale && m.Records > 0 {
					counts[key] += m.Records
				}
			}
		}
		missing := []string{}
		for _, key := range []string{"sleep", "hrv", "resting_heart_rate", "steps", "heart_rate", "exercise"} {
			if counts[key] == 0 {
				missing = append(missing, key)
			}
		}
		if err := a.emit(map[string]any{"schema_version": 1, "source": health.Source, "live": true, "complete": len(missing) == 0, "from": result.From, "until_exclusive": result.Until, "observed_record_counts": counts, "missing_required_metrics": missing, "version": a.options.Version, "revision": a.options.Revision}); err != nil {
			return err
		}
		if len(missing) > 0 {
			return errors.New("live verification incomplete: one or more core metrics have no observed usable records; no empty or synthetic pass")
		}
		return nil
	}
	state, err := a.store.Load()
	if err != nil {
		return err
	}
	if err := a.emit(map[string]any{"schema_version": 1, "auth": s, "cache_records": len(state.Records), "source": health.Source, "timezone": a.loc.String(), "network_checked": false, "ready_for_sync": s.Authorized}); err != nil {
		return err
	}
	if !s.Authorized {
		return auth.ErrLogin
	}
	return nil
}

func keychainTest(ctx context.Context) error {
	exe, err := secure.InstalledExecutable()
	if err != nil {
		return err
	}
	id := make([]byte, 16)
	value := make([]byte, 32)
	if _, err := rand.Read(id); err != nil {
		return errors.New("cannot generate probe ID")
	}
	if _, err := rand.Read(value); err != nil {
		return errors.New("cannot generate probe value")
	}
	service := "io.ghealth.probe." + hex.EncodeToString(id)
	run := func(action string) error {
		cmd := exec.CommandContext(ctx, exe, "internal-keychain-probe", action, service)
		cmd.Stdin = strings.NewReader(hex.EncodeToString(value))
		cmd.Stdout = io.Discard
		cmd.Stderr = io.Discard
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("fresh-process Keychain %s failed; no existing items or ACLs changed", action)
		}
		return nil
	}
	if err := run("add"); err != nil {
		return err
	}
	deleted := false
	defer func() {
		if deleted {
			return
		}
		cleanup, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		cmd := exec.CommandContext(cleanup, exe, "internal-keychain-probe", "delete", service)
		cmd.Stdin = strings.NewReader(hex.EncodeToString(value))
		_ = cmd.Run()
	}()
	for _, action := range []string{"compare", "delete", "absent"} {
		if err := run(action); err != nil {
			return err
		}
		if action == "delete" {
			deleted = true
		}
	}
	return nil
}

func probe(args []string, in io.Reader) error {
	if len(args) != 2 || !strings.HasPrefix(args[1], "io.ghealth.probe.") || len(args[1]) != len("io.ghealth.probe.")+32 {
		return errors.New("invalid probe scope")
	}
	if _, err := hex.DecodeString(strings.TrimPrefix(args[1], "io.ghealth.probe.")); err != nil {
		return errors.New("invalid probe ID")
	}
	data, err := io.ReadAll(io.LimitReader(in, 65))
	if err != nil || len(data) != 64 {
		return errors.New("invalid dummy probe value")
	}
	value, err := hex.DecodeString(string(data))
	if err != nil {
		return errors.New("invalid probe value")
	}
	vault := secure.Keychain{}
	service := args[1]
	switch args[0] {
	case "add":
		if _, err := vault.Get(service); !errors.Is(err, secure.ErrNotFound) {
			return errors.New("probe item already exists or Keychain inaccessible")
		}
		return vault.Set(service, value)
	case "compare", "delete":
		got, err := vault.Get(service)
		if err != nil {
			return err
		}
		if subtle.ConstantTimeCompare(got, value) != 1 {
			return errors.New("dummy value mismatch")
		}
		if args[0] == "delete" {
			return vault.Delete(service)
		}
		return nil
	case "absent":
		if _, err := vault.Get(service); !errors.Is(err, secure.ErrNotFound) {
			return errors.New("dummy item still exists or Keychain inaccessible")
		}
		return nil
	default:
		return errors.New("invalid probe action")
	}
}
