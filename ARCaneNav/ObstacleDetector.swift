import Foundation
import ARKit
import simd

class ObstacleDetector {
    
    // Detection parameters
    private let detectionDistance: Float = 3.0      // Look ahead 3 meters
    private let warningDistance: Float = 2.0        // Warn if obstacle within 2m
    private let criticalDistance: Float = 1.0       // Critical warning within 1m
    private let minObstacleHeight: Float = 0.15     // 15cm - detect even low obstacles
    private let maxObstacleHeight: Float = 2.0      // 2m - human height range
    
    // Scanning configuration - MUCH MORE COMPREHENSIVE
    private let horizontalRays = 9                  // 9 rays horizontally (wide coverage)
    private let verticalRays = 5                    // 5 rays vertically (floor to head)
    private let fieldOfView: Float = 60.0           // 60 degree FOV (degrees)
    
    func detectObstacles(
        arSession: ARSession,
        currentPosition: simd_float3,
        heading: Float,
        targetPosition: simd_float3
    ) -> ObstacleInfo {
        
        guard let frame = arSession.currentFrame else {
            return ObstacleInfo(hasObstacle: false)
        }
        
        // Calculate direction toward target
        let toTarget = targetPosition - currentPosition
        let toTargetHorizontal = simd_float3(toTarget.x, 0, toTarget.z)
        
        // Safety check
        let targetDistance = simd_length(toTargetHorizontal)
        if targetDistance < 0.01 {
            return ObstacleInfo(hasObstacle: false)
        }
        
        let forwardDirection = simd_normalize(toTargetHorizontal)
        
        // COMPREHENSIVE SCAN: Check entire forward view
        var obstacles: [DetectedObstacle] = []
        
        // Method 1: Ray casting in a wide grid pattern
        let rayObstacles = scanWithRaycasting(
            arSession: arSession,
            from: currentPosition,
            direction: forwardDirection
        )
        obstacles.append(contentsOf: rayObstacles)
        
        // Method 2: Check ARKit feature points for obstacles
        if let pointCloud = frame.rawFeaturePoints {
            let featureObstacles = scanFeaturePoints(
                pointCloud: pointCloud,
                from: currentPosition,
                direction: forwardDirection
            )
            obstacles.append(contentsOf: featureObstacles)
        }
        
        // Method 3: Check mesh anchors if available (LiDAR devices)
        if #available(iOS 13.4, *) {
            let meshObstacles = scanMeshAnchors(
                arSession: arSession,
                from: currentPosition,
                direction: forwardDirection
            )
            obstacles.append(contentsOf: meshObstacles)
        }
        
