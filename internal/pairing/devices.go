package pairing

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"slices"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

const EnrolmentDuration = 5 * time.Minute

var ErrEnrolmentEnded = errors.New("pairing code expired or already used")
var ErrDeviceNotFound = errors.New("paired device not found")

type Device struct {
	ID             string     `json:"id"`
	Name           string     `json:"name"`
	CredentialHash string     `json:"credential_sha256"`
	State          string     `json:"state"`
	Created        time.Time  `json:"created_at"`
	Approved       *time.Time `json:"approved_at"`
}

type enrolment struct {
	CodeHash     string    `json:"code_sha256"`
	Created      time.Time `json:"created_at"`
	Expires      time.Time `json:"expires_at"`
	State        string    `json:"state"`
	DeviceID     *string   `json:"device_id"`
	Verification *string   `json:"verification"`
}

type deviceBook struct {
	Version   int        `json:"version"`
	Devices   []Device   `json:"devices"`
	Enrolment *enrolment `json:"enrolment"`
}

type DeviceCredentials struct {
	book   deviceBook
	Legacy Token
}

func (c DeviceCredentials) Paired() bool {
	return c.Legacy.Value != "" || slices.ContainsFunc(c.book.Devices, func(device Device) bool { return device.State == "active" })
}

func (c DeviceCredentials) Device(token string, now time.Time) (Device, bool) {
	if token == "" {
		return Device{}, false
	}
	digest := hash(token)
	for _, device := range c.book.Devices {
		if matches(device.CredentialHash, digest) && (device.State == "active" || c.book.waiting(device.ID, now)) {
			return device, true
		}
	}
	return Device{}, false
}

type Devices struct {
	Dir   string
	Vault secure.Vault
}

func (d Devices) Credentials(ctx context.Context) (DeviceCredentials, error) {
	unlock, err := d.lock(ctx)
	if err != nil {
		return DeviceCredentials{}, err
	}
	defer unlock()
	return d.credentialsLocked()
}

func (d Devices) credentialsLocked() (DeviceCredentials, error) {
	book, err := d.load()
	if err != nil {
		return DeviceCredentials{}, err
	}
	legacy, err := d.legacy().Load()
	if err != nil && !errors.Is(err, secure.ErrNotFound) {
		return DeviceCredentials{}, err
	}
	if book.retired(legacy) {
		legacy = Token{}
	}
	return DeviceCredentials{book: book, Legacy: legacy}, nil
}

func (d Devices) Create(ctx context.Context, now time.Time) (string, error) {
	unlock, err := d.lock(ctx)
	if err != nil {
		return "", err
	}
	defer unlock()
	book, err := d.load()
	if err != nil {
		return "", err
	}
	if _, err := secure.CacheKey(d.Dir, d.Vault, true); err != nil {
		return "", err
	}
	code, err := randomString(32, base64.RawURLEncoding.EncodeToString)
	if err != nil {
		return "", err
	}
	book.clearEnrolment()
	book.Enrolment = &enrolment{CodeHash: hash(code), Created: now.UTC(), Expires: now.Add(EnrolmentDuration).UTC(), State: "open"}
	if err := d.save(book); err != nil {
		return "", err
	}
	return code, nil
}

type Redeemed struct {
	DeviceID     string
	Credential   string
	Verification string
	ProfileID    string
	Expires      time.Time
}

