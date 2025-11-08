import Foundation
import simd

struct Waypoint: Identifiable, Codable {
    let id: UUID
    let name: String
    let position: CodableFloat3
    let timestamp: Date
    
    init(name: String, position: simd_float3) {
        self.id = UUID()
        self.name = name
        self.position = CodableFloat3(position)
        self.timestamp = Date()
    }
    
    // Calculate distance from a given position (typically current position)
    func distance(from currentPosition: simd_float3) -> Float {
        return simd_distance(currentPosition, position.vector)
    }
    
    func distanceString(from currentPosition: simd_float3) -> String {
        let dist = distance(from: currentPosition)
        return String(format: "%.1fm", dist)
    }
}

// Helper to make simd_float3 Codable
struct CodableFloat3: Codable {
    let x: Float
    let y: Float
    let z: Float
    
    init(_ vector: simd_float3) {
        self.x = vector.x
        self.y = vector.y
        self.z = vector.z
    }
    
    var vector: simd_float3 {
        simd_float3(x, y, z)
    }
}
