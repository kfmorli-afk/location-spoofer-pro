import SwiftUI
import MapKit

public struct SearchResultsView: View {
    var completions: [MKLocalSearchCompletion]
    var onSelect: (MKLocalSearchCompletion) -> Void
    
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(completions, id: \.self) { completion in
                    Button(action: {
                        onSelect(completion)
                    }) {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 18))
                                .foregroundColor(.blue)
                                .frame(width: 28, height: 28)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
        .frame(maxHeight: 280)
    }
}
