package secure_test

import (
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

func TestSignedCredentialNamespaceDoesNotReuseAdHocItems(t *testing.T) {
	service := secure.Service("/synthetic/private/profile")
	if !strings.HasPrefix(service, "io.ghealth.signed.v1.") {
		t.Fatalf("signed installation must isolate credentials from the ad-hoc namespace: %s", service)
	}
	if service == secure.Service("/synthetic/other/profile") {
		t.Fatal("separate profiles shared credential items")
	}
}
