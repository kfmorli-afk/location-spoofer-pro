import Foundation
import CoreLocation
import MapKit
import Network

/// Synchronizes callbacks that race to finish the same Swift continuation.
private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

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

    private init() { addLog("Location Spoofer Pro bereit", level: .info) }

    func addLog(_ msg: String, level: LogEntry.Level = .info) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(message: msg, level: level))
            if self.logs.count > 300 { self.logs.removeFirst() }
        }
    }

    func clearLogs() { DispatchQueue.main.async { self.logs.removeAll() } }

    // MARK: - Spoof Action

    func spoof(coordinate: CLLocationCoordinate2D, host: String = "127.0.0.1", port: UInt16 = 62078) async throws {
        guard let pairing = PairingService.shared.record, pairing.isValid else {
            DispatchQueue.main.async { self.status = .error }
            addLog("Fehler: Keine gültige Pairing-Datei!", level: .error)
            throw PairingError.missingCredentials
        }

        DispatchQueue.main.async { self.status = .connecting }
        addLog("Starte Verbindung zu \(host):\(port)...", level: .info)

        do {
            // Step 1: Start Location Service via Lockdownd
            let targetPort = try await acquireLocationServicePort(pairingRecord: pairing, host: host, port: port)
            addLog("Standortdienst bereit auf Port \(targetPort)", level: .success)

            // Step 2: Inject GPS Coordinates
            addLog(String(format: "Sende GPS: %.5f, %.5f...", coordinate.latitude, coordinate.longitude), level: .info)
            try await sendLocationPacket(lat: coordinate.latitude, lon: coordinate.longitude, host: host, port: targetPort)

            DispatchQueue.main.async {
                self.isSpoofing = true
                self.spoofedCoordinate = coordinate
                self.status = .spoofing
            }
            addLog("Standort erfolgreich systemweit aktiviert! 📍", level: .success)
        } catch {
            DispatchQueue.main.async { self.status = .error }
            addLog("Fehler beim Spoofing: \(error.localizedDescription)", level: .error)
            throw error
        }
    }

    func reset(host: String = "127.0.0.1", port: UInt16 = 62078) async {
        addLog("Setze Standort auf echtes GPS zurück...", level: .info)
        do {
            if let pairing = PairingService.shared.record, pairing.isValid {
                let targetPort = (try? await acquireLocationServicePort(pairingRecord: pairing, host: host, port: port)) ?? port
                try await sendResetPacket(host: host, port: targetPort)
            } else {
                try await sendResetPacket(host: host, port: port)
            }
            addLog("Standort erfolgreich zurückgesetzt.", level: .success)
        } catch {
            addLog("Hinweis beim Reset: \(error.localizedDescription)", level: .warning)
        }
        DispatchQueue.main.async {
            self.isSpoofing = false
            self.spoofedCoordinate = nil
            self.status = .disconnected
        }
    }

    // MARK: - Acquire Location Service Port

    private func acquireLocationServicePort(pairingRecord: PairingRecord, host: String, port: UInt16) async throws -> UInt16 {
        return try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let gate = ContinuationGate()

            func finishWithError(_ err: Error) {
                if gate.claim() {
                    conn.cancel()
                    continuation.resume(throwing: err)
                }
            }

            func finishWithSuccess(targetPort: UInt16) {
                if gate.claim() {
                    conn.cancel()
                    continuation.resume(returning: targetPort)
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.addLog("Verbunden mit Lockdownd", level: .info)
                    // Step 1: QueryType
                    let queryDict: [String: Any] = ["Request": "QueryType"]
                    self.sendPlist(queryDict, over: conn) { qErr in
                        if let qErr = qErr {
                            finishWithError(qErr)
                            return
                        }
                        self.receivePlist(over: conn) { qRes in
                            switch qRes {
                            case .failure(let err):
                                finishWithError(err)
                            case .success(let typeDict):
                                self.addLog("Lockdownd Typ: \(typeDict["Type"] as? String ?? "OK")", level: .info)

                                // Step 2: Request StartService for com.apple.dt.simulatelocation
                                let startServiceDict: [String: Any] = [
                                    "Request": "StartService",
                                    "Service": "com.apple.dt.simulatelocation"
                                ]
                                self.sendPlist(startServiceDict, over: conn) { sErr in
                                    if let sErr = sErr {
                                        finishWithError(sErr)
                                        return
                                    }
                                    self.receivePlist(over: conn) { sRes in
                                        switch sRes {
                                        case .success(let servDict):
                                            if let servPort = servDict["Port"] as? Int {
                                                finishWithSuccess(targetPort: UInt16(servPort))
                                            } else if let errorMsg = servDict["Error"] as? String {
                                                self.addLog("Lockdownd Antwort: \(errorMsg)", level: .warning)
                                                if errorMsg.contains("PasswordProtected") {
                                                    let err = NSError(domain: "Lockdownd", code: -10, userInfo: [NSLocalizedDescriptionKey: "iPhone ist gesperrt. Bitte entsperren!"])
                                                    finishWithError(err)
                                                } else {
                                                    // Fallback to default port
                                                    finishWithSuccess(targetPort: port)
                                                }
                                            } else {
                                                finishWithSuccess(targetPort: port)
                                            }
                                        case .failure(_):
                                            // Direct fallback
                                            finishWithSuccess(targetPort: port)
                                        }
                                    }
                                }
                            }
                        }
                    }
                case .failed(let err):
                    finishWithError(err)
                default: break
                }
            }

            conn.start(queue: self.queue)

            self.queue.asyncAfter(deadline: .now() + 8) {
                let err = NSError(domain: "Lockdownd", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout bei Verbindung zu \(host):\(port)"])
                finishWithError(err)
            }
        }
    }

    // MARK: - Plist Wire Transport

    private func sendPlist(_ dict: [String: Any], over connection: NWConnection, completion: @escaping (Error?) -> Void) {
        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            var length = UInt32(plistData.count).bigEndian
            var packet = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            packet.append(plistData)

            connection.send(content: packet, completion: .contentProcessed { error in
                completion(error)
            })
        } catch {
            completion(error)
        }
    }

    private func receivePlist(over connection: NWConnection, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { content, _, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = content, data.count == 4 else {
                let err = NSError(domain: "Lockdownd", code: -3, userInfo: [NSLocalizedDescriptionKey: "Ungültige Header-Größe"])
                completion(.failure(err))
                return
            }

            let length = UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
            guard length > 0, length < 1_000_000 else {
                let err = NSError(domain: "Lockdownd", code: -4, userInfo: [NSLocalizedDescriptionKey: "Ungültige Payload-Größe (\(length))"])
                completion(.failure(err))
                return
            }

            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { payload, _, _, pError in
                if let pError = pError {
                    completion(.failure(pError))
                    return
                }
                guard let pData = payload else {
                    let err = NSError(domain: "Lockdownd", code: -5, userInfo: [NSLocalizedDescriptionKey: "Keine Daten empfangen"])
                    completion(.failure(err))
                    return
                }

                do {
                    if let dict = try PropertyListSerialization.propertyList(from: pData, options: [], format: nil) as? [String: Any] {
                        completion(.success(dict))
                    } else {
                        let err = NSError(domain: "Lockdownd", code: -6, userInfo: [NSLocalizedDescriptionKey: "Plist konnte nicht geparst werden"])
                        completion(.failure(err))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Binary Location Protocol

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
            let gate = ContinuationGate()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: packet, completion: .contentProcessed { err in
                        conn.cancel()
                        if gate.claim() {
                            if let err = err { continuation.resume(throwing: err) }
                            else { continuation.resume() }
                        }
                    })
                case .failed(let err):
                    if gate.claim() { conn.cancel(); continuation.resume(throwing: err) }
                default: break
                }
            }
            conn.start(queue: self.queue)

            self.queue.asyncAfter(deadline: .now() + 6) {
                if gate.claim() {
                    conn.cancel()
                    let err = NSError(domain: "Timeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keine Antwort vom Standort-Dienst auf \(host):\(port)"])
                    continuation.resume(throwing: err)
                }
            }
        }
    }

    // MARK: - VPN Test

    func testVPN(host: String = "127.0.0.1", port: UInt16 = 62078) async -> Bool {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let gate = ContinuationGate()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.claim() { conn.cancel(); continuation.resume(returning: true) }
                case .failed:
                    if gate.claim() { conn.cancel(); continuation.resume(returning: false) }
                case .cancelled:
                    if gate.claim() { continuation.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 3) {
                if gate.claim() { conn.cancel(); continuation.resume(returning: false) }
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
