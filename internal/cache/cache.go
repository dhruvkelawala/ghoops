package cache

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
)

const header = "ghealth-cache-v1\n"
const MaxSize = 256 << 20

type Coverage struct {
	Type      string     `json:"data_type"`
	Stream    string     `json:"stream"`
	Date      string     `json:"date"`
	Status    string     `json:"status"`
	AttemptAt time.Time  `json:"attempt_at"`
	SuccessAt *time.Time `json:"last_success_at"`
	Count     int        `json:"record_count"`
	Error     string     `json:"error,omitempty"`
}

type State struct {
	Version  int             `json:"schema_version"`
	Source   string          `json:"source"`
	Account  string          `json:"account"`
	Timezone string          `json:"timezone"`
	Records  []health.Record `json:"records"`
	Coverage []Coverage      `json:"coverage"`
}

func Empty() State {
	return State{Version: 1, Source: health.Source, Records: []health.Record{}, Coverage: []Coverage{}}
}

type Store struct {
	Dir   string
	Vault secure.Vault
}

func (s Store) key(create bool) ([]byte, error) {
	return secure.CacheKey(s.Dir, s.Vault, create)
}

func (s Store) Load() (State, error) {
	empty := Empty()
	if _, err := os.Lstat(s.Dir); errors.Is(err, os.ErrNotExist) {
		return empty, nil
	}
	if err := secure.PrivateDir(s.Dir); err != nil {
		return empty, err
	}
	f, err := secure.OpenPrivate(filepath.Join(s.Dir, "records.enc"), os.O_RDONLY)
	if errors.Is(err, os.ErrNotExist) {
		return empty, nil
	}
	if err != nil {
		return empty, errors.New("cannot open private encrypted cache")
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, MaxSize+1))
	if err != nil || len(b) > MaxSize {
		return empty, errors.New("encrypted cache exceeds size limit or cannot be read")
	}
	k, err := s.key(false)
	if err != nil {
		return empty, err
	}
	block, err := aes.NewCipher(k)
	if err != nil {
		return empty, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return empty, err
	}
	if len(b) < len(header)+aead.NonceSize()+aead.Overhead() || string(b[:len(header)]) != header {
		return empty, errors.New("invalid encrypted cache format")
	}
	nonce := b[len(header) : len(header)+aead.NonceSize()]
	plain, err := aead.Open(nil, nonce, b[len(header)+aead.NonceSize():], []byte(header+secure.Service(s.Dir)))
	if err != nil {
		return empty, errors.New("encrypted cache authentication failed")
	}
	var state State
	if json.Unmarshal(plain, &state) != nil || state.Version != 1 || state.Source != health.Source {
		return empty, errors.New("invalid encrypted cache schema")
	}
	return state, nil
}

func (s Store) Save(state State) error {
	if err := secure.PrivateDir(s.Dir); err != nil {
		return err
	}
	if state.Version != 1 || state.Source != health.Source {
		return errors.New("invalid cache state")
	}
	plain, err := json.Marshal(state)
	if err != nil || len(plain) > MaxSize-1024 {
		return errors.New("cache cannot be encoded or exceeds size limit")
	}
	k, err := s.key(true)
	if err != nil {
		return err
	}
	block, err := aes.NewCipher(k)
	if err != nil {
		return err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return errors.New("cannot generate cache nonce")
	}
	b := append([]byte(header), nonce...)
	b = aead.Seal(b, nonce, plain, []byte(header+secure.Service(s.Dir)))
	path := filepath.Join(s.Dir, "records.enc")
	if fi, err := os.Lstat(path); err == nil && (!fi.Mode().IsRegular() || fi.Mode().Perm()&0077 != 0) {
		return errors.New("refusing to replace unsafe cache file")
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return errors.New("cannot inspect cache file")
	}
	f, err := os.CreateTemp(s.Dir, ".records-*")
	if err != nil {
		return errors.New("cannot create encrypted cache")
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(b); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return errors.New("cannot write encrypted cache")
	}
	if err := os.Rename(f.Name(), path); err != nil {
		return errors.New("cannot atomically replace encrypted cache")
	}
	dir, err := os.Open(s.Dir)
	if err == nil {
		err = dir.Sync()
		_ = dir.Close()
	}
	if err != nil {
		return errors.New("cannot flush encrypted cache directory")
	}
	return nil
}

func resourceName(r health.Record) string {
	var identity struct {
		Name           string `json:"name"`
		ReconciledName string `json:"dataPointName"`
	}
	if json.Unmarshal(r.Raw, &identity) != nil {
		return ""
	}
	if r.Stream == "reconciled" {
		return identity.ReconciledName
	}
	return identity.Name
}

type Fetcher interface {
	Fetch(context.Context, health.Kind, string, time.Time, time.Time) ([]health.Record, error)
}
type SyncResult struct {
	Source   string     `json:"source"`
	From     string     `json:"from"`
	Until    string     `json:"until_exclusive"`
	Records  int        `json:"fetched_records"`
	Outcomes []Coverage `json:"outcomes"`
	Complete bool       `json:"complete"`
}

