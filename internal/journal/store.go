package journal

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
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

// FileName is the encrypted journal beside activities-v2.enc.
const FileName = "journal-v2.enc"

const header = "ghealth-cache-v2\n"

// Store reads and writes journal-v2.enc with the activities envelope and Keychain key.
type Store struct {
	Dir   string
	Vault secure.Vault
}

// Load returns the book; a missing file is the defaults with no entries.
func (s Store) Load() (Book, error) {
	book := Book{Entries: []Entry{}}
	if _, err := os.Lstat(s.Dir); errors.Is(err, os.ErrNotExist) {
		return book, nil
	}
	if err := secure.PrivateDir(s.Dir); err != nil {
		return Book{}, err
	}
	f, err := secure.OpenPrivate(filepath.Join(s.Dir, FileName), os.O_RDONLY)
	if errors.Is(err, os.ErrNotExist) {
		return book, nil
	}
	if err != nil {
		return Book{}, err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, 16<<20+1))
	if err != nil || len(b) > 16<<20 {
		return Book{}, errors.New("cannot read journal")
	}
	aead, err := s.aead(false)
	if err != nil {
		return Book{}, err
	}
	n := len(header)
	if len(b) < n+aead.NonceSize()+aead.Overhead() || string(b[:n]) != header {
		return Book{}, errors.New("invalid journal envelope")
	}
	plain, err := aead.Open(nil, b[n:n+aead.NonceSize()], b[n+aead.NonceSize():], []byte(header+secure.Service(s.Dir)))
	if err != nil {
		return Book{}, errors.New("journal authentication failed")
	}
	var body struct {
		Version int `json:"version"`
		Book
	}
	if json.Unmarshal(plain, &body) != nil || body.Version != 1 {
		return Book{}, errors.New("invalid journal schema")
	}
	book.Behaviours = body.Behaviours
	for _, entry := range body.Entries {
		if len(entry.Answers) > 0 {
			book.Entries = append(book.Entries, entry)
		}
	}
	sortEntries(book.Entries)
	return book, nil
}

// Put stores the answers change returns for date under journal.lock (journal-spec §6.2).
// change receives the stored answers (empty when none). An empty result removes the entry.
func (s Store) Put(ctx context.Context, date string, now time.Time, condition Precondition, change func(stored map[string]bool) (map[string]bool, error)) (*Entry, error) {
	unlock, err := secure.Lock(ctx, s.Dir, "journal.lock")
	if err != nil {
		return nil, err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return nil, err
	}
	old := book.Entry(date)
	stored := map[string]bool{}
	if old != nil {
		stored = old.Answers
	}
	answers, err := change(stored)
	if err != nil {
		return nil, err
	}
	if old != nil && sameAnswers(old.Answers, answers) {
		kept := *old
		return &kept, nil
	}
	if old == nil && len(answers) == 0 {
		return nil, nil
	}
	if condition.Present {
		matches := old == nil && condition.UpdatedAt == nil
		if old != nil && condition.UpdatedAt != nil {
			matches = old.UpdatedAt.Truncate(time.Second).Equal(condition.UpdatedAt.Truncate(time.Second))
		}
		if !matches {
			return nil, ErrChanged
		}
	}
	entries := []Entry{}
	for _, entry := range book.Entries {
		if entry.Date != date {
			entries = append(entries, entry)
		}
	}
	var entry *Entry
	if len(answers) > 0 {
		entry = &Entry{Date: date, Answers: answers, UpdatedAt: now.UTC().Truncate(time.Second)}
		entries = append(entries, *entry)
	}
	book.Entries = entries
	return entry, s.save(book, now)
}

// SetBehaviours stores the enabled set; nil means the defaults.
func (s Store) SetBehaviours(ctx context.Context, keys []string, now time.Time) (Book, error) {
	unlock, err := secure.Lock(ctx, s.Dir, "journal.lock")
	if err != nil {
		return Book{}, err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return Book{}, err
	}
	book.Behaviours = keys
	return book, s.save(book, now)
}

func (s Store) save(book Book, now time.Time) error {
	london, err := time.LoadLocation("Europe/London")
	if err != nil {
		return err
	}
	oldest := now.In(london).AddDate(0, 0, -RetentionDays).Format("2006-01-02")
	kept := []Entry{}
	for _, entry := range book.Entries {
		if entry.Date >= oldest {
			kept = append(kept, entry)
		}
	}
	sortEntries(kept)
	plain, err := json.Marshal(struct {
		Version int `json:"version"`
		Book
	}{1, Book{Behaviours: book.Behaviours, Entries: kept}})
	if err != nil {
		return err
	}
	aead, err := s.aead(true)
	if err != nil {
		return err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return err
	}
	b := append([]byte(header), nonce...)
	b = aead.Seal(b, nonce, plain, []byte(header+secure.Service(s.Dir)))
	path := filepath.Join(s.Dir, FileName)
	if info, e := os.Lstat(path); e == nil && (!info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0) {
		return errors.New("unsafe journal file")
	} else if e != nil && !errors.Is(e, os.ErrNotExist) {
		return e
	}
	f, err := os.CreateTemp(s.Dir, ".journal-*")
	if err != nil {
		return err
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
		return err
	}
	if err = os.Rename(f.Name(), path); err != nil {
		return err
	}
	dir, err := os.Open(s.Dir)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func (s Store) aead(create bool) (cipher.AEAD, error) {
	key, err := secure.CacheKey(s.Dir, s.Vault, create)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
