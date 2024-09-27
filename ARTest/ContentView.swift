//
//  ContentView.swift
//  ARTest
//
//  Created by Ben Visness on 8/29/24.
//

import SwiftUI
import ARKit
import RealityKit
import MessagePacker

struct ContentView : View {
    var body: some View {
        ARViewContainer().edgesIgnoringSafeArea(.all)
    }
}

var conn: WebSocketConnection!

let arView = ARView(frame: .zero)
var frameDelegate = FrameDelegate(view: arView)

//let cubeAnchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
let tagAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))

let cameraAnchor = AnchorEntity(world: simd_float3(0, 0, 0))
let cursor = ModelEntity(
    mesh: MeshResource.generateSphere(radius: 0.005),
    materials: [SimpleMaterial(color: .systemBlue, roughness: 0.25, isMetallic: false)]
)

var listener: ARWebsocketListener!

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        arView.session.delegate = frameDelegate
//        arView.renderOptions.insert(.disableMotionBlur)
        
        cursor.transform.translation.z = -0.15
//        cameraAnchor.children.append(cursor)

        arView.scene.anchors.append(tagAnchor)
        arView.scene.anchors.append(cameraAnchor)
        
        listener = ARWebsocketListener()

        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class ARWebsocketListener: WebSocketConnectionDelegate {
    var conn: WebSocketConnection
    var initializedScene = false
    
    init() {
        conn = WebSocketTaskConnection(url: URL(string: "ws://192.168.0.32:8080/")!)
        conn.delegate = self
        conn.connect()
    }
    
    func onConnected(connection: any WebSocketConnection) {
        print("Connected to WebSocket")
    }
    
    func onDisconnected(connection: any WebSocketConnection, error: (any Error)?) {
        if let error = error {
            print("Disconnected from WebSocket with error: \(error)")
        } else {
            print("Disconnected from WebSocket normally")
        }
    }
    
    func onError(connection: any WebSocketConnection, error: any Error) {
        print("WebSocket connection error: \(error)")
    }
    
    func onMessage(connection: any WebSocketConnection, text: String) {
        print("WebSocket text message: \(text)")
    }
    
    func onMessage(connection: any WebSocketConnection, data: Data) {
        print("WebSocket binary message: \(data)")
        let msg = try! MessagePackDecoder().decode(Message.self, from: data)
        print(msg)
        if !initializedScene {
            DispatchQueue.main.async {
                for obj in msg.objects {
                    let model: ModelEntity
                    let materials = [SimpleMaterial(color: .black, roughness: 0.25, isMetallic: false)]
                    
                    switch obj.type {
                    case 1: // box
                        model = ModelEntity(
                            mesh: MeshResource.generateBox(
                                width: Float(obj.size[0]),
                                height: Float(obj.size[1]),
                                depth: Float(obj.size[2]),
                                cornerRadius: 0.005
                            ),
                            materials: materials
                        )
                    case 2: // sphere
                        model = ModelEntity(
                            mesh: MeshResource.generateSphere(radius: 0.5),
                            materials: materials
                        )
                        model.transform.scale = simd_float3(Float(obj.size[0]), Float(obj.size[1]), Float(obj.size[2]))
                    default:
                        print("unknown object type: \(obj.type)")
                        continue
                    }
                    model.transform.translation = simd_float3(Float(obj.pos[0]), Float(obj.pos[1]), Float(obj.pos[2]))
                    
                    tagAnchor.addChild(model)
                }
                
                self.initializedScene = true
            }
        }
    }
}

struct Message: Codable {
    var type: Int
    var objects: [Object]
}

struct Object: Codable {
    var type: Int
    var pos: [Float64]
    var size: [Float64]
    var text: String
}

#Preview {
    ContentView()
}
