import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine

public class MapViewModel: ObservableObject {
    // MARK: - Map State
    @Published public var region: MKCoordinateRegion
    @Published public var selectedCoordinate: CLLocationCoordinate2D
    @Published public var currentAddressInfo: GeocodingService.AddressInfo?
    @Published public var isGeocoding: Bool = false
    
    // Map Display Options
    @Published public var mapType: MKMapType = .standard
    @Published public var showsTraffic: Bool = false
    @Published public var isJoystickActive: Bool = false
    
    // Favorites & History
    @Published public var favorites: [SavedLocation] = []
    @Published public var history: [SavedLocation] = []
    
    // Alerts & Notifications
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false
    @Published public var isSpoofingInProgress: Bool = false
    
    // Dependencies
    public let simulationClient = LocationSimulationClient.shared
    public let movementSimulator = MovementSimulator.shared
    private let geocodingService = GeocodingService.shared
    private let locationManager = LocationManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var geocodeDebounceTimer: Timer?
    
    public init() {
        // Default initial location: Berlin Brandenburger Tor
        let defaultCoord = CLLocationCoordinate2D(latitude: 52.5163, longitude: 13.3777)
        self.selectedCoordinate = defaultCoord
        self.region = MKCoordinateRegion(
            center: defaultCoord,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        loadFavoritesAndHistory()
        setupBindings()
        
        // Initial reverse geocode
        updateAddress(for: defaultCoord)
    }
    
    private func setupBindings() {
        // Listen to simulation client status
        simulationClient.$activeSpoofedCoordinate
            .sink { [weak self] coord in
                if let coord = coord {
                    self?.selectedCoordinate = coord
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Map Selection Actions
    
    public func selectCoordinate(_ coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        self.selectedCoordinate = coordinate
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.region.center = coordinate
            }
        } else {
            self.region.center = coordinate
        }
        
        // Debounce geocoding
        geocodeDebounceTimer?.invalidate()
        geocodeDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.updateAddress(for: coordinate)
        }
    }
    
    public func updateAddress(for coordinate: CLLocationCoordinate2D) {
        isGeocoding = true
        Task {
            let info = await geocodingService.reverseGeocode(coordinate: coordinate)
            DispatchQueue.main.async {
                self.currentAddressInfo = info
                self.isGeocoding = false
            }
        }
    }
    
    public func jumpToUserRealLocation() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        
        if let userLoc = locationManager.userLocation {
            selectCoordinate(userLoc.coordinate, animated: true)
        } else {
            // Wait slightly for location update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let userLoc = self?.locationManager.userLocation {
                    self?.selectCoordinate(userLoc.coordinate, animated: true)
                }
            }
        }
    }
    
    // MARK: - Spoofing Actions
    
    public func triggerSpoof() {
        isSpoofingInProgress = true
        let targetCoord = selectedCoordinate
        
        Task {
            do {
                try await simulationClient.spoofLocation(coordinate: targetCoord)
                
                DispatchQueue.main.async {
                    self.isSpoofingInProgress = false
                    self.addToHistory(coordinate: targetCoord, title: self.currentAddressInfo?.title ?? "Gefälschter Ort")
                    
                    // Trigger haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSpoofingInProgress = false
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                    
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
    
    public func triggerReset() {
        Task {
            do {
                try await simulationClient.resetLocation()
                DispatchQueue.main.async {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.alertMessage = "Zurücksetzen: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    // MARK: - Favorites & History Storage
    
    private func loadFavoritesAndHistory() {
        if let favData = UserDefaults.standard.data(forKey: "SavedFavorites_v1"),
           let saved = try? JSONDecoder().decode([SavedLocation].self, from: favData) {
            self.favorites = saved
        } else {
            self.favorites = SavedLocation.presets
        }
        
        if let histData = UserDefaults.standard.data(forKey: "SavedHistory_v1"),
           let hist = try? JSONDecoder().decode([SavedLocation].self, from: histData) {
            self.history = hist
        }
    }
    
    public func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: "SavedFavorites_v1")
        }
    }
    
    public func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "SavedHistory_v1")
        }
    }
    
    public func toggleFavorite(location: SavedLocation) {
        if let index = favorites.firstIndex(where: { $0.id == location.id || ($0.latitude == location.latitude && $0.longitude == location.longitude) }) {
            favorites.remove(at: index)
        } else {
            var newFav = location
            newFav.isFavorite = true
            favorites.insert(newFav, at: 0)
        }
        saveFavorites()
    }
    
    public func isCurrentlyFavorite(coordinate: CLLocationCoordinate2D) -> Bool {
        return favorites.contains(where: {
            abs($0.latitude - coordinate.latitude) < 0.0001 && abs($0.longitude - coordinate.longitude) < 0.0001
        })
    }
    
    public func addToHistory(coordinate: CLLocationCoordinate2D, title: String) {
        let entry = SavedLocation(
            title: title,
            subtitle: currentAddressInfo?.subtitle ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timestamp: Date(),
            isFavorite: false
        )
        
        // Remove duplicate if exists nearby
        history.removeAll { abs($0.latitude - coordinate.latitude) < 0.0001 && abs($0.longitude - coordinate.longitude) < 0.0001 }
        history.insert(entry, at: 0)
        
        if history.count > 40 {
            history = Array(history.prefix(40))
        }
        saveHistory()
    }
}
