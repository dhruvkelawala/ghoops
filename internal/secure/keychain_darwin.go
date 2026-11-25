//go:build darwin && cgo

package secure

/*
#cgo LDFLAGS: -framework Security -framework CoreFoundation
#cgo CFLAGS: -Wno-deprecated-declarations
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>

// The stored application path is a label. Its signing requirement controls access.
extern OSStatus SecTrustedApplicationCopyRequirement(SecTrustedApplicationRef, SecRequirementRef *) __attribute__((weak_import));

static OSStatus gh_find(const char *service, UInt32 *len, void **data, SecKeychainItemRef *item) {
    OSStatus s = SecKeychainSetUserInteractionAllowed(false);
    if (s != errSecSuccess) return s;
    return SecKeychainFindGenericPassword(NULL, (UInt32)strlen(service), service, 7, "ghealth", len, data, item);
}
static OSStatus gh_get(const char *service, UInt32 *len, void **data) {
    return gh_find(service, len, data, NULL);
}
static OSStatus gh_copy_requirement(SecTrustedApplicationRef app, CFDataRef *data) {
    if (!SecTrustedApplicationCopyRequirement) return errSecUnimplemented;
    SecRequirementRef requirement = NULL;
    OSStatus s = SecTrustedApplicationCopyRequirement(app, &requirement);
    if (s == errSecSuccess && requirement) {
        s = SecRequirementCopyData(requirement, kSecCSDefaultFlags, data);
    }
    if (requirement) CFRelease(requirement);
    return s;
}
static OSStatus gh_match_grant(SecACLRef acl, const char *path, CFDataRef expected, Boolean *matches) {
    *matches = false;
    CFArrayRef apps = NULL;
    CFStringRef description = NULL;
    SecKeychainPromptSelector prompt = 0;
    OSStatus s = SecACLCopyContents(acl, &apps, &description, &prompt);
    if (description) CFRelease(description);
    if (s == errSecSuccess && apps && CFArrayGetCount(apps) == 1) {
        SecTrustedApplicationRef app = (SecTrustedApplicationRef)CFArrayGetValueAtIndex(apps, 0);
        CFDataRef label = NULL;
        CFDataRef requirement = NULL;
        s = SecTrustedApplicationCopyData(app, &label);
        size_t path_size = strlen(path) + 1;
        if (s == errSecSuccess && label && CFDataGetLength(label) == (CFIndex)path_size &&
            memcmp(CFDataGetBytePtr(label), path, path_size) == 0) {
            s = gh_copy_requirement(app, &requirement);
            *matches = s == errSecSuccess && requirement && CFEqual(requirement, expected);
        }
        if (label) CFRelease(label);
        if (requirement) CFRelease(requirement);
    }
    if (apps) CFRelease(apps);
    return s == errSecACLNotSimple ? errSecSuccess : s;
}
static OSStatus gh_match_access(SecAccessRef access, const char *path, CFDataRef expected, Boolean *only) {
    const CFStringRef rights[] = {
        kSecACLAuthorizationDecrypt, kSecACLAuthorizationKeychainItemRead,
        kSecACLAuthorizationExportClear, kSecACLAuthorizationExportWrapped,
    };
    Boolean found = false;
    for (size_t i = 0; i < sizeof(rights) / sizeof(rights[0]); i++) {
        CFArrayRef grants = SecAccessCopyMatchingACLList(access, rights[i]);
        if (!grants) continue;
        for (CFIndex j = 0; j < CFArrayGetCount(grants); j++) {
            Boolean matches = false;
            OSStatus s = gh_match_grant((SecACLRef)CFArrayGetValueAtIndex(grants, j), path, expected, &matches);
            if (s != errSecSuccess || !matches) {
                CFRelease(grants);
                return s;
            }
            found = true;
        }
        CFRelease(grants);
    }
    *only = found;
    return errSecSuccess;
}
static OSStatus gh_acl(const char *service, const char *path, Boolean *only) {
    *only = false;
    SecKeychainItemRef item = NULL;
    OSStatus s = gh_find(service, NULL, NULL, &item);
    if (s != errSecSuccess) return s;
    SecAccessRef access = NULL;
    SecTrustedApplicationRef app = NULL;
    CFDataRef expected = NULL;
    s = SecKeychainItemCopyAccess(item, &access);
    CFRelease(item);
    if (s == errSecSuccess) s = SecTrustedApplicationCreateFromPath(path, &app);
    if (s == errSecSuccess) s = gh_copy_requirement(app, &expected);
    if (s == errSecSuccess && expected) s = gh_match_access(access, path, expected, only);
    if (expected) CFRelease(expected);
    if (app) CFRelease(app);
    if (access) CFRelease(access);
    return s;
}
static OSStatus gh_create(const char *service, const char *path, UInt32 len, const void *data) {
    OSStatus s = SecKeychainSetUserInteractionAllowed(false);
    if (s != errSecSuccess) return s;
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
        s = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list, len, data, NULL, access, NULL);
    }
    if (access) CFRelease(access);
    CFRelease(label); CFRelease(apps); CFRelease(app);
    return s;
}
static OSStatus gh_set(const char *service, const char *path, UInt32 len, const void *data) {
    SecKeychainItemRef item = NULL;
    OSStatus s = gh_find(service, NULL, NULL, &item);
    if (s == errSecItemNotFound) return gh_create(service, path, len, data);
    if (s != errSecSuccess) return s;
    s = SecKeychainItemModifyAttributesAndData(item, NULL, len, data);
    CFRelease(item);
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
	if s == C.errSecDuplicateItem {
		return ErrExists
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

// OnlyInstalledBinary checks the item's credential-access grants without reading its value.
func (Keychain) OnlyInstalledBinary(service string) (bool, error) {
	exe, err := InstalledExecutable()
	if err != nil {
		return false, err
	}
	s, p := C.CString(service), C.CString(exe)
	defer C.free(unsafe.Pointer(s))
	defer C.free(unsafe.Pointer(p))
	var only C.Boolean
	if err := keychainError(C.gh_acl(s, p, &only)); err != nil {
		return false, err
	}
	return only != 0, nil
}

func (Keychain) Set(service string, data []byte) error {
	return writeKeychainItem(service, data, false)
}

func (Keychain) Create(service string, data []byte) error {
	return writeKeychainItem(service, data, true)
}

func writeKeychainItem(service string, data []byte, createOnly bool) error {
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
	if createOnly {
		return keychainError(C.gh_create(s, p, C.UInt32(len(data)), ptr))
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
