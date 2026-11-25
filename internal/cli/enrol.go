package cli

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/dhruvkelawala/ghoops/internal/pairing"
	"github.com/dhruvkelawala/ghoops/internal/v2report"
)

func (a *app) enrol(ctx context.Context, input io.Reader, devices pairing.Devices, origin, png string) (failure error) {
	if !validEnrolmentOrigin(origin) {
		return usageError{"url must be an HTTPS origin that fits in the pairing code"}
	}
	now := a.options.Now
	if now == nil {
		now = time.Now
	}
	code, err := devices.Create(ctx, now())
	if err != nil {
		return err
	}
	defer func() {
		if failure != nil {
			cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
			defer cancel()
			failure = errors.Join(failure, devices.Cancel(cleanup, code))
		}
	}()
	payload := "GHOOPS1 " + origin + " " + code
	matrix, err := pairing.Matrix(payload)
	if err != nil {
		return err
	}
	if png != "" {
		if err := pairing.PNG(png, matrix); err != nil {
			return err
		}
	}
	if err := pairing.Terminal(a.out, matrix); err != nil {
		return err
	}
	if _, err := fmt.Fprintln(a.out, payload+"\nWaiting for your iPhone…"); err != nil {
		return err
	}

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	var answer <-chan bool
	for {
		verification, err := devices.Verification(code, now())
		if errors.Is(err, pairing.ErrEnrolmentEnded) {
			return pairingFailure("The pairing code expired or was replaced. Run ghoops pair again.")
		}
		if err != nil {
			return err
		}
		if verification != "" && answer == nil {
			if _, err := fmt.Fprintf(a.out, "Verification code: %s\nIs the same code on your iPhone? Pair it? [y/N]\n", verification); err != nil {
				return err
			}
			answer = readPairingAnswer(input)
		}
		select {
		case yes := <-answer:
			if !yes {
				return pairingFailure("Pairing declined.")
			}
			if err := devices.Approve(ctx, code, now()); err != nil {
				if errors.Is(err, pairing.ErrEnrolmentEnded) {
					return pairingFailure("The pairing code expired or was replaced. Run ghoops pair again.")
				}
				return err
			}
			_, err := fmt.Fprintln(a.out, "Paired.")
			return err
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func readPairingAnswer(input io.Reader) <-chan bool {
	answer := make(chan bool, 1)
	go func() {
		if input == nil {
			answer <- false
			return
		}
		text, _ := bufio.NewReader(io.LimitReader(input, 64)).ReadString('\n')
		answer <- strings.EqualFold(strings.TrimSpace(text), "y")
	}()
	return answer
}

func pairingFailure(message string) *v2report.Error {
	failure := v2report.NewError("unauthorized")
	failure.Message = message
	return failure
}

func validEnrolmentOrigin(origin string) bool {
	const codeBytes = 43
	if len("GHOOPS1 ")+len(origin)+1+codeBytes > 200 || strings.ContainsAny(origin, " \t\r\n") {
		return false
	}
	u, err := url.Parse(origin)
	if err != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.Path != "" || u.ForceQuery || u.RawQuery != "" || strings.Contains(origin, "#") {
		return false
	}
	if u.Port() != "" || strings.HasSuffix(u.Host, ":") {
		port, err := strconv.Atoi(u.Port())
		return err == nil && port > 0 && port <= 65535
	}
	return true
}
