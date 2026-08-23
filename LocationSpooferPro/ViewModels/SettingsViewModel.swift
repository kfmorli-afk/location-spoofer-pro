import Foundation
import SwiftUI
import Combine

public class SettingsViewModel: ObservableObject {
    @Published public var lockdowndHost: String = "127.0.0.1"
    @Published public var lockdowndPort: String = "62078"
    @Published public var isTestingConnection: Bool = false
    @Published public var testConnectionSuccess: Bool?
    @Published public var showingFileImporter: Bool = false
    @Published public var alertMessage: String?
    @Published public var showAlert: Bool = false
    
    public let pairingService = PairingService.shared
    public let lockdownClient = LockdownClient.shared
    public let simulationClient = LocationSimulationClient.shared
    
    public init() {
        if let savedHost = UserDefaults.standard.string(forKey: "LockdowndHost_v1") {
            self.lockdowndHost = savedHost
        }
        if let savedPort = UserDefaults.standard.string(forKey: "LockdowndPort_v1") {
            self.lockdowndPort = savedPort
        }
    }
    
    public func saveSettings() {
        UserDefaults.standard.set(lockdowndHost, forKey: "LockdowndHost_v1")
        UserDefaults.standard.set(lockdowndPort, forKey: "LockdowndPort_v1")
    }
    
    public func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            
            let shouldStopAccessing = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let fileData = try Data(contentsOf: selectedURL)
                let record = try pairingService.importPairing(from: fileData, fileName: selectedURL.lastPathComponent)
                
                simulationClient.log("Pairing-Datei erfolgreich importiert: \(record.summary)", type: .success)
                
                self.alertMessage = "Pairing-Datei '\(selectedURL.lastPathComponent)' wurde erfolgreich geladen!"
                self.showAlert = true
            } catch {
                simulationClient.log("Fehler beim Importieren der Pairing-Datei: \(error.localizedDescription)", type: .error)
                self.alertMessage = error.localizedDescription
                self.showAlert = true
            }
            
        case .failure(let error):
            simulationClient.log("Dateiauswahl fehlgeschlagen: \(error.localizedDescription)", type: .error)
            self.alertMessage = error.localizedDescription
            self.showAlert = true
        }
    }
    
    public func testVPNConnection() {
        guard let portNum = UInt16(lockdowndPort) else {
            self.alertMessage = "Ungültiger Port angegeben."
            self.showAlert = true
            return
        }
        
        isTestingConnection = true
        testConnectionSuccess = nil
        
        Task {
            let success = await lockdownClient.testConnection(host: lockdowndHost, port: portNum)
            DispatchQueue.main.async {
                self.isTestingConnection = false
                self.testConnectionSuccess = success
                
                if success {
                    self.simulationClient.log("Verbindung zu Lockdownd (\(self.lockdowndHost):\(portNum)) erfolgreich!", type: .success)
                } else {
                    self.simulationClient.log("Verbindung zu Lockdownd fehlgeschlagen. Prüfe Local Dev VPN.", type: .warning)
                }
            }
        }
    }
}