// Sync holds sync.lock across account resolution, validation, fetching and saving.
// resolveAccount may acquire auth.lock but must not reacquire sync.lock.
func Sync(ctx context.Context, store Store, fetcher Fetcher, resolveAccount func(context.Context) (string, error), from, until time.Time) (result SyncResult, err error) {
	result = SyncResult{Source: health.Source, From: from.Format("2006-01-02"), Until: until.Format("2006-01-02"), Outcomes: []Coverage{}, Complete: true}
	defer func() {
		if err != nil {
			result.Complete = false
		}
	}()
	unlock, err := secure.Lock(ctx, store.Dir, "sync.lock")
	if err != nil {
		return result, err
	}
	defer unlock()
	account, err := resolveAccount(ctx)
	if err != nil {
		return result, err
	}
	if account == "" {
		return result, errors.New("collection account is missing; authorize again")
	}
	state, err := store.Load()
	if err != nil {
		return result, err
	}
	if state.Account != "" && state.Account != account {
		return result, errors.New("cache belongs to another account; use a separate --state-dir")
	}
	if state.Timezone != "" && state.Timezone != from.Location().String() {
		return result, errors.New("cache uses another timezone; use a separate --state-dir")
	}
	state.Account, state.Timezone = account, from.Location().String()
	for _, kind := range health.Kinds {
		streams := []string{"raw"}
		if kind.Reconcile {
			streams = append(streams, "reconciled")
		}
		for _, stream := range streams {
			if ctx.Err() != nil {
				return result, errors.New("sync cancelled; cache unchanged")
			}
			records, fetchErr := fetcher.Fetch(ctx, kind, stream, from, until)
			now := time.Now().UTC()
			status, errorCode := "ok", ""
			if fetchErr != nil {
				status, errorCode = "unavailable", health.CollectionErrorCode(fetchErr)
				var api *health.APIError
				if errors.As(fetchErr, &api) && api != nil && api.Status == 501 {
					status = "unsupported"
				}
				result.Complete = false
			}
			for date := from; date.Before(until); date = date.AddDate(0, 0, 1) {
				c := Coverage{Type: kind.ID, Stream: stream, Date: date.Format("2006-01-02"), Status: status, AttemptAt: now, Error: errorCode}
				for _, old := range state.Coverage {
					if old.Type == c.Type && old.Stream == c.Stream && old.Date == c.Date {
						c.SuccessAt, c.Count = old.SuccessAt, old.Count
					}
				}
				if fetchErr == nil {
					c.SuccessAt = &now
					c.Count = 0
					for _, r := range records {
						if r.Date == c.Date {
							c.Count++
						}
					}
				}
				filtered := state.Coverage[:0]
				for _, old := range state.Coverage {
					if old.Type != c.Type || old.Stream != c.Stream || old.Date != c.Date {
						filtered = append(filtered, old)
					}
				}
				state.Coverage = append(filtered, c)
				result.Outcomes = append(result.Outcomes, c)
			}
			if fetchErr == nil {
				freshNames := map[string]bool{}
				for _, r := range records {
					if r.Type == kind.ID && r.Stream == stream {
						if name := resourceName(r); name != "" {
							freshNames[name] = true
						}
					}
				}
				affectedDates := map[string]bool{}
				filtered := state.Records[:0]
				for _, old := range state.Records {
					if old.Type == kind.ID && old.Stream == stream {
						if old.Date >= result.From && old.Date < result.Until {
							continue
						}
						if freshNames[resourceName(old)] {
							affectedDates[old.Date] = true
							continue
						}
					}
					filtered = append(filtered, old)
				}
				state.Records = append(filtered, records...)
				if len(affectedDates) > 0 {
					counts := map[string]int{}
					for _, r := range state.Records {
						if r.Type == kind.ID && r.Stream == stream && affectedDates[r.Date] {
							counts[r.Date]++
						}
					}
					for i := range state.Coverage {
						c := &state.Coverage[i]
						if c.Type == kind.ID && c.Stream == stream && affectedDates[c.Date] {
							c.Status, c.Error, c.Count = "stale", "record_timestamp_changed", counts[c.Date]
						}
					}
				}
				result.Records += len(records)
			}
		}
	}
	sort.Slice(state.Records, func(i, j int) bool {
		a, b := state.Records[i], state.Records[j]
		if a.Date != b.Date {
			return a.Date < b.Date
		}
		if a.Type != b.Type {
			return a.Type < b.Type
		}
		if a.Stream != b.Stream {
			return a.Stream < b.Stream
		}
		return string(a.Raw) < string(b.Raw)
	})
	sort.Slice(state.Coverage, func(i, j int) bool {
		a, b := state.Coverage[i], state.Coverage[j]
		if a.Date != b.Date {
			return a.Date < b.Date
		}
		if a.Type != b.Type {
			return a.Type < b.Type
		}
		return a.Stream < b.Stream
	})
	if ctx.Err() != nil {
		return result, errors.New("sync cancelled; cache unchanged")
	}
	if err := store.Save(state); err != nil {
		return result, err
	}
	if !result.Complete {
		return result, errors.New("sync incomplete; failed streams are explicit in outcomes and prior records are retained")
	}
	return result, nil
}
