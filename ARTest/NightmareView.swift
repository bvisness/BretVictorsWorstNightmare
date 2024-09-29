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
    var tagEntities: [Entity] = []
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
        var data: Data = Data()
        var sceneHash: Int = 0
        
        init(id: Int, program: String) {
            self.id = id
            self.program = program
        }
    }
    var instances: [Int: Instance] = [:]
    var copiedInstance: Instance?
    var copiedInstancePreview: Entity?
    
    var conn: WebSocketConnection!
    
    required init(frame frameRect: CGRect) {
        super.init(frame: frameRect)

        frameDelegate = FrameDelegate(view: self)
        frameDelegate.delegate = self
        session.delegate = frameDelegate
        renderOptions.insert(.disableMotionBlur)

        conn = WebSocketTaskConnection(url: URL(string: "ws://192.168.1.6:8080/")!)
        conn.delegate = self
        conn.connect()
        
        cursor.transform.translation.z = -0.15
//        cameraEntity.children.append(cursor)

        scene.anchors.append(origin)
        for tagEntity in tagEntities {
            origin.addChild(tagEntity)
        }
        origin.addChild(cameraEntity)
        
        for i in 0..<16 {
            let tagEntity = Entity()
            let tagTrigger = TriggerVolume(
                shape: .generateBox(size: simd_float3(0.08, 0.08, 0.03))
            )
            tagTrigger.name = "__tag\(i)"
            tagEntity.addChild(tagTrigger)
            origin.addChild(tagEntity)
            tagEntities.append(tagEntity)
        }
        
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
        if let frame = session.currentFrame {
            cameraEntity.transform.matrix = frame.camera.transform
        }
        
        if copiedInstance != nil && copiedInstancePreview == nil {
            let preview = renderTag(program: copiedInstance!.program)
            preview.transform.translation = simd_float3(0.02, -0.01, -0.05)
            preview.transform.scale = simd_float3(0.2, 0.2, 0.2)
            preview.transform.rotation = simd_quatf(angle: .pi/2, axis: simd_float3(0, 0, 1))
            cameraEntity.addChild(preview)
            copiedInstancePreview = preview
        } else if copiedInstance == nil && copiedInstancePreview != nil {
            copiedInstancePreview!.removeFromParent()
            copiedInstancePreview = nil
        }
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
        let hitEntities = self.raycastCenter()
        guard let hit = hitEntities.first else {
            return
        }
        let tag: Int
        if hit.name.hasPrefix("__tag") {
            tag = Int(hit.name.substring(from: "__tag".count))!
        } else {
            print("Swiped on non-tag object \(hit)")
            return
        }
        
        if sender.direction == .up {
            if let paste = copiedInstance {
                let message = ClientMessage(type: .instantiate, instantiate: InstantiateRequest(
                    program: paste.program,
                    data: paste.data,
                    tag: tag
                ))
                let data = try! MessagePackEncoder().encode(message)
                conn.send(data: data)
                copiedInstance = .none
                print("Requested instantiation of program \(paste.program)")
            }
        } else if sender.direction == .down {
            if let instanceID = tagInstance(tag: tag) {
                // Swiping down copies this tag's instance to the phone
                let instance = instances[instanceID]!
                copiedInstance = Instance(id: instances.count, program: instance.program)
                copiedInstance!.data = instance.data
                print("Copied instance of program \(instance.program)")
            }
        }
    }
    
    func tagInstance(tag: Int) -> Int? {
        for instance in instances.values {
            if isChildOf(entity: instance.root, parent: tagEntities[tag]) {
                return instance.id
            }
        }
        return .none
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
                    
                    let tagVisual = self.renderTag(program: instance.program)
                    instance.root.addChild(tagVisual)
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
                instance.data = update.data

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
            let alignment: CTTextAlignment = switch object.textalign {
            case "center": .center
            case "right": .right
            default: .left
            }
            let lineBreakMode: CTLineBreakMode = object.textwrap ? .byWordWrapping : .byTruncatingTail
            
            // Hack: You're supposed to specify text size with two elements instead of three.
            // That means that the third component will be zero if you provide it. But if you
            // leave out the size then it defaults to (1, 1, 1), and if you leave out the size,
            // you should have no explicit text frame. So if the third component is 1 we can use
            // a frame of zero, and otherwise we can use a real frame. This is totally incoherent
            // but I have no more time left.
            let frame = object.size[2] == 1 ? CGPoint.zero : CGPoint(x: object.size[0], y: object.size[1])
            
            entity = renderText(
                object.text,
                materials: [material],
                font: .systemFont(ofSize: object.textsize),
                frame: frame,
                alignment: alignment,
                lineBreakMode: lineBreakMode
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
    
    func renderTag(program: String) -> Entity {
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
        
        return tagVisual
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
    var data: Data
    var tag: Int?
}

struct ClientMessage: Codable {
    var type: ClientMessage.MessageType
    var instance: Int?
    var entityid: String?
    var instantiate: InstantiateRequest?
    
    enum MessageType: Int, Codable {
        case tap = 1
        case hover = 2
        case instantiate = 3
    }
}

struct InstantiateRequest: Codable {
    var program: String
    var data: Data
    var tag: Int
}

struct Object: Codable {
    var type: Int
    var id: String
    var pos: [Float64]
    var size: [Float64]
    var text: String
    var textsize: Float64
    var textalign: String
    var textwrap: Bool
    
    var children: [Object]?
}

#Preview {
    NightmareView()
}
