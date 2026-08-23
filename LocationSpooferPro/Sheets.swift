import SwiftUI
import UniformTypeIdentifiers

// MARK: - Favorites Sheet

struct FavoritesSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var tab = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Favoriten").tag(0)
                    Text("Highlights").tag(2)
                    Text("Verlauf").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if tab == 0 {
                    listView(items: state.favorites, onDelete: { state.favorites.remove(atOffsets: $0); state.saveFavorites() })
                } else if tab == 1 {
                    listView(items: state.history, onDelete: { state.history.remove(atOffsets: $0); state.saveHistory() })
                } else {
                    listView(items: SavedLocation.presets, onDelete: nil)
                }
            }
            .navigationTitle("Gespeicherte Orte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    func listView(items: [SavedLocation], onDelete: ((IndexSet) -> Void)?) -> some View {
        if items.isEmpty {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "mappin.slash").font(.system(size: 44)).foregroundColor(.secondary)
                Text("Keine Orte vorhanden").font(.headline)
                Spacer()
            }
        } else {
            List {
                ForEach(items) { loc in
                    Button {
                        state.select(coordinate: loc.coordinate)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(loc.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                                if !loc.subtitle.isEmpty {
                                    Text(loc.subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                Text(loc.formattedCoordinates).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.4))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: onDelete)
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showFileImporter = false
    @State private var showLog = false
    @State private var importError: String?
    @State private var showImportError = false

    var body: some View {
        NavigationView {
            Form {
                // Pairing
                Section(header: Text("Apple Pairing-Zertifikat")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status").font(.system(size: 14, weight: .semibold))
                            Text(state.pairingService.hasValidRecord ? "Gültige Datei geladen" : "Keine Datei")
                                .font(.system(size: 13))
                                .foregroundColor(state.pairingService.hasValidRecord ? .green : .red)
                        }
                        Spacer()
                        Image(systemName: state.pairingService.hasValidRecord ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundColor(state.pairingService.hasValidRecord ? .green : .red)
                            .font(.system(size: 22))
                    }

                    if let r = state.pairingService.record {
                        Text(r.summary).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label(
                            state.pairingService.hasValidRecord ? "Andere Datei importieren" : "Pairing-Datei importieren (.plist)",
                            systemImage: "square.and.arrow.down"
                        )
                        .font(.system(size: 14, weight: .semibold))
                    }

                    if state.pairingService.hasValidRecord {
                        Button(role: .destructive) {
                            state.pairingService.remove()
                        } label: {
                            Label("Pairing-Datei löschen", systemImage: "trash")
                        }
                    }
                }

                // VPN
                Section(header: Text("Local Dev VPN / Lockdownd")) {
                    HStack {
                        Text("Host IP")
                        Spacer()
                        TextField("127.0.0.1", text: $state.lockdownHost)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14, design: .monospaced))
                    }
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("62078", text: $state.lockdownPort)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14, design: .monospaced))
                    }
                    Button {
                        state.testVPN()
                    } label: {
                        Label("VPN-Verbindung testen", systemImage: "network")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }

                // Debug
                Section(header: Text("Diagnose")) {
                    Button {
                        showLog = true
                    } label: {
                        Label("Live Debug-Konsole", systemImage: "terminal.fill")
                    }
                }

                // Guide
                Section(header: Text("Kurzanleitung")) {
                    guideRow(n: "1", title: "Entwicklermodus", detail: "Einstellungen › Datenschutz & Sicherheit › Entwicklermodus aktivieren.")
                    guideRow(n: "2", title: "Pairing-Datei importieren", detail: "Pairing-Datei (.plist) aus Sideloadly oder iTunes holen und oben importieren.")
                    guideRow(n: "3", title: "LocalDevVPN starten", detail: "Die LocalDevVPN App öffnen und den VPN-Schalter aktivieren.")
                    guideRow(n: "4", title: "Standort wählen & spoofing", detail: "Ort auf der Karte antippen, dann 'Standort fälschen' drücken.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        state.saveSettings()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.propertyList, .xml, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let stop = url.startAccessingSecurityScopedResource()
                    defer { if stop { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        try state.pairingService.importFrom(data: data, fileName: url.lastPathComponent)
                        state.simulator.addLog("Pairing-Datei importiert: \(url.lastPathComponent)", level: .success)
                    } catch {
                        importError = error.localizedDescription
                        showImportError = true
                    }
                case .failure(let err):
                    importError = err.localizedDescription
                    showImportError = true
                }
            }
            .alert("Import-Fehler", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(isPresented: $showLog) {
                LogConsole()
            }
        }
    }

    func guideRow(n: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.blue))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Log Console

struct LogConsole: View {
    @ObservedObject var sim = LocationSimulator.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(sim.logs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timeString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("[\(entry.level.rawValue)]")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(levelColor(entry.level))
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color.black.opacity(0.9))
                .onChange(of: sim.logs.count) { _ in
                    if let last = sim.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .navigationTitle("Debug-Konsole")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leeren") { sim.clearLogs() }.foregroundColor(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    func levelColor(_ level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .cyan
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }
}
