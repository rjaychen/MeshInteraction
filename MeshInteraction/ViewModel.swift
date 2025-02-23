import ARKit
import SwiftUI
import Accelerate
import RealityKit
import RealityKitContent

@Observable
class ViewModel {

    var appState: AppState? = nil

    let handTracking = HandTrackingProvider() /// Used to track spatial taps
    let sceneReconstruction = SceneReconstructionProvider() /// Used to access Scene MeshAnchors
    let worldTracking = WorldTrackingProvider() /// Used to receive camera transform
    let imageTracking = ImageTrackingProvider(referenceImages: ReferenceImage.loadReferenceImages(inGroupNamed: "Target"))
    let contentEntity = Entity()

    private var meshEntities = [UUID: ModelEntity]()
    private let fingerEntities: [HandAnchor.Chirality: ModelEntity] = [
        .left: .createFingertip(),
        .right: .createFingertip()
    ]
    
    /// Variables I added
//    private var boundingBox: Entity? = nil
//    private var topLeftBackVert: SIMD3<Float> = [0, 0, 0]
//    private var bottomRightFrontVert: SIMD3<Float> = [0, 0, 0]
    /// Bounding Radius Variables
    private var location3D: SIMD3<Float> = [0, 0, 0]
    private var meshAnchors = [UUID: MeshAnchor]()
    private var newMeshes = [ModelEntity]()
    private var audioFilePath = "/applepay.mp3"
    /// Shader Graph materials
    private var projectiveMaterial: ShaderGraphMaterial? = nil
    private var matrixMaterial: ShaderGraphMaterial? = nil
    private var blurMaterial: ShaderGraphMaterial? = nil
    private var tableMaterial: ShaderGraphMaterial? = nil
    /// Image Tracking Anchors
    private var imageAnchors: [UUID: Entity] = [:]
    /// Data Collection Variables
    private var timer = Timer()
    private var dataArray: [Dictionary<String, AnyObject>] = Array()
    
    func loadMaterial() async {
        projectiveMaterial = try! await ShaderGraphMaterial(named: "/Root/ProjectMaterial", from: "ProjectMaterial", in: realityKitContentBundle)
        if projectiveMaterial != nil {
            try! await projectiveMaterial?.setParameter(name: "uiImage", value: .textureResource(TextureResource(named: "checkerboard")))
            print("PTM loaded")
        } else { print("PTM loading unsuccessful") }
        blurMaterial = try! await ShaderGraphMaterial(named: "/Root/BlurMaterial", from: "ProjectMaterial", in: realityKitContentBundle)
        matrixMaterial = try! await ShaderGraphMaterial(named: "/Root/Matrix", from: "MatrixMaterial", in: realityKitContentBundle)
        if matrixMaterial != nil { print("Matrix loaded") } else { print("Matrix failed to load.") }
        tableMaterial = try! await ShaderGraphMaterial(named: "/Root/TableMaterial", from: "TableMaterial", in: realityKitContentBundle)
    }
    
    func setMaterialTexture(uiImage: UIImage) async {
        try! await projectiveMaterial?.setParameter(name: "uiImage", value: .textureResource(TextureResource(image: uiImage.cgImage!, options: .init(semantic: .color))))
    }
    
    func setupContentEntity() -> Entity {
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
        return contentEntity
    }

    var dataProvidersAreSupported: Bool {
        HandTrackingProvider.isSupported && SceneReconstructionProvider.isSupported && ImageTrackingProvider.isSupported && WorldTrackingProvider.isSupported
    }

    var isReadyToRun: Bool {
        handTracking.state == .initialized && 
        sceneReconstruction.state == .initialized &&
        worldTracking.state == .initialized &&
        imageTracking.state == .initialized
    }

    // MARK: - ARKit and Anchor handlings

    @MainActor
    func runARKitSession() async {
        do {
            try await appState!.arkitSession.run([handTracking, sceneReconstruction, worldTracking, imageTracking])
        } catch {
            return
        }
    }

    @MainActor
    /// Updates hand information from ARKit.
    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor

            guard
                handAnchor.isTracked,
                let indexFingerTipJoint = handAnchor.handSkeleton?.joint(.indexFingerTip),
                indexFingerTipJoint.isTracked else { continue }
            
