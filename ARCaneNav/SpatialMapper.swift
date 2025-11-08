import ARKit
import Combine
import Accelerate
import SwiftUI
class SpatialMapper: NSObject, ObservableObject, ARSessionDelegate {
    
    @Published var currentPosition: simd_float3 = .zero
    @Published var smoothedPosition: simd_float3 = .zero
    @Published var meshAnchorCount: Int = 0
    @Published var isMapping = false
    @Published var statusMessage = "Ready to start"
    @Published var waypoints: [Waypoint] = []
    @Published var trackingQuality: String = "Not Tracking"
    
    @Published var targetPosition: simd_float3?
    @Published var targetDistance: Float?
    @Published var isTargetValid: Bool = false
    @Published var navigator: Navigator?
    var arSession = ARSession()
    
    // Position smoothing
    private var positionHistory: [simd_float3] = []
    private let smoothingWindowSize = 5
    
    override init() {
        super.init()
        arSession.delegate = self
        checkLiDARSupport()
        loadWaypoints()
    }
    
    func checkLiDARSupport() {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            statusMessage = "✅ LiDAR supported"
            print("✅ LiDAR is supported on this device")
        } else {
            statusMessage = "❌ LiDAR not supported"
            print("❌ LiDAR not supported on this device")
        }
    }
    
    func startMapping() {
        let config = ARWorldTrackingConfiguration()
        
        // MAXIMUM ACCURACY SETTINGS
        
        // Enable LiDAR scene reconstruction with highest quality
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            print("✅ LiDAR mesh reconstruction enabled")
        }
        
        // Enable plane detection for anchoring
        config.planeDetection = [.horizontal, .vertical]
        
        // Enable scene depth for better accuracy
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            print("✅ Scene depth enabled")
        }
        
        // Enable smooth depth for cleaner data
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
            print("✅ Smoothed scene depth enabled")
        }
        
        // High quality environmental texturing
        config.environmentTexturing = .automatic
        
        // Enable better lighting estimation
        config.wantsHDREnvironmentTextures = true
        
        // Maximum world mapping capability
        config.initialWorldMap = nil // Fresh start for best accuracy
        
        // Run with highest priority
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        isMapping = true
        statusMessage = "Mapping active - High accuracy mode"
        print("📍 ARKit mapping started with maximum accuracy settings")
        
        // Reset position history for fresh start
        positionHistory.removeAll()
    }
    
    func stopMapping() {
        arSession.pause()
        isMapping = false
        statusMessage = "Mapping paused"
        print("⏸️ Mapping paused")
    }
    
    // MARK: - Position Smoothing
    
    private func smoothPosition(_ newPosition: simd_float3) -> simd_float3 {
        // Add to history
        positionHistory.append(newPosition)
        
        // Keep only recent positions
        if positionHistory.count > smoothingWindowSize {
            positionHistory.removeFirst()
        }
        
        // Calculate moving average
        guard positionHistory.count > 0 else { return newPosition }
        
        var sum = simd_float3(0, 0, 0)
        for position in positionHistory {
            sum += position
        }
        
        return sum / Float(positionHistory.count)
    }
    
    // MARK: - Waypoint Management
    
    func saveWaypoint(name: String) {
        // Use smoothed position for better accuracy
        let waypoint = Waypoint(name: name, position: smoothedPosition)
        waypoints.append(waypoint)
        print("📌 Saved waypoint: \(name) at \(smoothedPosition)")
        print("   Raw position: \(currentPosition)")
        print("   Tracking quality: \(trackingQuality)")
        saveWaypointsToDisk()
    }
    
    func deleteWaypoint(at offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        saveWaypointsToDisk()
    }
    
    func getWaypoint(named name: String) -> Waypoint? {
        return waypoints.first { $0.name.lowercased() == name.lowercased() }
    }
    
    func getNearbyWaypoints(radius: Float = 5.0) -> [(Waypoint, Float)] {
        return waypoints.compactMap { waypoint in
            let distance = simd_distance(smoothedPosition, waypoint.position.vector)
            return distance <= radius ? (waypoint, distance) : nil
        }.sorted { $0.1 < $1.1 }
    }
    
    // Get direction to waypoint (for navigation)
    func getDirection(to waypoint: Waypoint, currentHeading: Float) -> NavigationDirection {
        let toWaypoint = waypoint.position.vector - smoothedPosition
        let targetAngle = atan2(toWaypoint.z, toWaypoint.x)
        
        // Normalize angle difference to [-π, π]
        var angleDiff = targetAngle - currentHeading
        while angleDiff > .pi { angleDiff -= 2 * .pi }
        while angleDiff < -.pi { angleDiff += 2 * .pi }
        
        let distance = simd_distance(smoothedPosition, waypoint.position.vector)
        
        // Determine direction
        if distance < 0.5 {
            return .arrived
        } else if abs(angleDiff) < 0.2 { // ~11 degrees
            return .straight
        } else if angleDiff > 0 {
            return .left
        } else {
            return .right
        }
    }
    
    func getCurrentHeading() -> Float {
        guard let frame = arSession.currentFrame else { return 0 }
        let transform = frame.camera.transform
        
        // IMPORTANT: columns.2 is BACKWARD in ARKit, so negate it to get forward
        let forward = simd_float3(-transform.columns.2.x, 0, -transform.columns.2.z)
        let normalizedForward = simd_normalize(forward)
        
        return atan2(normalizedForward.z, normalizedForward.x)
    }
    
    // MARK: - Persistence
    
    private func waypointsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("waypoints.json")
    }
    
    private func saveWaypointsToDisk() {
        do {
            let data = try JSONEncoder().encode(waypoints)
            try data.write(to: waypointsURL())
            print("💾 Saved \(waypoints.count) waypoints to disk")
        } catch {
            print("❌ Failed to save waypoints: \(error)")
        }
    }
    
    private func loadWaypoints() {
        do {
            let data = try Data(contentsOf: waypointsURL())
            waypoints = try JSONDecoder().decode([Waypoint].self, from: data)
            print("📂 Loaded \(waypoints.count) waypoints from disk")
        } catch {
            print("ℹ️ No saved waypoints found (this is normal on first launch)")
        }
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Get raw position
        let transform = frame.camera.transform
        let rawPosition = simd_float3(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        
        // Update positions
        currentPosition = rawPosition
        smoothedPosition = smoothPosition(rawPosition)
        
        // Track quality
        switch frame.camera.trackingState {
        case .normal:
            trackingQuality = "✅ Excellent"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                trackingQuality = "⚠️ Move slower"
            case .insufficientFeatures:
                trackingQuality = "⚠️ Point at textured surfaces"
            case .initializing:
                trackingQuality = "🔄 Initializing..."
            case .relocalizing:
                trackingQuality = "🔄 Relocalizing..."
            @unknown default:
                trackingQuality = "⚠️ Limited"
            }
        case .notAvailable:
            trackingQuality = "❌ Not tracking"
        }
        
        // Count mesh anchors
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        DispatchQueue.main.async {
            self.meshAnchorCount = meshAnchors.count
        }
        updateTargetPosition()
        updateNavigator()
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshCount = anchors.compactMap { $0 as? ARMeshAnchor }.count
        let planeCount = anchors.compactMap { $0 as? ARPlaneAnchor }.count
        if meshCount > 0 || planeCount > 0 {
            print("➕ Added \(meshCount) mesh anchors, \(planeCount) plane anchors")
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ ARSession error: \(error.localizedDescription)")
        statusMessage = "Error: \(error.localizedDescription)"
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("⚠️ Session interrupted")
        statusMessage = "Session interrupted"
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("✅ Session resumed")
        statusMessage = "Session resumed"
    }
    // MARK: - Targeting System
        
    func updateTargetPosition() {
        guard let frame = arSession.currentFrame else {
            targetPosition = nil
            targetDistance = nil
            isTargetValid = false
            return
        }
        
        // Get camera position and orientation
        let cameraTransform = frame.camera.transform
        let cameraPosition = simd_float3(cameraTransform.columns.3.x,
                                         cameraTransform.columns.3.y,
                                         cameraTransform.columns.3.z)
        
        // Get forward direction (where camera is pointing)
        let forward = simd_float3(-cameraTransform.columns.2.x,
                                  -cameraTransform.columns.2.y,
                                  -cameraTransform.columns.2.z)
        
        // Method 1: Try raycast against scene geometry (LiDAR mesh)
        let query = ARRaycastQuery(
            origin: cameraPosition,
            direction: forward,
            allowing: .estimatedPlane,
            alignment: .any
        )
        
        if let result = arSession.raycast(query).first {
            // Hit something!
            let hitPosition = result.worldTransform.columns.3
            targetPosition = simd_float3(hitPosition.x, hitPosition.y, hitPosition.z)
            targetDistance = simd_distance(cameraPosition, targetPosition!)
            isTargetValid = targetDistance! < 10.0 // Valid if within 10 meters
            return
        }
        
        // Method 2: Use scene depth map from LiDAR (more accurate)
        if let depthData = frame.sceneDepth?.depthMap {
            // Get depth at center of screen
            let centerX = CVPixelBufferGetWidth(depthData) / 2
            let centerY = CVPixelBufferGetHeight(depthData) / 2
            
            CVPixelBufferLockBaseAddress(depthData, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthData, .readOnly) }
            
            if let baseAddress = CVPixelBufferGetBaseAddress(depthData) {
                let width = CVPixelBufferGetWidth(depthData)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(depthData)
                
                // Depth is stored as Float32
                let row = baseAddress.advanced(by: centerY * bytesPerRow)
                let depthPointer = row.assumingMemoryBound(to: Float32.self)
                let depth = depthPointer[centerX]
                
                // Calculate target position
                if depth > 0 && depth < 10.0 { // Valid depth
                    targetPosition = cameraPosition + forward * depth
                    targetDistance = depth
                    isTargetValid = true
                    return
                }
            }
        }
        
        // Method 3: Fallback - use fixed distance if no hit
        let fallbackDistance: Float = 2.0
        targetPosition = cameraPosition + forward * fallbackDistance
        targetDistance = fallbackDistance
        isTargetValid = false
    }

    func saveWaypointAtTarget(name: String) {
        // Try to get target position first
        updateTargetPosition()
        
        guard let target = targetPosition else {
            print("⚠️ No target position available, using camera position")
            saveWaypoint(name: name)
            return
        }
        
        // Save waypoint at target location
        let waypoint = Waypoint(name: name, position: target)
        waypoints.append(waypoint)
        
        let distance = targetDistance ?? 0
        print("📌 Saved waypoint: \(name)")
        print("   Target position: \(target)")
        print("   Distance from camera: \(String(format: "%.2f", distance))m")
        print("   Valid target: \(isTargetValid)")
        
        saveWaypointsToDisk()
    }
    func updateNavigator() {
        navigator?.updateNavigation(currentPosition: smoothedPosition, currentHeading: getCurrentHeading())
    }
}
