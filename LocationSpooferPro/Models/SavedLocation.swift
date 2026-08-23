import Foundation
import CoreLocation

public struct SavedLocation: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var timestamp: Date
    public var isFavorite: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        latitude: Double,
        longitude: Double,
        altitude: Double = 0.0,
        timestamp: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public var formattedCoordinates: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }
}

// Preset popular locations for quick testing
extension SavedLocation {
    public static let presets: [SavedLocation] = [
        SavedLocation(
            title: "Eiffelturm",
            subtitle: "Paris, Frankreich",
            latitude: 48.8584,
            longitude: 2.2945,
            isFavorite: true
        ),
        SavedLocation(
            title: "Times Square",
            subtitle: "New York, USA",
            latitude: 40.7580,
            longitude: -73.9855,
            isFavorite: true
        ),
        SavedLocation(
            title: "Shibuya Crossing",
            subtitle: "Tokio, Japan",
            latitude: 35.6595,
            longitude: 139.7005,
            isFavorite: true
        ),
        SavedLocation(
            title: "Brandenburger Tor",
            subtitle: "Berlin, Deutschland",
            latitude: 52.5163,
            longitude: 13.3777,
            isFavorite: true
        ),
        SavedLocation(
            title: "Big Ben",
            subtitle: "London, UK",
            latitude: 51.5007,
            longitude: -0.1246,
            isFavorite: true
        ),
        SavedLocation(
            title: "Burj Khalifa",
            subtitle: "Dubai, VAE",
            latitude: 25.1972,
            longitude: 55.2744,
            isFavorite: true
        ),
        SavedLocation(
            title: "Sydney Opera House",
            subtitle: "Sydney, Australien",
            latitude: -33.8568,
            longitude: 151.2153,
            isFavorite: true
        )
    ]
}
