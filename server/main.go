package main

import (
	"log"
	"net/http"
	"time"

	"github.com/bvisness/BretVictorsWorstNightmare/server/src/program"
	"github.com/gorilla/websocket"
	"github.com/vmihailenco/msgpack/v5"
)

// TODO: No global program instance.
var instance *program.Instance

func init() {
	var err error
	instance, err = program.Instantiate(&program.Program{
		Name:   "Tic-Tac-Toe",
		Source: program.TicTacToe,
	})
	if err != nil {
		panic(err)
	}
}

func main() {
	var upgrader = websocket.Upgrader{}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println(err)
			return
		}

		// TODO: Save latest tick results for each instance and send them to clients, rather than
		// rendering once per tick per client.
		for {
			time.Sleep(time.Second * 1)

			if object, err := instance.RenderScene(); err == nil {
				out, err := msgpack.Marshal(Message{
					Type:   MessageTypeScene,
					Object: object,
				})
				if err != nil {
					panic(err)
				}
				err = conn.WriteMessage(websocket.BinaryMessage, out)
				if err == nil {
					log.Println("wote message uwu")
				} else {
					log.Printf("ewwow witing message uwu: %v", err)
					return
				}
			} else {
				log.Printf("WARNING! Failed to render scene: %v", err)
			}
		}
	})

	log.Println("Serving AR nonsense at :8080!")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

type Message struct {
	Type   MessageType    `msgpack:"type"`
	Object program.Object `msgpack:"object,omitempty"`
}

type MessageType int

const (
	MessageTypeScene MessageType = iota + 1
)
