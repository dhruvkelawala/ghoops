package activities

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
	"reflect"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

type Pause struct {
	Start time.Time `json:"start"`
	End   time.Time `json:"end"`
}
type Upload struct {
	ID           string          `json:"id"`
	ExerciseType string          `json:"exercise_type"`
	DisplayName  string          `json:"display_name"`
	Start        time.Time       `json:"start"`
	End          time.Time       `json:"end"`
	Pauses       []Pause         `json:"pauses"`
	Live         json.RawMessage `json:"live,omitempty"`
	Origin       string          `json:"origin"`
	Notes        *string         `json:"notes"`
}
type Record struct {
	Upload
	CreatedAt time.Time `json:"created_at"`
}
type Store struct {
	Dir   string
	Vault secure.Vault
}
type ValidationError struct{ Field string }

func (e *ValidationError) Error() string { return "Invalid activity field: " + e.Field + "." }

var ErrConflict = errors.New("activity conflict")
var ErrNotFound = errors.New("activity not found")
var uuid = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
var Sports = map[string]string{"BOXING": "Boxing", "KICKBOXING": "Kickboxing", "MARTIAL_ARTS": "Martial Arts", "WALKING": "Walking", "RUNNING": "Running", "WEIGHTLIFTING": "Weightlifting", "BIKING": "Cycling", "HIIT": "HIIT", "YOGA": "Yoga", "SWIMMING": "Swimming", "HIKING": "Hiking", "OTHER": "Other"}

