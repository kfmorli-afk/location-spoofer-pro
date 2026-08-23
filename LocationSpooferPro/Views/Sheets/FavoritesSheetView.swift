import SwiftUI
import CoreLocation

public struct FavoritesSheetView: View {
    @EnvironmentObject var mapViewModel: MapViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab: Int = 0 // 0 = Favoriten, 1 = Verlauf, 2 = Welt-Highlights
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Segmented Picker
                Picker("Ansicht", selection: $selectedTab) {
                    Text("Favoriten").tag(0)
                    Text("Highlights").tag(2)
                    Text("Verlauf").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if selectedTab == 0 {
                    // User Saved Favorites
                    if mapViewModel.favorites.isEmpty {
                        emptyStateView(
                            icon: "star.slash",
                            title: "Keine Favoriten gespeichert",
                            message: "Tippe auf den Stern auf der Karte, um deine Lieblingsorte zu speichern."
                        )
                    } else {
                        List {
                            ForEach(mapViewModel.favorites) { fav in
                                locationRow(fav)
                            }
                            .onDelete(perform: deleteFavorite)
                        }
                        .listStyle(InsetGroupedListStyle())
                    }
                } else if selectedTab == 1 {
                    // History
                    if mapViewModel.history.isEmpty {
                        emptyStateView(
                            icon: "clock.arrow.circlepath",
                            title: "Kein Verlauf vorhanden",
                            message: "Gefälschte Standorte werden hier automatisch aufgelistet."
                        )
                    } else {
                        List {
                            ForEach(mapViewModel.history) { hist in
                                locationRow(hist)
                            }
                            .onDelete(perform: deleteHistory)
                        }
                        .listStyle(InsetGroupedListStyle())
                    }
                } else {
                    // Presets / Highlights
                    List {
                        ForEach(SavedLocation.presets) { preset in
                            locationRow(preset)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Gespeicherte Orte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func locationRow(_ item: SavedLocation) -> some View {
        Button(action: {
            mapViewModel.selectCoordinate(item.coordinate, animated: true)
            dismiss()
        }) {
            HStack(spacing: 14) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(item.formattedCoordinates)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
    }
    
    private func deleteFavorite(at offsets: IndexSet) {
        mapViewModel.favorites.remove(atOffsets: offsets)
        mapViewModel.saveFavorites()
    }
    
    private func deleteHistory(at offsets: IndexSet) {
        mapViewModel.history.remove(atOffsets: offsets)
        mapViewModel.saveHistory()
    }
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
