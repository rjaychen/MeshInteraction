//
//  Extensions.swift
//  MeshInteraction
//
//  Created by I3T Duke on 6/21/24.
//

import ARKit
import RealityKit

extension ModelEntity {
    /// Creates an invisible sphere that can interact with dropped cubes in the scene.
    class func createFingertip() -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.005),
            materials: [UnlitMaterial(color: .cyan)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0)

        entity.components.set(PhysicsBodyComponent(mode: .kinematic))
        entity.components.set(OpacityComponent(opacity: 0.0))

        return entity
    }
}

extension GeometrySource {
    @MainActor
    func asArray<T>(ofType: T.Type) -> [T] {
        assert(MemoryLayout<T>.stride == stride, "Invalid stride \(MemoryLayout<T>.stride); expected \(stride)")
        return (0..<self.count).map {
            buffer.contents().advanced(by: offset + stride * Int($0)).assumingMemoryBound(to: T.self).pointee
        }
    }

    @MainActor
    func asSIMD3<T>(ofType: T.Type) -> [SIMD3<T>] {
        return asArray(ofType: (T, T, T).self).map { .init($0.0, $0.1, $0.2) }
    }
}

extension MeshAnchor.Geometry{
    func vertex(at index: UInt32) -> SIMD3<Float> {
            assert(vertices.format == MTLVertexFormat.float3, "Expected three floats (twelve bytes) per vertex.")
            let vertexPointer = vertices.buffer.contents().advanced(by: vertices.offset + (vertices.stride * Int(index)))
            let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            return vertex
        }
}

extension simd_float4x4 {
    func position() -> SIMD3<Float> {
        return [columns.3.x, columns.3.y, columns.3.z]
    }
}

func anchorToWorld(anchorMatrix: simd_float4x4, pos: SIMD3<Float>) -> SIMD3<Float>{
    var localTransform = matrix_identity_float4x4
    localTransform.columns.3 = [pos.x, pos.y, pos.z, 1]
    let worldPosition = (anchorMatrix * localTransform).position()
    return worldPosition
}

func createCSV(from data:[Dictionary<String, AnyObject>]) {
    var csvString = "\("Time"),\("Transform")\n\n"
    for dct in data {
        csvString = csvString.appending("\(String(describing: dct["date"]!)),\(String(describing: dct["transform"]!))\n")
    }
    let fileManager = FileManager.default
    do {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dataURL = documentsURL.appendingPathComponent("CSVFiles")
        try fileManager.createDirectory(at: dataURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
        print("Error creating directory: \(error)")
    }
    do {
        let path = try fileManager.url(for: .documentDirectory, in: .allDomainsMask, appropriateFor: nil, create: false)
        let dataURL = path.appendingPathComponent("CSVFiles")
        let date = Date()
        let components = date.get(.month, .day, .hour, .minute)
        var fileName = "HeadTransform.csv"
        if let month = components.month, let day = components.day, let hour = components.hour, let minute = components.minute {
            fileName = "HeadTransform_\(month)-\(day)_\(hour)-\(minute).csv"
        }
        let fileURL = dataURL.appendingPathComponent(fileName)
        try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
        print(fileURL)
    } catch {
        print("Error creating CSV file: \(error)")
    }
}

extension Date {
    func get(_ components: Calendar.Component..., calendar: Calendar = Calendar.current) -> DateComponents {
        return calendar.dateComponents(Set(components), from: self)
    }

    func get(_ component: Calendar.Component, calendar: Calendar = Calendar.current) -> Int {
        return calendar.component(component, from: self)
    }
}
