import Foundation
import Network
import CoreLocation
import Combine

public class LocationSimulationClient: ObservableObject {
    public static let shared = LocationSimulationClient()
    
    @Published public var isSpoofingActive: Bool = false
    @Published public var activeSpoofedCoordinate: CLLocationCoordinate2D?
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var logs: [LogEntry] = []
    
    private var simulationConnection: NWConnection?
    private let queue = DispatchQueue(label: "pro.locationspoofer.simulation", qos: .userInitiated)
    private var lastSpoofedLatitude: Double?
    private var lastSpoofedLongitude: Double?
    
    public init() {
        log("Location Spoofer Pro Engine initialisiert", type: .info)
    }
    
    public func log(_ message: String, type: LogEntry.LogType = .info) {
        DispatchQueue.main.async {
            let entry = LogEntry(message: message, type: type)
            self.logs.append(entry)
            if self.logs.count > 300 {
                self.logs.removeFirst(50)
            }
        }
        print("[\(type.rawValue)] \(message)")
    }
    
    public func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
    
    // MARK: - Spoofing Commands
    
    /// Spoofs location to specified coordinate
    public func spoofLocation(
        coordinate: CLLocationCoordinate2D,
        host: String = "127.0.0.1",
        port: UInt16 = 62078
    ) async throws {
        log("Starte Spoofing zu: \(coordinate.latitude), \(coordinate.longitude)...", type: .info)
        
        guard let pairingRecord = PairingService.shared.currentPairing, pairingRecord.isValid else {
            DispatchQueue.main.async {
                self.connectionStatus = .error
            }
            log("Fehler: Keine gültige Pairing-Datei geladen!", type: .error)
            throw PairingError.missingCredentials
        }
        
        DispatchQueue.main.async {
            self.connectionStatus = .checkingVPN
        }
        
        // Step 1: Check LocalDevVPN connection to lockdown
        let isVPNReachable = await LockdownClient.shared.testConnection(host: host, port: port)
        if !isVPNReachable {
            log("Warnung: Lockdownd nicht erreichbar auf \(host):\(port). Prüfe ob LocalDevVPN eingeschaltet ist.", type: .warning)
        }
        
        DispatchQueue.main.async {
            self.connectionStatus = .connecting
        }
        
        do {
            // Step 2: Request service port from lockdownd
            log("Verhandle com.apple.dt.simulatelocation Dienst...", type: .info)
            let (servicePort, _) = try await LockdownClient.shared.startSimulateLocationService(
                host: host,
                port: port,
                pairingRecord: pairingRecord
            )
            
            log("Dienst gestartet auf Port \(servicePort)", type: .success)
            
            // Step 3: Send location packet
            try await sendLocationPacket(latitude: coordinate.latitude, longitude: coordinate.longitude, host: host, port: servicePort)
            
            DispatchQueue.main.async {
                self.isSpoofingActive = true
                self.activeSpoofedCoordinate = coordinate
                self.connectionStatus = .activeSpoofing
            }
            
            self.lastSpoofedLatitude = coordinate.latitude
            self.lastSpoofedLongitude = coordinate.longitude
            
            log("Standort erfolgreich gefälscht auf: \(coordinate.latitude), \(coordinate.longitude)", type: .success)
        } catch {
            DispatchQueue.main.async {
                self.connectionStatus = .error
            }
            log("Spoofing fehlgeschlagen: \(error.localizedDescription)", type: .error)
            throw error
        }
    }
    
