import Foundation
import Combine
import simd
import ARKit


class Navigator: ObservableObject {
    
    @Published var isNavigating = false
    @Published var targetWaypoint: Waypoint?
    @Published var currentDirection: NavigationDirection = .none
    @Published var distanceToTarget: Float = 0
    @Published var bearingToTarget: Float = 0  // Angle in degrees
    @Published var navigationMessage = ""
    
    // Obstacle detection properties
    @Published var obstacleDetected = false
    @Published var obstacleWarning = ""
    @Published var obstacleDistance: Float = 0
    
    private var obstacleDetector = ObstacleDetector()
    private var arSession: ARSession?
    
    private var mapper: SpatialMapper?
    
    // Heading smoothing for stable direction
    private var headingHistory: [Float] = []
    private let headingSmoothingWindow = 5
    
    // Hysteresis to prevent rapid switching
    private var lastDirection: NavigationDirection = .none
    private var directionChangeCounter = 0
    private let directionChangeThreshold = 2  // Must be consistent for 2 frames
    
    func setup(mapper: SpatialMapper) {
        self.mapper = mapper
    }
    
    func setupARSession(_ session: ARSession) {
        self.arSession = session
    }
    
    // Start navigation to a waypoint
    func navigateTo(_ waypoint: Waypoint) {
        targetWaypoint = waypoint
        isNavigating = true
        navigationMessage = "Navigating to \(waypoint.name)"
        
        // Reset smoothing
        headingHistory.removeAll()
        lastDirection = .none
        directionChangeCounter = 0
        
        // Clear any previous obstacle warnings
        obstacleDetected = false
        obstacleWarning = ""
        obstacleDistance = 0
        
        print("🧭 Navigation started to \(waypoint.name)")
    }
    
    // Stop navigation
    func stop() {
        isNavigating = false
        targetWaypoint = nil
        currentDirection = .none
        navigationMessage = ""
        headingHistory.removeAll()
        lastDirection = .none
        
        // CLEAR OBSTACLE WARNINGS
        obstacleDetected = false
        obstacleWarning = ""
        obstacleDistance = 0
        
        print("🛑 Navigation stopped")
    }
    
    // Smooth heading to reduce jitter
    private func smoothHeading(_ newHeading: Float) -> Float {
        headingHistory.append(newHeading)
        
        if headingHistory.count > headingSmoothingWindow {
            headingHistory.removeFirst()
        }
        
        guard headingHistory.count > 0 else { return newHeading }
        
        // Circular mean for angles (important for wrapping around ±π)
        var sinSum: Float = 0
        var cosSum: Float = 0
        
        for heading in headingHistory {
            sinSum += sin(heading)
            cosSum += cos(heading)
        }
        
        return atan2(sinSum / Float(headingHistory.count), cosSum / Float(headingHistory.count))
    }
    
