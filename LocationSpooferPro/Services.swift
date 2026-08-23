import Foundation
import CoreLocation
import MapKit
import Network

// MARK: - Pairing Service

class PairingService: ObservableObject {
    static let shared = PairingService()
    private let key = "PairingRecord_v2"

    @Published var record: PairingRecord?
    @Published var hasValidRecord: Bool = false

    private init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let r = try? JSONDecoder().decode(PairingRecord.self, from: data) else { return }
        record = r
        hasValidRecord = r.isValid
    }

    func importFrom(data: Data, fileName: String) throws {
        let r = try PairingRecord.parse(from: data, fileName: fileName)
        guard r.isValid else { throw PairingError.missingCredentials }
        let encoded = try JSONEncoder().encode(r)
        UserDefaults.standard.set(encoded, forKey: key)
        DispatchQueue.main.async {
            self.record = r
            self.hasValidRecord = true
        }
    }

    func remove() {
        UserDefaults.standard.removeObject(forKey: key)
        record = nil
        hasValidRecord = false
    }
}

// MARK: - Location Simulation Service

class LocationSimulator: ObservableObject {
    static let shared = LocationSimulator()

    @Published var isSpoofing: Bool = false
    @Published var spoofedCoordinate: CLLocationCoordinate2D?
    @Published var status: ConnectionStatus = .disconnected
    @Published var logs: [LogEntry] = []

    private let queue = DispatchQueue(label: "pro.spoofer.sim", qos: .userInitiated)

    private init() { addLog("Location Spoofer Pro gestartet", level: .info) }

    func addLog(_ msg: String, level: LogEntry.Level = .info) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(message: msg, level: level))
            if self.logs.count > 200 { self.logs.removeFirst() }
        }
    }

    func clearLogs() { DispatchQueue.main.async { self.logs.removeAll() } }

    // MARK: Spoof

    func spoof(coordinate: CLLocationCoordinate2D, host: String = "127.0.0.1", port: UInt16 = 62078) async throws {
        guard let pairing = PairingService.shared.record, pairing.isValid else {
            DispatchQueue.main.async { self.status = .error }
            addLog("Fehler: Keine Pairing-Datei!", level: .error)
            throw PairingError.missingCredentials
        }

        DispatchQueue.main.async { self.status = .connecting }
        addLog("Verbinde mit Lockdownd \(host):\(port)...", level: .info)

        // Send the binary location packet
        try await sendLocationPacket(lat: coordinate.latitude, lon: coordinate.longitude, host: host, port: port)

        DispatchQueue.main.async {
            self.isSpoofing = true
            self.spoofedCoordinate = coordinate
            self.status = .spoofing
        }
        addLog(String(format: "Standort gesetzt: %.5f, %.5f", coordinate.latitude, coordinate.longitude), level: .success)
    }

    func reset(host: String = "127.0.0.1", port: UInt16 = 62078) async {
        addLog("Setze Standort zurück...", level: .info)
        try? await sendResetPacket(host: host, port: port)
        DispatchQueue.main.async {
            self.isSpoofing = false
            self.spoofedCoordinate = nil
            self.status = .disconnected
        }
        addLog("Standort zurückgesetzt.", level: .success)
    }

    // MARK: Binary Protocol

    private func sendLocationPacket(lat: Double, lon: Double, host: String, port: UInt16) async throws {
        let latStr = String(format: "%.8f", lat)
        let lonStr = String(format: "%.8f", lon)
        guard let latData = latStr.data(using: .utf8),
              let lonData = lonStr.data(using: .utf8) else { return }

        var packet = Data()
        var cmd: UInt32 = UInt32(1).bigEndian
        packet.append(Data(bytes: &cmd, count: 4))
        var latLen: UInt32 = UInt32(latData.count).bigEndian
        packet.append(Data(bytes: &latLen, count: 4))
        packet.append(latData)
        var lonLen: UInt32 = UInt32(lonData.count).bigEndian
        packet.append(Data(bytes: &lonLen, count: 4))
        packet.append(lonData)

        try await sendPacket(packet, host: host, port: port)
    }

    private func sendResetPacket(host: String, port: UInt16) async throws {
        var cmd: UInt32 = UInt32(0).bigEndian
        let packet = Data(bytes: &cmd, count: 4)
        try await sendPacket(packet, host: host, port: port)
    }

    private func sendPacket(_ packet: Data, host: String, port: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            var resumed = false

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: packet, completion: .contentProcessed { err in
                        conn.cancel()
                        if !resumed {
                            resumed = true
                            if let err = err { continuation.resume(throwing: err) }
                            else { continuation.resume() }
                        }
                    })
                case .failed(let err):
                    if !resumed { resumed = true; conn.cancel(); continuation.resume(throwing: err) }
                default: break
                }
            }
            conn.start(queue: self.queue)

            self.queue.asyncAfter(deadline: .now() + 6) {
                if !resumed {
                    resumed = true
                    conn.cancel()
                    let err = NSError(domain: "Timeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "Verbindung zu Lockdownd abgelaufen"])
                    continuation.resume(throwing: err)
                }
            }
        }
    }

    // MARK: VPN Test

    func testVPN(host: String = "127.0.0.1", port: UInt16 = 62078) async -> Bool {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            var resumed = false
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; conn.cancel(); continuation.resume(returning: true) }
                case .failed:
                    if !resumed { resumed = true; conn.cancel(); continuation.resume(returning: false) }
                case .cancelled:
                    if !resumed { resumed = true; continuation.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 3) {
                if !resumed { resumed = true; conn.cancel(); continuation.resume(returning: false) }
            }
        }
    }
}

// MARK: - Geocoding Service

class GeocodingService {
    static let shared = GeocodingService()
    private let geocoder = CLGeocoder()

    struct AddressInfo {
        var title: String
        var subtitle: String
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> AddressInfo {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let p = placemarks.first {
                let name = p.name ?? p.thoroughfare ?? String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
                let sub = [p.locality, p.country].compactMap { $0 }.joined(separator: ", ")
                return AddressInfo(title: name, subtitle: sub)
            }
        } catch {}
        return AddressInfo(
            title: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
            subtitle: "Keine Adresse verfügbar"
        )
    }
}
