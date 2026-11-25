package secure_test

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/secure"
	"github.com/dhruvkelawala/ghoops/internal/testutil"
)

func TestLockWaitCancellationAndRelease(t *testing.T) {
	dir := testutil.Dir(t)
	unlock, err := secure.Lock(context.Background(), dir, "synthetic.lock")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()
	if _, err := secure.Lock(ctx, dir, "synthetic.lock"); err == nil {
		t.Fatal("concurrent lock acquired")
	}
	unlock()
	again, err := secure.Lock(context.Background(), dir, "synthetic.lock")
	if err != nil {
		t.Fatal(err)
	}
	again()
}
func TestPrivateDirectoryRejectsSymlinksAndPublicFiles(t *testing.T) {
	dir := testutil.Dir(t)
	link := filepath.Join(testutil.Dir(t), "link")
	_ = os.Symlink(dir, link)
	if err := secure.PrivateDir(filepath.Join(link, "state")); err == nil {
		t.Fatal("symlink ancestor accepted")
	}
	path := filepath.Join(dir, "public")
	if err := os.WriteFile(path, []byte("synthetic"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0644); err != nil {
		t.Fatal(err)
	}
	if f, err := secure.OpenPrivate(path, os.O_RDONLY); err == nil {
		f.Close()
		t.Fatal("public file accepted")
	}
	if err := os.Chmod(dir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := secure.PrivateDir(dir); err == nil {
		t.Fatal("public directory accepted")
	}
}
func TestTestBinaryCannotAccessKeychain(t *testing.T) {
	if _, err := secure.InstalledExecutable(); err == nil {
		t.Fatal("test executable trusted")
	}
	if _, err := (secure.Keychain{}).Get("io.ghealth.synthetic-never-created"); err == nil {
		t.Fatal("test executable accessed Keychain")
	}
	if err := (secure.Keychain{}).Create("io.ghealth.synthetic-never-created", nil); err == nil {
		t.Fatal("test executable created a Keychain item")
	}
}

func TestLockAcrossFreshProcesses(t *testing.T) {
	if dir := os.Getenv("GHEALTH_SYNTHETIC_LOCK_CHILD"); dir != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
		defer cancel()
		if unlock, err := secure.Lock(ctx, dir, "synthetic.lock"); err == nil {
			unlock()
			t.Fatal("child acquired parent's lock")
		}
		return
	}
	dir := testutil.Dir(t)
	unlock, err := secure.Lock(context.Background(), dir, "synthetic.lock")
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, exe, "-test.run=^TestLockAcrossFreshProcesses$")
	cmd.Env = append(os.Environ(), "GHEALTH_SYNTHETIC_LOCK_CHILD="+dir)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("fresh-process lock check: %v %s", err, output)
	}
}
