package collect

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/auth"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
)

var ErrFailed = errors.New("collect_failed")
var ErrPartial = errors.New("collect_partial")

type Options struct {
	From, Until time.Time
	Now         func() time.Time
	Progress    func(stream, status string, records int)
}

type Result struct {
	Version      int       `json:"schema_version"`
	Kind         string    `json:"kind"`
	Source       string    `json:"source"`
	GeneratedAt  time.Time `json:"generated_at"`
	Timezone     string    `json:"timezone"`
	Status       string    `json:"status"`
	Pass         string    `json:"pass"`
	From         string    `json:"from"`
	Until        string    `json:"until_exclusive"`
	Requests     int       `json:"requests"`
	DurationMS   int64     `json:"duration_ms"`
	CoreComplete bool      `json:"core_complete"`
	Streams      []Stream  `json:"streams"`
}

type Stream struct {
	Stream  string  `json:"stream"`
	Dates   int     `json:"dates"`
	Status  string  `json:"status"`
	Records int     `json:"records"`
	Error   *string `json:"error"`
}

// Run owns collect.lock from account resolution through the atomic v2 save.
func Run(ctx context.Context, store store2.Store, provider *health.Client, manager *auth.Manager, options Options) (Result, error) {
	unlock, err := store.Lock()
	if err != nil {
		return Result{}, err
	}
	defer unlock()
	if err := rotateLogs(store.Dir); err != nil {
		return Result{}, err
	}
	now := options.Now
	if now == nil {
		now = time.Now
	}
	started, clock := now().UTC(), time.Now()
	account, authErr := manager.Account(ctx)
	if authErr != nil && !errors.Is(authErr, auth.ErrLogin) {
		return Result{}, authErr
	}
	state, err := store.Load()
	if err != nil {
		return Result{}, err
	}
	if state.Account != "" && state.Account != account && authErr == nil {
		return Result{}, auth.ErrProfileOwner
	}
	if state.Timezone != "" && state.Timezone != "Europe/London" {
		return Result{}, errors.New("cache uses another timezone")
	}
	from, until, pass := plan(state, started, options)
	result := Result{Version: 2, Kind: "collect", Source: health.Source, Timezone: "Europe/London", Status: "ok", Pass: pass, From: from.Format("2006-01-02"), Until: until.Format("2006-01-02"), CoreComplete: true, Streams: []Stream{}}
	access := func(ctx context.Context, rejected string) (string, error) {
		return manager.AccessForAccount(ctx, account, rejected)
	}
	if authErr == nil {
		_, authErr = access(ctx, "")
	}
	if errors.Is(authErr, auth.ErrAccountChanged) || errors.Is(authErr, secure.ErrKeychainAccess) {
		return Result{}, authErr
	}
	if authErr != nil {
		result.Status, result.CoreComplete = "failed", false
		for _, stream := range Streams() {
			code := "unauthorized"
			result.Streams = append(result.Streams, Stream{Stream: stream, Status: "unavailable", Error: &code})
		}
		result.GeneratedAt, result.DurationMS = now().UTC(), time.Since(clock).Milliseconds()
		state.Runs = append(state.Runs, store2.Run{StartedAt: started, FinishedAt: result.GeneratedAt, Pass: pass, Status: "failed", FailedStreams: []string{}, CoreComplete: false})
		if err := save(ctx, store, manager, account, state, result.GeneratedAt); err != nil {
			return Result{}, err
		}
		return result, ErrFailed
	}
	state.Account, state.Timezone = account, "Europe/London"
	client := &health.Client{HTTP: provider.HTTP, BaseURL: provider.BaseURL, Access: access}
	jobs := jobsFor(state, from, until, pass, started)
	outputs := runJobs(ctx, client, jobs, options.Progress)
	if ctx.Err() != nil {
		return Result{}, errors.New("collect cancelled; cache unchanged")
	}
	failed := []string{}
	seenFailed := map[string]bool{}
	for _, output := range outputs {
		if errors.Is(output.err, auth.ErrAccountChanged) || errors.Is(output.err, secure.ErrKeychainAccess) {
			return Result{}, output.err
		}
		status, code := jobStatus(output.err)
		if output.err != nil {
			if !seenFailed[output.job.stream()] {
				failed = append(failed, output.job.stream())
				seenFailed[output.job.stream()] = true
			}
			if isCore(output.job.stream()) {
				result.Status, result.CoreComplete = "failed", false
			} else if status != "permission_missing" && result.Status != "failed" {
				result.Status = "partial"
			}
		}
		merge(&state, output, status, code, now().UTC())
	}
	result.GeneratedAt, result.DurationMS, result.Requests = now().UTC(), time.Since(clock).Milliseconds(), client.RequestCount()
	for _, stream := range Streams() {
		summary := Stream{Stream: stream, Status: "ok"}
		for _, c := range state.Coverage {
			if c.Type+"/"+c.Stream == stream && c.Date >= result.From && c.Date < result.Until {
				summary.Dates++
				summary.Records += c.Count
				if rank(c.Status) > rank(summary.Status) {
					summary.Status = c.Status
				}
				if summary.Error == nil && c.Error != "" {
					code := c.Error
					summary.Error = &code
				}
			}
		}
		result.Streams = append(result.Streams, summary)
	}
	state.Runs = append(state.Runs, store2.Run{StartedAt: started, FinishedAt: result.GeneratedAt, Pass: pass, Status: result.Status, CoreComplete: result.CoreComplete, Requests: result.Requests, FailedStreams: failed})
	sortState(&state)
	if err := save(ctx, store, manager, account, state, result.GeneratedAt); err != nil {
		return Result{}, err
	}
	switch result.Status {
	case "failed":
		return result, ErrFailed
	case "partial":
		return result, ErrPartial
	}
	return result, nil
}

