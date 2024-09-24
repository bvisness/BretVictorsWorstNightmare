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

let arView = ARView(frame: .zero)
var frameDelegate = FrameDelegate(view: arView)

//let cubeAnchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
let cubeAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
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

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        arView.session.delegate = frameDelegate
//        arView.renderOptions.insert(.disableMotionBlur)

//        cube.transform.translation.z = 0.025
        cubeAnchor.children.append(cube)
        
        cursor.transform.translation.z = -0.15
        cameraAnchor.children.append(cursor)

        arView.scene.anchors.append(cubeAnchor)
        arView.scene.anchors.append(cameraAnchor)

        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

#Preview {
    ContentView()
}
