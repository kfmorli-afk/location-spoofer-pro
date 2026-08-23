import Foundation
import Network
import Combine

public class LockdownClient: ObservableObject {
    public static let shared = LockdownClient()
    
    @Published public var isConnected: Bool = false
    @Published public var statusMessage: String = "Bereit"
    @Published public var lastLog: String = ""
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "pro.locationspoofer.lockdown", qos: .userInitiated)
    
    public init() {}
    
    public enum LockdownError: LocalizedError {
        case notConnected
        case connectionFailed(String)
        case timeout
        case invalidResponse
        case serviceStartFailed(String)
        case noPairingRecord
        
        public var errorDescription: String? {
            switch self {
            case .notConnected:
                return "Nicht mit Lockdownd verbunden. Bitte sicherstellen, dass Local Dev VPN aktiv ist."
            case .connectionFailed(let reason):
                return "Verbindung zu Lockdownd fehlgeschlagen: \(reason)"
            case .timeout:
                return "Zeitüberschreitung bei der Kommunikation mit Lockdownd."
            case .invalidResponse:
                return "Ungültige Antwort vom iOS Lockdownd-Daemon empfangen."
            case .serviceStartFailed(let reason):
                return "Konnte 'com.apple.dt.simulatelocation' nicht starten: \(reason)"
            case .noPairingRecord:
                return "Keine gültige Pairing-Datei geladen. Bitte in den Einstellungen importieren."
            }
        }
    }
    
    /// Tests connectivity to 127.0.0.1:62078 (Lockdown over LocalDevVPN)
    public func testConnection(host: String = "127.0.0.1", port: UInt16 = 62078) async -> Bool {
        return await withCheckedContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            let testConn = NWConnection(host: nwHost, port: nwPort, using: params)
            var didResume = false
            
            testConn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !didResume {
                        didResume = true
                        testConn.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed(let err):
                    if !didResume {
                        didResume = true
                        testConn.cancel()
                        continuation.resume(returning: false)
                    }
                case .cancelled:
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            
            testConn.start(queue: self.queue)
            
            // Timeout after 3 seconds
            self.queue.asyncAfter(deadline: .now() + 3.0) {
                if !didResume {
                    didResume = true
                    testConn.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Starts the com.apple.dt.simulatelocation service on device via Lockdownd
    public func startSimulateLocationService(
        host: String = "127.0.0.1",
        port: UInt16 = 62078,
        pairingRecord: PairingRecord
    ) async throws -> (servicePort: UInt16, enableSSL: Bool) {
        
        guard pairingRecord.isValid else {
            throw LockdownError.noPairingRecord
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            
            let params = NWParameters.tcp
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            
            var didResume = false
            
            func finishWithError(_ error: Error) {
                if !didResume {
                    didResume = true
                    conn.cancel()
                    continuation.resume(throwing: error)
                }
            }
            
            func finishWithSuccess(port: UInt16, ssl: Bool) {
                if !didResume {
                    didResume = true
                    conn.cancel()
                    continuation.resume(returning: (port, ssl))
                }
            }
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Step 1: Send QueryType
                    let queryTypeDict: [String: Any] = [
                        "Request": "QueryType"
                    ]
                    
                    self.sendPlist(queryTypeDict, over: conn) { error in
                        if let error = error {
                            finishWithError(LockdownError.connectionFailed(error.localizedDescription))
                            return
                        }
                        
                        self.receivePlist(over: conn) { result in
                            switch result {
                            case .failure(let err):
                                finishWithError(err)
                            case .success(let resp):
                                // Step 2: StartSession
                                let hostID = pairingRecord.hostID ?? UUID().uuidString
                                let systemBUID = pairingRecord.systemBUID ?? ""
                                
                                var startSessionDict: [String: Any] = [
                                    "Request": "StartSession",
                                    "HostID": hostID
                                ]
                                if !systemBUID.isEmpty {
                                    startSessionDict["SystemBUID"] = systemBUID
                                }
                                
                                self.sendPlist(startSessionDict, over: conn) { error in
                                    if let error = error {
                                        finishWithError(LockdownError.connectionFailed(error.localizedDescription))
                                        return
                                    }
                                    
                                    self.receivePlist(over: conn) { sessionResult in
                                        // Step 3: StartService for com.apple.dt.simulatelocation
                                        let startServiceDict: [String: Any] = [
                                            "Request": "StartService",
                                            "Service": "com.apple.dt.simulatelocation"
                                        ]
                                        
                                        self.sendPlist(startServiceDict, over: conn) { error in
                                            if let error = error {
                                                finishWithError(LockdownError.serviceStartFailed(error.localizedDescription))
                                                return
                                            }
                                            
                                            self.receivePlist(over: conn) { serviceResult in
                                                switch serviceResult {
                                                case .failure(let sErr):
                                                    finishWithError(sErr)
                                                case .success(let sResp):
                                                    if let servicePort = sResp["Port"] as? Int {
                                                        let enableSSL = (sResp["EnableServiceSSL"] as? Bool) ?? false
                                                        finishWithSuccess(port: UInt16(servicePort), ssl: enableSSL)
                                                    } else if let errorMsg = sResp["Error"] as? String {
                                                        finishWithError(LockdownError.serviceStartFailed(errorMsg))
                                                    } else {
                                                        // Default fallback port for direct simulation
                                                        finishWithSuccess(port: 62078, ssl: false)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                case .failed(let err):
                    finishWithError(LockdownError.connectionFailed(err.localizedDescription))
                default:
                    break
                }
            }
            
            conn.start(queue: self.queue)
            
            // Timeout
            self.queue.asyncAfter(deadline: .now() + 8.0) {
                if !didResume {
                    finishWithError(LockdownError.timeout)
                }
            }
        }
    }
    
    // MARK: - Plist Wire Helpers
    
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
        // Read 4 bytes length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { content, _, isComplete, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = content, data.count == 4 else {
                completion(.failure(LockdownError.invalidResponse))
                return
            }
            
            let length = UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
            guard length > 0, length < 1_000_000 else {
                completion(.failure(LockdownError.invalidResponse))
                return
            }
            
            // Read Plist payload
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { payload, _, _, pError in
                if let pError = pError {
                    completion(.failure(pError))
                    return
                }
                guard let pData = payload else {
                    completion(.failure(LockdownError.invalidResponse))
                    return
                }
                
                do {
                    if let dict = try PropertyListSerialization.propertyList(from: pData, options: [], format: nil) as? [String: Any] {
                        completion(.success(dict))
                    } else {
                        completion(.failure(LockdownError.invalidResponse))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}
