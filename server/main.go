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
	err = instance.Init()
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

		go func() {
			for {
				t, data, err := conn.ReadMessage()
				if err != nil {
					log.Printf("Error reading from client: %v", err)
					return
				}
				if t != websocket.BinaryMessage {
					continue
				}

				var msg ClientMessage
				err = msgpack.Unmarshal(data, &msg)
				if err != nil {
					log.Printf("ERROR: Bad MessagePack data from client: %v", err)
				}

				switch msg.Type {
				case MessageTypeTap:
					log.Printf("Tapped on ID %v", msg.ID)
					instance.Tap(msg.ID)
				default:
					log.Printf("Ignoring client message of type %v", msg.Type)
				}
			}
		}()

		// TODO: Save latest tick results for each instance and send them to clients, rather than
		// rendering once per tick per client.
		for {
			time.Sleep(time.Millisecond * 100)

			if object, err := instance.RenderScene(); err == nil {
				out, err := msgpack.Marshal(ServerMessage{
					Type:   MessageTypeScene,
					Object: object,
				})
				if err != nil {
					panic(err)
				}
				err = conn.WriteMessage(websocket.BinaryMessage, out)
				if err != nil {
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

type ServerMessage struct {
	Type   ServerMessageType `msgpack:"type"`
	Object program.Object    `msgpack:"object"`
}

type ClientMessage struct {
	Type ClientMessageType `msgpack:"type"`
	ID   string            `msgpack:"id"`
}

type ServerMessageType int
type ClientMessageType int

const (
	MessageTypeScene ServerMessageType = iota + 1
)

const (
	MessageTypeTap ClientMessageType = iota + 1
	MessageTypeHover
)
