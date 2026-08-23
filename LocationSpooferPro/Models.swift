import Foundation
import CoreLocation

// MARK: - Saved Location

struct SavedLocation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var isFavorite: Bool = false
    var timestamp: Date = Date()

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var formattedCoordinates: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    static let presets: [SavedLocation] = [
        SavedLocation(title: "Eiffelturm", subtitle: "Paris, Frankreich", latitude: 48.8584, longitude: 2.2945, isFavorite: true),
        SavedLocation(title: "Times Square", subtitle: "New York, USA", latitude: 40.7580, longitude: -73.9855, isFavorite: true),
        SavedLocation(title: "Brandenburger Tor", subtitle: "Berlin, Deutschland", latitude: 52.5163, longitude: 13.3777, isFavorite: true),
        SavedLocation(title: "Shibuya Crossing", subtitle: "Tokio, Japan", latitude: 35.6595, longitude: 139.7005, isFavorite: true),
        SavedLocation(title: "Big Ben", subtitle: "London, UK", latitude: 51.5007, longitude: -0.1246, isFavorite: true),
        SavedLocation(title: "Burj Khalifa", subtitle: "Dubai, VAE", latitude: 25.1972, longitude: 55.2744, isFavorite: true),
        SavedLocation(title: "Kolosseum", subtitle: "Rom, Italien", latitude: 41.8902, longitude: 12.4924, isFavorite: true),
    ]
}

// MARK: - Pairing Record

struct PairingRecord: Codable, Equatable {
    var udid: String
    var hostID: String?
    var systemBUID: String?
    var hostCertificateData: Data?
    var hostPrivateKeyData: Data?
    var rootCertificateData: Data?
    var deviceCertificateData: Data?
    var fileName: String
    var importedAt: Date = Date()

    var isValid: Bool {
        return hostCertificateData != nil && hostPrivateKeyData != nil
    }

    var summary: String {
        guard !udid.isEmpty else { return "Gekoppelt (Zertifikate aktiv)" }
        let short = udid.count > 12 ? "\(udid.prefix(8))…\(udid.suffix(4))" : udid
        return "UDID: \(short)"
    }

    static func parse(from data: Data, fileName: String) throws -> PairingRecord {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw PairingError.invalidFormat
        }
        var udid = (plist["UDID"] as? String) ?? (plist["DeviceUDID"] as? String) ?? ""
        if udid.isEmpty {
            let rawName = (fileName as NSString).deletingPathExtension
            if rawName.count >= 16 {
                udid = rawName
            } else if let hostID = plist["HostID"] as? String {
                udid = hostID
            } else {
                udid = "iPhone-Zertifikat"
            }
        }
        return PairingRecord(
            udid: udid,
            hostID: plist["HostID"] as? String,
            systemBUID: plist["SystemBUID"] as? String,
            hostCertificateData: plist["HostCertificate"] as? Data,
            hostPrivateKeyData: plist["HostPrivateKey"] as? Data,
            rootCertificateData: plist["RootCertificate"] as? Data,
            deviceCertificateData: plist["DeviceCertificate"] as? Data,
            fileName: fileName
        )
    }
}

enum PairingError: LocalizedError {
    case invalidFormat, missingCredentials

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Keine gültige Apple Pairing-Datei."
        case .missingCredentials: return "Datei enthält keine Zertifikate."
        }
    }
}

// MARK: - Connection Status

enum ConnectionStatus: String {
    case disconnected = "Nicht verbunden"
    case connecting = "Verbinde..."
    case ready = "Bereit"
    case spoofing = "Standort aktiv"
    case error = "Fehler"

    var color: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "orange"
        case .ready: return "blue"
        case .spoofing: return "green"
        case .error: return "red"
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var message: String
    var level: Level

    enum Level: String {
        case info = "INFO"
        case success = "OK"
        case warning = "WARN"
        case error = "ERROR"
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}
