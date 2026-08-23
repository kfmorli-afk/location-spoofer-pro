import SwiftUI
import MapKit

// MARK: - Search Bar Overlay

struct SearchBarOverlay: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Orte oder Adressen suchen...", text: $state.searchQuery)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onChange(of: state.searchQuery) { q in state.updateSearch(q) }
                    .onSubmit {
                        if !state.searchQuery.isEmpty {
                            state.selectCompletion(MKLocalSearchCompletion())
                        }
                    }
                if !state.searchQuery.isEmpty {
                    Button { state.searchQuery = ""; state.searchResults = []; focused = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if !state.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.searchResults, id: \.self) { result in
                            Button {
                                state.selectCompletion(result)
                                focused = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.blue)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    @EnvironmentObject var state: AppState

    var status: ConnectionStatus { state.simulator.status }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pillColor)
                .frame(width: 8, height: 8)
            Text(status.rawValue)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(pillColor.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
    }

    var pillColor: Color {
        switch status {
        case .spoofing: return .green
        case .ready: return .blue
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }
}