func save(ctx context.Context, store store2.Store, manager *auth.Manager, account string, state store2.State2, now time.Time) error {
	current, err := manager.Account(ctx)
	if ctx.Err() != nil {
		return errors.New("collect cancelled; cache unchanged")
	}
	if err != nil && !errors.Is(err, auth.ErrLogin) {
		return err
	}
	if current != account {
		return auth.ErrAccountChanged
	}
	return store.Save(state, now)
}

func Streams() []string {
	streams := []string{}
	for _, kind := range health.V2Kinds {
		route := "list"
		if kind.Reconcile {
			route = "reconcile"
		}
		streams = append(streams, kind.ID+"/"+route)
	}
	return append(streams, "heart-rate/rollUp", "steps/dailyRollUp", "active-zone-minutes/dailyRollUp", "total-calories/dailyRollUp", "distance/dailyRollUp")
}

func plan(state store2.State2, now time.Time, options Options) (time.Time, time.Time, string) {
	if !options.From.IsZero() {
		return options.From, options.Until, "explicit"
	}
	loc, _ := time.LoadLocation("Europe/London")
	local := now.In(loc)
	today := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, loc)
	pass, days := "hot", 3
	if local.Hour() >= 12 {
		settled := false
		for _, run := range state.Runs {
			if run.Pass == "settle" && run.CoreComplete && run.StartedAt.In(loc).Format("2006-01-02") == today.Format("2006-01-02") {
				settled = true
			}
		}
		if !settled {
			pass, days = "settle", 10
		}
	}
	return today.AddDate(0, 0, 1-days), today.AddDate(0, 0, 1), pass
}

type job struct {
	kind            health.Kind
	route, resource string
	from, until     time.Time
}

func (j job) stream() string {
	if j.resource != "" {
		return "user/" + strings.ReplaceAll(j.resource, "_", "-")
	}
	return j.kind.ID + "/" + j.route
}

type output struct {
	job     job
	records []health.Record
	minutes []health.RollupMinute
	days    []health.RollupDay
	body    json.RawMessage
	err     error
}

