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

    let origin = AnchorEntity(world: simd_float3(0, 0, 0))
    let tagEntity = Entity()
    let cameraEntity = Entity()
    let cursor = ModelEntity(
        mesh: MeshResource.generateSphere(radius: 0.005),
        materials: [SimpleMaterial(color: .systemBlue, roughness: 0.25, isMetallic: false)]
    )

    var conn: WebSocketConnection!
    var initializedScene = false
    
    required init(frame frameRect: CGRect) {
        super.init(frame: frameRect)

        frameDelegate = FrameDelegate(view: self)
        frameDelegate.delegate = self
        session.delegate = frameDelegate

        conn = WebSocketTaskConnection(url: URL(string: "wss://d1dc-96-72-40-158.ngrok-free.app/")!)
        conn.delegate = self
        conn.connect()
        
        cursor.transform.translation.z = -0.15
//        cameraAnchor.children.append(cursor)

        scene.anchors.append(origin)
        origin.addChild(tagEntity)
        origin.addChild(cameraEntity)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        default:
            print("unknown object type: \(object.type)")
            return .none
        }
        entity.transform.translation = simd_float3(
            Float(object.pos[0]), Float(object.pos[1]), Float(object.pos[2])
        )
        
        for child in object.children ?? [] {
            if let childEntity = renderEntity(object: child) {
                entity.addChild(childEntity)
            }
        }
        
        return entity
    }
}

struct Message: Codable {
    var type: Int
    var object: Object
}

struct Object: Codable {
    var type: Int
    var pos: [Float64]
    var size: [Float64]
    var text: String
    
    var children: [Object]?
}

#Preview {
    NightmareView()
}
