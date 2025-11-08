import SwiftUI

struct NavigationOverlay: View {
    @ObservedObject var navigator: Navigator
    
    var body: some View {
        VStack(spacing: 20) {
            if navigator.isNavigating {
                // Obstacle warning banner (if detected)
                if navigator.obstacleDetected {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(navigator.obstacleWarning)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("(\(String(format: "%.1fm", navigator.obstacleDistance)))")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
                    .shadow(radius: 5)
                }
                
                // Large directional arrow
                Image(systemName: navigator.currentDirection.arrowSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .foregroundColor(Color(
                        red: navigator.currentDirection.color.red,
                        green: navigator.currentDirection.color.green,
                        blue: navigator.currentDirection.color.blue
                    ))
                    .shadow(color: .black.opacity(0.5), radius: 10)
                
                // Direction text
                Text(navigator.currentDirection.displayName)
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 5)
                
                // Navigation message
                Text(navigator.navigationMessage)
                    .font(.title2)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                
                // Visual haptic indicator (simulates motor vibration)
                HapticSimulator(direction: navigator.currentDirection)
                
                // Stop button
                Button(action: {
                    navigator.stop()
                }) {
                    Text("Stop Navigation")
                        .bold()
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
        }
        .padding()
    }
}

struct HapticSimulator: View {
    let direction: NavigationDirection
    @State private var pulseLeft = false
    @State private var pulseCenter = false
    @State private var pulseRight = false
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Haptic Motors (Simulated)")
                .font(.caption)
                .foregroundColor(.white)
            
            HStack(spacing: 30) {
                // Left motor
                Circle()
                    .fill(direction == .left ? Color.orange : Color.gray)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text("L")
                            .foregroundColor(.white)
                            .bold()
                    )
                    .opacity(pulseLeft ? 1.0 : 0.3)
                
                // Center motor
                Circle()
                    .fill(direction == .straight ? Color.green : Color.gray)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text("C")
                            .foregroundColor(.white)
                            .bold()
                    )
                    .opacity(pulseCenter ? 1.0 : 0.3)
                
                // Right motor
                Circle()
                    .fill(direction == .right ? Color.orange : Color.gray)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text("R")
                            .foregroundColor(.white)
                            .bold()
                    )
                    .opacity(pulseRight ? 1.0 : 0.3)
            }
            .onAppear {
                startPulsing()
            }
            .onChange(of: direction) { _ in
                startPulsing()
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }
    
    func startPulsing() {
        // Reset
        pulseLeft = false
        pulseCenter = false
        pulseRight = false
        
        switch direction {
        case .left:
            withAnimation(Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                pulseLeft = true
            }
        case .straight:
            withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                pulseCenter = true
            }
        case .right:
            withAnimation(Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                pulseRight = true
            }
        case .turnBack:
            // All motors pulse rapidly - WRONG DIRECTION!
            withAnimation(Animation.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                pulseLeft = true
                pulseCenter = true
                pulseRight = true
            }
        case .arrived:
            // All motors pulse together - celebration
            withAnimation(Animation.easeInOut(duration: 0.2).repeatCount(3, autoreverses: true)) {
                pulseLeft = true
                pulseCenter = true
                pulseRight = true
            }
        case .none:
            break
        }
    }
}
