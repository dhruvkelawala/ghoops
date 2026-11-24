//go:build !darwin || !cgo

package pairing

import "errors"

func Matrix(string) ([][]bool, error) { return nil, errors.New("QR needs macOS") }
