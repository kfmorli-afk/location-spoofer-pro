import Foundation
import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Combine

// MARK: - App State (combines all ViewModels)

class AppState: ObservableObject {
    // Map
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.5163, longitude: 13.3777),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var selectedCoordinate = CLLocationCoordinate2D(latitude: 52.5163, longitude: 13.3777)
    @Published var addressInfo: GeocodingService.AddressInfo?
    @Published var isGeocoding = false

    // Map Options
    @Published var mapType: MKMapType = .standard
    @Published var showSearch = false

    // Search
    @Published var searchQuery = ""
    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var isSearchActive = false

    // Favorites & History
    @Published var favorites: [SavedLocation] = []
    @Published var history: [SavedLocation] = []

    // Spoofing
    @Published var isSpoofing = false
    @Published var isProcessing = false

    // Settings
    @Published var lockdownHost = "127.0.0.1"
    @Published var lockdownPort = "62078"
    @Published var showAlert = false
    @Published var alertMessage = ""

    // Services
    let simulator = LocationSimulator.shared
    let pairingService = PairingService.shared

    private let searchCompleter = MKLocalSearchCompleter()
    private var completerDelegate: CompleterDelegate?
    private var geocodeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadFavorites()
        loadSettings()

        // Listen to simulator
        simulator.$isSpoofing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSpoofing)

        // Setup search completer
        completerDelegate = CompleterDelegate(state: self)
        searchCompleter.delegate = completerDelegate
        searchCompleter.resultTypes = [.address, .pointOfInterest]

        // Geocode initial location
        updateAddress(for: selectedCoordinate)
    }

    // MARK: - Selection

    func select(coordinate: CLLocationCoordinate2D) {
        selectedCoordinate = coordinate
        withAnimation { region.center = coordinate }
        updateAddress(for: coordinate)
    }

    func updateAddress(for coordinate: CLLocationCoordinate2D) {
        isGeocoding = true
        Task {
            let info = await GeocodingService.shared.reverseGeocode(coordinate: coordinate)
            await MainActor.run {
                self.addressInfo = info
                self.isGeocoding = false
            }
        }
    }

    // MARK: - Search

    func updateSearch(_ query: String) {
        searchQuery = query
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults = []
            return
        }
        searchCompleter.queryFragment = query
    }

    func selectCompletion(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, _ in
            guard let coord = response?.mapItems.first?.placemark.coordinate else { return }
            DispatchQueue.main.async {
                self?.select(coordinate: coord)
                self?.searchQuery = ""
                self?.searchResults = []
                self?.showSearch = false
            }
        }
    }

    // MARK: - Spoof Actions

    func triggerSpoof() {
        isProcessing = true
        let coord = selectedCoordinate
        let host = lockdownHost
        let port = UInt16(lockdownPort) ?? 62078

        Task {
            do {
                try await simulator.spoof(coordinate: coord, host: host, port: port)
                await MainActor.run {
                    self.isProcessing = false
                    self.addToHistory(coord: coord)
                    let g = UINotificationFeedbackGenerator()
                    g.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                    let g = UINotificationFeedbackGenerator()
                    g.notificationOccurred(.error)
                }
            }
        }
    }

    func triggerReset() {
        let host = lockdownHost
        let port = UInt16(lockdownPort) ?? 62078
        Task {
            await simulator.reset(host: host, port: port)
        }
    }

    func testVPN() {
        let host = lockdownHost
        let port = UInt16(lockdownPort) ?? 62078
        Task {
            let ok = await simulator.testVPN(host: host, port: port)
            await MainActor.run {
                if ok {
                    self.simulator.addLog("VPN-Verbindung zu \(host):\(port) erfolgreich!", level: .success)
                } else {
                    self.simulator.addLog("Keine Verbindung zu Lockdownd. VPN aktiv?", level: .warning)
                }
            }
        }
    }

    // MARK: - Favorites

    func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: "Favorites_v1"),
           let saved = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            favorites = saved
        } else {
            favorites = SavedLocation.presets
        }
        if let data = UserDefaults.standard.data(forKey: "History_v1"),
           let saved = try? JSONDecoder().decode([SavedLocation].self, from: data) {
            history = saved
        }
    }

    func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: "Favorites_v1")
        }
    }

    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "History_v1")
        }
    }

    func addToHistory(coord: CLLocationCoordinate2D) {
        let title = addressInfo?.title ?? String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
        let sub = addressInfo?.subtitle ?? ""
        let entry = SavedLocation(title: title, subtitle: sub, latitude: coord.latitude, longitude: coord.longitude)
        history.removeAll { abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001 }
        history.insert(entry, at: 0)
        if history.count > 30 { history = Array(history.prefix(30)) }
        saveHistory()
    }

    func isFavorite(coord: CLLocationCoordinate2D) -> Bool {
        favorites.contains { abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001 }
    }

    func toggleFavorite() {
        let coord = selectedCoordinate
        if let idx = favorites.firstIndex(where: { abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001 }) {
            favorites.remove(at: idx)
        } else {
            let title = addressInfo?.title ?? "Gespeicherter Ort"
            let sub = addressInfo?.subtitle ?? ""
            favorites.insert(SavedLocation(title: title, subtitle: sub, latitude: coord.latitude, longitude: coord.longitude, isFavorite: true), at: 0)
        }
        saveFavorites()
    }

    // MARK: - Settings

    func loadSettings() {
        lockdownHost = UserDefaults.standard.string(forKey: "LockdownHost") ?? "127.0.0.1"
        lockdownPort = UserDefaults.standard.string(forKey: "LockdownPort") ?? "62078"
    }

    func saveSettings() {
        UserDefaults.standard.set(lockdownHost, forKey: "LockdownHost")
        UserDefaults.standard.set(lockdownPort, forKey: "LockdownPort")
    }

    // MARK: - Completer Delegate

    class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
        weak var state: AppState?
        init(state: AppState) { self.state = state }

        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            DispatchQueue.main.async { self.state?.searchResults = completer.results }
        }
        func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
    }
}
