// Features/Feed/FeedCard.swift
import SwiftUI
struct FeedCard: View {
    var post: Post
    var showActions: Bool = true
    var captionLines: Int = 2
    var showCaption: Bool = true

    // clamp portrait/square variety
    private let aspectRange: ClosedRange<CGFloat> = 1.9...2.5
    // clamp absolute height (tweak to taste)
    private let minImageH: CGFloat = 160
    private let maxImageH: CGFloat = 320
    private let corner: CGFloat = 3

    private var clampedAspect: CGFloat {
        guard let m = post.media.first else { return 1.25 }
        let raw = max(CGFloat(m.height), 1) / max(CGFloat(m.width), 1)
        return min(max(raw, aspectRange.lowerBound), aspectRange.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

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
                                .overlay(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.55)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: corner))
                                )
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
            if showCaption && !post.media.isEmpty {
                if !post.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(post.title)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(captionLines)
                        .padding(.horizontal, 6)
                } else {
                    Text(post.text)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(captionLines)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                }
            }

            // FOOTER
            HStack(spacing: 10) {
                NavigationLink(value: post.author) {
                    HStack(spacing: 10) {
                        AvatarView(user: post.author, size: 15)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.author.displayName)
                                .font(.caption2).fontWeight(.semibold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 6)

                if showActions {
                    PostActionsView(post: post)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
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
//  LocustSocial
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
                .foregroundColor(isLiked ? .red : .secondary)
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
