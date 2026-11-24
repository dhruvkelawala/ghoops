package netx

import (
	"context"
	"errors"
	"io"
	"math/rand/v2"
	"net/http"
	"strconv"
	"time"
)

const MaxBody = 32 << 20

func Client() *http.Client {
	return &http.Client{Timeout: 30 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
}

func Read(resp *http.Response) ([]byte, error) {
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, MaxBody+1))
	if err != nil || len(b) > MaxBody {
		return nil, errors.New("HTTP response unreadable or exceeds size limit")
	}
	return b, nil
}

func Wait(ctx context.Context, attempt int, retryAfter string) error {
	d := time.Duration(1<<attempt)*250*time.Millisecond + time.Duration(rand.IntN(200))*time.Millisecond
	if retryAfter != "" {
		if n, err := strconv.Atoi(retryAfter); err == nil && n >= 0 {
			if n > 60 {
				return errors.New("server Retry-After exceeds retry budget; try sync later")
			}
			d = time.Duration(n) * time.Second
		} else if t, err := http.ParseTime(retryAfter); err == nil {
			d = time.Until(t)
			if d < 0 {
				d = 0
			}
		}
	}
	if d > 60*time.Second {
		return errors.New("server Retry-After exceeds retry budget; try sync later")
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}
