package serve

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/activities"
	"github.com/dhruvkelawala/ghoops/internal/config"
	"github.com/dhruvkelawala/ghoops/internal/journal"
	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/store2"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

type Settings struct {
	Store   store2.Store
	Config  config.File
	Tokens  pairing.Tokens
	Options func(context.Context) (v2report.Options, error)
	Now     func() time.Time
	Log     io.Writer
	MacName string
}
type Handler struct {
	settings       Settings
	devices        pairing.Devices
	authMu         sync.Mutex
	credentials    pairing.DeviceCredentials
	credentialErr  error
	readAt         time.Time
	failures       []time.Time
	storeMu        sync.Mutex
	state          store2.State2
	profileID      *string
	stamp          time.Time
	size           int64
	loaded         bool
	activityMu     sync.Mutex
	activityBook   activities.Book
	activityStamp  time.Time
	activitySize   int64
	activityLoaded bool
	journalMu      sync.Mutex
	journalBook    journal.Book
	journalStamp   time.Time
	journalSize    int64
	journalLoaded  bool
	logMu          sync.Mutex
}

func New(settings Settings) (*Handler, error) {
	if settings.Now == nil {
		settings.Now = time.Now
	}
	if settings.Log == nil {
		settings.Log = io.Discard
	}
	if settings.MacName == "" {
		settings.MacName = "Mac"
	}
	h := &Handler{settings: settings, devices: pairing.Devices{Dir: settings.Tokens.Dir, Vault: settings.Tokens.Vault}}
	if h.loadCredentials(context.Background(), settings.Now()) == nil && !h.credentials.Paired() {
		io.WriteString(settings.Log, "no pairing token; run ghoops pair\n")
	}
	return h, nil
}
func Listen(address string) (net.Listener, error) {
	host, _, err := net.SplitHostPort(address)
	if err != nil || host != "127.0.0.1" {
		return nil, errors.New("server requires IPv4 loopback")
	}
	return net.Listen("tcp4", address)
}
func Server(handler http.Handler) *http.Server {
	return &http.Server{
		Handler:           handler,
		MaxHeaderBytes:    8 << 10,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
}
func (h *Handler) Run(ctx context.Context, address string) error {
	listener, err := Listen(address)
	if err != nil {
		return err
	}
	server := Server(h)
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			server.Shutdown(shutdown)
		case <-done:
		}
	}()
	err = server.Serve(listener)
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := h.settings.Now()
	status := 200
	defer func() {
		h.logMu.Lock()
		defer h.logMu.Unlock()
		json.NewEncoder(h.settings.Log).Encode(struct {
			Time     time.Time `json:"time"`
			Method   string    `json:"method"`
			Path     string    `json:"path"`
			Status   int       `json:"status"`
			Duration int64     `json:"duration_ms"`
		}{start.UTC(), r.Method, routeTemplate(r.URL.Path), status, h.settings.Now().Sub(start).Milliseconds()})
	}()
	response := &bufferedResponse{ResponseWriter: w}
	defer response.send(r.Header.Values("Accept-Encoding"))
	w = response
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Ghealth-Schema", "2")
	fail := func(e *v2report.Error) {
		status = *e.HTTP
		if status == 429 {
			w.Header().Set("Retry-After", "60")
		}
		if status == 405 {
			allow := "GET"
			if r.URL.Path == "/v2/pair/redeem" {
				allow = "POST"
			}
			w.Header().Set("Allow", allow)
		}
		w.WriteHeader(status)
		json.NewEncoder(w).Encode(e.Body(start))
	}
	if r.URL.Path == "/v2/pair/redeem" {
		body, err := h.redeem(w, r, start)
		if err != nil {
			fail(err)
			return
		}
		status = http.StatusCreated
		w.WriteHeader(status)
		json.NewEncoder(w).Encode(body)
		return
	}
	device, code := h.authorize(r, start)
	if code != "" {
		fail(v2report.NewError(code))
		return
	}
	if r.URL.Path == "/v2/pair/status" {
		if r.Method != http.MethodGet {
			fail(v2report.NewError("method_not_allowed"))
		} else if r.ContentLength != 0 || len(r.TransferEncoding) > 0 || r.URL.RawQuery != "" {
			fail(v2report.NewError("invalid_request"))
		} else if device.ID == "" {
			fail(v2report.NewError("unauthorized"))
		} else {
			json.NewEncoder(w).Encode(v2report.PairStatus{Envelope: v2report.CommandEnvelope("pair_status", start), DeviceID: device.ID, State: device.State})
		}
		return
	}
	if r.URL.Path == "/v2/sleep-edits" || strings.HasPrefix(r.URL.Path, "/v2/sleep-edits/") {
		status = h.sleepEdit(w, r, start)
		return
	}
	if r.URL.Path == "/v2/edits" || strings.HasPrefix(r.URL.Path, "/v2/edits/") {
		status = h.edit(w, r, start)
		return
	}
	if r.URL.Path == "/v2/ratings" || strings.HasPrefix(r.URL.Path, "/v2/ratings/") {
		status = h.rating(w, r, start)
		return
	}
	if strings.HasPrefix(r.URL.Path, "/v2/journal/") {
		status = h.journalPut(w, r, start)
		return
	}
	if r.URL.Path == "/v2/activities" || strings.HasPrefix(r.URL.Path, "/v2/activities/") {
		status = h.activity(w, r, start)
		return
	}
	if r.Method != http.MethodGet {
		fail(v2report.NewError("method_not_allowed"))
		return
	}
	headerSize := 0
	for key, values := range r.Header {
		for _, value := range values {
			headerSize += len(key) + len(value) + 4
		}
	}
	if r.ContentLength != 0 || len(r.TransferEncoding) > 0 || headerSize > 8<<10 {
		fail(v2report.NewError("invalid_request"))
		return
	}
	kind := readKind(r.URL.Path)
	if kind == "" {
		fail(v2report.NewError("not_found"))
		return
	}
	params, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil {
		fail(v2report.NewError("invalid_request"))
		return
	}
	state, profileID, err := h.load()
	if err != nil {
		h.logKeychainError(err)
		fail(v2report.NewError("store_unavailable"))
		return
	}
	cfg, err := h.settings.Config.Load()
	if err != nil {
		fail(v2report.NewError("store_unavailable"))
		return
	}
	options := v2report.Options{}
	if h.settings.Options != nil {
		options, err = h.settings.Options(r.Context())
		if err != nil {
			h.logKeychainError(err)
			fail(v2report.NewError("store_unavailable"))
			return
		}
	}
	options.Server.ProfileID = profileID
	book, err := h.loadActivities()
	options.Activities, options.Edits, options.SleepEdits, options.Ratings = book.Activities, book.Edits, book.SleepEdits, book.Ratings
	if err != nil {
		h.logKeychainError(err)
		fail(v2report.NewError("store_unavailable"))
		return
	}
	if kind == "journal" || kind == "snapshot" {
		if options.Journal, err = h.loadJournal(); err != nil {
			h.logKeychainError(err)
			fail(v2report.NewError("store_unavailable"))
			return
		}
	}
	builder, err := v2report.New(state, start, cfg, options)
	if err != nil {
		fail(v2report.NewError("store_unavailable"))
		return
	}
	if kind == "heart-rate" {
		kind = "heart_rate"
	}
	body, err := builder.Build(kind, params)
	if err != nil {
		var e *v2report.Error
		if errors.As(err, &e) {
			fail(e)
		} else {
			fail(v2report.NewError("internal"))
		}
		return
	}
	data, err := json.Marshal(body)
	if err != nil {
		fail(v2report.NewError("internal"))
		return
	}
	w.Write(append(data, '\n'))
}

