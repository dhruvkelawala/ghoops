package pairing

import (
	"image"
	"image/color"
	"image/png"
	"io"
	"os"
	"strings"

	"github.com/dhruvkelawala/ghoops/internal/secure"
)

func Terminal(w io.Writer, matrix [][]bool) error {
	size := len(matrix) + 4
	pixel := func(x, y int) bool { return y >= 2 && y < size-2 && x >= 2 && x < size-2 && matrix[y-2][x-2] }
	var out strings.Builder
	for y := 0; y < size; y += 2 {
		for x := 0; x < size; x++ {
			a, b := pixel(x, y), pixel(x, y+1)
			switch {
			case a && b:
				out.WriteRune('█')
			case a:
				out.WriteRune('▀')
			case b:
				out.WriteRune('▄')
			default:
				out.WriteByte(' ')
			}
		}
		out.WriteByte('\n')
	}
	_, err := io.WriteString(w, out.String())
	return err
}
func PNG(path string, matrix [][]bool) error {
	f, err := secure.OpenPrivate(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY)
	if err != nil {
		return err
	}
	saved := false
	defer func() {
		f.Close()
		if !saved {
			os.Remove(path)
		}
	}()
	size := (len(matrix) + 4) * 8
	img := image.NewGray(image.Rect(0, 0, size, size))
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			v := uint8(255)
			mx, my := x/8-2, y/8-2
			if mx >= 0 && my >= 0 && my < len(matrix) && mx < len(matrix) && matrix[my][mx] {
				v = 0
			}
			img.SetGray(x, y, color.Gray{Y: v})
		}
	}
	if err = png.Encode(f, img); err != nil {
		return err
	}
	if err = f.Sync(); err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	saved = true
	return nil
}
