import Foundation
import Security
import Combine
import Network

public class PairingService: ObservableObject {
    public static let shared = PairingService()
    
    private let userDefaultsKey = "SavedPairingRecord_v1"
    
    @Published public var currentPairing: PairingRecord?
    @Published public var hasValidPairing: Bool = false
    @Published public var isImporting: Bool = false
    @Published public var lastErrorMessage: String?
    
    private init() {
        loadSavedPairing()
    }
    
    public func loadSavedPairing() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            self.currentPairing = nil
            self.hasValidPairing = false
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let record = try decoder.decode(PairingRecord.self, from: data)
            self.currentPairing = record
            self.hasValidPairing = record.isValid
        } catch {
            print("[PairingService] Fehler beim Laden des gespeicherten Pairing-Records: \(error)")
            self.currentPairing = nil
            self.hasValidPairing = false
        }
    }
    
    public func importPairing(from data: Data, fileName: String = "pairing.plist") throws -> PairingRecord {
        do {
            let record = try PairingRecord.parse(from: data, fileName: fileName)
            guard record.isValid else {
                throw PairingError.missingCredentials
            }
            
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(record)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            
            DispatchQueue.main.async {
                self.currentPairing = record
                self.hasValidPairing = true
                self.lastErrorMessage = nil
            }
            
            return record
        } catch {
            DispatchQueue.main.async {
                self.lastErrorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    public func removePairing() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        self.currentPairing = nil
        self.hasValidPairing = false
    }
    
    /// Creates SecIdentity from HostCertificate and HostPrivateKey stored in the pairing record
    public func createSecIdentity() -> SecIdentity? {
        guard let record = currentPairing,
              let certData = record.hostCertificateData,
              let keyData = record.hostPrivateKeyData else {
            return nil
        }
        
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            print("[PairingService] Konnte SecCertificate nicht aus Daten erstellen.")
            return nil
        }
        
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, keyDict as CFDictionary, &error) else {
            print("[PairingService] Konnte SecKey nicht erstellen: \(String(describing: error))")
            return nil
        }
        
        // Return identity if already available in keychain or construct identity
        var identity: SecIdentity?
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, &identity as? AnyObject as! UnsafeMutablePointer<AnyObject?>)
        if status == errSecSuccess, let found = identity {
            return found
        }
        
        return nil
    }
}
