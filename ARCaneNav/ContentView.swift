import SwiftUI
import ARKit
import simd
import RealityKit

struct ContentView: View {
    @StateObject private var mapper = SpatialMapper()
    @StateObject private var navigator = Navigator()

    @State private var waypointName = ""
    @State private var showingSaveSheet = false
    @State private var showARView = false
    
    
    var body: some View {
        ZStack {
            Color.clear.onAppear {
                navigator.setup(mapper: mapper)
                navigator.setupARSession(mapper.arSession)
                mapper.navigator = navigator
                
            }
            
            if showARView && mapper.isMapping {
                // AR Camera View (full screen)
                ARViewContainer(mapper: mapper)
                    .ignoresSafeArea()
                
                // Navigation overlay (if navigating)
                if navigator.isNavigating {
                    NavigationOverlay(navigator: navigator)
                }
                
                // Targeting reticle in center (only if NOT navigating)
                if !navigator.isNavigating {
                    VStack {
                        Spacer()
                        TargetingReticle(
                            targetDistance: mapper.targetDistance,
                            isTargetValid: mapper.isTargetValid
                        )
                        Spacer()
                    }
                }
                
                // Overlay controls on top of AR view (only if NOT navigating)
                if !navigator.isNavigating {
                    VStack {
                        // Top status bar
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tracking: \(mapper.trackingQuality)")
                                    .font(.caption)
                                Text("Mesh: \(mapper.meshAnchorCount)")
                                    .font(.caption)
                                Text("Waypoints: \(mapper.waypoints.count)")
                                    .font(.caption)
                                if mapper.isTargetValid {
                                    Text("✅ Target Locked")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("⚠️ No Target")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            
                            Spacer()
                            
                            Button(action: { showARView = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(20)
                            }
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Bottom controls
                        VStack(spacing: 12) {
                            // Instructions
                            Text(mapper.isTargetValid ?
                                 "🎯 Point at object and tap Save" :
                                 "❌ Point at a surface to target")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(mapper.isTargetValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                                .cornerRadius(8)
                            
                            Button(action: { showingSaveSheet = true }) {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                    Text(mapper.isTargetValid ? "Save Waypoint Here" : "No Target Selected")
                                        .bold()
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(mapper.isTargetValid ? Color.green : Color.gray)
                                .cornerRadius(12)
                            }
                            .disabled(!mapper.isTargetValid)
                        }
                        .padding()
                    }
                }
            } else {
                // Control View
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("AR Cane Navigator")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white)
                    
                    // Status Display
                    VStack(alignment: .leading, spacing: 12) {
                        StatusRow(label: "Status", value: mapper.statusMessage)
                        StatusRow(label: "Tracking", value: mapper.trackingQuality)
                        StatusRow(label: "Position", value: String(format: "(%.2f, %.2f, %.2f)",
                                                                    mapper.smoothedPosition.x,
                                                                    mapper.smoothedPosition.y,
                                                                    mapper.smoothedPosition.z))
                        StatusRow(label: "Mesh Anchors", value: "\(mapper.meshAnchorCount)")
                        StatusRow(label: "Waypoints", value: "\(mapper.waypoints.count)")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    // Control Buttons
                    VStack(spacing: 15) {
                        Button(action: {
                            if mapper.isMapping {
                                mapper.stopMapping()
                                showARView = false
                            } else {
                                mapper.startMapping()
                                showARView = true
                            }
                        }) {
                            HStack {
                                Image(systemName: mapper.isMapping ? "stop.circle.fill" : "play.circle.fill")
                                Text(mapper.isMapping ? "Stop Mapping" : "Start Mapping")
                                    .bold()
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(mapper.isMapping ? Color.red : Color.green)
                            .cornerRadius(12)
                        }
                        
                        if mapper.isMapping {
                            Button(action: { showARView.toggle() }) {
                                HStack {
                                    Image(systemName: showARView ? "list.bullet" : "camera.fill")
                                    Text(showARView ? "Show List" : "Show AR Camera")
                                        .bold()
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Waypoint List
                    if !mapper.waypoints.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Saved Waypoints")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            List {
                                ForEach(mapper.waypoints) { waypoint in
                                    WaypointRow(
                                        waypoint: waypoint,
                                        currentPosition: mapper.smoothedPosition,
                                        onNavigate: {
                                            navigator.navigateTo(waypoint)
                                            showARView = true  // Auto-switch to AR view
                                        }
                                    )
                                    .listRowBackground(Color.gray.opacity(0.2))
                                }
                                .onDelete(perform: mapper.deleteWaypoint)
                            }
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .cornerRadius(12)
                        }
                        .frame(maxHeight: 250)
                    } else {
                        Text("No waypoints saved yet.\nStart mapping and save your first waypoint!")
                            .font(.callout)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveWaypointSheet(waypointName: $waypointName, onSave: {
                if !waypointName.isEmpty {
                    mapper.saveWaypointAtTarget(name: waypointName)
                    waypointName = ""
                    showingSaveSheet = false
                }
            }, onCancel: {
                waypointName = ""
                showingSaveSheet = false
            })
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.gray)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .foregroundColor(.white)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct WaypointRow: View {
    let waypoint: Waypoint
    let currentPosition: simd_float3
    let onNavigate: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(waypoint.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(formattedDate(waypoint.timestamp))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(waypoint.distanceString(from: currentPosition))
                    .font(.subheadline)
                    .foregroundColor(.cyan)
                    .bold()
                
                Button(action: onNavigate) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        Text("Navigate")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct SaveWaypointSheet: View {
    @Binding var waypointName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Save Target Location")
                    .font(.title2)
                    .bold()
                    .padding(.top)
                
                Text("Waypoint will be saved at the targeted surface")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                TextField("Waypoint name (e.g., Door, Table)", text: $waypointName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .autocapitalization(.words)
                
                HStack(spacing: 15) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    Button("Save") {
                        onSave()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(waypointName.isEmpty ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(waypointName.isEmpty)
                }
                .padding()
                
                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
