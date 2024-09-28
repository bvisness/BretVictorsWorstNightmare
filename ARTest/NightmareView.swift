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
    let tagEntities: [Entity] = [Entity(), Entity(), Entity(), Entity(), Entity(), Entity(), Entity(), Entity()]
    let cameraEntity = Entity()
    let cursor = ModelEntity(
        mesh: MeshResource.generateSphere(radius: 0.005),
        materials: [SimpleMaterial(color: .systemBlue, roughness: 0.25, isMetallic: false)]
    )
    lazy var tagCoverMaterial = {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white)
        mat.blending = .transparent(opacity: 0.75)
        return mat
    }()
    
    class Instance {
        let id: Int
        let program: String
        let root: Entity = Entity()
        var sceneHash: Int = 0
        
        init(id: Int, program: String) {
            self.id = id
            self.program = program
        }
    }
    var instances: [Int: Instance] = [:]
    
    var conn: WebSocketConnection!
    
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
        for tagEntity in tagEntities {
            origin.addChild(tagEntity)
        }
        origin.addChild(cameraEntity)
        
        scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.onUpdate(updateEvent: event)
        }
        .store(in: &cancellables)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        self.addGestureRecognizer(tapGesture)
        
        let swipeUpGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeUpGesture.direction = .up
        self.addGestureRecognizer(swipeUpGesture)

        let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeDownGesture.direction = .down
        self.addGestureRecognizer(swipeDownGesture)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func onUpdate(updateEvent: SceneEvents.Update) {
        let deltaTime = updateEvent.deltaTime
    }
    
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: self)

        let hitEntities = self.raycastCenter()
        guard let hit = hitEntities.first else {
            return
        }
        guard let instance = entity2instance(hit) else {
            return
        }
        
        if !hit.name.isEmpty {
            let message = ClientMessage(type: .tap, instance: instance.id, entityid: hit.name)
            let data = try! MessagePackEncoder().encode(message)
            conn.send(data: data)
        }
    }
    
    @objc private func handleSwipe(_ sender: UISwipeGestureRecognizer) {
        if sender.direction == .up {
            print("Swipe-Up detected")
            // Handle swipe-up action
        } else if sender.direction == .down {
            print("Swipe-Down detected")
            // Handle swipe-down action
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
    
    func entity2instance(_ entity: Entity) -> Instance? {
        for instance in instances.values {
            if isChildOf(entity: entity, parent: instance.root) {
                return instance
            }
        }
        return .none
    }
    
    func isChildOf(entity: Entity, parent: Entity) -> Bool {
        var test: Entity? = entity
        while let e = test {
            if test == parent {
                return true
            }
            test = e.parent
        }
        return false
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
        
        switch msg.type {
        case 1: // scenes
            guard let instance = instances[msg.scene.instance] else {
                print("ERROR: Couldn't find instance with id \(msg.scene.instance); this should not happen because the server should have already informed us of all instances before sending us rendered scenes.")
                break
            }
            
            let hash = data.hashValue
            defer { instance.sceneHash = hash }
            
            if hash != instance.sceneHash {
                DispatchQueue.main.async {
                    // Reset the scene
                    for child in instance.root.children {
                        child.removeFromParent()
                    }
                    
                    // Render the scene
                    if let rendered = self.renderEntity(object: msg.scene.scene) {
                        instance.root.addChild(rendered)
                    }
                    
                    let (tagVisual, tagTrigger) = self.renderTag(program: instance.program)
                    instance.root.addChild(tagVisual)
                    instance.root.addChild(tagTrigger)
                }
            }
        case 2: // instances
            guard let instanceUpdates = msg.instances else { break }
            for update in instanceUpdates {
                let instance: Instance
                if let i = instances[update.instance] {
                    instance = i
                } else {
                    instance = Instance(id: update.instance, program: update.program)
                    instances[instance.id] = instance
                }

                if let tag = update.tag {
                    let tagEntity = tagEntities[tag]
                    if !isChildOf(entity: instance.root, parent: tagEntity) {
                        instance.root.removeFromParent()
                        tagEntity.addChild(instance.root)
                    }
                } else { // Not associated with a tag; remove from scene
                    instance.root.removeFromParent()
                }
            }
        default:
            print("Ignoring server message of type \(msg.type)")
        }
    }
    
    func detectedTags(tags: [TagDetection]) {
        for tag in tags {
            if tag.id > tagEntities.count {
                break
            }
            tagEntities[tag.id].transform = tag.pose
        }
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
            entity.name = object.id
        }
        
        for child in object.children ?? [] {
            if let childEntity = renderEntity(object: child) {
                entity.addChild(childEntity)
            }
        }
        
        return entity
    }
    
    func renderTag(program: String) -> (Entity, Entity) {
        let tagVisual = Entity()
        
        let tagCover = ModelEntity(
            mesh: .generateBox(
                size: simd_float3(Float(FrameDelegate.tagOuterSize), Float(FrameDelegate.tagOuterSize), 0.005),
                cornerRadius: 0.0002
            ),
            materials: [tagCoverMaterial]
        )
        tagCover.transform.translation.z = 0.0025
        let tagProgram = renderText(
            program,
            materials: [SimpleMaterial(color: .black, roughness: 0.25, isMetallic: false)],
            font: .systemFont(ofSize: 0.01),
            frame: CGPoint(x: FrameDelegate.tagOuterSize, y: FrameDelegate.tagOuterSize),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        tagProgram.transform.translation.z = 0.005
        tagVisual.addChild(tagCover)
        tagVisual.addChild(tagProgram)

        let tagTrigger = TriggerVolume(
            shape: .generateBox(size: simd_float3(0.08, 0.08, 0.01))
        )
        
        return (tagVisual, tagTrigger)
    }
    
    func renderText(
        _ str: String,
        materials: [any RealityFoundation.Material],
        font: MeshResource.Font = .systemFont(ofSize: MeshResource.Font.systemFontSize),
        frame: CGPoint = CGPoint.zero,
        alignment: CTTextAlignment = .left,
        lineBreakMode: CTLineBreakMode = .byTruncatingTail
    ) -> Entity {
        let mesh = MeshResource.generateText(
            str,
            extrusionDepth: Float(font.pointSize) * 0.1,
            font: font,
            containerFrame: CGRect(x: 0, y: 0, width: frame.x, height: frame.y),
            alignment: alignment,
            lineBreakMode: lineBreakMode
        )
        let text = ModelEntity(mesh: mesh, materials: materials)
        if alignment == .center {
            let centerer = Entity()
            centerer.addChild(text)
            text.transform.translation = simd_float3(
                -mesh.bounds.center.x,
                 -mesh.bounds.center.y,
                 0
            )
            return centerer
        }
        return text
    }
}

struct ServerMessage: Codable {
    var type: Int
    var scene: SceneUpdate
    var instances: [InstanceUpdate]?
}

struct SceneUpdate: Codable {
    var instance: Int
    var scene: Object
}

struct InstanceUpdate: Codable {
    var instance: Int
    var program: String
    var tag: Int?
}

struct ClientMessage: Codable {
    var type: ClientMessage.MessageType
    var instance: Int
    var entityid: String
    
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
