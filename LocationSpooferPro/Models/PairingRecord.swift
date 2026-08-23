import Foundation
import Security

public struct PairingRecord: Codable, Equatable {
    public var udid: String
    public var hostID: String?
    public var systemBUID: String?
    public var wifiMACAddress: String?
    
    public var hostCertificateData: Data?
    public var hostPrivateKeyData: Data?
    public var deviceCertificateData: Data?
    public var rootCertificateData: Data?
    
    public var importedAt: Date
    public var fileName: String
    
    public init(
        udid: String = "",
        hostID: String? = nil,
        systemBUID: String? = nil,
        wifiMACAddress: String? = nil,
        hostCertificateData: Data? = nil,
        hostPrivateKeyData: Data? = nil,
        deviceCertificateData: Data? = nil,
        rootCertificateData: Data? = nil,
        importedAt: Date = Date(),
        fileName: String = "pairing.plist"
    ) {
        self.udid = udid
        self.hostID = hostID
        self.systemBUID = systemBUID
        self.wifiMACAddress = wifiMACAddress
        self.hostCertificateData = hostCertificateData
        self.hostPrivateKeyData = hostPrivateKeyData
        self.deviceCertificateData = deviceCertificateData
        self.rootCertificateData = rootCertificateData
        self.importedAt = importedAt
        self.fileName = fileName
    }
    
    public var isValid: Bool {
        return !udid.isEmpty && hostCertificateData != nil && hostPrivateKeyData != nil
    }
    
    public var summary: String {
        if udid.isEmpty {
            return "Keine Pairing-Datei geladen"
        }
        let shortUdid = udid.count > 12 ? "\(udid.prefix(8))...\(udid.suffix(4))" : udid
        return "UDID: \(shortUdid) (\(fileName))"
    }
    
    /// Parses a standard Apple mobiledevicepairing / lockdown plist file
    public static func parse(from data: Data, fileName: String = "pairing.plist") throws -> PairingRecord {
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw PairingError.invalidFormat
        }
        
        let udid = (plist["UDID"] as? String) ?? (plist["DeviceUDID"] as? String) ?? ""
        let hostID = plist["HostID"] as? String
        let systemBUID = plist["SystemBUID"] as? String
        let wifiMAC = plist["WiFiMACAddress"] as? String
        
        let hostCert = plist["HostCertificate"] as? Data
        let hostKey = plist["HostPrivateKey"] as? Data
        let deviceCert = plist["DeviceCertificate"] as? Data
        let rootCert = plist["RootCertificate"] as? Data
        
        guard hostCert != nil || hostKey != nil || !udid.isEmpty else {
            throw PairingError.missingCredentials
        }
        
        return PairingRecord(
            udid: udid,
            hostID: hostID,
            systemBUID: systemBUID,
            wifiMACAddress: wifiMAC,
            hostCertificateData: hostCert,
            hostPrivateKeyData: hostKey,
            deviceCertificateData: deviceCert,
            rootCertificateData: rootCert,
            importedAt: Date(),
            fileName: fileName
        )
    }
}

public enum PairingError: LocalizedError {
    case invalidFormat
    case missingCredentials
    case fileReadFailed
    case certificateCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Die ausgewählte Datei ist keine gültige Apple Pairing-Datei (.mobiledevicepairing / .plist)."
        case .missingCredentials:
            return "Die Datei enthält keine gültigen Host-Zertifikate oder privaten Schlüssel."
        case .fileReadFailed:
            return "Die Pairing-Datei konnte nicht gelesen werden."
        case .certificateCreationFailed:
            return "Das TLS-Sicherheitszertifikat konnte nicht aus dem Schlüsselbund initialisiert werden."
        }
    }
}
