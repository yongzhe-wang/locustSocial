// Features/Feed/FeedCard.swift
import SwiftUI
struct FeedCard: View {
    var post: Post
    var showActions: Bool = true
    var captionLines: Int = 2
    var showCaption: Bool = true

    // clamp portrait/square variety
    private let aspectRange: ClosedRange<CGFloat> = 1.2...1.8
    // clamp absolute height (tweak to taste)
    private let minImageH: CGFloat = 200
    private let maxImageH: CGFloat = 400
    private let corner: CGFloat = 24

    private var clampedAspect: CGFloat {
        guard let m = post.media.first else { return 1.5 }
        let raw = max(CGFloat(m.height), 1) / max(CGFloat(m.width), 1)
        return min(max(raw, aspectRange.lowerBound), aspectRange.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // IMAGE OR TEXT THUMBNAIL
            Group {
                if let firstMedia = post.media.first {
                    AsyncImage(url: firstMedia.thumbURL ?? firstMedia.url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(.gray.opacity(0.12))
                                .aspectRatio(clampedAspect, contentMode: .fit)
                                .frame(minHeight: minImageH, maxHeight: maxImageH)
                                .clipShape(RoundedRectangle(cornerRadius: corner))

                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                                .aspectRatio(clampedAspect, contentMode: .fit)
                                .frame(maxHeight: maxImageH)
                                .clipShape(RoundedRectangle(cornerRadius: corner))
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    if post.media.count > 1 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "photo.on.rectangle")
                                            Text("\(post.media.count)").fontWeight(.semibold)
                                        }
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(10)
                                    }
                                }

                        case .failure:
                            Rectangle()
                                .fill(.gray.opacity(0.12))
                                .aspectRatio(clampedAspect, contentMode: .fit)
                                .frame(minHeight: minImageH, maxHeight: maxImageH)
                                .clipShape(RoundedRectangle(cornerRadius: corner))
                                .overlay(Image(systemName: "photo").foregroundColor(.gray))

                        @unknown default:
                            EmptyView()
                        }
                    }
                    .transaction { $0.animation = nil }

                } else {
                    // No image: use a cute text-based thumbnail
                    TextThumbnailView(
                        title: post.title.isEmpty ? post.text : post.title,
                        cornerRadius: corner
                    )
                    .frame(minHeight: minImageH, maxHeight: maxImageH)
                }
            }

            // Caption below card; hide when there is no media to avoid repetition
            if showCaption {
                VStack(alignment: .leading, spacing: 4) {
                    if !post.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(post.title)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(captionLines)
                    }
                    
                    if !post.text.isEmpty {
                        Text(post.text)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(12)
        .background(Theme.cardWhite)
        .cornerRadius(corner)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}


private struct IconCount: View {
    let name: String
    let count: Int
    init(_ name: String, _ count: Int) { self.name = name; self.count = count }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: name).imageScale(.small)
            Text("\(count)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
//

//
//  PostActionsView 2.swift
//  CircleYa
//
//  Created by Andrew Wang on 11/22/25.
//

// MARK: - Like Button (optimistic, non-blocking)
struct PostActionsView: View {
    @State private var isLiked = false
    @State private var likeCount: Int

    let post: Post
    let api = FirebaseFeedAPI()

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                handleLikeTap()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                    Text("\(likeCount)")
                }
                .font(.caption)
                .foregroundColor(isLiked ? Theme.likeRed : .secondary)
            }
            .buttonStyle(.plain)
        }
        .task {
            // initial load, can be a little slower – doesn't affect tap UX
            isLiked = await api.isPostLiked(post.id)
        }
    }

    private func handleLikeTap() {
        // 1) Optimistic update on main thread
        let newState = !isLiked
        let delta = newState ? 1 : -1

        isLiked = newState
        likeCount = max(0, likeCount + delta)

        // 2) Fire-and-forget network write
        Task {
            do {
                // We don't *need* the return value to update the UI,
                // since we already did it optimistically.
                _ = try await api.toggleLike(for: post.id)
            } catch {
                // 3) Revert if the backend call fails
                await MainActor.run {
                    isLiked.toggle()
                    likeCount = max(0, likeCount - delta)
                }
                print("❌ Like failed:", error)
            }
        }
    }
}