    // Update navigation (call this every frame)
    func updateNavigation(currentPosition: simd_float3, currentHeading: Float) {
        guard let target = targetWaypoint, isNavigating else { return }
        
        // Smooth the heading for stable navigation
        let smoothedHeading = smoothHeading(currentHeading)
        
        // Calculate distance (full 3D for display)
        distanceToTarget = simd_distance(currentPosition, target.position.vector)

        // Calculate HORIZONTAL distance for arrival detection (ignore height difference)
        let currentHorizontal = simd_float3(currentPosition.x, 0, currentPosition.z)
        let targetHorizontal = simd_float3(target.position.vector.x, 0, target.position.vector.z)
        let horizontalDistance = simd_distance(currentHorizontal, targetHorizontal)

        print("📍 Distance Check:")
        print("   3D distance: \(String(format: "%.2f", distanceToTarget))m")
        print("   Horizontal distance: \(String(format: "%.2f", horizontalDistance))m")
        print("   Height diff: \(String(format: "%.2f", abs(currentPosition.y - target.position.vector.y)))m")

        // Check if arrived (using HORIZONTAL distance only)
        if horizontalDistance < 0.75 {  // Within 75cm horizontally
            let newDirection: NavigationDirection = .arrived
            if applyHysteresis(newDirection) {
                currentDirection = newDirection
                navigationMessage = "🎉 Arrived at \(target.name)!"
                print("   ✅ ARRIVED! (horizontal distance < 0.75m)")
                
                // CLEAR OBSTACLE WARNINGS WHEN ARRIVED
                obstacleDetected = false
                obstacleWarning = ""
                obstacleDistance = 0
            }
            return
        }
        
        // Obstacle Detection - ONLY when actively navigating and not arrived
        var obstacleInfo = ObstacleInfo(hasObstacle: false)
        if let session = arSession, isNavigating && currentDirection != .arrived {
            obstacleInfo = obstacleDetector.detectObstacles(
                arSession: session,
                currentPosition: currentPosition,
                heading: smoothedHeading,
                targetPosition: target.position.vector
            )
            
            obstacleDetected = obstacleInfo.hasObstacle
            obstacleWarning = obstacleInfo.warning
            obstacleDistance = obstacleInfo.obstacleDistance
            
            if obstacleInfo.hasObstacle {
                print("⚠️ OBSTACLE DETECTED!")
                print("   Distance: \(String(format: "%.2f", obstacleInfo.obstacleDistance))m")
                print("   Suggestion: \(obstacleInfo.suggestedDirection)")
            }
        }
        
        // Calculate direction to target
        let toTarget = target.position.vector - currentPosition
        
        // Project to horizontal plane (ignore height differences)
        let toTargetHorizontal = simd_float3(toTarget.x, 0, toTarget.z)
        let toTargetNormalized = simd_normalize(toTargetHorizontal)
        
        let targetAngle = atan2(toTargetNormalized.z, toTargetNormalized.x)
        
        // Calculate bearing (angle difference)
        var angleDiff = targetAngle - smoothedHeading
        
        // Normalize to [-π, π]
        while angleDiff > .pi { angleDiff -= 2 * .pi }
        while angleDiff < -.pi { angleDiff += 2 * .pi }
        
        // Convert to degrees for display
        bearingToTarget = angleDiff * 180 / .pi
        
        // NAVIGATION ZONES for human walking
        let straightThreshold: Float = 40 * .pi / 180      // ±40° = straight corridor
        let turnThreshold: Float = 50 * .pi / 180          // ±50° = need to turn
        let wrongWayThreshold: Float = 135 * .pi / 180     // ±135° = facing wrong way!
        
        // Determine new direction (with obstacle avoidance)
        let newDirection: NavigationDirection
        let degrees = Int(abs(bearingToTarget))
        
        print("🧭 Navigation Debug:")
        print("   Angle to target: \(String(format: "%.1f", bearingToTarget))°")
        print("   Distance: \(String(format: "%.2f", distanceToTarget))m")
        print("   Current heading: \(String(format: "%.1f", smoothedHeading * 180 / .pi))°")
        print("   Target angle: \(String(format: "%.1f", targetAngle * 180 / .pi))°")
        
        // PRIORITY 1: Obstacle Avoidance
        if obstacleInfo.hasObstacle {
            // Obstacle detected, override normal navigation
            if obstacleInfo.suggestedDirection == .left {
                newDirection = .left
                navigationMessage = "⚠️ \(obstacleInfo.warning)\n\(String(format: "%.1fm", distanceToTarget)) to destination"
                print("   ⚠️ AVOIDING OBSTACLE - GO LEFT")
            } else {
                newDirection = .right
                navigationMessage = "⚠️ \(obstacleInfo.warning)\n\(String(format: "%.1fm", distanceToTarget)) to destination"
                print("   ⚠️ AVOIDING OBSTACLE - GO RIGHT")
            }
            
        // PRIORITY 2: Normal Navigation (no obstacles)
        } else if abs(angleDiff) < straightThreshold {
            // Within ±40 degrees - GO STRAIGHT
            newDirection = .straight
            navigationMessage = "⬆️ Keep Going Straight\n\(String(format: "%.1fm", distanceToTarget)) ahead"
            print("   ✅ STRAIGHT (within ±40°)")
            
        } else if abs(angleDiff) > wrongWayThreshold {
            // More than 135 degrees - FACING WRONG WAY!
            newDirection = .turnBack
            navigationMessage = "🔄 Turn Around!\nYou're facing the wrong way"
            print("   🔄 TURN AROUND! (\(degrees)° off)")
            
        } else if abs(angleDiff) > turnThreshold {
            // Between 50-135 degrees - TURN
            if angleDiff > 0 {
                newDirection = .right
                navigationMessage = "➡️ Turn Right\nAdjust \(degrees)° right"
                print("   ➡️ TURN RIGHT (\(degrees)°)")
            } else {
                newDirection = .left
                navigationMessage = "⬅️ Turn Left\nAdjust \(degrees)° left"
                print("   ⬅️ TURN LEFT (\(degrees)°)")
            }
            
        } else {
            // Between 40-50 degrees - SLIGHT CORRECTION
            if angleDiff > 0 {
                newDirection = .right
                navigationMessage = "↗️ Slight Right\nAdjust \(degrees)° right"
                print("   ↗️ SLIGHT RIGHT (\(degrees)°)")
            } else {
                newDirection = .left
                navigationMessage = "↖️ Slight Left\nAdjust \(degrees)° left"
                print("   ↖️ SLIGHT LEFT (\(degrees)°)")
            }
        }
        
        // Apply hysteresis to prevent rapid switching
        if applyHysteresis(newDirection) {
            currentDirection = newDirection
        }
    }
    
