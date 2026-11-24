//go:build darwin && cgo

package secure

/*
#cgo LDFLAGS: -framework Security -framework CoreFoundation
#cgo CFLAGS: -Wno-deprecated-declarations
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>

static OSStatus gh_find(const char *service, UInt32 *len, void **data, SecKeychainItemRef *item) {
    OSStatus s = SecKeychainSetUserInteractionAllowed(false);
    if (s != errSecSuccess) return s;
    return SecKeychainFindGenericPassword(NULL, (UInt32)strlen(service), service, 7, "ghealth", len, data, item);
}
static OSStatus gh_get(const char *service, UInt32 *len, void **data) {
    return gh_find(service, len, data, NULL);
}
static OSStatus gh_set(const char *service, const char *path, UInt32 len, const void *data) {
    SecKeychainItemRef item = NULL;
    OSStatus s = gh_find(service, NULL, NULL, &item);
    if (s == errSecSuccess) {
        s = SecKeychainItemModifyAttributesAndData(item, NULL, len, data);
        CFRelease(item);
        return s;
    }
    if (s != errSecItemNotFound) return s;
    SecTrustedApplicationRef app = NULL;
    SecAccessRef access = NULL;
    s = SecTrustedApplicationCreateFromPath(path, &app);
    if (s != errSecSuccess) return s;
    CFArrayRef apps = CFArrayCreate(NULL, (const void **)&app, 1, &kCFTypeArrayCallBacks);
    CFStringRef label = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
    s = SecAccessCreate(label, apps, &access);
    if (s == errSecSuccess) {
        SecKeychainAttribute attrs[] = {{kSecServiceItemAttr, (UInt32)strlen(service), (void *)service}, {kSecAccountItemAttr, 7, "ghealth"}};
        SecKeychainAttributeList list = {2, attrs};
        s = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list, len, data, NULL, access, &item);
        if (item) CFRelease(item);
    }
    if (access) CFRelease(access);
    CFRelease(label); CFRelease(apps); CFRelease(app);
    return s;
}
static OSStatus gh_delete(const char *service) {
    SecKeychainItemRef item = NULL;
    OSStatus s = gh_find(service, NULL, NULL, &item);
    if (s != errSecSuccess) return s;
    s = SecKeychainItemDelete(item);
    CFRelease(item);
    return s;
}
*/
import "C"

import (
	"fmt"
	"unsafe"
)

type Keychain struct{}

func keychainError(s C.OSStatus) error {
	if s == C.errSecSuccess {
		return nil
	}
	if s == C.errSecItemNotFound {
		return ErrNotFound
	}
	return fmt.Errorf("Keychain unavailable (OSStatus %d); unlock or authorize the installed binary interactively; no plaintext fallback", int32(s))
}

func (Keychain) Get(service string) ([]byte, error) {
	if _, err := InstalledExecutable(); err != nil {
		return nil, err
	}
	s := C.CString(service)
	defer C.free(unsafe.Pointer(s))
	var n C.UInt32
	var data unsafe.Pointer
	if err := keychainError(C.gh_get(s, &n, &data)); err != nil {
		return nil, err
	}
	defer C.SecKeychainItemFreeContent(nil, data)
	return C.GoBytes(data, C.int(n)), nil
}

func (Keychain) Set(service string, data []byte) error {
	exe, err := InstalledExecutable()
	if err != nil {
		return err
	}
	s, p := C.CString(service), C.CString(exe)
	defer C.free(unsafe.Pointer(s))
	defer C.free(unsafe.Pointer(p))
	var ptr unsafe.Pointer
	if len(data) > 0 {
		ptr = C.CBytes(data)
		defer C.free(ptr)
	}
	return keychainError(C.gh_set(s, p, C.UInt32(len(data)), ptr))
}

func (Keychain) Delete(service string) error {
	if _, err := InstalledExecutable(); err != nil {
		return err
	}
	s := C.CString(service)
	defer C.free(unsafe.Pointer(s))
	return keychainError(C.gh_delete(s))
}
