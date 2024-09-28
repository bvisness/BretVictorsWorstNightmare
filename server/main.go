package main

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/bvisness/BretVictorsWorstNightmare/server/src/program"
	"github.com/bvisness/BretVictorsWorstNightmare/server/src/utils"
	"github.com/gorilla/websocket"
	"github.com/vmihailenco/msgpack/v5"
)

// TODO: Save these persistently
var programs = make(map[string]*program.Program)
var instances []*program.Instance
var tag2instance = make(map[int]InstanceID)

var renderedScenes []program.Object

type InstanceID int

func registerProgram(p *program.Program) {
	programs[p.Name] = p
}

func instantiate(p *program.Program, init bool) (InstanceID, error) {
	instance, err := program.Instantiate(p)
	if err != nil {
		return -1, fmt.Errorf("failed to instantiate program \"%s\": %w", p.Name, err)
	}
	if init {
		err := instance.Init()
		if err != nil {
			return -1, fmt.Errorf("failed to init instance: %w", err)
		}
	}
	instances = append(instances, instance)
	return InstanceID(len(instances) - 1), nil
}

func init() {
	registerProgram(&program.Program{
		Name:   "Tic-Tac-Toe",
		Source: program.TicTacToe,
	})
	tag2instance[0] = utils.Must1(instantiate(programs["Tic-Tac-Toe"], true))
	tag2instance[1] = utils.Must1(instantiate(programs["Tic-Tac-Toe"], true))
}

func main() {
	go runPrograms()

	var upgrader = websocket.Upgrader{}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println(err)
			return
		}
		defer conn.Close()

		// Client message read loop
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
					log.Printf("Tapped on ID %v", msg.EntityID)
					instances[msg.Instance].Tap(msg.EntityID)
				default:
					log.Printf("Ignoring client message of type %v", msg.Type)
				}
			}
		}()

		// Server message send loop
		for range time.NewTicker(time.Millisecond * 100).C {
			var instanceUpdates []InstanceUpdate
			var activeInstances []InstanceID
			for id, instance := range instances {
				// Generate instance updates and track which instances are active
				update := InstanceUpdate{
					Instance: InstanceID(id),
					Program:  instance.Program.Name,
				}
				for tag, otherID := range tag2instance {
					if InstanceID(id) == otherID {
						t := &tag
						update.Tag = t
						activeInstances = append(activeInstances, InstanceID(id))
					}
				}
				instanceUpdates = append(instanceUpdates, update)
			}

			// Inform the client of all instances
			out := utils.Must1(msgpack.Marshal(ServerMessage{
				Type:      MessageTypeInstances,
				Instances: instanceUpdates,
			}))
			err = conn.WriteMessage(websocket.BinaryMessage, out)
			if err != nil {
				log.Printf("failed to send tag instances to client: %v", err)
				return
			}

			// Send renders of active instances
			for _, instanceID := range activeInstances {
				if len(renderedScenes) <= int(instanceID) {
					log.Printf("INTERESTING! Race condition meant that active instance %d did not have a rendered scene.", instanceID)
					continue
				}
				out := utils.Must1(msgpack.Marshal(ServerMessage{
					Type: MessageTypeScene,
					Scene: SceneUpdate{
						Instance: instanceID,
						Scene:    renderedScenes[instanceID],
					},
				}))
				err = conn.WriteMessage(websocket.BinaryMessage, out)
				if err != nil {
					log.Printf("failed to send scene to client: %v", err)
					return
				}
			}
		}
	})

	log.Println("Serving AR nonsense at :8080!")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func runPrograms() {
	for range time.NewTicker(time.Millisecond * 100).C {
		// We swap the rendered scene data to an entirely separate array to
		// avoid data race issues. We don't necessarily care if every client
		// gets the newest set of scene data, only that they receive a coherent
		// set of scene data, and swapping the whole array to new memory (and
		// leaving the rest to the garbage collector) satisfies that need.
		newRenderedScenes := make([]program.Object, len(instances))
		for i, instance := range instances {
			scene, err := instance.RenderScene()
			if err != nil {
				log.Printf("WARNING! Failed to render instance %d: %v", i, err)
				continue
			}
			newRenderedScenes[i] = scene
		}
		renderedScenes = newRenderedScenes
	}
}

type ServerMessage struct {
	Type      ServerMessageType `msgpack:"type"`
	Scene     SceneUpdate       `msgpack:"scene"`
	Instances []InstanceUpdate  `msgpack:"instances"`
}

type SceneUpdate struct {
	Instance InstanceID     `msgpack:"instance"`
	Scene    program.Object `msgpack:"scene"`
}

type InstanceUpdate struct {
	Instance InstanceID `msgpack:"instance"`
	Program  string     `msgpack:"program"`
	Tag      *int       `msgpack:"tag,omitempty"`
}

type ClientMessage struct {
	Type     ClientMessageType `msgpack:"type"`
	Instance InstanceID        `msgpack:"instance"`
	EntityID string            `msgpack:"entityid"`
}

type ServerMessageType int
type ClientMessageType int

const (
	MessageTypeScene ServerMessageType = iota + 1
	MessageTypeInstances
)

const (
	MessageTypeTap ClientMessageType = iota + 1
	MessageTypeHover
)