        // Analyze detected obstacles
        return analyzeObstacles(
            obstacles: obstacles,
            currentPosition: currentPosition,
            forwardDirection: forwardDirection
        )
    }
    
    // MARK: - Ray Casting Method (Primary)
    
    private func scanWithRaycasting(
        arSession: ARSession,
        from origin: simd_float3,
        direction: simd_float3
    ) -> [DetectedObstacle] {
        
        var detectedObstacles: [DetectedObstacle] = []
        
        // Calculate perpendicular for horizontal scanning
        let right = simd_normalize(simd_float3(direction.z, 0, -direction.x))
        let up = simd_float3(0, 1, 0)
        
        // Cast rays in a grid pattern
        for v in 0..<verticalRays {
            // Height from floor level (0.2m) to head level (1.8m)
            let heightRatio = Float(v) / Float(verticalRays - 1)
            let height = 0.2 + heightRatio * 1.6  // 0.2m to 1.8m
            
            for h in 0..<horizontalRays {
                // Horizontal angle from -30° to +30°
                let angleRatio = (Float(h) / Float(horizontalRays - 1)) - 0.5
                let angle = angleRatio * fieldOfView * .pi / 180.0
                
                // Calculate ray direction
                let rotatedDir = simd_normalize(
                    direction * cos(angle) + right * sin(angle)
                )
                
                // Ray origin at specific height
                let rayOrigin = origin + up * height
                
                // Perform raycast
                let query = ARRaycastQuery(
                    origin: rayOrigin,
                    direction: rotatedDir,
                    allowing: .estimatedPlane,
                    alignment: .any
                )
                
                if let result = arSession.raycast(query).first {
                    let hitPosition = simd_float3(
                        result.worldTransform.columns.3.x,
                        result.worldTransform.columns.3.y,
                        result.worldTransform.columns.3.z
                    )
                    
                    let distance = simd_distance(rayOrigin, hitPosition)
                    
                    // Check if this is a relevant obstacle
                    let heightAboveFloor = hitPosition.y - origin.y
                    
                    if distance < detectionDistance &&
                       heightAboveFloor > minObstacleHeight &&
                       heightAboveFloor < maxObstacleHeight {
                        
                        detectedObstacles.append(DetectedObstacle(
                            position: hitPosition,
                            distance: distance,
                            height: heightAboveFloor,
                            confidence: 0.8
                        ))
                    }
                }
            }
        }
        
        return detectedObstacles
    }
    
    // MARK: - Feature Points Method (Secondary)
    
    private func scanFeaturePoints(
        pointCloud: ARPointCloud,
        from origin: simd_float3,
        direction: simd_float3
    ) -> [DetectedObstacle] {
        
        var detectedObstacles: [DetectedObstacle] = []
        
        // Check each feature point
        for i in 0..<pointCloud.points.count {
            let point = pointCloud.points[i]
            let pointPosition = simd_float3(point.x, point.y, point.z)
            
            // Vector from origin to point
            let toPoint = pointPosition - origin
            let distance = simd_length(toPoint)
            
            // Check if point is in front of us
            guard distance > 0.1 && distance < detectionDistance else { continue }
            
            let toPointNormalized = simd_normalize(toPoint)
            let dotProduct = simd_dot(toPointNormalized, direction)
            
            // Point must be in forward hemisphere (within 90° of direction)
            guard dotProduct > 0.5 else { continue }  // ~60° cone
            
            // Check height
            let heightAboveFloor = pointPosition.y - origin.y
            guard heightAboveFloor > minObstacleHeight && heightAboveFloor < maxObstacleHeight else { continue }
            
            detectedObstacles.append(DetectedObstacle(
                position: pointPosition,
                distance: distance,
                height: heightAboveFloor,
                confidence: 0.6
            ))
        }
        
        return detectedObstacles
    }
    
    // MARK: - Mesh Anchors Method (Best for LiDAR)
    
    @available(iOS 13.4, *)
    private func scanMeshAnchors(
        arSession: ARSession,
        from origin: simd_float3,
        direction: simd_float3
    ) -> [DetectedObstacle] {
        
        var detectedObstacles: [DetectedObstacle] = []
        
        // Get all mesh anchors
        let meshAnchors = arSession.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        
        for meshAnchor in meshAnchors {
            let geometry = meshAnchor.geometry
            let vertices = geometry.vertices
            let transform = meshAnchor.transform
            
            // Access the vertex buffer
            let vertexCount = vertices.count
            let vertexBuffer = vertices.buffer.contents()
            let vertexStride = vertices.stride
            
            // Sample vertices (check every 5th vertex for performance)
            for i in stride(from: 0, to: Int(vertexCount), by: 5) {
                // Calculate offset in buffer
                let offset = i * vertexStride
                let vertexPointer = vertexBuffer.advanced(by: offset).assumingMemoryBound(to: (Float, Float, Float).self)
                let vertex = vertexPointer.pointee
                
                // Transform to world space
                let localPos = simd_float4(vertex.0, vertex.1, vertex.2, 1)
                let worldPos = transform * localPos
                let vertexPosition = simd_float3(worldPos.x, worldPos.y, worldPos.z)
                
                // Check if vertex is in path
                let toVertex = vertexPosition - origin
                let distance = simd_length(toVertex)
                
                guard distance > 0.1 && distance < detectionDistance else { continue }
                
                let toVertexNormalized = simd_normalize(toVertex)
                let dotProduct = simd_dot(toVertexNormalized, direction)
                
                guard dotProduct > 0.7 else { continue }  // ~45° cone
                
                let heightAboveFloor = vertexPosition.y - origin.y
                guard heightAboveFloor > minObstacleHeight && heightAboveFloor < maxObstacleHeight else { continue }
                
                detectedObstacles.append(DetectedObstacle(
                    position: vertexPosition,
                    distance: distance,
                    height: heightAboveFloor,
                    confidence: 0.9  // Mesh data is most reliable
                ))
            }
        }
        
        return detectedObstacles
    }
    
    // MARK: - Analysis
    
    private func analyzeObstacles(
        obstacles: [DetectedObstacle],
        currentPosition: simd_float3,
        forwardDirection: simd_float3
    ) -> ObstacleInfo {
        
        guard !obstacles.isEmpty else {
            return ObstacleInfo(hasObstacle: false)
        }
        
        // Cluster obstacles by proximity
        let clusteredObstacles = clusterObstacles(obstacles)
        
        // Find closest significant obstacle
        guard let closestCluster = clusteredObstacles.min(by: { $0.averageDistance < $1.averageDistance }) else {
            return ObstacleInfo(hasObstacle: false)
        }
        
        let closestDistance = closestCluster.averageDistance
        
        // Determine if this is a real threat
        guard closestDistance < warningDistance else {
            return ObstacleInfo(hasObstacle: false)
        }
        
        // Determine which side is clearer
        let right = simd_float3(forwardDirection.z, 0, -forwardDirection.x)
        
        var leftScore: Float = 0
        var rightScore: Float = 0
        
        for obstacle in obstacles where obstacle.distance < warningDistance {
            let toObstacle = obstacle.position - currentPosition
            let lateralOffset = simd_dot(toObstacle, right)
            
            if lateralOffset < 0 {
                leftScore += 1.0
            } else {
                rightScore += 1.0
            }
        }
        
        // Suggest direction with fewer obstacles
        let suggestedDirection: ObstacleAvoidanceDirection = (rightScore < leftScore) ? .right : .left
        
        // Create warning message
        let warning: String
        if closestDistance < criticalDistance {
            warning = "STOP! Obstacle \(String(format: "%.1f", closestDistance))m ahead"
        } else {
            warning = "Obstacle detected"
        }
        
        print("⚠️ OBSTACLE ANALYSIS:")
        print("   Total detected: \(obstacles.count)")
        print("   Closest: \(String(format: "%.2f", closestDistance))m")
        print("   Left score: \(leftScore), Right score: \(rightScore)")
        print("   Suggestion: Go \(suggestedDirection == .left ? "LEFT" : "RIGHT")")
        
        return ObstacleInfo(
            hasObstacle: true,
            obstacleDistance: closestDistance,
            suggestedDirection: suggestedDirection,
            warning: warning
        )
    }
    
    private func clusterObstacles(_ obstacles: [DetectedObstacle]) -> [ObstacleCluster] {
        var clusters: [ObstacleCluster] = []
        let clusterRadius: Float = 0.5  // 50cm cluster radius
        
        for obstacle in obstacles {
            var addedToCluster = false
            
            for i in 0..<clusters.count {
                if simd_distance(obstacle.position, clusters[i].center) < clusterRadius {
                    clusters[i].obstacles.append(obstacle)
                    clusters[i].updateCenter()
                    addedToCluster = true
                    break
                }
            }
            
            if !addedToCluster {
                clusters.append(ObstacleCluster(obstacles: [obstacle]))
            }
        }
        
        return clusters
    }
}

