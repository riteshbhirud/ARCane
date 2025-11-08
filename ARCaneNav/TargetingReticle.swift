import SwiftUI

struct TargetingReticle: View {
    let targetDistance: Float?
    let isTargetValid: Bool
    
    var body: some View {
        ZStack {
            // Crosshair
            Circle()
                .stroke(isTargetValid ? Color.green : Color.red, lineWidth: 3)
                .frame(width: 40, height: 40)
            
            // Center dot
            Circle()
                .fill(isTargetValid ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Horizontal line
            Rectangle()
                .fill(isTargetValid ? Color.green : Color.red)
                .frame(width: 60, height: 2)
            
            // Vertical line
            Rectangle()
                .fill(isTargetValid ? Color.green : Color.red)
                .frame(width: 2, height: 60)
            
            // Distance indicator
            if let distance = targetDistance {
                Text(String(format: "%.2fm", distance))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(isTargetValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .offset(y: 50)
            } else {
                Text("No Target")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .offset(y: 50)
            }
        }
    }
}