            let originFromIndexFingerTip = handAnchor.originFromAnchorTransform * indexFingerTipJoint.anchorFromJointTransform
            fingerEntities[handAnchor.chirality]?.setTransformMatrix(originFromIndexFingerTip, relativeTo: nil)
        }
    }
    
    @MainActor
    func processReconstructionUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            let meshAnchor = update.anchor

            guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { continue }
            switch update.event {
            case .added:
                print("added \(meshAnchor.id)")
                meshAnchors[meshAnchor.id] = meshAnchor
                let entity = appState!.visualizeSceneMeshes ? try! await generateModelEntity(geometry: meshAnchor.geometry) : ModelEntity()
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision = try? await CollisionComponent(shapes: [ShapeResource.generateStaticMesh(from: meshAnchor)], isStatic: true)
                entity.components.set(InputTargetComponent())
                entity.physicsBody = PhysicsBodyComponent(mode: .static)
                meshEntities[meshAnchor.id] = entity
                contentEntity.addChild(entity)
            case .updated:
                guard let entity = meshEntities[meshAnchor.id] else { continue }
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision?.shapes = [shape]
                meshAnchors[meshAnchor.id] = meshAnchor
            case .removed:
                meshEntities[meshAnchor.id]?.removeFromParent()
                meshEntities.removeValue(forKey: meshAnchor.id)
                meshAnchors.removeValue(forKey: meshAnchor.id)
            }
        }
    }
    
    @MainActor
    func processImageTrackingUpdates() async {
        //print("[\(type(of: self))] [\(#function)] called")
        for await update in imageTracking.anchorUpdates {
            //print("[\(type(of: self))] [\(#function)] anchorUpdates")
            updateImageAnchor(update.anchor)
        }
    }
    
    @MainActor
    func generateModelEntity(geometry: MeshAnchor.Geometry) async throws -> ModelEntity {
        // Generate MeshResource from MeshAnchor Geometry
        var desc = MeshDescriptor()
        let posValues = geometry.vertices.asSIMD3(ofType: Float.self)
        desc.positions = .init(posValues)
        let normalValues = geometry.normals.asSIMD3(ofType: Float.self)
        desc.normals = .init(normalValues)
        do {
            desc.primitives = .polygons(
                (0..<geometry.faces.count).map { _ in UInt8(3) },
                (0..<geometry.faces.count * 3).map {
                    geometry.faces.buffer.contents()
                        .advanced(by: $0 * geometry.faces.bytesPerIndex)
                        .assumingMemoryBound(to: UInt32.self).pointee
                }
            )
        }
        let meshResource = try MeshResource.generate(from: [desc])
        // Customize Model Entity
        //var material = SimpleMaterial(color: .green.withAlphaComponent(0.8), isMetallic: false)
        //material.triangleFillMode = .lines
        if appState!.useMatrixShader {
            let modelEntity = ModelEntity(mesh: meshResource, materials: [matrixMaterial!])
            return modelEntity
        }
        else if appState!.useBlurShader {
            let modelEntity = ModelEntity(mesh: meshResource, materials: [blurMaterial!])
            return modelEntity
        }
        else {
            var material = SimpleMaterial(color: .green.withAlphaComponent(0.8), isMetallic: false)
            material.triangleFillMode = .lines
            let modelEntity = ModelEntity(mesh: meshResource, materials: [material])
            return modelEntity
        }
    }
    
    func addCube(tapLocation: SIMD3<Float>) {
        let placementLocation = tapLocation + SIMD3<Float>(0, 0.2, 0)

        let entity = ModelEntity(
            mesh: .generateBox(size: 0.1, cornerRadius: 0.0),
            materials: [SimpleMaterial(color: .systemPink, isMetallic: false)],
            collisionShape: .generateBox(size: SIMD3<Float>(repeating: 0.1)),
            mass: 1.0)

        entity.setPosition(placementLocation, relativeTo: nil)
        entity.components.set(InputTargetComponent(allowedInputTypes: .indirect))

        let material = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.0)
        entity.components.set(
            PhysicsBodyComponent(
                shapes: entity.collision!.shapes,
                mass: 1.0,
                material: material,
                mode: .dynamic)
        )
        contentEntity.addChild(entity)
    }
    
    /// Creates a mesh object from the mesh anchors based on a bounding radius provided.
    @MainActor
    func createBoundingEntity(location: SIMD3<Float>, useBlur: Bool = false){
        location3D = location
        newMeshes.forEach {mesh in mesh.removeFromParent()}
        for (_, anchor) in meshAnchors {
            let geometry = anchor.geometry
            let anchorMatrix = anchor.originFromAnchorTransform
            var triangleList: [Int] = []
            let vertices: [SIMD3<Float>] = geometry.vertices.asSIMD3(ofType: Float.self).map {
                anchorToWorld(anchorMatrix: anchorMatrix, pos: $0)
            }
            let normals = geometry.normals.asSIMD3(ofType: Float.self)
            let tIndices = (0..<geometry.faces.count * 3).map {
                geometry.faces.buffer.contents()
                    .advanced(by: $0 * geometry.faces.bytesPerIndex)
                    .assumingMemoryBound(to: UInt32.self).pointee
            }
            for i in stride(from: 0, to: tIndices.count, by: 3) {
                let indexA = Int(tIndices[i]), indexB = Int(tIndices[i+1]), indexC = Int(tIndices[i+2])
                let pointA = vertices[indexA]
                let pointB = vertices[indexB]
                let pointC = vertices[indexC]
                let center = (pointA + pointB + pointC) / 3
                let containsCenter = distance(center, location3D) < appState!.boundingRadius
                //let containsA = distance(pointA, location3D) < 0.25, containsB = distance(pointB, location3D) < 0.25, containsC = distance(pointC, location3D) < 0.25
                if containsCenter {
                    triangleList.append(indexA)
                    triangleList.append(indexB)
                    triangleList.append(indexC)
                }
            }
            if !triangleList.isEmpty {
                var newVertices: [SIMD3<Float>] = []
                var newNormals: [SIMD3<Float>] = []
                var newTriangles: [UInt32] = []
                for i in 0..<triangleList.count {
                    newVertices.append(vertices[triangleList[i]])
                    newNormals.append(normals[triangleList[i]])
                    newTriangles.append(UInt32(i))
                }
                var meshDescriptor = MeshDescriptor()
                meshDescriptor.positions = .init(newVertices)
                meshDescriptor.primitives = .triangles(newTriangles)
                meshDescriptor.normals = .init(newNormals)
                if meshDescriptor.positions.count > 0 {
                    let meshResource = try! MeshResource.generate(from: [meshDescriptor])
                    //var mat = SimpleMaterial(color: .magenta, isMetallic: false)
                    //mat.triangleFillMode = .lines
                    //let newMeshEntity = ModelEntity(mesh: meshResource, materials: [mat])
                    let newMeshEntity = ModelEntity(mesh: meshResource, materials: [projectiveMaterial!])
                    // MARK: We need to calculate the matrices at runtime and pass them as parameters. This should solve any existing artifact problems. Consider using a LowLevelTexture with a GPU compute kernel. Also look into Sparse Voxel Octrees.
                    Task {
                        let cameraMatrix = await getDeviceTransform()
                        let viewMatrix = cameraMatrix.inverse
                        //print(viewMatrix.columns.3.x, viewMatrix.columns.3.y, viewMatrix.columns.3.z)
                        try! projectiveMaterial?.setParameter(name: "viewMatrix", value: .float4x4(viewMatrix))
                        let resource = try! AudioFileResource.load(named: audioFilePath)
                        newMeshEntity.playAudio(resource)
                        newMeshes.append(newMeshEntity)
                        contentEntity.addChild(newMeshEntity)
                    }
                }
            }
        }
    }

    func loadTextureAndApplyToMaterial(frame: UIImage?) -> PhysicallyBasedMaterial? {
        guard let image = frame else {
            print("Failed to load image")
            return nil
        }
        guard let cgImage = image.cgImage else {
            print("Failed to get CGImage")
            return nil
        }
        let textureResource = try? TextureResource.init(image: cgImage, options: .init(semantic: .color))
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(texture: PhysicallyBasedMaterial.Texture(textureResource!))
        material.blending = .transparent(opacity: .init(floatLiteral:0.8))
        return material
    }
    
    @MainActor
    func createPortal(location: SIMD3<Float>, frame: UIImage) {
        let depthToPlace = abs(location.z) + 1.0
        let scale = 0.9 * depthToPlace
        
        let world = Entity()
        world.components.set(WorldComponent())
        
        let target = AnchoringComponent.Target.head
        let anchoringComponent = AnchoringComponent(target, trackingMode: .once)
        let head = Entity()
        head.components.set(anchoringComponent)
        world.addChild(head)

        if let material = loadTextureAndApplyToMaterial(frame: frame) {
            let plane = ModelEntity(mesh: MeshResource.generatePlane(width: 1.92 * scale, height: 1.08 * scale), materials: [material])
            plane.transform.translation = [0, 0, -depthToPlace]
            head.addChild(plane)
        }
        
        let portal = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.5), materials: [PortalMaterial()])
        let portalComponent = PortalComponent(target: world)
        portal.components.set(portalComponent)
        portal.transform.translation = location
        
        contentEntity.addChild(world)
        contentEntity.addChild(portal)
    }
    
    @MainActor
    func testImage(location: SIMD3<Float>, frame: UIImage) {
        let depthToPlace = abs(location.z) + 1.0
        let scale = 0.9 * depthToPlace
        
        let target = AnchoringComponent.Target.head
        let anchoringComponent = AnchoringComponent(target, trackingMode: .predicted)
        let head = Entity()
        head.components.set(anchoringComponent)
        contentEntity.addChild(head)

        if let material = loadTextureAndApplyToMaterial(frame: frame) {
            let plane = ModelEntity(mesh: MeshResource.generatePlane(width: 1.92 * scale, height: 1.08 * scale), materials: [material])
            plane.transform.translation = [0, 0, -depthToPlace]
            head.addChild(plane)
        }
    }
    
    
    @MainActor 
    private func updateImageAnchor(_ anchor: ImageAnchor) {
        /// Create the anchor entity
        if imageAnchors[anchor.id] == nil {
            let w = Float(anchor.referenceImage.physicalSize.width) * anchor.estimatedScaleFactor
            let h = Float(anchor.referenceImage.physicalSize.height) * anchor.estimatedScaleFactor
            let entity = ModelEntity(mesh: MeshResource.generateBox(width: w+0.01, height: h+0.01, depth: 0.001))
            entity.model?.materials = [tableMaterial!]
            imageAnchors[anchor.id] = entity
            contentEntity.addChild(entity)
        }
        
        
        /// What to do once the anchor has been found
        if anchor.isTracked {
            imageAnchors[anchor.id]?.transform = Transform(matrix: anchor.originFromAnchorTransform)
            imageAnchors[anchor.id]?.transform = Transform(matrix: anchor.originFromAnchorTransform * makeXRotationMatrix(angle: -.pi/2))
//            imageAnchors[anchor.id]?.scale = SIMD3<Float>(repeating: appState!.boundingRadius) // for bounding occlusion sphere
        }
    }
    
    // Utilities --------------------------------------------
    /// Uses World Tracking to return the device anchor transform
    func getDeviceTransform() async -> simd_float4x4 {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
            else { return .init() }
            return deviceAnchor.originFromAnchorTransform
    }
    
    @MainActor
    func getTransformUpdates() async {
        print("Starting Data Collection")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
            Task {
                if self.worldTracking.state == .running {
                    let transform = await self.getDeviceTransform()
                    /// make function here
                    var dct = Dictionary<String, AnyObject>()
                    let date = Date()
                    dct.updateValue(date as AnyObject, forKey: "date")
                    dct.updateValue(transform as AnyObject,
                                    forKey: "transform")
                    self.dataArray.append(dct)
                    ///
                } else {
                    self.timer.invalidate()
                    createCSV(from: self.dataArray)
                }
            }
        })
    }
    
    func makeXRotationMatrix(angle: Float) -> simd_float4x4 {
        let rows = [
            simd_float4(1,          0,           0, 0),
            simd_float4(0, cos(angle), -sin(angle), 0),
            simd_float4(0, sin(angle),  cos(angle), 0),
            simd_float4(0,          0,           0, 1)
        ]
        return float4x4(rows: rows)
    }
}