// MARK: - Supporting Types

struct DetectedObstacle {
    let position: simd_float3
    let distance: Float
    let height: Float
    let confidence: Float
}

struct ObstacleCluster {
    var obstacles: [DetectedObstacle]
    var center: simd_float3
    
    init(obstacles: [DetectedObstacle]) {
        self.obstacles = obstacles
        self.center = simd_float3(0, 0, 0)
        updateCenter()
    }
    
    mutating func updateCenter() {
        var sum = simd_float3(0, 0, 0)
        for obs in obstacles {
            sum += obs.position
        }
        center = sum / Float(obstacles.count)
    }
    
    var averageDistance: Float {
        obstacles.map { $0.distance }.reduce(0, +) / Float(obstacles.count)
    }
}

struct ObstacleInfo {
    let hasObstacle: Bool
    let obstacleDistance: Float
    let suggestedDirection: ObstacleAvoidanceDirection
    let warning: String
    
    init(hasObstacle: Bool,
         obstacleDistance: Float = 0,
         suggestedDirection: ObstacleAvoidanceDirection = .none,
         warning: String = "") {
        self.hasObstacle = hasObstacle
        self.obstacleDistance = obstacleDistance
        self.suggestedDirection = suggestedDirection
        self.warning = warning
    }
}

enum ObstacleAvoidanceDirection {
    case none
    case left
    case right
}
