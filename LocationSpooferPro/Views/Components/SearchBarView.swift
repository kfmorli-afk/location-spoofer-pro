import SwiftUI

public struct SearchBarView: View {
    @Binding var text: String
    @Binding var isSearching: Bool
    var onCommit: () -> Void
    var onClear: () -> Void
    
    @FocusState private var isFocused: Bool
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.secondary)
            
            TextField("Orte oder Adressen suchen...", text: $text)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.primary)
                .focused($isFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    onCommit()
                }
            
            if isSearching {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            }
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