func (h *Handler) logKeychainError(err error) {
	if errors.Is(err, secure.ErrKeychainAccess) {
		h.logMu.Lock()
		defer h.logMu.Unlock()
		fmt.Fprintln(h.settings.Log, err)
	}
}
func readKind(path string) string {
	kind, ok := strings.CutPrefix(path, "/v2/")
	if !ok {
		return ""
	}
	switch kind {
	case "status", "day", "sleep", "days", "workouts", "snapshot", "brief", "heart-rate", "journal", "week":
		return kind
	default:
		return ""
	}
}

func routeTemplate(path string) string {
	if readKind(path) != "" || path == "/v2/pair/redeem" || path == "/v2/pair/status" {
		return path
	}
	rest, ok := strings.CutPrefix(path, "/v2/")
	if !ok {
		return "other"
	}
	route, key, ok := strings.Cut(rest, "/")
	if !ok || key == "" || strings.Contains(key, "/") {
		return "other"
	}
	switch route {
	case "activities", "edits", "ratings":
		return "/v2/" + route + "/{id}"
	case "sleep-edits", "journal":
		return "/v2/" + route + "/{date}"
	default:
		return "other"
	}
}

func (h *Handler) loadCredentials(ctx context.Context, now time.Time) error {
	if h.readAt.IsZero() || now.Sub(h.readAt) >= 5*time.Second {
		h.credentials, h.credentialErr = h.devices.Credentials(ctx)
		h.logKeychainError(h.credentialErr)
		h.readAt = now
	}
	return h.credentialErr
}

