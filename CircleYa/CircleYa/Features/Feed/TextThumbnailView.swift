import SwiftUI

// MARK: - Text Thumbnail for Posts Without Images
struct TextThumbnailView: View {
    let title: String
    let cornerRadius: CGFloat

    private var primaryColor: Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .indigo]
        let idx = abs(title.hashValue) % colors.count
        return colors[idx]
    }

    var body: some View {
        ZStack {
            // Softer, more muted background
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            primaryColor.opacity(0.18),
                            primaryColor.opacity(0.08)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(primaryColor.opacity(0.2), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                // Title a bit higher
                Text(title.isEmpty ? "New post" : title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 10)

                Spacer()

                HStack {
                    Spacer()
                    Image(systemName: "text.bubble")
                        .font(.caption2)
                        .foregroundColor(primaryColor.opacity(0.6))
                }
            }
            .padding(14)
        }
    }
}
