import SwiftUI
import CoreLocation

public struct JoystickOverlayView: View {
    @ObservedObject var movementSimulator: MovementSimulator
    var currentCoordinate: CLLocationCoordinate2D
    var onCoordinateChange: (CLLocationCoordinate2D) -> Void
    var onClose: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    private let joystickRadius: CGFloat = 65.0
    private let thumbRadius: CGFloat = 26.0
    
    public var body: some View {
        VStack(spacing: 12) {
            // Speed Preset Selector Bar
            HStack(spacing: 8) {
                ForEach(SpeedPreset.allCases) { preset in
                    Button(action: {
                        movementSimulator.speedPreset = preset
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 11))
                            Text("\(Int(preset.rawValue))")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            movementSimulator.speedPreset == preset ?
                            AnyView(Capsule().fill(Color.blue)) :
                            AnyView(Capsule().fill(Color.white.opacity(0.15)))
                        )
                        .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            
            // Joystick Pad
            ZStack {
                // Outer ring
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: joystickRadius * 2, height: joystickRadius * 2)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                // Direction arrows
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.6))
                    .offset(y: -joystickRadius + 10)
                
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .rotationEffect(.degrees(180))
                    .foregroundColor(.secondary.opacity(0.6))
                    .offset(y: joystickRadius - 10)
                
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .rotationEffect(.degrees(90))
                    .foregroundColor(.secondary.opacity(0.6))
                    .offset(x: joystickRadius - 10)
                
                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .rotationEffect(.degrees(-90))
                    .foregroundColor(.secondary.opacity(0.6))
                    .offset(x: -joystickRadius + 10)
                
                // Thumb Stick
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: Color.blue.opacity(0.5), radius: 8, x: 0, y: 3)
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let translation = value.translation
                                let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
                                
                                if distance <= joystickRadius {
                                    dragOffset = translation
                                } else {
                                    let angle = atan2(translation.height, translation.width)
                                    dragOffset = CGSize(
                                        width: cos(angle) * joystickRadius,
                                        height: sin(angle) * joystickRadius
                                    )
                                }
                                
                                let normalizedX = dragOffset.width / joystickRadius
                                let normalizedY = dragOffset.height / joystickRadius
                                movementSimulator.updateJoystick(x: normalizedX, y: normalizedY)
                                
                                if !movementSimulator.isMoving {
                                    movementSimulator.startJoystickMovement(from: currentCoordinate) { newCoord in
                                        onCoordinateChange(newCoord)
                                    }
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                    dragOffset = .zero
                                }
                                movementSimulator.updateJoystick(x: 0, y: 0)
                                movementSimulator.stopJoystickMovement()
                            }
                    )
            }
        }
    }
}
