import SwiftUI

struct MasonryFeedCard: View {
    let post: Post
    
    private var aspectRatio: CGFloat {
        guard let media = post.media.first, media.height > 0 else { return 1.0 }
        return CGFloat(media.width) / CGFloat(media.height)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Image / Thumbnail
            Group {
                if let firstMedia = post.media.first {
                    AsyncImage(url: firstMedia.thumbURL ?? firstMedia.url) { phase in
                        switch phase {
                        case .empty:
                            Color.gray.opacity(0.1)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.1)
                        @unknown default:
                            Color.gray.opacity(0.1)
                        }
                    }
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
                } else {
                    // Text-only fallback
                    ZStack {
                        Theme.sunnyGradient.opacity(0.1)
                        Text(post.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                            .multilineTextAlignment(.center)
                    }
                    .frame(height: 180)
                }
            }
            
            // Content Container
            VStack(alignment: .leading, spacing: 8) {
                // 2. Title
                if !post.title.isEmpty {
                    Text(post.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !post.text.isEmpty {
                     Text(post.text)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // 3. Author & Likes
                HStack {
                    // Author
                    HStack(spacing: 6) {
                        AvatarView(user: post.author, size: 16)
                        Text(post.author.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Likes
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.caption2)
                        Text("\(post.likeCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.textHint)
                }
            }
            .padding(10)
        }
        .background(Color(.systemBackground))
        .cornerRadius(8) // Tighter corner radius
    }
}
