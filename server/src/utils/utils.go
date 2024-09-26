package utils

import "fmt"

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