func (d Devices) Redeem(ctx context.Context, code, name string, now time.Time) (Redeemed, error) {
	unlock, err := d.lock(ctx)
	if err != nil {
		return Redeemed{}, err
	}
	defer unlock()
	book, err := d.load()
	if err != nil {
		return Redeemed{}, err
	}
	active := book.enrolment(code, now)
	if active == nil || active.State != "open" {
		return Redeemed{}, ErrEnrolmentEnded
	}
	key, err := secure.CacheKey(d.Dir, d.Vault, false)
	if err != nil {
		return Redeemed{}, err
	}
	id, err := randomString(6, hex.EncodeToString)
	if err != nil {
		return Redeemed{}, err
	}
	id = "dev_" + id
	if slices.ContainsFunc(book.Devices, func(device Device) bool { return device.ID == id }) {
		return Redeemed{}, errors.New("cannot allocate pairing device ID")
	}
	raw, err := randomString(32, base64.RawURLEncoding.EncodeToString)
	if err != nil {
		return Redeemed{}, err
	}
	number, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return Redeemed{}, err
	}
	credential, verification := "ghv3_"+raw, fmt.Sprintf("%06d", number.Int64())
	book.Devices = append(book.Devices, Device{ID: id, Name: name, CredentialHash: hash(credential), State: "pending", Created: now.UTC()})
	active.State, active.DeviceID, active.Verification = "redeemed", &id, &verification
	if err := d.save(book); err != nil {
		return Redeemed{}, err
	}
	return Redeemed{DeviceID: id, Credential: credential, Verification: verification, ProfileID: secure.ProfileID(key), Expires: active.Expires}, nil
}

func (d Devices) Verification(code string, now time.Time) (string, error) {
	book, err := d.load()
	if err != nil {
		return "", err
	}
	active := book.enrolment(code, now)
	if active == nil {
		return "", ErrEnrolmentEnded
	}
	if active.Verification == nil {
		return "", nil
	}
	return *active.Verification, nil
}

