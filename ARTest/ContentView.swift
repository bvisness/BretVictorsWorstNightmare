//
//  ContentView.swift
//  ARTest
//
//  Created by Ben Visness on 8/29/24.
//

import SwiftUI
import ARKit
import RealityKit

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
let cube = ModelEntity(
//    mesh: MeshResource.generateBox(size: 0.05, cornerRadius: 0.005),
    mesh: MeshResource.generateText(
        "Handmade",
        extrusionDepth: 0.001,
        font: .systemFont(ofSize: 0.01),
        alignment: CTTextAlignment.center
    ),
    materials: [SimpleMaterial(color: .systemPurple, roughness: 0.25, isMetallic: false)]
)

let cameraAnchor = AnchorEntity(world: simd_float3(0, 0, 0))
let cursor = ModelEntity(
    mesh: MeshResource.generateSphere(radius: 0.005),
    materials: [SimpleMaterial(color: .systemBlue, roughness: 0.25, isMetallic: false)]
)

struct ARViewContainer: UIViewRepresentable, WebSocketConnectionDelegate {
    
    func makeUIView(context: Context) -> ARView {
        arView.session.delegate = frameDelegate
//        arView.renderOptions.insert(.disableMotionBlur)

//        cube.transform.translation.z = 0.025
        tagAnchor.children.append(cube)
        
        cursor.transform.translation.z = -0.15
        cameraAnchor.children.append(cursor)

        arView.scene.anchors.append(tagAnchor)
        arView.scene.anchors.append(cameraAnchor)
        
        conn = WebSocketTaskConnection(url: URL(string: "ws://192.168.0.32:8080/")!)
        conn.delegate = self
        conn.connect()

        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
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
    }
}

#Preview {
    ContentView()
}
