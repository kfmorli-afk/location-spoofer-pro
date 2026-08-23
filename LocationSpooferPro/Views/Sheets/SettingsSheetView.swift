import SwiftUI
import UniformTypeIdentifiers

public struct SettingsSheetView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var showLogConsole: Bool = false
    
    public var body: some View {
        NavigationView {
            Form {
                // Section 1: Pairing File Status
                Section(header: Text("Apple Pairing-Zertifikat")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.system(size: 15, weight: .semibold))
                            
                            Text(settingsViewModel.pairingService.hasValidPairing ? "Gültige Pairing-Datei geladen" : "Keine Pairing-Datei vorhanden")
                                .font(.system(size: 13))
                                .foregroundColor(settingsViewModel.pairingService.hasValidPairing ? .green : .red)
                        }
                        
                        Spacer()
                        
                        Image(systemName: settingsViewModel.pairingService.hasValidPairing ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .font(.system(size: 22))
                            .foregroundColor(settingsViewModel.pairingService.hasValidPairing ? .green : .red)
                    }
                    
                    if let pairing = settingsViewModel.pairingService.currentPairing {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Datei:")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(pairing.fileName)
                                    .font(.system(size: 13))
                            }
                            
                            if !pairing.udid.isEmpty {
                                HStack {
                                    Text("UDID:")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(pairing.udid)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    Button(action: {
                        settingsViewModel.showingFileImporter = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text(settingsViewModel.pairingService.hasValidPairing ? "Andere Pairing-Datei importieren" : "Pairing-Datei importieren (.plist / .mobiledevicepairing)")
                        }
                        .font(.system(size: 15, weight: .semibold))
                    }
                    
                    if settingsViewModel.pairingService.hasValidPairing {
                        Button(role: .destructive, action: {
                            settingsViewModel.pairingService.removePairing()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Pairing-Datei löschen")
                            }
                        }
                    }
                }
                
                // Section 2: Local Dev VPN & Network
                Section(header: Text("Local Dev VPN & Lockdownd Tunnel")) {
                    HStack {
                        Text("Host IP")
                        Spacer()
                        TextField("127.0.0.1", text: $settingsViewModel.lockdowndHost)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Lockdown Port")
                        Spacer()
                        TextField("62078", text: $settingsViewModel.lockdowndPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15, design: .monospaced))
                    }
                    
                    Button(action: {
                        settingsViewModel.testVPNConnection()
                    }) {
                        HStack {
                            if settingsViewModel.isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Teste Verbindung...")
                            } else {
                                Image(systemName: "network")
                                Text("Verbindung zu Lockdownd testen")
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(settingsViewModel.isTestingConnection)
                    
                    if let result = settingsViewModel.testConnectionSuccess {
                        HStack {
                            Text("Testergebnis:")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(result ? "Erfolgreich verbunden!" : "Fehlgeschlagen (VPN aktiv?)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(result ? .green : .red)
                        }
                    }
                }
                
                // Section 3: Tools & Logs
                Section(header: Text("Diagnose & Logs")) {
                    Button(action: {
                        showLogConsole = true
                    }) {
                        HStack {
                            Image(systemName: "terminal.fill")
                            Text("Live Debug-Konsole öffnen")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Section 4: Quick Guide
                Section(header: Text("Kurzanleitung: So funktioniert's")) {
                    VStack(alignment: .leading, spacing: 10) {
                        guideStep(
                            number: "1",
                            title: "Entwicklermodus aktivieren",
                            detail: "Einstellungen > Datenschutz & Sicherheit > Entwicklermodus auf dem iPhone 15 einschalten."
                        )
                        
                        guideStep(
                            number: "2",
                            title: "Pairing-Datei besorgen",
                            detail: "Beim Sideloaden mit Sideloadly oder via PC wird eine .mobiledevicepairing Datei erzeugt. Diese in iCloud Drive speichern und hier oben importieren."
                        )
                        
                        guideStep(
                            number: "3",
                            title: "Local Dev VPN starten",
                            detail: "Öffne die App 'LocalDevVPN' (oder SideStore VPN) auf deinem iPhone und aktiviere den VPN-Schalter."
                        )
                        
                        guideStep(
                            number: "4",
                            title: "Standort fälschen",
                            detail: "Wähle auf der Karte einen Ort aus und drücke auf 'Standort Fälschen'. Der Standort ändert sich nun sofort in Snapchat, Wo ist?, etc."
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Einstellungen & VPN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        settingsViewModel.saveSettings()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $settingsViewModel.showingFileImporter,
                allowedContentTypes: [.xml, .propertyList, .data, UTType(filenameExtension: "mobiledevicepairing") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                settingsViewModel.handleFileImport(result: result)
            }
            .sheet(isPresented: $showLogConsole) {
                LogConsoleSheetView()
            }
            .alert(isPresented: $settingsViewModel.showAlert) {
                Alert(
                    title: Text("Hinweis"),
                    message: Text(settingsViewModel.alertMessage ?? ""),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func guideStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}
