import Foundation
import CoreLocation
import MapKit
import Network
import Security

/// Thread-safe gate ensuring a continuation is resumed exactly once.
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
    private var activeConnection: NWConnection?
    private var heartbeatTimer: DispatchSourceTimer?
    private var currentHost: String = "10.7.0.1"
    private var currentPort: UInt16 = 62078

    private init() { addLog("Location Spoofer Pro bereit", level: .info) }

    func addLog(_ msg: String, level: LogEntry.Level = .info) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(message: msg, level: level))
            if self.logs.count > 400 { self.logs.removeFirst() }
        }
    }

    func clearLogs() { DispatchQueue.main.async { self.logs.removeAll() } }

    // MARK: - Main Spoof Workflow (Auto-Discovery + Keep-Alive Stream)

    func spoof(coordinate: CLLocationCoordinate2D, host: String = "10.7.0.1", port: UInt16 = 62078) async throws {
        guard let pairing = PairingService.shared.record, pairing.isValid else {
            DispatchQueue.main.async { self.status = .error }
            addLog("Fehler: Keine gültige Pairing-Datei!", level: .error)
            throw PairingError.missingCredentials
        }

        stopHeartbeat()
        closeActiveConnection()

        DispatchQueue.main.async { self.status = .connecting }
        addLog(String(format: "Zielkoordinaten: %.5f, %.5f", coordinate.latitude, coordinate.longitude), level: .info)

        // Step 1: Discover Active Lockdownd Host IP
        var candidateHosts = [host, "10.7.0.2", "172.20.10.1", "127.0.0.1", "10.7.0.1", "::1", "localhost"]
        candidateHosts.append(contentsOf: getLocalIPAddresses())
        candidateHosts = Array(Set(candidateHosts)) // Deduplicate
        var workingHost: String?

        addLog("▶ Suche aktiven Lockdownd-Kanal (WLAN/Hotspot erforderlich)...", level: .info)
        for candidate in candidateHosts {
            if await probeLockdownd(host: candidate, port: port) {
                workingHost = candidate
                addLog("✅ Lockdownd antwortet auf \(candidate):\(port)", level: .success)
                break
            }
        }

        let effectiveHost = workingHost ?? host
        if workingHost == nil {
            addLog("❌ Kein Lockdownd-QueryType auf Standard-IPs möglich.", level: .error)
            addLog("⚠️ WICHTIG: Der Apple-Dienst ist blockiert. Du musst KEINEN Port in iTunes eingeben! Setze in iTunes einfach nur den Haken bei 'Mit diesem iPhone über WLAN synchronisieren'.", level: .warning)
            addLog("💡 LTE/5G TRICK: Schalte 'Persönlicher Hotspot' ein! Dadurch wird der Dienst auch ohne WLAN-Netzwerk aktiviert.", level: .warning)
        }

        self.currentHost = effectiveHost
        self.currentPort = port

        var resolvedPort: UInt16 = port

        // Step 2: Apple Lockdownd Handshake & ValidatePairing
        addLog("▶ Starte Apple Dienst com.apple.dt.simulatelocation...", level: .info)
        do {
            let targetPort = try await startLocationServiceWithValidation(pairing: pairing, host: effectiveHost, port: port)
            addLog("✅ Dienst bereit auf Port \(targetPort)", level: .success)
            resolvedPort = targetPort
        } catch {
            let errMsg = error.localizedDescription
            addLog("Handshake Info: \(errMsg)", level: .warning)
            if errMsg.contains("54") || errMsg.contains("Connection reset by peer") {
                addLog("💡 LÖSUNG für Fehler 54: WLAN-Sync am PC in iTunes aktivieren! WLAN muss am iPhone eingeschaltet sein.", level: .error)
            }

            // Step 3: Direct StartService Fallback
            do {
                let targetPort = try await startLocationServiceDirect(host: effectiveHost, port: port)
                addLog("Dienst direkt gestartet auf Port \(targetPort)", level: .success)
                resolvedPort = targetPort
            } catch {
                addLog("Direkt-Info: \(error.localizedDescription)", level: .warning)
                resolvedPort = port
            }
        }

        // Step 4: Establish Continuous GPS Simulation Stream
        addLog("▶ Sende GPS-Koordinaten an \(effectiveHost):\(resolvedPort)...", level: .info)
        do {
            try await establishSimulationStream(coordinate: coordinate, host: effectiveHost, port: resolvedPort)
            startHeartbeat(coordinate: coordinate, host: effectiveHost, port: resolvedPort)
            completeSpoofSuccess(coordinate)
        } catch {
            DispatchQueue.main.async { self.status = .error }
            addLog("Spoofing-Fehler: \(error.localizedDescription)", level: .error)
            throw error
        }
    }

    private func completeSpoofSuccess(_ coordinate: CLLocationCoordinate2D) {
        DispatchQueue.main.async {
            self.isSpoofing = true
            self.spoofedCoordinate = coordinate
            self.status = .spoofing
        }
        addLog(String(format: "GPS-Signal aktiv & dauerhaft übertragen: %.5f, %.5f 📍", coordinate.latitude, coordinate.longitude), level: .success)
    }

    // MARK: - IP Discovery

    private func getLocalIPAddresses() -> [String] {
        var addresses = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return addresses }
        guard let firstAddr = ifaddr else { return addresses }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let address = String(cString: hostname)
                        if !address.contains("%") { // Skip IPv6 scope IDs
                            addresses.append(address)
                        }
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return addresses
    }

    // MARK: - Lockdownd Probe

    private func probeLockdownd(host: String, port: UInt16) async -> Bool {
        return await withCheckedContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let gate = ContinuationGate()

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let queryDict: [String: Any] = ["Request": "QueryType"]
                    self.sendPlist(queryDict, over: conn) { qErr in
                        if qErr != nil {
                            if gate.claim() { conn.cancel(); continuation.resume(returning: false) }
                            return
                        }
                        self.receivePlist(over: conn) { qRes in
                            if gate.claim() {
                                conn.cancel()
                                switch qRes {
                                case .success(let dict):
                                    let type = dict["Type"] as? String ?? ""
                                    continuation.resume(returning: type.contains("lockdown") || type.contains("Apple"))
                                case .failure:
                                    continuation.resume(returning: false)
                                }
                            }
                        }
                    }
                case .failed:
                    if gate.claim() { conn.cancel(); continuation.resume(returning: false) }
                default: break
                }
            }

            conn.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 1.5) {
                if gate.claim() { conn.cancel(); continuation.resume(returning: false) }
            }
        }
    }

    // MARK: - Reset Action

    func reset(host: String = "10.7.0.1", port: UInt16 = 62078) async {
        addLog("Setze Standort auf echtes GPS zurück...", level: .info)
        stopHeartbeat()

        if let conn = activeConnection {
            let resetPacket = makeResetPacket()
            conn.send(content: resetPacket, completion: .contentProcessed { _ in })
        } else {
            try? await sendStandaloneReset(host: host, port: port)
        }

        closeActiveConnection()

        DispatchQueue.main.async {
            self.isSpoofing = false
            self.spoofedCoordinate = nil
            self.status = .disconnected
        }
        addLog("Standort zurückgesetzt.", level: .success)
    }

    // MARK: - Continuous Simulation Stream

    private func establishSimulationStream(coordinate: CLLocationCoordinate2D, host: String, port: UInt16) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let gate = ContinuationGate()
            self.activeConnection = conn

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let packet = self.makeLocationPacket(lat: coordinate.latitude, lon: coordinate.longitude)
                    conn.send(content: packet, completion: .contentProcessed { err in
                        if gate.claim() {
                            if let err = err {
                                continuation.resume(throwing: err)
                            } else {
                                continuation.resume()
                            }
                        }
                    })
                case .failed(let err):
                    if gate.claim() {
                        continuation.resume(throwing: err)
                    }
                default: break
                }
            }

            conn.start(queue: self.queue)

            self.queue.asyncAfter(deadline: .now() + 6) {
                if gate.claim() {
                    let err = NSError(domain: "LocationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout bei Verbindung zum Standortkanal \(host):\(port)"])
                    continuation.resume(throwing: err)
                }
            }
        }
    }

    private func startHeartbeat(coordinate: CLLocationCoordinate2D, host: String, port: UInt16) {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isSpoofing else { return }
            let packet = self.makeLocationPacket(lat: coordinate.latitude, lon: coordinate.longitude)
            if let conn = self.activeConnection {
                conn.send(content: packet, completion: .contentProcessed { _ in })
            }
        }
        timer.resume()
        self.heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func closeActiveConnection() {
        activeConnection?.cancel()
        activeConnection = nil
    }

    // MARK: - Strategy 1: Lockdownd with ValidatePairing

    private func startLocationServiceWithValidation(pairing: PairingRecord, host: String, port: UInt16) async throws -> UInt16 {
        return try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let gate = ContinuationGate()

            @Sendable func finishWithError(_ err: Error) {
                if gate.claim() {
                    conn.cancel()
                    continuation.resume(throwing: err)
                }
            }

            @Sendable func finishWithSuccess(targetPort: UInt16) {
                if gate.claim() {
                    conn.cancel()
                    continuation.resume(returning: targetPort)
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Step 1: QueryType
                    let queryDict: [String: Any] = ["Request": "QueryType"]
                    self.sendPlist(queryDict, over: conn) { qErr in
                        if let qErr = qErr { finishWithError(qErr); return }

                        self.receivePlist(over: conn) { qRes in
                            switch qRes {
                            case .failure(let err): finishWithError(err)
                            case .success(let typeDict):
                                let typeName = typeDict["Type"] as? String ?? "OK"
                                self.addLog("Lockdownd Typ: \(typeName)", level: .info)

                                // Step 2: ValidatePairing
                                let validateDict: [String: Any] = [
                                    "Request": "ValidatePairing",
                                    "PairingRecord": pairing.toPlistDictionary()
                                ]
                                self.sendPlist(validateDict, over: conn) { vErr in
                                    if let vErr = vErr { finishWithError(vErr); return }

                                    self.receivePlist(over: conn) { vRes in
                                        let vResult = (try? vRes.get())?["Result"] as? String ?? "Success"
                                        self.addLog("Pairing Status: \(vResult)", level: .info)

                                        // Step 3: StartService com.apple.dt.simulatelocation
                                        let startDict: [String: Any] = [
                                            "Request": "StartService",
                                            "Service": "com.apple.dt.simulatelocation"
                                        ]
                                        self.sendPlist(startDict, over: conn) { sErr in
                                            if let sErr = sErr { finishWithError(sErr); return }

                                            self.receivePlist(over: conn) { sRes in
                                                switch sRes {
                                                case .success(let dict):
                                                    if let servPort = dict["Port"] as? Int {
                                                        finishWithSuccess(targetPort: UInt16(servPort))
                                                    } else if let errorMsg = dict["Error"] as? String {
                                                        let err = NSError(domain: "Lockdownd", code: -2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                                                        finishWithError(err)
                                                    } else {
                                                        finishWithSuccess(targetPort: port)
                                                    }
                                                case .failure(let err):
                                                    finishWithError(err)
                                                }
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

            self.queue.asyncAfter(deadline: .now() + 6) {
                let err = NSError(domain: "Lockdownd", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout bei Lockdownd auf \(host):\(port)"])
                finishWithError(err)
            }
        }
    }

    // MARK: - Strategy 2: Direct StartService

    private func startLocationServiceDirect(host: String, port: UInt16) async throws -> UInt16 {
        return try await withCheckedThrowingContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let gate = ContinuationGate()

            @Sendable func finishWithError(_ err: Error) {
                if gate.claim() {
                    conn.cancel()
                    continuation.resume(throwing: err)
                }
            }

            @Sendable func finishWithSuccess(targetPort: UInt16) {
                if gate.claim() {
                    conn.cancel()
                    continuation.resume(returning: targetPort)
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let startDict: [String: Any] = [
                        "Request": "StartService",
                        "Service": "com.apple.dt.simulatelocation"
                    ]
                    self.sendPlist(startDict, over: conn) { sErr in
                        if let sErr = sErr { finishWithError(sErr); return }

                        self.receivePlist(over: conn) { sRes in
                            switch sRes {
                            case .success(let dict):
                                if let servPort = dict["Port"] as? Int {
                                    finishWithSuccess(targetPort: UInt16(servPort))
                                } else if let errorMsg = dict["Error"] as? String {
                                    let err = NSError(domain: "Lockdownd", code: -2, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                                    finishWithError(err)
                                } else {
                                    finishWithSuccess(targetPort: port)
                                }
                            case .failure(let err):
                                finishWithError(err)
                            }
                        }
                    }
                case .failed(let err):
                    finishWithError(err)
                default: break
                }
            }

            conn.start(queue: self.queue)

            self.queue.asyncAfter(deadline: .now() + 5) {
                let err = NSError(domain: "Lockdownd", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout bei Direktabfrage"])
                finishWithError(err)
            }
        }
    }

    // MARK: - Robust Exact-Length Plist Transport

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

    private func receiveExact(bytes count: Int, over connection: NWConnection, completion: @escaping (Result<Data, Error>) -> Void) {
        var buffer = Data()

        func readChunk() {
            let needed = count - buffer.count
            guard needed > 0 else {
                completion(.success(buffer))
                return
            }

            connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { content, _, isComplete, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                if let data = content, !data.isEmpty {
                    buffer.append(data)
                    if buffer.count >= count {
                        completion(.success(buffer.prefix(count)))
                    } else {
                        readChunk()
                    }
                } else if isComplete {
                    let err = NSError(domain: "Lockdownd", code: -3, userInfo: [NSLocalizedDescriptionKey: "Verbindung vorzeitig beendet (\(buffer.count)/\(count) Bytes)"])
                    completion(.failure(err))
                }
            }
        }

        readChunk()
    }

    private func receivePlist(over connection: NWConnection, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        // Step 1: Read 4-byte big endian length header
        receiveExact(bytes: 4, over: connection) { lenResult in
            switch lenResult {
            case .failure(let err):
                completion(.failure(err))
            case .success(let headerData):
                let length = UInt32(bigEndian: headerData.withUnsafeBytes { $0.load(as: UInt32.self) })
                guard length > 0, length < 10_000_000 else {
                    let err = NSError(domain: "Lockdownd", code: -4, userInfo: [NSLocalizedDescriptionKey: "Ungültige Payload-Größe: \(length)"])
                    completion(.failure(err))
                    return
                }

                // Step 2: Read exact payload bytes
                self.receiveExact(bytes: Int(length), over: connection) { payloadResult in
                    switch payloadResult {
                    case .failure(let pErr):
                        completion(.failure(pErr))
                    case .success(let payloadData):
                        do {
                            if let dict = try PropertyListSerialization.propertyList(from: payloadData, options: [], format: nil) as? [String: Any] {
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
        }
    }

    // MARK: - Binary Packets

    private func makeLocationPacket(lat: Double, lon: Double) -> Data {
        let latStr = String(format: "%.8f", lat)
        let lonStr = String(format: "%.8f", lon)
        guard let latData = latStr.data(using: .utf8),
              let lonData = lonStr.data(using: .utf8) else { return Data() }

        var packet = Data()
        var cmd: UInt32 = UInt32(1).bigEndian
        packet.append(Data(bytes: &cmd, count: 4))
        var latLen: UInt32 = UInt32(latData.count).bigEndian
        packet.append(Data(bytes: &latLen, count: 4))
        packet.append(latData)
        var lonLen: UInt32 = UInt32(lonData.count).bigEndian
        packet.append(Data(bytes: &lonLen, count: 4))
        packet.append(lonData)
        return packet
    }

    private func makeResetPacket() -> Data {
        var cmd: UInt32 = UInt32(0).bigEndian
        return Data(bytes: &cmd, count: 4)
    }

    private func sendStandaloneReset(host: String, port: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            let gate = ContinuationGate()
            let packet = self.makeResetPacket()

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
            self.queue.asyncAfter(deadline: .now() + 4) {
                if gate.claim() { conn.cancel(); continuation.resume() }
            }
        }
    }

    // MARK: - VPN Test

    func testVPN(host: String = "10.7.0.1", port: UInt16 = 62078) async -> Bool {
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
