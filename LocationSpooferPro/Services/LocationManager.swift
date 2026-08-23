import Foundation
import CoreLocation
import Combine

public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    
    @Published public var userLocation: CLLocation?
    @Published public var userHeading: CLHeading?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isLocatingUser: Bool = false
    
    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        self.authorizationStatus = locationManager.authorizationStatus
    }
    
    public func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    public func startUpdating() {
        isLocatingUser = true
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    public func stopUpdating() {
        isLocatingUser = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        self.userLocation = latest
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.userHeading = newHeading
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Fehler beim Abrufen des echten Standorts: \(error.localizedDescription)")
    }
}