func jobsFor(state store2.State2, from, until time.Time, pass string, now time.Time) []job {
	jobs := []job{}
	for _, kind := range health.V2Kinds {
		route := "list"
		if kind.Reconcile {
			route = "reconcile"
		}
		jobs = append(jobs, job{kind: kind, route: route, from: from, until: until})
	}
	for day := from; day.Before(until); day = day.AddDate(0, 0, 1) {
		jobs = append(jobs, job{kind: health.Kind{ID: "heart-rate"}, route: "rollUp", from: day, until: day.AddDate(0, 0, 1)})
	}
	for _, id := range []string{"steps", "active-zone-minutes", "total-calories", "distance"} {
		size := 90
		if id == "total-calories" {
			size = 14
		}
		for day := from; day.Before(until); {
			end := day.AddDate(0, 0, size)
			if end.After(until) {
				end = until
			}
			jobs = append(jobs, job{kind: health.Kind{ID: id}, route: "dailyRollUp", from: day, until: end})
			day = end
		}
	}
	for _, resource := range []string{"profile", "settings", "paired_devices", "irn_profile"} {
		old := state.User[resource]
		if pass == "explicit" || resource == "paired_devices" || old.FetchedAt == nil || now.Sub(*old.FetchedAt) > 24*time.Hour {
			jobs = append(jobs, job{resource: resource})
		}
	}
	return jobs
}

func runJobs(ctx context.Context, client *health.Client, jobs []job, progress func(string, string, int)) []output {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	type indexed struct {
		index  int
		output output
	}
	queue := make(chan int, len(jobs))
	done := make(chan indexed, len(jobs))
	for i := range jobs {
		queue <- i
	}
	close(queue)
	var workers sync.WaitGroup
	for worker := 0; worker < 4; worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for i := range queue {
				j := jobs[i]
				o := output{job: j}
				switch {
				case ctx.Err() != nil:
					o.err = ctx.Err()
				case j.resource != "":
					o.body, o.err = client.UserResource(ctx, j.resource)
				case j.route == "rollUp":
					o.minutes, o.err = client.RollUp(ctx, j.from)
				case j.route == "dailyRollUp":
					o.days, o.err = client.DailyRollUp(ctx, j.kind.ID, j.from, j.until)
				default:
					stream := "raw"
					if j.route == "reconcile" {
						stream = "reconciled"
					}
					o.records, o.err = client.FetchV2(ctx, j.kind, stream, j.from, j.until)
				}
				if errors.Is(o.err, auth.ErrAccountChanged) {
					cancel()
				}
				done <- indexed{i, o}
			}
		}()
	}
	go func() { workers.Wait(); close(done) }()
	outputs := make([]output, len(jobs))
	for indexed := range done {
		outputs[indexed.index] = indexed.output
		if progress != nil {
			status, _ := jobStatus(indexed.output.err)
			progress(indexed.output.job.stream(), status, len(indexed.output.records)+len(indexed.output.minutes)+len(indexed.output.days))
		}
	}
	return outputs
}

func jobStatus(err error) (string, string) {
	if err == nil {
		return "ok", ""
	}
	var api *health.APIError
	if errors.As(err, &api) && api != nil {
		if api.Status == 403 {
			return "permission_missing", "permission_denied"
		}
		if api.Status == 501 {
			return "unsupported", "unsupported"
		}
	}
	return "unavailable", health.CollectionErrorCode(err)
}
func isCore(stream string) bool {
	switch stream {
	case "sleep/reconcile", "daily-heart-rate-variability/list", "daily-resting-heart-rate/list", "heart-rate/rollUp":
		return true
	}
	return false
}
func rank(status string) int {
	switch status {
	case "ok":
		return 0
	case "permission_missing":
		return 1
	case "unavailable", "stale":
		return 2
	case "unsupported":
		return 3
	}
	return 4
}

func rotateLogs(dir string) error {
	for _, name := range []string{"collect.log", "serve.log"} {
		path := filepath.Join(dir, "logs", name)
		file, err := secure.OpenPrivate(path, os.O_RDWR)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return errors.New("cannot open private service log")
		}
		info, err := file.Stat()
		if err == nil && info.Size() > 1<<20 {
			err = file.Truncate(0)
		}
		file.Close()
		if err != nil {
			return errors.New("cannot rotate service log")
		}
	}
	return nil
}
