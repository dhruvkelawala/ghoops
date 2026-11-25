package secure

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

var ErrNotFound = errors.New("Keychain item not found")
var ErrExists = errors.New("Keychain item already exists")

type Vault interface {
	Get(string) ([]byte, error)
	Set(string, []byte) error
	Create(string, []byte) error
	Delete(string) error
}

func Service(dir string) string {
	return fmt.Sprintf("io.ghealth.signed.v1.%x", sha256.Sum256([]byte(dir)))
}

type KeychainItem string

const (
	CacheKeyItem     KeychainItem = ".cache-key"
	OAuthSessionItem KeychainItem = ".oauth"
	ServeTokenItem   KeychainItem = ".serve-token"
	ServeDevicesItem KeychainItem = ".serve-devices"
)

func (item KeychainItem) Service(dir string) string {
	return Service(dir) + string(item)
}

func PrivateDir(path string) error {
	path, err := filepath.Abs(path)
	if err != nil {
		return errors.New("invalid state directory")
	}
	for p := path; ; p = filepath.Dir(p) {
		fi, e := os.Lstat(p)
		if e == nil && fi.Mode()&os.ModeSymlink != 0 {
			return errors.New("state path contains a symlink")
		}
		if e != nil && !errors.Is(e, os.ErrNotExist) {
			return errors.New("cannot inspect state directory")
		}
		if p == filepath.Dir(p) {
			break
		}
	}
	if err := os.MkdirAll(path, 0700); err != nil {
		return errors.New("cannot create state directory")
	}
	fi, err := os.Lstat(path)
	if err != nil || !fi.IsDir() {
		return errors.New("state path is not a directory")
	}
	if fi.Mode().Perm()&0077 != 0 {
		return errors.New("state directory must have permissions 0700")
	}
	if s, ok := fi.Sys().(*syscall.Stat_t); !ok || int(s.Uid) != os.Getuid() {
		return errors.New("state directory must belong to current user")
	}
	return nil
}

func OpenPrivate(path string, flags int) (*os.File, error) {
	f, err := os.OpenFile(path, flags|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, err
	}
	fi, err := f.Stat()
	if err != nil || !fi.Mode().IsRegular() || fi.Mode().Perm()&0077 != 0 {
		f.Close()
		return nil, errors.New("private file must be regular with permissions 0600")
	}
	if s, ok := fi.Sys().(*syscall.Stat_t); !ok || int(s.Uid) != os.Getuid() {
		f.Close()
		return nil, errors.New("private file must belong to current user")
	}
	return f, nil
}

func Lock(ctx context.Context, dir, name string) (func(), error) {
	if err := PrivateDir(dir); err != nil {
		return nil, err
	}
	f, err := OpenPrivate(filepath.Join(dir, name), os.O_CREATE|os.O_RDWR)
	if err != nil {
		return nil, errors.New("cannot open private lock file")
	}
	for {
		err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			return func() { _ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN); _ = f.Close() }, nil
		}
		if err != syscall.EWOULDBLOCK && err != syscall.EAGAIN {
			f.Close()
			return nil, errors.New("cannot lock local state")
		}
		select {
		case <-ctx.Done():
			f.Close()
			return nil, errors.New("timed out waiting for local state lock")
		case <-time.After(50 * time.Millisecond):
		}
	}
}

func InstalledExecutable() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", errors.New("cannot find home directory")
	}
	exe, err := os.Executable()
	if err != nil {
		return "", errors.New("cannot identify executable")
	}
	exe, err = filepath.EvalSymlinks(exe)
	if err != nil || exe != filepath.Join(home, ".local", "bin", "ghealth") {
		return "", errors.New("Keychain access requires the installed ~/.local/bin/ghealth binary; run make install")
	}
	return exe, nil
}
