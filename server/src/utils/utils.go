package utils

import "fmt"

// Takes an (error) return and panics if there is an error.
// Helps avoid `if err != nil` in scripts. Use sparingly in real code.
func Must(err error) {
	if err != nil {
		panic(err)
	}
}

// Takes a (something, error) return and panics if there is an error.
// Helps avoid `if err != nil` in scripts. Use sparingly in real code.
func Must1[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

// Panics if the provided value is falsy (so, zero). This works for booleans
// but also normal values, through the magic of generics.
func Assert[T comparable](value T, msg ...any) {
	var zero T
	if value == zero {
		finalMsg := ""
		for i, arg := range msg {
			if i > 0 {
				finalMsg += " "
			}
			finalMsg += fmt.Sprintf("%v", arg)
		}
		panic(finalMsg)
	}
}
