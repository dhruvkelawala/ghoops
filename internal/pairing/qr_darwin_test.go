//go:build darwin && cgo

package pairing_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dhruvkelawala/ghoops/internal/pairing"
)

func TestCoreImageQRRoundTrip(t *testing.T) {
	link := "ghealth://pair?v=1&url=https%3A%2F%2Fsynthetic.ts.net%3A8787&token=ghv2_synthetic_00000000000000000000000000000000000&name=Synthetic"
	matrix, err := pairing.Matrix(link)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "pair.png")
	if err = pairing.PNG(path, matrix); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("PNG mode")
	}
	if err = pairing.PNG(path, matrix); err == nil {
		t.Fatal("PNG overwrite allowed")
	}
	script := `import Foundation
import CoreImage
let image = CIImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
let features = detector.features(in: image)
guard let qr = features.first as? CIQRCodeFeature, let text = qr.messageString else { exit(1) }
print(text, terminator: "")
`
	cmd := exec.Command("/usr/bin/swift", "-", path)
	cmd.Stdin = strings.NewReader(script)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	data, err := cmd.Output()
	if err != nil {
		t.Fatalf("CIDetector: %v %s", err, stderr.String())
	}
	if string(data) != link {
		t.Fatalf("QR did not decode to original link: got %d bytes, stderr %q", len(data), stderr.String())
	}
}
