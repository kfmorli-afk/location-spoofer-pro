import SwiftUI

// MARK: - Bottom Control Card

struct ControlCard: View {
    @EnvironmentObject var state: AppState
    var onFavorites: () -> Void
    var onSettings: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            // Address display
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    if state.isGeocoding {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Lade Adresse...").font(.system(size: 13)).foregroundColor(.secondary)
                        }
                    } else {
                        Text(state.addressInfo?.title ?? "Ort wählen")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(state.addressInfo?.subtitle ?? "Auf Karte tippen")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(String(format: "%.5f, %.5f", state.selectedCoordinate.latitude, state.selectedCoordinate.longitude))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Button {
                            let str = String(format: "%.6f, %.6f", state.selectedCoordinate.latitude, state.selectedCoordinate.longitude)
                            UIPasteboard.general.string = str
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(copied ? .green : .blue)
                        }
                    }
                }
                Spacer()
                Button {
                    state.toggleFavorite()
                } label: {
                    Image(systemName: state.isFavorite(coord: state.selectedCoordinate) ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(state.isFavorite(coord: state.selectedCoordinate) ? .yellow : .secondary)
                        .padding(10)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Action Buttons
            HStack(spacing: 12) {
                // Reset
                Button {
                    state.triggerReset()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Spoof
                Button {
                    state.triggerSpoof()
                } label: {
                    HStack(spacing: 8) {
                        if state.isProcessing {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: state.isSpoofing ? "checkmark.circle.fill" : "location.north.fill")
                            Text(state.isSpoofing ? "Aktiv" : "Standort fälschen")
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        LinearGradient(
                            colors: state.isSpoofing ? [.green, Color(red: 0.1, green: 0.7, blue: 0.3)] : [.blue, Color(red: 0.1, green: 0.4, blue: 0.95)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: (state.isSpoofing ? Color.green : Color.blue).opacity(0.4), radius: 10, x: 0, y: 4)
                }
                .disabled(state.isProcessing)
            }

            // Quick bar
            HStack {
                Button {
                    onFavorites()
                } label: {
                    Label("Favoriten", systemImage: "bookmark.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    onSettings()
                } label: {
                    Label("VPN & Setup", systemImage: "gearshape.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
