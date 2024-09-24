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

//let cubeAnchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
let cubeAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
let cube = ModelEntity(
    mesh: MeshResource.generateBox(size: 0.05, cornerRadius: 0.005),
    materials: [SimpleMaterial(color: .systemGreen, roughness: 0.05, isMetallic: true)]
)

let arView = ARView(frame: .zero)
var frameDelegate = FrameDelegate(view: arView)

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        arView.session.delegate = frameDelegate

        cube.transform.translation.z = -0.025
        cubeAnchor.children.append(cube)

        // Add the horizontal plane anchor to the scene
        arView.scene.anchors.append(cubeAnchor)

        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

#Preview {
    ContentView()
}