func (h *Handler) authorize(r *http.Request, now time.Time) (pairing.Device, string) {
	h.authMu.Lock()
	defer h.authMu.Unlock()
	if h.loadCredentials(r.Context(), now) != nil {
		return pairing.Device{}, "store_unavailable"
	}
	values := r.Header.Values("Authorization")
	presented := ""
	if len(values) == 1 && strings.HasPrefix(values[0], "Bearer ") {
		presented = strings.TrimPrefix(values[0], "Bearer ")
	}
	got, want := sha256.Sum256([]byte(presented)), sha256.Sum256([]byte(h.credentials.Legacy.Value))
	if h.credentials.Legacy.Value != "" && presented != "" && subtle.ConstantTimeCompare(got[:], want[:]) == 1 {
		return pairing.Device{}, ""
	}
	if device, found := h.credentials.Device(presented, now); found {
		if device.State == "active" || r.URL.Path == "/v2/pair/status" {
			return device, ""
		}
		return pairing.Device{}, "unauthorized"
	}
	return pairing.Device{}, h.countAuthFailure(now)
}

func (h *Handler) countAuthFailure(now time.Time) string {
	const failureLimit = 11
	kept := h.failures[:0]
	for _, at := range h.failures {
		if now.Sub(at) < 60*time.Second {
			kept = append(kept, at)
		}
	}
	if len(kept) < failureLimit {
		kept = append(kept, now)
	}
	h.failures = kept
	if len(h.failures) == failureLimit {
		return "rate_limited"
	}
	return "unauthorized"
}
func (h *Handler) load() (store2.State2, *string, error) {
	h.storeMu.Lock()
	defer h.storeMu.Unlock()
	var stamp time.Time
	var size int64
	info, err := os.Stat(filepath.Join(h.settings.Store.Dir, "records-v2.enc"))
	if err == nil {
		stamp, size = info.ModTime(), info.Size()
	} else if !errors.Is(err, os.ErrNotExist) {
		return store2.State2{}, nil, err
	}
	if !h.loaded || stamp.IsZero() || !stamp.Equal(h.stamp) || size != h.size {
		state, profileID, err := h.settings.Store.LoadWithProfile()
		if err != nil {
			return store2.State2{}, nil, err
		}
		h.profileID = profileID
		h.state, h.stamp, h.size, h.loaded = state, stamp, size, true
	}
	return h.state, h.profileID, nil
}
