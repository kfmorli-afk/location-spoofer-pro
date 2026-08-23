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
        addLog("Starte Apple Location Service auf \(host):\(port)...", level: .info)

        do {
            // Step 1: Handshake with lockdownd and request com.apple.dt.simulatelocation
            let (targetPort, _) = try await startSimulateLocationService(pairingRecord: pairing, host: host, port: port)
            addLog("Dienst com.apple.dt.simulatelocation bereit (Port: \(targetPort))", level: .info)

            // Step 2: Send GPS location coordinates to service
            try await sendLocationPacket(lat: coordinate.latitude, lon: coordinate.longitude, host: host, port: targetPort)

            DispatchQueue.main.async {
                self.isSpoofing = true
                self.spoofedCoordinate = coordinate
                self.status = .spoofing
            }
            addLog(String(format: "Standort aktiv: %.5f, %.5f", coordinate.latitude, coordinate.longitude), level: .success)
        } catch {
            DispatchQueue.main.async { self.status = .error }
            addLog("Fehler: \(error.localizedDescription)", level: .error)
            throw error
        }
    }

    func reset(host: String = "127.0.0.1", port: UInt16 = 62078) async {
        addLog("Setze Standort zurück...", level: .info)
        do {
            if let pairing = PairingService.shared.record, pairing.isValid {
                if let (targetPort, _) = try? await startSimulateLocationService(pairingRecord: pairing, host: host, port: port) {
                    try? await sendResetPacket(host: host, port: targetPort)
                } else {
                    try? await sendResetPacket(host: host, port: port)
                }
            } else {
                try? await sendResetPacket(host: host, port: port)
            }
        }
        DispatchQueue.main.async {
            self.isSpoofing = false
            self.spoofedCoordinate = nil
            self.status = .disconnected
        }
        addLog("Standort auf echten GPS-Standort zurückgesetzt.", level: .success)
    }

    // MARK: - Lockdownd Handshake & Service Start

    private func startSimulateLocationService(pairingRecord: PairingRecord, host: String, port: UInt16) async throws -> (port: UInt16, enableSSL: Bool) {
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

            func finishWithSuccess(targetPort: UInt16, ssl: Bool) {
                if gate.claim() {
                    conn.cancel()
                    continuation.resume(returning: (targetPort, ssl))
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // 1. QueryType
                    let queryDict: [String: Any] = ["Request": "QueryType"]
                    self.sendPlist(queryDict, over: conn) { err in
                        if let err = err {
                            finishWithError(err)
                            return
                        }
                        self.receivePlist(over: conn) { res in
                            // 2. StartSession
                            let hostID = pairingRecord.hostID ?? UUID().uuidString
                            var sessionDict: [String: Any] = [
                                "Request": "StartSession",
                                "HostID": hostID
                            ]
                            if let buid = pairingRecord.systemBUID, !buid.isEmpty {
                                sessionDict["SystemBUID"] = buid
                            }

                            self.sendPlist(sessionDict, over: conn) { sErr in
                                if let sErr = sErr {
                                    finishWithError(sErr)
                                    return
                                }
                                self.receivePlist(over: conn) { sessRes in
                                    // 3. Start com.apple.dt.simulatelocation service
                                    let serviceDict: [String: Any] = [
                                        "Request": "StartService",
                                        "Service": "com.apple.dt.simulatelocation"
                                    ]
                                    self.sendPlist(serviceDict, over: conn) { servErr in
                                        if let servErr = servErr {
                                            finishWithError(servErr)
                                            return
                                        }
                                        self.receivePlist(over: conn) { startRes in
                                            switch startRes {
                                            case .success(let dict):
                                                if let servPort = dict["Port"] as? Int {
                                                    let ssl = (dict["EnableServiceSSL"] as? Bool) ?? false
                                                    finishWithSuccess(targetPort: UInt16(servPort), ssl: ssl)
                                                } else if let errorMsg = dict["Error"] as? String {
                                                    let customErr = NSError(domain: "Lockdownd", code: -2, userInfo: [NSLocalizedDescriptionKey: "Dienst-Fehler: \(errorMsg)"])
                                                    finishWithError(customErr)
                                                } else {
                                                    // Fallback directly to lockdownd port
                                                    finishWithSuccess(targetPort: port, ssl: false)
                                                }
                                            case .failure(_):
                                                // Fallback port
                                                finishWithSuccess(targetPort: port, ssl: false)
                                            }
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
                let timeoutErr = NSError(domain: "Lockdownd", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lockdownd Timeout auf \(host):\(port)"])
                finishWithError(timeoutErr)
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
                let err = NSError(domain: "Lockdownd", code: -3, userInfo: [NSLocalizedDescriptionKey: "Ungültige Antwortlänge"])
                completion(.failure(err))
                return
            }

            let length = UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
            guard length > 0, length < 1_000_000 else {
                let err = NSError(domain: "Lockdownd", code: -4, userInfo: [NSLocalizedDescriptionKey: "Ungültige Paketgröße"])
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
                        let err = NSError(domain: "Lockdownd", code: -6, userInfo: [NSLocalizedDescriptionKey: "Plist konnte nicht dekodiert werden"])
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
