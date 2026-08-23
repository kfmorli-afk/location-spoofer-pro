import Foundation
import CoreLocation

public enum ConnectionStatus: String, Codable {
    case disconnected = "Nicht verbunden"
    case checkingVPN = "Prüfe Local Dev VPN..."
    case connecting = "Verbinde mit Lockdownd..."
    case paired = "Verbunden & Bereit"
    case activeSpoofing = "Standort aktiv gefälscht"
    case error = "Fehler"
    
    public var iconName: String {
        switch self {
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .checkingVPN: return "arrow.triangle.2.circlepath"
        case .connecting: return "bolt.horizontal.circle"
        case .paired: return "checkmark.shield.fill"
        case .activeSpoofing: return "location.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

public enum SpeedPreset: Double, CaseIterable, Identifiable {
    case walk = 5.0     // 5 km/h
    case jog = 12.0     // 12 km/h
    case cycle = 25.0   // 25 km/h
    case car = 60.0     // 60 km/h
    case fast = 120.0   // 120 km/h
    
    public var id: Double { self.rawValue }
    
    public var title: String {
        switch self {
        case .walk: return "Gehen (5 km/h)"
        case .jog: return "Joggen (12 km/h)"
        case .cycle: return "Fahrrad (25 km/h)"
        case .car: return "Auto (60 km/h)"
        case .fast: return "Schnell (120 km/h)"
        }
    }
    
    public var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .jog: return "figure.run"
        case .cycle: return "bicycle"
        case .car: return "car.fill"
        case .fast: return "bolt.car.fill"
        }
    }
    
    /// Speed in meters per second
    public var metersPerSecond: Double {
        return (rawValue * 1000.0) / 3600.0
    }
}

public struct LogEntry: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var message: String
    public var type: LogType
    
    public enum LogType: String, Codable {
        case info = "INFO"
        case success = "SUCCESS"
        case warning = "WARN"
        case error = "ERROR"
        case packet = "DATA"
    }
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}
