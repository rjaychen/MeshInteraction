import ARKit
import SwiftUI
import RealityKit
import Accelerate
import RealityKitContent

@Observable
class ViewModel {

    var appState: AppState? = nil

    let handTracking = HandTrackingProvider()
    let sceneReconstruction = SceneReconstructionProvider()
    let contentEntity = Entity()

    private var meshEntities = [UUID: ModelEntity]()
    private let fingerEntities: [HandAnchor.Chirality: ModelEntity] = [
        .left: .createFingertip(),
        .right: .createFingertip()
    ]
    
    /// Variables I added
    private var boundingBox: BoundingBox? = nil
    private var location3D: SIMD3<Float> = [0, 0, 0]
    private var meshAnchors = [UUID: MeshAnchor]()
    private var newMeshes = [ModelEntity]()
    private var audioFilePath = "/applepay.mp3"
    
    func setupContentEntity() -> Entity {
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
        return contentEntity
    }

    var dataProvidersAreSupported: Bool {
        HandTrackingProvider.isSupported && SceneReconstructionProvider.isSupported
    }

    var isReadyToRun: Bool {
        handTracking.state == .initialized && sceneReconstruction.state == .initialized
    }

    // MARK: - ARKit and Anchor handlings

    @MainActor
    func runARKitSession() async {
        do {
            try await appState!.arkitSession.run([handTracking, sceneReconstruction])
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
            let material = try! await ShaderGraphMaterial(named: "/Root/Matrix", from: "MatrixMaterial", in: realityKitContentBundle)
            let modelEntity = ModelEntity(mesh: meshResource, materials: [material])
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
    func createBoundingEntity(location: SIMD3<Float>) {
        location3D = location
        //newMeshes.first?.removeFromParent()
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
                    var mat = SimpleMaterial(color: .magenta, isMetallic: false)
                    mat.triangleFillMode = .lines
                    let newMeshEntity = ModelEntity(mesh: meshResource, materials: [mat])
                    let resource = try! AudioFileResource.load(named: audioFilePath)
                    newMeshEntity.playAudio(resource)
                    newMeshes.append(newMeshEntity)
                    contentEntity.addChild(newMeshEntity)
                }
            }
        }
    }
    
}
