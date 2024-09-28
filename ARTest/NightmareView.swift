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
import Combine

struct NightmareView : View {
    var body: some View {
        NightmareViewContainer().edgesIgnoringSafeArea(.all)
    }
}

struct NightmareViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        return Nightmare(frame: .zero)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class Nightmare: ARView, WebSocketConnectionDelegate, NightmareTrackingDelegate {
    var frameDelegate: FrameDelegate!
    var cancellables = Set<AnyCancellable>()

    let origin = AnchorEntity(world: simd_float3(0, 0, 0))
    let tagEntity = Entity()
    let cameraEntity = Entity()
    let cursor = ModelEntity(
        mesh: MeshResource.generateSphere(radius: 0.005),
        materials: [SimpleMaterial(color: .systemBlue, roughness: 0.25, isMetallic: false)]
    )
    
    var entityIDs: [Entity: String] = [:]

    var conn: WebSocketConnection!
    var initializedScene = false
    
    required init(frame frameRect: CGRect) {
        super.init(frame: frameRect)

        frameDelegate = FrameDelegate(view: self)
        frameDelegate.delegate = self
        session.delegate = frameDelegate
        renderOptions.insert(.disableMotionBlur)

        conn = WebSocketTaskConnection(url: URL(string: "ws://192.168.0.32:8080/")!)
        conn.delegate = self
        conn.connect()
        
        cursor.transform.translation.z = -0.15
//        cameraAnchor.children.append(cursor)

        scene.anchors.append(origin)
        origin.addChild(tagEntity)
        origin.addChild(cameraEntity)
        
        scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onUpdate(updateEvent: event)
        }
        .store(in: &cancellables)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        self.addGestureRecognizer(tapGesture)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func onUpdate(updateEvent: SceneEvents.Update) {
        let deltaTime = updateEvent.deltaTime
    }
    
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        // 1. Get the location of the tap on the screen
        let tapLocation = sender.location(in: self)

        let hitEntities = self.raycastCenter()
        if let hit = hitEntities.first {
            if let id = entityIDs[hit] {
                let message = ClientMessage(type: .tap, id: id)
                let data = try! MessagePackEncoder().encode(message)
                conn.send(data: data)
            }
        }
    }
    
    func raycastCenter() -> [Entity] {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let ray = self.ray(through: center) {
            let hits = scene.raycast(origin: ray.origin, direction: ray.direction)
            var hitEntities: [Entity] = []
            for hit in hits {
                hitEntities.append(hit.entity)
            }
            return hitEntities
        }
        return []
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
//        print("WebSocket binary message: \(data)")
        let msg = try! MessagePackDecoder().decode(ServerMessage.self, from: data)
//        print(msg)
        if !initializedScene {
            DispatchQueue.main.async {
                if let rendered = self.renderEntity(object: msg.object) {
                    self.tagEntity.addChild(rendered)
                }
                self.initializedScene = true
            }
        }
    }
    
    func detectedTags(tags: [Transform]) {
        if tags.isEmpty {
            return
        }
        
        tagEntity.transform = tags.first!
    }
    
    func renderEntity(object: Object) -> Entity? {
        let entity: Entity
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .black)
        material.roughness = 0.25
//                    material.blending = .transparent(opacity: 0.5)
        
        switch object.type {
        case 0: // anchor
            entity = Entity()
        case 1: // box
            entity = ModelEntity(
                mesh: MeshResource.generateBox(
                    width: Float(object.size[0]),
                    height: Float(object.size[1]),
                    depth: Float(object.size[2]),
                    cornerRadius: 0.005
                ),
                materials: [material]
            )
        case 2: // sphere
            entity = ModelEntity(
                mesh: MeshResource.generateSphere(radius: 0.5),
                materials: [material]
            )
            entity.transform.scale = simd_float3(
                Float(object.size[0]), Float(object.size[1]), Float(object.size[2])
            )
        case 5:
            entity = ModelEntity(
                mesh: MeshResource.generateText(
                    object.text,
                    extrusionDepth: 0.01,
                    font: .systemFont(ofSize: object.size[0])
                ),
                materials: [material]
            )
        case 6: // trigger box
            entity = TriggerVolume(shape: ShapeResource.generateBox(
                width: Float(object.size[0]),
                height: Float(object.size[1]),
                depth: Float(object.size[2])
            ))
        default:
            print("unknown object type: \(object.type)")
            return .none
        }
        entity.transform.translation = simd_float3(
            Float(object.pos[0]), Float(object.pos[1]), Float(object.pos[2])
        )
        
        if object.id != "" {
            entityIDs[entity] = object.id
        }
        
        for child in object.children ?? [] {
            if let childEntity = renderEntity(object: child) {
                entity.addChild(childEntity)
            }
        }
        
        return entity
    }
}

struct ServerMessage: Codable {
    var type: Int
    var object: Object
}

struct ClientMessage: Codable {
    var type: ClientMessage.MessageType
    var id: String
    
    enum MessageType: Int, Codable {
        case tap = 1
        case hover = 2
    }
}

struct Object: Codable {
    var type: Int
    var id: String
    var pos: [Float64]
    var size: [Float64]
    var text: String
    
    var children: [Object]?
}

#Preview {
    NightmareView()
}