    // Hysteresis: Direction must be consistent for multiple frames before changing
    private func applyHysteresis(_ newDirection: NavigationDirection) -> Bool {
        // Special cases: Always allow immediate changes for critical directions
        if newDirection == .arrived || lastDirection == .none {
            lastDirection = newDirection
            directionChangeCounter = 0
            return true
        }
        
        // If same as last direction, keep it
        if newDirection == lastDirection {
            directionChangeCounter = 0
            return true
        }
        
        // If different, must be consistent for multiple frames
        directionChangeCounter += 1
        
        if directionChangeCounter >= directionChangeThreshold {
            // Direction has been consistent, allow change
            lastDirection = newDirection
            directionChangeCounter = 0
            return true
        }
        
        // Not consistent yet, keep old direction
        return false
    }
}

// Navigation directions - ONLY DEFINED HERE
enum NavigationDirection: Equatable {
    case none
    case straight
    case left
    case right
    case turnBack
    case arrived
    
    var displayName: String {
        switch self {
        case .none: return "No Navigation"
        case .straight: return "Go Straight"
        case .left: return "Turn Left"
        case .right: return "Turn Right"
        case .turnBack: return "Turn Around"
        case .arrived: return "Arrived!"
        }
    }
    
    var color: (red: Double, green: Double, blue: Double) {
        switch self {
        case .none: return (0.5, 0.5, 0.5)
        case .straight: return (0, 1, 0)      // Green
        case .left: return (1, 0.5, 0)         // Orange
        case .right: return (1, 0.5, 0)        // Orange
        case .turnBack: return (1, 0, 0)       // Red - wrong direction!
        case .arrived: return (0, 1, 1)        // Cyan
        }
    }
    
    var arrowSymbol: String {
        switch self {
        case .none: return "circle"
        case .straight: return "arrow.up.circle.fill"
        case .left: return "arrow.left.circle.fill"
        case .right: return "arrow.right.circle.fill"
        case .turnBack: return "arrow.uturn.down.circle.fill"
        case .arrived: return "checkmark.circle.fill"
        }
    }
}