func (d Devices) Approve(ctx context.Context, code string, now time.Time) error {
	unlock, err := d.lock(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	book, err := d.load()
	if err != nil {
		return err
	}
	active := book.enrolment(code, now)
	if active == nil || active.DeviceID == nil {
		return ErrEnrolmentEnded
	}
	index := slices.IndexFunc(book.Devices, func(device Device) bool { return device.ID == *active.DeviceID })
	if index == -1 || book.Devices[index].State != "pending" {
		return ErrEnrolmentEnded
	}
	previous := deviceBook{Version: book.Version, Devices: slices.Clone(book.Devices), Enrolment: book.Enrolment}
	approved := now.UTC()
	book.Devices[index].State, book.Devices[index].Approved = "active", &approved
	book.Enrolment = nil
	if err := d.save(book); err != nil {
		return err
	}
	if err := d.legacy().revokeLocked(); err != nil {
		return errors.Join(err, d.save(previous))
	}
	return nil
}

func (d Devices) Cancel(ctx context.Context, code string) error {
	unlock, err := d.lock(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	book, err := d.load()
	if err != nil {
		return err
	}
	if book.Enrolment == nil || !matches(book.Enrolment.CodeHash, hash(code)) {
		return nil
	}
	book.clearEnrolment()
	return d.save(book)
}

func (d Devices) List(ctx context.Context, now time.Time) ([]Device, Token, error) {
	unlock, err := d.lock(ctx)
	if err != nil {
		return nil, Token{}, err
	}
	defer unlock()
	credentials, err := d.credentialsLocked()
	if err != nil {
		return nil, Token{}, err
	}
	book := credentials.book
	if book.Enrolment != nil && !now.Before(book.Enrolment.Expires) {
		book.clearEnrolment()
		if err := d.save(book); err != nil {
			return nil, Token{}, err
		}
	}
	return book.Devices, credentials.Legacy, nil
}

func (d Devices) Revoke(ctx context.Context, id string) error {
	unlock, err := d.lock(ctx)
	if err != nil {
		return err
	}
	defer unlock()
	if id == "" {
		if err := d.legacy().revokeLocked(); err != nil {
			return err
		}
		return d.save(deviceBook{Version: 1, Devices: []Device{}})
	}
	book, err := d.load()
	if err != nil {
		return err
	}
	index := slices.IndexFunc(book.Devices, func(device Device) bool { return device.ID == id })
	if index == -1 {
		return ErrDeviceNotFound
	}
	legacy, err := d.legacy().Load()
	if err != nil && !errors.Is(err, secure.ErrNotFound) {
		return err
	}
	if book.retired(legacy) {
		if err := d.legacy().revokeLocked(); err != nil {
			return err
		}
	}
	book.Devices = slices.Delete(book.Devices, index, index+1)
	if book.Enrolment != nil && book.Enrolment.DeviceID != nil && *book.Enrolment.DeviceID == id {
		book.Enrolment = nil
	}
	return d.save(book)
}

func (b deviceBook) enrolment(code string, now time.Time) *enrolment {
	active := b.Enrolment
	if active != nil && now.Before(active.Expires) && matches(active.CodeHash, hash(code)) {
		return active
	}
	return nil
}

func (b deviceBook) waiting(id string, now time.Time) bool {
	active := b.Enrolment
	return active != nil && active.DeviceID != nil && *active.DeviceID == id && now.Before(active.Expires)
}

func (b deviceBook) retired(legacy Token) bool {
	return legacy.Value != "" && slices.ContainsFunc(b.Devices, func(device Device) bool {
		return device.Approved != nil && !legacy.Created.After(*device.Approved)
	})
}

func (b *deviceBook) clearEnrolment() {
	b.Devices = slices.DeleteFunc(b.Devices, func(device Device) bool { return device.State == "pending" })
	b.Enrolment = nil
}

func (d Devices) load() (deviceBook, error) {
	data, err := d.Vault.Get(d.item())
	if errors.Is(err, secure.ErrNotFound) {
		return deviceBook{Version: 1, Devices: []Device{}}, nil
	}
	if err != nil {
		return deviceBook{}, err
	}
	var book deviceBook
	if json.Unmarshal(data, &book) != nil || !book.valid() {
		return deviceBook{}, errors.New("invalid paired device list")
	}
	return book, nil
}

func (b deviceBook) valid() bool {
	if b.Version != 1 || b.Devices == nil {
		return false
	}
	var pending string
	for _, device := range b.Devices {
		id, ok := strings.CutPrefix(device.ID, "dev_")
		if !ok || !isHex(id, 6) || !isHex(device.CredentialHash, sha256.Size) || device.Created.IsZero() {
			return false
		}
		switch device.State {
		case "active":
			if device.Approved == nil || device.Approved.IsZero() {
				return false
			}
		case "pending":
			if pending != "" || device.Approved != nil {
				return false
			}
			pending = device.ID
		default:
			return false
		}
	}
	active := b.Enrolment
	if active == nil {
		return pending == ""
	}
	if !isHex(active.CodeHash, sha256.Size) || active.Created.IsZero() || !active.Expires.After(active.Created) {
		return false
	}
	if active.State == "open" {
		return pending == "" && active.DeviceID == nil && active.Verification == nil
	}
	return active.State == "redeemed" && pending != "" && active.DeviceID != nil && *active.DeviceID == pending &&
		active.Verification != nil && len(*active.Verification) == 6 && !strings.ContainsFunc(*active.Verification, func(r rune) bool { return r < '0' || r > '9' })
}

func isHex(value string, bytes int) bool {
	if len(value) != 2*bytes {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func (d Devices) save(book deviceBook) error {
	data, err := json.Marshal(book)
	if err != nil {
		return err
	}
	return d.Vault.Set(d.item(), data)
}

func (d Devices) item() string   { return secure.ServeDevicesItem.Service(d.Dir) }
func (d Devices) legacy() Tokens { return Tokens{Dir: d.Dir, Vault: d.Vault} }
func (d Devices) lock(ctx context.Context) (func(), error) {
	return secure.Lock(ctx, d.Dir, "pair.lock")
}

func randomString(size int, encode func([]byte) string) (string, error) {
	random := make([]byte, size)
	if _, err := rand.Read(random); err != nil {
		return "", err
	}
	return encode(random), nil
}

func hash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func matches(left, right string) bool {
	return subtle.ConstantTimeCompare([]byte(left), []byte(right)) == 1
}
