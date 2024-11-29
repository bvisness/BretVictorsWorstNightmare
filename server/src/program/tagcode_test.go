package program

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTagIDToCode(t *testing.T) {
	for id := 0; id < numPossibleTags; id++ {
		code := TagIDToCode(id)
		t.Log(code)
		if reversed, err := CodeToTagID(code); assert.Nil(t, err) {
			assert.Equal(t, id, reversed)
		}
	}
}