func (a Upload) Validate(now time.Time) error {
	bad := func(s string) error { return &ValidationError{s} }
	if !uuid.MatchString(a.ID) {
		return bad("id")
	}
	if _, ok := Sports[a.ExerciseType]; !ok {
		return bad("exercise_type")
	}
	if n := utf8.RuneCountInString(a.DisplayName); n < 1 || n > 40 {
		return bad("display_name")
	}
	if a.Start.IsZero() || a.Start.Before(now.Add(-EditHorizonDays*24*time.Hour)) {
		return bad("start")
	}
	if !a.End.After(a.Start) || a.End.After(now.Add(5*time.Minute)) {
		return bad("end")
	}
	active := a.End.Sub(a.Start)
	last := a.Start
	for _, p := range a.Pauses {
		if p.Start.Before(last) || !p.End.After(p.Start) || p.End.After(a.End) {
			return bad("pauses")
		}
		last = p.End
		active -= p.End.Sub(p.Start)
	}
	if active < ActiveMinMinutes*time.Minute || active > ActiveMaxMinutes*time.Minute {
		return bad("active_duration")
	}
	if a.Origin != "" && a.Origin != "live" && a.Origin != "added" {
		return bad("origin")
	}
	if a.Notes != nil {
		if n := utf8.RuneCountInString(strings.TrimSpace(*a.Notes)); n < 1 || n > NotesMaxRunes {
			return bad("notes")
		}
	}
	if a.Origin == "added" && len(a.Live) > 0 {
		return bad("live")
	}
	if len(a.Live) > 0 {
		var live map[string]json.RawMessage
		if json.Unmarshal(a.Live, &live) != nil || live == nil {
			return bad("live")
		}
	}
	return nil
}
func (s Store) Put(ctx context.Context, a Upload, now time.Time) (Record, bool, error) {
	a = a.clean()
	if err := a.Validate(now); err != nil {
		return Record{}, false, err
	}
	if a.Pauses == nil {
		a.Pauses = []Pause{}
	}
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return Record{}, false, err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return Record{}, false, err
	}
	for _, r := range book.Activities {
		if r.ID == a.ID {
			var x, y any
			b, _ := json.Marshal(r.Upload)
			json.Unmarshal(b, &x)
			b, _ = json.Marshal(a)
			json.Unmarshal(b, &y)
			if !reflect.DeepEqual(x, y) {
				return Record{}, false, ErrConflict
			}
			return r, false, nil
		}
	}
	r := Record{a, now.UTC()}
	book.Activities = append(book.Activities, r)
	return r, true, s.save(book, now)
}
func (s Store) Delete(ctx context.Context, id string, now time.Time) error {
	unlock, err := secure.Lock(ctx, s.Dir, "activities.lock")
	if err != nil {
		return err
	}
	defer unlock()
	book, err := s.Load()
	if err != nil {
		return err
	}
	for i, r := range book.Activities {
		if r.ID == id {
			book.Activities = append(book.Activities[:i], book.Activities[i+1:]...)
			target := "goop-" + id
			edits := book.Edits[:0]
			for _, edit := range book.Edits {
				if edit.ID == target {
					continue
				}
				ids := edit.MergeWith[:0]
				for _, merged := range edit.MergeWith {
					if merged != target {
						ids = append(ids, merged)
					}
				}
				edit.MergeWith = ids
				if !edit.empty() {
					edits = append(edits, edit)
				}
			}
			book.Edits = edits
			ratings := book.Ratings[:0]
			for _, rating := range book.Ratings {
				if rating.ID != target {
					ratings = append(ratings, rating)
				}
			}
			book.Ratings = ratings
			return s.save(book, now)
		}
	}
	return ErrNotFound
}
func (s Store) List() ([]Record, error) {
	book, err := s.Load()
	return book.Activities, err
}
func (s Store) Load() (Book, error) {
	book := Book{Activities: []Record{}, Edits: []Edit{}, SleepEdits: []SleepEdit{}, Ratings: []Rating{}}
	if _, err := os.Lstat(s.Dir); errors.Is(err, os.ErrNotExist) {
		return book, nil
	}
	if err := secure.PrivateDir(s.Dir); err != nil {
		return Book{}, err
	}
	f, err := secure.OpenPrivate(filepath.Join(s.Dir, "activities-v2.enc"), os.O_RDONLY)
	if errors.Is(err, os.ErrNotExist) {
		return book, nil
	}
	if err != nil {
		return Book{}, err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, 16<<20+1))
	if err != nil || len(b) > 16<<20 {
		return Book{}, errors.New("cannot read activities")
	}
	aead, err := s.aead(false)
	if err != nil {
		return Book{}, err
	}
	const header = "ghealth-cache-v2\n"
	n := len(header)
	if len(b) < n+aead.NonceSize()+aead.Overhead() || string(b[:n]) != header {
		return Book{}, errors.New("invalid activities envelope")
	}
	plain, err := aead.Open(nil, b[n:n+aead.NonceSize()], b[n+aead.NonceSize():], []byte(header+secure.Service(s.Dir)))
	if err != nil {
		return Book{}, errors.New("activities authentication failed")
	}
	var body struct {
		Version int `json:"version"`
		Book
	}
	if json.Unmarshal(plain, &body) != nil || body.Version != 1 {
		return Book{}, errors.New("invalid activities schema")
	}
	for _, row := range body.Activities {
		row.Upload = row.Upload.clean()
		book.Activities = append(book.Activities, row)
	}
	book.Edits = append(book.Edits, body.Edits...)
	book.SleepEdits = append(book.SleepEdits, body.SleepEdits...)
	book.Ratings = append(book.Ratings, body.Ratings...)
	sort.Slice(book.Ratings, func(i, j int) bool { return book.Ratings[i].ID < book.Ratings[j].ID })
	sort.Slice(book.SleepEdits, func(i, j int) bool { return book.SleepEdits[i].Date < book.SleepEdits[j].Date })
	for i := range book.Edits {
		if book.Edits[i].MergeWith == nil {
			book.Edits[i].MergeWith = []string{}
		}
	}
	sort.Slice(book.Activities, func(i, j int) bool { return book.Activities[i].Start.Before(book.Activities[j].Start) })
	sort.Slice(book.Edits, func(i, j int) bool { return book.Edits[i].ID < book.Edits[j].ID })
	return book, nil
}
func (s Store) save(book Book, now time.Time) error {
	kept := []Record{}
	for _, r := range book.Activities {
		if !r.End.Before(now.AddDate(0, 0, -400)) {
			kept = append(kept, r)
		}
	}
	edits := []Edit{}
	for _, e := range book.Edits {
		if !e.UpdatedAt.Before(now.AddDate(0, 0, -400)) {
			edits = append(edits, e)
		}
	}
	sleepEdits := []SleepEdit{}
	for _, edit := range book.SleepEdits {
		if !edit.UpdatedAt.Before(now.AddDate(0, 0, -400)) {
			sleepEdits = append(sleepEdits, edit)
		}
	}
	ratings := []Rating{}
	for _, rating := range book.Ratings {
		if !rating.UpdatedAt.Before(now.AddDate(0, 0, -400)) {
			ratings = append(ratings, rating)
		}
	}
	plain, err := json.Marshal(struct {
		Version int `json:"version"`
		Book
	}{1, Book{Activities: kept, Edits: edits, SleepEdits: sleepEdits, Ratings: ratings}})
	if err != nil {
		return err
	}

	aead, err := s.aead(true)
	if err != nil {
		return err
	}
	const header = "ghealth-cache-v2\n"
	nonce := make([]byte, aead.NonceSize())
	if _, err = rand.Read(nonce); err != nil {
		return err
	}
	b := append([]byte(header), nonce...)
	b = aead.Seal(b, nonce, plain, []byte(header+secure.Service(s.Dir)))
	path := filepath.Join(s.Dir, "activities-v2.enc")
	if info, e := os.Lstat(path); e == nil && (!info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0) {
		return errors.New("unsafe activities file")
	} else if e != nil && !errors.Is(e, os.ErrNotExist) {
		return e
	}
	f, err := os.CreateTemp(s.Dir, ".activities-*")
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

func (a Upload) clean() Upload {
	if a.Origin == "" {
		a.Origin = "live"
	}
	if a.Notes != nil {
		note := strings.TrimSpace(*a.Notes)
		a.Notes = &note
	}
	return a
}

func DecodeUpload(body []byte) (Upload, error) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(body, &fields) != nil || fields == nil {
		return Upload{}, &ValidationError{"body"}
	}
	if raw, ok := fields["origin"]; ok {
		var origin string
		if json.Unmarshal(raw, &origin) != nil || origin != "live" && origin != "added" {
			return Upload{}, &ValidationError{"origin"}
		}
	}
	var upload Upload
	if json.Unmarshal(body, &upload) != nil {
		return Upload{}, &ValidationError{"body"}
	}
	return upload, nil
}
