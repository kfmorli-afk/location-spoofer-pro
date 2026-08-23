import Foundation
import CoreLocation
import MapKit

public class GeocodingService {
    public static let shared = GeocodingService()
    
    private let geocoder = CLGeocoder()
    private var lastGeocodeTime: Date = .distantPast
    
    private init() {}
    
    public struct AddressInfo {
        public var title: String
        public var subtitle: String
        public var country: String
        public var postalCode: String
        public var city: String
        public var street: String
        
        public var fullDescription: String {
            if street.isEmpty && city.isEmpty {
                return title
            }
            if street.isEmpty {
                return "\(city), \(country)"
            }
            return "\(street), \(city), \(country)"
        }
    }
    
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> AddressInfo {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return fallbackAddress(for: coordinate)
            }
            
            let name = placemark.name ?? ""
            let street = placemark.thoroughfare ?? ""
            let streetNumber = placemark.subThoroughfare ?? ""
            let city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
            let postalCode = placemark.postalCode ?? ""
            let country = placemark.country ?? ""
            
            let fullStreet = [street, streetNumber].filter { !$0.isEmpty }.joined(separator: " ")
            let title = !name.isEmpty ? name : (!fullStreet.isEmpty ? fullStreet : (!city.isEmpty ? city : "Ausgewählter Ort"))
            let subtitle = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
            
            return AddressInfo(
                title: title,
                subtitle: subtitle,
                country: country,
                postalCode: postalCode,
                city: city,
                street: fullStreet
            )
        } catch {
            return fallbackAddress(for: coordinate)
        }
    }
    
    private func fallbackAddress(for coordinate: CLLocationCoordinate2D) -> AddressInfo {
        let latStr = String(format: "%.4f°", coordinate.latitude)
        let lonStr = String(format: "%.4f°", coordinate.longitude)
        return AddressInfo(
            title: "\(latStr), \(lonStr)",
            subtitle: "Keine Adressdaten verfügbar",
            country: "",
            postalCode: "",
            city: "",
            street: ""
        )
    }
    
    public func search(query: String, region: MKCoordinateRegion? = nil) async throws -> [MKMapItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = region {
            request.region = region
        }
        
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }
}
