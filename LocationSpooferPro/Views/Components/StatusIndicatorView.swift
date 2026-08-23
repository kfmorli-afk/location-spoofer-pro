import SwiftUI

public struct StatusIndicatorView: View {
    var status: ConnectionStatus
    var isPairingValid: Bool
    var onTap: () -> Void
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(statusColor.opacity(0.5), lineWidth: 3)
                            .scaleEffect(status == .activeSpoofing ? 1.5 : 1.0)
                            .opacity(status == .activeSpoofing ? 0.8 : 0.0)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: status)
                    )
                
                Text(status.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(statusColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .activeSpoofing:
            return .green
        case .paired:
            return .blue
        case .connecting, .checkingVPN:
            return .orange
        case .disconnected:
            return isPairingValid ? .yellow : .gray
        case .error:
            return .red
        }
    }
}
