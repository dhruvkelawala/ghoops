package store2

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
	"syscall"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/cache"
	"github.com/dhruvkelawala/ghoops/internal/health"
	"github.com/dhruvkelawala/ghoops/internal/secure"
)

const header = "ghealth-cache-v2\n"
const MaxSize = 256 << 20
const collectLock = "collect.lock"

var ErrCollectInProgress = errors.New("collect_in_progress")

type Store struct {
	Dir   string
	Vault secure.Vault
}

func (s Store) Load() (State2, error) {
	state, _, err := s.load()
	return state, err
}

func (s Store) LoadWithProfile() (State2, *string, error) {
	state, key, err := s.load()
	if err != nil {
		return state, nil, err
	}
	if key == nil && s.Vault != nil {
		key, _ = secure.CacheKey(s.Dir, s.Vault, false)
	}
	if id := secure.ProfileID(key); id != "" {
		return state, &id, nil
	}
	return state, nil, nil
}

func (s Store) load() (State2, []byte, error) {
	empty := Empty()
	if _, err := os.Lstat(s.Dir); errors.Is(err, os.ErrNotExist) {
		return empty, nil, nil
	}
	if err := secure.PrivateDir(s.Dir); err != nil {
		return empty, nil, err
	}
	f, err := secure.OpenPrivate(filepath.Join(s.Dir, "records-v2.enc"), os.O_RDONLY)
	if errors.Is(err, os.ErrNotExist) {
		return empty, nil, nil
	}
	if err != nil {
		return empty, nil, errors.New("cannot open private encrypted cache")
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, MaxSize+1))
	if err != nil || len(b) > MaxSize {
		return empty, nil, errors.New("encrypted cache exceeds size limit or cannot be read")
	}
	k, err := secure.CacheKey(s.Dir, s.Vault, false)
	if err != nil {
		return empty, nil, err
	}
	block, err := aes.NewCipher(k)
	if err != nil {
		return empty, nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return empty, nil, err
	}
	if len(b) < len(header)+aead.NonceSize()+aead.Overhead() || string(b[:len(header)]) != header {
		return empty, nil, errors.New("invalid encrypted cache format")
	}
	nonce := b[len(header) : len(header)+aead.NonceSize()]
	plain, err := aead.Open(nil, nonce, b[len(header)+aead.NonceSize():], []byte(header+secure.Service(s.Dir)))
	if err != nil {
		return empty, nil, errors.New("encrypted cache authentication failed")
	}
	var state State2
	if json.Unmarshal(plain, &state) != nil || state.Version != 2 || state.Source != health.Source {
		return empty, nil, errors.New("invalid encrypted cache schema")
	}
	return state, k, nil
}

func (s Store) Save(state State2, now time.Time) error {
	state = retained(state, now)
	if err := secure.PrivateDir(s.Dir); err != nil {
		return err
	}
	if state.Version != 2 || state.Source != health.Source {
		return errors.New("invalid cache state")
	}
	plain, err := json.Marshal(state)
	if err != nil || len(plain) > MaxSize-1024 {
		return errors.New("cache cannot be encoded or exceeds size limit")
	}
	k, err := secure.CacheKey(s.Dir, s.Vault, true)
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
	path := filepath.Join(s.Dir, "records-v2.enc")
	if fi, err := os.Lstat(path); err == nil && (!fi.Mode().IsRegular() || fi.Mode().Perm()&0077 != 0) {
		return errors.New("refusing to replace unsafe cache file")
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return errors.New("cannot inspect cache file")
	}
	f, err := os.CreateTemp(s.Dir, ".records-v2-*")
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

func (s Store) Lock() (func(), error) {
	if err := secure.PrivateDir(s.Dir); err != nil {
		return nil, err
	}
	file, err := secure.OpenPrivate(filepath.Join(s.Dir, collectLock), os.O_CREATE|os.O_RDWR)
	if err != nil {
		return nil, errors.New("cannot open private collect lock")
	}
	if err = syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		file.Close()
		if err == syscall.EWOULDBLOCK || err == syscall.EAGAIN {
			return nil, ErrCollectInProgress
		}
		return nil, errors.New("cannot lock v2 store")
	}
	return func() { _ = syscall.Flock(int(file.Fd()), syscall.LOCK_UN); _ = file.Close() }, nil
}

func (s Store) WaitLock(ctx context.Context) (func(), error) {
	return secure.Lock(ctx, s.Dir, collectLock)
}

func retained(state State2, now time.Time) State2 {
	loc, _ := time.LoadLocation("Europe/London")
	cutoff := now.In(loc).AddDate(0, 0, -400).Format("2006-01-02")
	records := state.Records
	state.Records = []health.Record{}
	for _, row := range records {
		if row.Date >= cutoff {
			state.Records = append(state.Records, row)
		}
	}
	minutes := state.HRMinutes
	state.HRMinutes = []MinuteDay{}
	for _, row := range minutes {
		if row.Date >= cutoff {
			state.HRMinutes = append(state.HRMinutes, row)
		}
	}
	rollups := state.DailyRollups
	state.DailyRollups = []DailyRollup{}
	for _, row := range rollups {
		if row.Date >= cutoff {
			state.DailyRollups = append(state.DailyRollups, row)
		}
	}
	coverage := state.Coverage
	state.Coverage = []cache.Coverage{}
	for _, row := range coverage {
		if row.Date >= cutoff {
			state.Coverage = append(state.Coverage, row)
		}
	}
	if len(state.Runs) > 50 {
		state.Runs = state.Runs[len(state.Runs)-50:]
	}
	return state
}
