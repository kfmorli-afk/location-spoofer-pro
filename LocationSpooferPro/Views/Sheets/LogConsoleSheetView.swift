import SwiftUI

public struct LogConsoleSheetView: View {
    @ObservedObject var simulationClient = LocationSimulationClient.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var isCopied: Bool = false
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Toolbar info
                HStack {
                    Text("\(simulationClient.logs.count) Einträge")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: copyAllLogs) {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            Text(isCopied ? "Kopiert" : "Alle Kopieren")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isCopied ? .green : .blue)
                    }
                    
                    Button(action: {
                        simulationClient.clearLogs()
                    }) {
                        Text("Leeren")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                
                Divider()
                
                // Console Log Window
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(simulationClient.logs) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(entry.formattedTime)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Text("[\(entry.type.rawValue)]")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(typeColor(for: entry.type))
                                    
                                    Text(entry.message)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                }
                                .id(entry.id)
                            }
                        }
                        .padding(12)
                    }
                    .background(Color.black.opacity(0.85))
                    .onChange(of: simulationClient.logs.count) { _ in
                        if let last = simulationClient.logs.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Live Debug-Konsole")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func typeColor(for type: LogEntry.LogType) -> Color {
        switch type {
        case .info: return .cyan
        case .success: return .green
        case .warning: return .yellow
        case .error: return .red
        case .packet: return .purple
        }
    }
    
    private func copyAllLogs() {
        let fullText = simulationClient.logs.map { "[\($0.formattedTime)] [\($0.type.rawValue)] \($0.message)" }.joined(separator: "\n")
        UIPasteboard.general.string = fullText
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isCopied = false
        }
    }
}
