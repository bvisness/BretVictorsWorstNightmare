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
        mesh: MeshResource.generateSphere(radius: 0.0001),
        materials: [SimpleMaterial(color: .black, roughness: 1, isMetallic: true)]
    )
    lazy var tagCoverMaterial = {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white)
        mat.blending = .transparent(opacity: 0.75)
        return mat
    }()
    lazy var coneMesh = convertSCNGeometryToMeshResource(geometry: SCNCone(topRadius: 0, bottomRadius: 0.5, height: 1), name: "Cone")
    lazy var cylinderMesh = convertSCNGeometryToMeshResource(geometry: SCNCylinder(radius: 0.5, height: 1), name: "Cylinder")
    
    class Instance {
        let id: Int
        let program: String
        let root: Entity = Entity()
        var data: Data?
        var sceneHash: Int = 0
        
        init(id: Int, program: String) {
            self.id = id
            self.program = program
        }
    }
    struct PendingProgram {
        let program: String
        let data: Data?
    }
    var instances: [Int: Instance] = [:]
    var copiedProgram: PendingProgram?
    var copiedProgramPreview: Entity?
    var scannedProgram: String?
    var detectedTags = Set<Int>()
    
    var conn: WebSocketConnection!
    
    required init(frame frameRect: CGRect) {
        super.init(frame: frameRect)

        frameDelegate = FrameDelegate(view: self)
        frameDelegate.delegate = self
        session.delegate = frameDelegate
        renderOptions.insert(.disableMotionBlur)

        conn = WebSocketTaskConnection(url: URL(string: "wss://5fe6-174-20-239-98.ngrok-free.app/")!)
        conn.delegate = self
        conn.connect()
        
        cursor.transform.translation.z = -0.02
        cameraEntity.children.append(cursor)

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
        
        if copiedProgram != nil && copiedProgramPreview == nil {
            let preview = renderTag(program: copiedProgram!.program)
            preview.transform.translation = simd_float3(0.02, -0.01, -0.05)
            preview.transform.scale = simd_float3(0.2, 0.2, 0.2)
            preview.transform.rotation = simd_quatf(angle: .pi/2, axis: simd_float3(0, 0, 1))
            cameraEntity.addChild(preview)
            copiedProgramPreview = preview
        } else if copiedProgram == nil && copiedProgramPreview != nil {
            copiedProgramPreview!.removeFromParent()
            copiedProgramPreview = nil
        }
    }
    
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: self)

        let hitEntities = self.raycast(point: tapLocation)
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
        let tag = hitTag(hit: hitEntities.first)
        
        if sender.direction == .up {
            guard let tag = tag else {
                print("Swiped up, but not on tag")
                return
            }
            guard let paste = copiedProgram else {
                print("No program to paste")
                return
            }
            
            let message = ClientMessage(type: .instantiate, instantiate: InstantiateRequest(
                program: paste.program,
                data: paste.data,
                tag: tag
            ))
            let data = try! MessagePackEncoder().encode(message)
            conn.send(data: data)
            copiedProgram = .none
            print("Requested instantiation of program \(paste.program) for tag \(tag)")
        } else if sender.direction == .down {
            if let tag = tag, let instanceID = tagInstance(tag: tag) {
                // Swiping down copies this tag's program/data to the phone
                let instance = instances[instanceID]!
                copyProgram(PendingProgram(program: instance.program, data: instance.data))
                print("Copied instance of program \(instance.program)")
            } else if let scanned = scannedProgram {
                copyProgram(PendingProgram(program: scanned, data: nil))
                print("Copied fresh instance of program \(scanned)")
            } else {
                print("Nothing to swipe down on")
            }
        }
    }
    
    func hitTag(hit: Entity?) -> Int? {
        guard let hit = hit else { return nil }
        if hit.name.hasPrefix("__tag") {
            return Int(hit.name.substring(from: "__tag".count))!
        }
        return nil
    }
    
    func copyProgram(_ p: PendingProgram) {
        copiedProgram = p
        copiedProgramPreview?.removeFromParent()
        copiedProgramPreview = nil
    }
    
    func tagInstance(tag: Int) -> Int? {
        for instance in instances.values {
            if isChildOf(entity: instance.root, parent: tagEntities[tag]) {
                return instance.id
            }
        }
        return .none
    }
    
    func raycast(point: CGPoint) -> [Entity] {
        if let ray = self.ray(through: point) {
            let hits = scene.raycast(origin: ray.origin, direction: ray.direction)
            var hitEntities: [Entity] = []
            for hit in hits {
                hitEntities.append(hit.entity)
            }
            return hitEntities
        }
        return []
    }
    
    func raycastCenter() -> [Entity] {
        return raycast(point: CGPoint(x: bounds.midX, y: bounds.midY))
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
                    instance.root.children.removeAll()

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

                if let tag = update.tag, detectedTags.contains(tag) {
                    let tagEntity = tagEntities[tag]
                    if !isChildOf(entity: instance.root, parent: tagEntity) {
                        instance.root.removeFromParent()
                        tagEntity.addChild(instance.root)
                    }
                } else { // Not associated with a tag or haven't seen the tag; remove from scene
                    instance.root.removeFromParent()
                }
            }
        default:
            print("Ignoring server message of type \(msg.type)")
        }
    }
    
    func detectedTags(tags: [TagDetection]) {
        for tag in tags {
            detectedTags.insert(tag.id)
            if tag.id > tagEntities.count {
                break
            }
            tagEntities[tag.id].transform = tag.pose
        }
    }
    
    func detectedQRCodes(barcodes: [VNBarcodeObservation]) {
        if barcodes.isEmpty {
            scannedProgram = nil
            return
        }
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var centermost = barcodes.first!
        for barcode in barcodes[1...] {
            let oldCenter = CGPoint(x: centermost.boundingBox.midX, y: centermost.boundingBox.midY)
            let newCenter = CGPoint(x: barcode.boundingBox.midX, y: barcode.boundingBox.midY)
            if (newCenter - center).length < (oldCenter - center).length {
                centermost = barcode
            }
        }
        
        guard let payload = centermost.payloadStringValue else {
            print("Non-string QR code.")
            return
        }
        if !payload.hasPrefix("nightmare://") {
            print("Non-nightmare QR code.")
            return
        }
        scannedProgram = payload.substring(from: "nightmare://".count)
        print("Scanned program \(scannedProgram!)")
    }
    
    func renderEntity(object: Object) -> Entity? {
        let entity: Entity
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: text2color(object.color))
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
        case 3: // cylinder
            entity = Entity()
            let cylinderEntity = ModelEntity(mesh: cylinderMesh, materials: [material])
            cylinderEntity.transform.rotation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_float3(0, 0, 1))
            entity.addChild(cylinderEntity)
            entity.transform.scale = simd_float3(
                Float(object.size[0]), Float(object.size[1]), Float(object.size[2])
            )
        case 4: // cone
            entity = Entity()
            let cylinderEntity = ModelEntity(mesh: coneMesh, materials: [material])
            cylinderEntity.transform.rotation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_float3(0, 0, 1))
            entity.addChild(cylinderEntity)
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
        entity.transform.rotation = simd_quatf(ix: Float(object.rot[0]), iy: Float(object.rot[1]), iz: Float(object.rot[2]), r: Float(object.rot[3]))
        
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
    
    func text2color(_ str: String) -> UIColor {
        return switch str {
        case "black": .black
        case "darkGray": .darkGray
        case "lightGray": .lightGray
        case "white": .white
        case "gray": .gray
        case "red": .red
        case "green": .green
        case "blue": .blue
        case "cyan": .cyan
        case "yellow": .yellow
        case "magenta": .magenta
        case "orange": .orange
        case "purple": .purple
        case "brown": .brown
        default: .black
        }
    }
    
    func convertSCNGeometryToMeshResource(geometry: SCNGeometry, name: String) -> MeshResource {
        let source = geometry.sources(for: .vertex).first!
        let indices = geometry.elements.first!.data

        let vertexCount = source.vectorCount
        let stride = source.dataStride
        let offset = source.dataOffset
        let data = source.data

        // Extract vertex positions
        var vertices: [SIMD3<Float>] = []
        for i in 0..<vertexCount {
            let start = data.startIndex + (i * stride) + offset
            let end = start + 12
            let vertexData = data[start..<end]
            let vertex = vertexData.withUnsafeBytes { buffer in
                return SIMD3<Float>(buffer.load(fromByteOffset: 0, as: Float.self),
                                    buffer.load(fromByteOffset: 4, as: Float.self),
                                    buffer.load(fromByteOffset: 8, as: Float.self))
            }
            vertices.append(vertex)
        }

        // Extract indices
        assert(geometry.elements.first!.primitiveType == .triangles)
        let indexCount = geometry.elements.first!.primitiveCount * 3  // Assuming triangles
        let indexSize = geometry.elements.first!.bytesPerIndex // Size of each index (2 for UInt16, 4 for UInt32)
        var indicesArray: [UInt32] = []
        for i in 0..<indexCount {
            indices.withUnsafeBytes { buffer in
                if indexSize == 2 {
                    // 16-bit indices (UInt16)
                    let index: UInt16 = buffer.load(fromByteOffset: i * indexSize, as: UInt16.self)
                    indicesArray.append(UInt32(index))
                } else if indexSize == 4 {
                    // 32-bit indices (UInt32)
                    let index: UInt32 = buffer.load(fromByteOffset: i * indexSize, as: UInt32.self)
                    indicesArray.append(index)
                } else {
                    fatalError("Unsupported index size")
                }
            }
        }

        // Create RealityKit MeshResource from vertices and indices
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles(indicesArray)
        
        return try! MeshResource.generate(from: [descriptor])
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
    var data: Data?
    var tag: Int
}

struct Object: Codable {
    var type: Int
    var id: String
    var pos: [Float64]
    var rot: [Float64]
    var size: [Float64]
    var color: String
    var text: String
    var textsize: Float64
    var textalign: String
    var textwrap: Bool
    
    var children: [Object]?
}

#Preview {
    NightmareView()
}
