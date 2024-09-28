module github.com/bvisness/BretVictorsWorstNightmare/server

go 1.23.0

require (
	github.com/gorilla/websocket v1.5.3
	github.com/stretchr/testify v1.9.0
	github.com/vmihailenco/msgpack/v5 v5.4.1
	github.com/yuin/gopher-lua v1.1.0
)

require (
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/kr/pretty v0.1.0 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/vmihailenco/tagparser/v2 v2.0.0 // indirect
	gopkg.in/check.v1 v1.0.0-20190902080502-41f04d3bba15 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace github.com/yuin/gopher-lua v1.1.0 => github.com/bvisness/gopher-lua v0.0.0-20231210210735-90501ab9848b
