import SwiftUI
import CoreLocation

public struct LocationControlCard: View {
    @EnvironmentObject var mapViewModel: MapViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var onSpoof: () -> Void
    var onReset: () -> Void
    var onToggleFavorites: () -> Void
    var onToggleSettings: () -> Void
    var onToggleJoystick: () -> Void
    
    @State private var isCopied: Bool = false
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header: Address and Quick Icons
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if mapViewModel.isGeocoding {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Lade Adresse...")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    } else if let info = mapViewModel.currentAddressInfo {
                        Text(info.title)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if !info.subtitle.isEmpty {
                            Text(info.subtitle)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // Coordinates Subtext
                    HStack(spacing: 8) {
                        Text(String(format: "LAT: %.6f  LON: %.6f", mapViewModel.selectedCoordinate.latitude, mapViewModel.selectedCoordinate.longitude))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Button(action: copyCoordinates) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(isCopied ? .green : .blue)
                        }
                    }
                    .padding(.top, 2)
                }
                
                Spacer()
                
                // Favorite Button
                Button(action: toggleFavorite) {
                    Image(systemName: mapViewModel.isCurrentlyFavorite(coordinate: mapViewModel.selectedCoordinate) ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(mapViewModel.isCurrentlyFavorite(coordinate: mapViewModel.selectedCoordinate) ? .yellow : .secondary)
                        .padding(10)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Action Buttons Row
            HStack(spacing: 12) {
                // Reset Button
                Button(action: onReset) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Reset")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                
                // Spoof Button (Primary)
                Button(action: onSpoof) {
                    HStack(spacing: 8) {
                        if mapViewModel.isSpoofingInProgress {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: mapViewModel.simulationClient.isSpoofingActive ? "checkmark.circle.fill" : "location.north.fill")
                                .font(.system(size: 17, weight: .bold))
                            
                            Text(mapViewModel.simulationClient.isSpoofingActive ? "Standort Aktiv" : "Standort Fälschen")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: mapViewModel.simulationClient.isSpoofingActive ?
                                [Color.green, Color(red: 0.1, green: 0.7, blue: 0.3)] :
                                [Color.blue, Color(red: 0.1, green: 0.4, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(
                        color: mapViewModel.simulationClient.isSpoofingActive ? Color.green.opacity(0.4) : Color.blue.opacity(0.4),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                }
                .disabled(mapViewModel.isSpoofingInProgress)
            }
            
            // Bottom Quick Feature Bar
            HStack(spacing: 18) {
                // Joystick Mode
                Button(action: onToggleJoystick) {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14))
                        Text("Joystick")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(mapViewModel.isJoystickActive ? .cyan : .secondary)
                }
                
                Spacer()
                
                // Favorites List
                Button(action: onToggleFavorites) {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 14))
                        Text("Favoriten")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Settings
                Button(action: onToggleSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                        Text("VPN & Setup")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.35), radius: 25, x: 0, y: -5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func copyCoordinates() {
        let coordStr = String(format: "%.6f, %.6f", mapViewModel.selectedCoordinate.latitude, mapViewModel.selectedCoordinate.longitude)
        UIPasteboard.general.string = coordStr
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
    }
    
    private func toggleFavorite() {
        let title = mapViewModel.currentAddressInfo?.title ?? "Gespeicherter Ort"
        let subtitle = mapViewModel.currentAddressInfo?.subtitle ?? ""
        let location = SavedLocation(
            title: title,
            subtitle: subtitle,
            latitude: mapViewModel.selectedCoordinate.latitude,
            longitude: mapViewModel.selectedCoordinate.longitude,
            isFavorite: true
        )
        mapViewModel.toggleFavorite(location: location)
    }
}
