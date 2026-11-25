package secure

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
)

func ProfileID(key []byte) string {
	if len(key) != 32 {
		return ""
	}
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte("ghoops profile id v1"))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))[:22]
}
