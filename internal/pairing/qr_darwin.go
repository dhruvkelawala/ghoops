//go:build darwin && cgo

package pairing

/*
#cgo LDFLAGS: -framework Foundation -framework CoreImage -framework CoreGraphics
#include <stdlib.h>
unsigned char *gh_qr(const char *text, int *size);
*/
import "C"
import (
	"errors"
	"unsafe"
)

func Matrix(text string) ([][]bool, error) {
	value := C.CString(text)
	defer C.free(unsafe.Pointer(value))
	var size C.int
	data := C.gh_qr(value, &size)
	if data == nil || size <= 0 {
		return nil, errors.New("QR generation failed")
	}
	defer C.free(unsafe.Pointer(data))
	pixels := C.GoBytes(unsafe.Pointer(data), size*size)
	out := make([][]bool, int(size))
	for y := range out {
		out[y] = make([]bool, int(size))
		for x := range out[y] {
			out[y][x] = pixels[y*int(size)+x] < 128
		}
	}
	return out, nil
}
