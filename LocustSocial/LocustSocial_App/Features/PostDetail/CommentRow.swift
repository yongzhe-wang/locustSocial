// Features/PostDetail/CommentRow.swift
import SwiftUI

struct CommentRow: View {
    let postId: String
    @State var comment: Comment

    /// Direct children of this comment (one layer only)
    var replies: [Comment] = []

    /// Called after a reply is successfully created so the parent view can reload
    var onReplyAdded: (() -> Void)? = nil

    @State private var isLiked = false
    @State private var isDisliked = false
    @State private var showReplyField = false
    @State private var replyText = ""

    private let api = FirebaseFeedAPI()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                // avatar
                NavigationLink(
                    destination: OtherUserProfileView(userId: comment.author.id)
                ) {
                    Group {
                        if let url = comment.author.avatarURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Color.gray.opacity(0.15)
                                }
                            }
                        } else {
                            Color.gray.opacity(0.15)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // main bubble
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        NavigationLink(
                            destination: OtherUserProfileView(userId: comment.author.id)
                        ) {
                            Text(comment.author.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 6)

                        Text(
                            comment.createdAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Text(comment.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // actions row
                    HStack(spacing: 16) {
                        // like
                        Button {
                            Task {
                                await toggleLike()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                Text("\(comment.likeCount)")
                            }
                            .font(.caption)
                            .foregroundStyle(isLiked ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)

                        // dislike
                        Button {
                            Task {
                                await toggleDislike()
                            }
                        } label: {
                            Image(systemName: isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.caption)
                                .foregroundStyle(isDisliked ? .red : .secondary)
                        }
                        .buttonStyle(.plain)

                        // reply
                        Button {
                            withAnimation {
                                showReplyField.toggle()
                            }
                        } label: {
                            Text("Reply")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.top, 2)

                    // reply input (only for this parent comment)
                    if showReplyField {
                        HStack(spacing: 8) {
                            TextField("Write a reply…", text: $replyText, axis: .vertical)
                                .lineLimit(1...3)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                Task { await sendReply() }
                            } label: {
                                Text("Send")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            // one layer of replies – indented
            if !replies.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(replies) { reply in
                        HStack(alignment: .top, spacing: 8) {
                            // small indent
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 2)
                                .cornerRadius(1)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    NavigationLink(
                                        destination: OtherUserProfileView(userId: reply.author.id)
                                    ) {
                                        Text(reply.author.displayName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer(minLength: 4)

                                    Text(
                                        reply.createdAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }

                                Text(reply.text)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.leading, 40) // align under the parent text
            }
        }
        .padding(.vertical, 4)
        .task {
            isLiked = await api.isCommentLiked(postId: postId, commentId: comment.id)
            isDisliked = await api.isCommentDisliked(postId: postId, commentId: comment.id)
        }
    }

    // MARK: - Actions

    private func toggleLike() async {
        do {
            let (liked, count) = try await api.toggleCommentLike(
                postId: postId,
                commentId: comment.id
            )
            await MainActor.run {
                isLiked = liked
                if liked { isDisliked = false }
                comment.likeCount = count
            }
        } catch {
            print("❌ like toggle:", error)
        }
    }

    private func toggleDislike() async {
        do {
            let disliked = try await api.toggleCommentDislike(
                postId: postId,
                commentId: comment.id
            )
            await MainActor.run {
                isDisliked = disliked
                if disliked { isLiked = false }
            }
        } catch {
            print("❌ dislike toggle:", error)
        }
    }

    private func sendReply() async {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let payload = text
        replyText = ""
        showReplyField = false

        do {
            _ = try await api.addReply(
                postId: postId,
                parentCommentId: comment.id,
                text: payload
            )
            await MainActor.run {
                onReplyAdded?()
            }
        } catch {
            print("❌ addReply:", error.localizedDescription)
        }
    }
}
