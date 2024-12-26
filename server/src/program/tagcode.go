package program

import (
	"errors"
	"fmt"
	"math"

	"github.com/bvisness/BretVictorsWorstNightmare/server/src/utils"
)

const numPossibleTags = 2115
const codeLength = 4

var alphabet = []byte{'B', 'F', 'K', 'L', 'M', 'R', 'S', 'T'}

func init() {
	if math.Pow(2, 12)-1 < numPossibleTags {
		panic("the tag code math depends on the maximum tag ID fitting in 12 bits")
	}

	numPossibleCodes := math.Pow(float64(len(alphabet)), codeLength)
	if numPossibleCodes < numPossibleTags {
		panic(fmt.Errorf("alphabet and code length do not generate enough codes (only %.0f possible)", numPossibleCodes))
	}
}

func TagIDToCode(id int) string {
	if id < 0 || numPossibleTags <= id {
		panic(fmt.Errorf("invalid tag ID (must be from 0 to %d)", numPossibleTags-1))
	}

	b0 := (id >> 0) & 0b111
	b1 := (id >> 3) & 0b111
	b2 := (id >> 6) & 0b111
	b3 := (id >> 9) & 0b111

	c0 := alphabet[b0]
	c1 := alphabet[b1]
	c2 := alphabet[b2]
	c3 := alphabet[b3]

	return string([]byte{c0, c1, c2, c3})
}

func CodeToTagID(code string) (int, error) {
	if len(code) != 4 {
		return 0, errors.New("invalid length for tag code")
	}

	b0, err0 := alphabetIndex(code[0])
	b1, err1 := alphabetIndex(code[1])
	b2, err2 := alphabetIndex(code[2])
	b3, err3 := alphabetIndex(code[3])
	if err := utils.FirstError(err0, err1, err2, err3); err != nil {
		return 0, err
	}

	return b0<<0 | b1<<3 | b2<<6 | b3<<9, nil
}

func alphabetIndex(b byte) (int, error) {
	for i, letter := range alphabet {
		if letter == b {
			return i, nil
		}
	}
	return 0, fmt.Errorf("character %c is not valid in a tag code", b)
}
