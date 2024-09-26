package program_test

import (
	"testing"

	"github.com/bvisness/BretVictorsWorstNightmare/server/src/program"
	"github.com/stretchr/testify/assert"
)

func TestInstantiate(t *testing.T) {
	p := program.Program{
		Name: "Tic-Tac-Toe",
		Source: `
function ARInit()
  ar.setdata("board", {
    "", "", "",
    "", "", "",
    "", "", "",
  })
  ar.setdata("turn", "x")
end
`,
	}
	instance, err := program.Instantiate(&p)
	assert.Nil(t, err)
	assert.Nil(t, instance.Init())
	t.Logf("%#v", instance.Data)
}
