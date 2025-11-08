import SwiftUI
import ARKit
import SceneKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var mapper: SpatialMapper
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.session = mapper.arSession
        arView.delegate = context.coordinator
        
        // Enable default lighting for better visibility
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true
        
        // Show feature points to see tracking quality
        arView.debugOptions = [.showFeaturePoints]
        
        // Show statistics
        arView.showsStatistics = true
        
        // Set the scene
        let scene = SCNScene()
        arView.scene = scene
        
        // Store reference for coordinator
        context.coordinator.sceneView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Update waypoint markers whenever waypoints change
        context.coordinator.updateWaypoints(mapper.waypoints, currentPosition: mapper.currentPosition)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        var parent: ARViewContainer
        var waypointNodes: [UUID: SCNNode] = [:]
        weak var sceneView: ARSCNView?
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        // Visualize mesh anchors from LiDAR
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            let node = SCNNode()
            
            if let meshAnchor = anchor as? ARMeshAnchor {
                // Create mesh geometry from LiDAR data
                guard let device = renderer.device else { return node }
                let meshGeometry = createGeometry(from: meshAnchor, device: device)
                
                // Style the mesh - semi-transparent cyan wireframe
                meshGeometry.firstMaterial?.fillMode = .lines
                meshGeometry.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.3)
                meshGeometry.firstMaterial?.lightingModel = .constant
                
                node.geometry = meshGeometry
            } else if let planeAnchor = anchor as? ARPlaneAnchor {
                // Visualize detected planes (floor, walls)
                let planeNode = createPlaneNode(from: planeAnchor)
                node.addChildNode(planeNode)
            }
            
            return node
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            // Update mesh as LiDAR refines it
            if let meshAnchor = anchor as? ARMeshAnchor,
               let device = renderer.device {
                let meshGeometry = createGeometry(from: meshAnchor, device: device)
                meshGeometry.firstMaterial?.fillMode = .lines
                meshGeometry.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.3)
                meshGeometry.firstMaterial?.lightingModel = .constant
                node.geometry = meshGeometry
            }
        }
        
        func createPlaneNode(from planeAnchor: ARPlaneAnchor) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(planeAnchor.planeExtent.width),
                                height: CGFloat(planeAnchor.planeExtent.height))
            plane.firstMaterial?.diffuse.contents = UIColor.blue.withAlphaComponent(0.1)
            
            let planeNode = SCNNode(geometry: plane)
            planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
            planeNode.eulerAngles.x = -.pi / 2
            
            return planeNode
        }
        
        func createGeometry(from meshAnchor: ARMeshAnchor, device: MTLDevice) -> SCNGeometry {
            let meshGeometry = meshAnchor.geometry
            
            // Vertices
            let vertices = meshGeometry.vertices
            let vertexCount = vertices.count
            let vertexPointer = vertices.buffer.contents()
            let vertexData = Data(bytes: vertexPointer, count: vertexCount * vertices.stride)
            
            let vertexSource = SCNGeometrySource(
                data: vertexData,
                semantic: .vertex,
                vectorCount: vertexCount,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: vertices.offset,
                dataStride: vertices.stride
            )
            
            // Faces/Indices
            let faces = meshGeometry.faces
            let faceCount = faces.count
            let indexPointer = faces.buffer.contents()
            let bytesPerIndex = faces.bytesPerIndex
            
            let indexData = Data(bytes: indexPointer, count: faceCount * faces.indexCountPerPrimitive * bytesPerIndex)
            
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: faceCount,
                bytesPerIndex: bytesPerIndex
            )
            
            return SCNGeometry(sources: [vertexSource], elements: [element])
        }
        
        // MARK: - Waypoint Markers
        
        func updateWaypoints(_ waypoints: [Waypoint], currentPosition: simd_float3) {
            guard let sceneView = sceneView else { return }
            
            // Remove deleted waypoints
            let existingIDs = Set(waypointNodes.keys)
            let currentIDs = Set(waypoints.map { $0.id })
            let removedIDs = existingIDs.subtracting(currentIDs)
            
            for id in removedIDs {
                waypointNodes[id]?.removeFromParentNode()
                waypointNodes.removeValue(forKey: id)
            }
            
            // Add or update waypoint markers
            for waypoint in waypoints {
                if let existingNode = waypointNodes[waypoint.id] {
                    // Update distance text only
                    updateDistanceText(for: existingNode, waypoint: waypoint, currentPosition: currentPosition)
                } else {
                    // Create new waypoint marker
                    let node = createWaypointMarker(for: waypoint, currentPosition: currentPosition)
                    sceneView.scene.rootNode.addChildNode(node)
                    waypointNodes[waypoint.id] = node
                    print("✅ Added waypoint marker for \(waypoint.name) at position \(waypoint.position.vector)")
                }
            }
            
            
            updateTargetIndicator()
        }
        func updateTargetIndicator() {
            guard let sceneView = sceneView else { return }
            
            // Remove old target indicator
            sceneView.scene.rootNode.childNode(withName: "targetIndicator", recursively: false)?.removeFromParentNode()
            
            // Add new target indicator if we have a valid target
            if let targetPos = parent.mapper.targetPosition, parent.mapper.isTargetValid {
                let indicator = SCNNode()
                indicator.name = "targetIndicator"
                indicator.position = SCNVector3(targetPos.x, targetPos.y, targetPos.z)
                
                // Create pulsing ring
                let torus = SCNTorus(ringRadius: 0.15, pipeRadius: 0.02)
                torus.firstMaterial?.diffuse.contents = UIColor.yellow
                torus.firstMaterial?.emission.contents = UIColor.yellow
                torus.firstMaterial?.lightingModel = .constant
                
                let torusNode = SCNNode(geometry: torus)
                torusNode.eulerAngles.x = .pi / 2
                indicator.addChildNode(torusNode)
                
                // Add pulsing animation
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1.0
                pulse.toValue = 0.3
                pulse.duration = 0.5
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                torusNode.addAnimation(pulse, forKey: "pulse")
                
                sceneView.scene.rootNode.addChildNode(indicator)
            }
        }
        
        func createWaypointMarker(for waypoint: Waypoint, currentPosition: simd_float3) -> SCNNode {
            let node = SCNNode()
            let position = waypoint.position.vector
            node.position = SCNVector3(position.x, position.y, position.z)
            
            // Create glowing sphere
            let sphere = SCNSphere(radius: 0.15)
            sphere.firstMaterial?.diffuse.contents = UIColor.green
            sphere.firstMaterial?.emission.contents = UIColor.green.withAlphaComponent(0.8)
            sphere.firstMaterial?.lightingModel = .constant
            
            let sphereNode = SCNNode(geometry: sphere)
            node.addChildNode(sphereNode)
            
            // Create vertical line down to floor for better visibility
            let lineHeight: Float = 2.0
            let cylinder = SCNCylinder(radius: 0.01, height: CGFloat(lineHeight))
            cylinder.firstMaterial?.diffuse.contents = UIColor.green.withAlphaComponent(0.5)
            cylinder.firstMaterial?.lightingModel = .constant
            
            let lineNode = SCNNode(geometry: cylinder)
            lineNode.position = SCNVector3(0, -lineHeight/2, 0)
            node.addChildNode(lineNode)
            
            // Create text label
            let distance = waypoint.distance(from: currentPosition)
            let text = SCNText(string: "\(waypoint.name)\n\(String(format: "%.1fm", distance))", extrusionDepth: 0.5)
            text.font = UIFont.boldSystemFont(ofSize: 12)
            text.firstMaterial?.diffuse.contents = UIColor.white
            text.firstMaterial?.emission.contents = UIColor.white
            text.firstMaterial?.lightingModel = .constant
            text.flatness = 0.1
            text.alignmentMode = CATextLayerAlignmentMode.center.rawValue
            
            let textNode = SCNNode(geometry: text)
            textNode.name = "distanceText"
            textNode.scale = SCNVector3(0.01, 0.01, 0.01)
            textNode.position = SCNVector3(0, 0.25, 0)
            
            // Billboard constraint - always face camera
            let billboardConstraint = SCNBillboardConstraint()
            billboardConstraint.freeAxes = [.X, .Y, .Z]
            textNode.constraints = [billboardConstraint]
            
            node.addChildNode(textNode)
            
            return node
        }
        
        func updateDistanceText(for node: SCNNode, waypoint: Waypoint, currentPosition: simd_float3) {
            guard let textNode = node.childNode(withName: "distanceText", recursively: false),
                  let textGeometry = textNode.geometry as? SCNText else { return }
            
            let distance = waypoint.distance(from: currentPosition)
            textGeometry.string = "\(waypoint.name)\n\(String(format: "%.1fm", distance))"
        }
    }
}