    /// Resets spoofed location and restores genuine device GPS
    public func resetLocation(host: String = "127.0.0.1", port: UInt16 = 62078) async throws {
        log("Setze Standort auf echten GPS-Standort zurück...", type: .info)
        
        guard let pairingRecord = PairingService.shared.currentPairing, pairingRecord.isValid else {
            DispatchQueue.main.async {
                self.isSpoofingActive = false
                self.activeSpoofedCoordinate = nil
                self.connectionStatus = .disconnected
            }
            return
        }
        
        do {
            let (servicePort, _) = try await LockdownClient.shared.startSimulateLocationService(
                host: host,
                port: port,
                pairingRecord: pairingRecord
            )
            
            try await sendResetPacket(host: host, port: servicePort)
            
            DispatchQueue.main.async {
                self.isSpoofingActive = false
                self.activeSpoofedCoordinate = nil
                self.connectionStatus = .paired
            }
            
            log("Standort erfolgreich auf echten GPS zurückgesetzt!", type: .success)
        } catch {
            DispatchQueue.main.async {
                self.isSpoofingActive = false
                self.activeSpoofedCoordinate = nil
                self.connectionStatus = .disconnected
            }
            log("Fehler beim Zurücksetzen: \(error.localizedDescription)", type: .warning)
            throw error
        }
    }
    
    // MARK: - Binary Packet Protocol
    
    /// Sends the binary packet: [0x00000001] [lat_len] [lat_str] [lon_len] [lon_str]
    private func sendLocationPacket(latitude: Double, longitude: Double, host: String, port: UInt16) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            
            let latStr = String(format: "%.8f", latitude)
            let lonStr = String(format: "%.8f", longitude)
            
            guard let latData = latStr.data(using: .utf8),
                  let lonData = lonStr.data(using: .utf8) else {
                continuation.resume(throwing: LockdownClient.LockdownError.invalidResponse)
                return
            }
            
            var packet = Data()
            
            // Command 1 = Start / Update simulation
            var command: UInt32 = (1 as UInt32).bigEndian
            packet.append(Data(bytes: &command, count: MemoryLayout<UInt32>.size))
            
            // Latitude length + bytes
            var latLen: UInt32 = UInt32(latData.count).bigEndian
            packet.append(Data(bytes: &latLen, count: MemoryLayout<UInt32>.size))
            packet.append(latData)
            
            // Longitude length + bytes
            var lonLen: UInt32 = UInt32(lonData.count).bigEndian
            packet.append(Data(bytes: &lonLen, count: MemoryLayout<UInt32>.size))
            packet.append(lonData)
            
            var didResume = false
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: packet, completion: .contentProcessed { sendErr in
                        if !didResume {
                            didResume = true
                            conn.cancel()
                            if let sendErr = sendErr {
                                continuation.resume(throwing: sendErr)
                            } else {
                                continuation.resume()
                            }
                        }
                    })
                case .failed(let err):
                    if !didResume {
                        didResume = true
                        conn.cancel()
                        continuation.resume(throwing: err)
                    }
                default:
                    break
                }
            }
            
            conn.start(queue: self.queue)
            
            self.queue.asyncAfter(deadline: .now() + 5.0) {
                if !didResume {
                    didResume = true
                    conn.cancel()
                    continuation.resume(throwing: LockdownClient.LockdownError.timeout)
                }
            }
        }
    }
    
    /// Sends the binary packet: [0x00000000] to stop simulation
    private func sendResetPacket(host: String, port: UInt16) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            
            var command: UInt32 = (0 as UInt32).bigEndian
            let packet = Data(bytes: &command, count: MemoryLayout<UInt32>.size)
            
            var didResume = false
            
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: packet, completion: .contentProcessed { sendErr in
                        if !didResume {
                            didResume = true
                            conn.cancel()
                            if let sendErr = sendErr {
                                continuation.resume(throwing: sendErr)
                            } else {
                                continuation.resume()
                            }
                        }
                    })
                case .failed(let err):
                    if !didResume {
                        didResume = true
                        conn.cancel()
                        continuation.resume(throwing: err)
                    }
                default:
                    break
                }
            }
            
            conn.start(queue: self.queue)
            
            self.queue.asyncAfter(deadline: .now() + 5.0) {
                if !didResume {
                    didResume = true
                    conn.cancel()
                    continuation.resume(throwing: LockdownClient.LockdownError.timeout)
                }
            }
        }
    }
}
