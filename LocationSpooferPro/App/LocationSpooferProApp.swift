import SwiftUI

@main
struct LocationSpooferProApp: App {
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    
    var body: some Scene {
        WindowGroup {
            MainMapView()
                .environmentObject(mapViewModel)
                .environmentObject(settingsViewModel)
                .preferredColorScheme(.dark)
        }
    }
}
