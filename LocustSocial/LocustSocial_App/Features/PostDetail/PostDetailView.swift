// Features/PostDetail/PostDetailView.swift
import SwiftUI

struct CommentThread: Identifiable {
    let parent: Comment
    let replies: [Comment]

    var id: String { parent.id }
}

struct PostDetailView: View {
    let post: Post

    private let api = FirebaseFeedAPI()
    @State private var didLogView = false
    @State private var viewStart: Date?

    // post like/save
    @State private var isLiked = false
    @State private var isSaved = false
    @State private var likeCount: Int

    // comments (flat from Firestore)
    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false
    @State private var newComment = ""

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
    }

    // MARK: - Threads from flat comments

    private var commentThreads: [CommentThread] {
        let parents = comments.filter { $0.parentId == nil }
        let replies = comments.filter { $0.parentId != nil }
        let groupedReplies = Dictionary(grouping: replies, by: { $0.parentId! })

        return parents.map { parent in
            CommentThread(
                parent: parent,
                replies: groupedReplies[parent.id] ?? []
            )
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // IMAGE
                    mediaView

                    // AUTHOR
                    authorRow

                    // TITLE
                    if !post.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(post.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    // BODY TEXT
                    if !post.text.isEmpty {
                        Text(post.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // META ROW
                    metaRow

                    Divider()
                        .padding(.top, 4)

                    // COMMENTS
                    commentsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .refreshable { await loadComments() }

            // INPUT BAR
            Divider()
            commentInputBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !didLogView {
                didLogView = true
                await api.recordHistoryView(postId: post.id)
            }

            await loadComments()
            isLiked = await api.isPostLiked(post.id)
            isSaved = await api.isPostSaved(post.id)
        }
        .onAppear { viewStart = Date() }
        .onDisappear {
            if let t0 = viewStart {
                Task {
                    await api.recordViewTime(
                        postId: post.id,
                        seconds: Date().timeIntervalSince(t0)
                    )
                }
            }
        }
    }

    // MARK: - Media

    private var mediaView: some View {
        Group {
            if let first = post.media.first {
                AsyncImage(url: first.url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(.gray.opacity(0.12))
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(.gray.opacity(0.12))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
                .cornerRadius(16)
            }
        }
    }

    // MARK: - Author row

    private var authorRow: some View {
        HStack(spacing: 10) {
            NavigationLink(
                destination: OtherUserProfileView(userId: post.author.id)
            ) {
                HStack(spacing: 10) {
                    AvatarView(user: post.author, size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let bio = post.author.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Meta row (date, like, save)

    private var metaRow: some View {
        HStack(spacing: 12) {
            Text(
                post.createdAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            // LIKE
            Button {
                toggleLikeOptimistic()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                    Text("\(likeCount)")
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .strokeBorder(isLiked ? Color.red.opacity(0.5) : Color.gray.opacity(0.25), lineWidth: 1)
                )
                .foregroundColor(isLiked ? .red : .primary)
            }
            .buttonStyle(.plain)

            // SAVE
            Button {
                toggleSaveOptimistic()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    Text("Save")
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .strokeBorder(isSaved ? Color.blue.opacity(0.5) : Color.gray.opacity(0.25), lineWidth: 1)
                )
                .foregroundColor(isSaved ? .blue : .primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Optimistic like/save

    private func toggleLikeOptimistic() {
        let newState = !isLiked
        let delta = newState ? 1 : -1

        isLiked = newState
        likeCount = max(0, likeCount + delta)

        Task {
            do {
                _ = try await api.toggleLike(for: post.id)
            } catch {
                await MainActor.run {
                    isLiked.toggle()
                    likeCount = max(0, likeCount - delta)
                }
                print("❌ like failed:", error)
            }
        }
    }

    private func toggleSaveOptimistic() {
        let newState = !isSaved
        isSaved = newState

        Task {
            do {
                _ = try await api.toggleSave(for: post.id)
            } catch {
                await MainActor.run {
                    isSaved.toggle()
                }
                print("❌ save failed:", error)
            }
        }
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comments")
                    .font(.headline)
                if !comments.isEmpty {
                    Text("• \(comments.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoadingComments {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            if commentThreads.isEmpty && !isLoadingComments {
                Text("Be the first to comment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(commentThreads) { thread in
                        CommentRow(
                            postId: post.id,
                            comment: thread.parent,
                            replies: thread.replies,
                            onReplyAdded: {
                                Task { await loadComments() }
                            }
                        )
                    }
                }
            }
        }
    }

    private var commentInputBar: some View {
        HStack(spacing: 8) {
            TextField("Write a comment…", text: $newComment, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await addComment() }
            } label: {
                Text("Send")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - I/O

    private func loadComments() async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            comments = try await api.fetchComments(postId: post.id, limit: 100)
        } catch {
            print("⚠️ loadComments:", error.localizedDescription)
        }
    }

    private func addComment() async {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            _ = try await api.addComment(postId: post.id, text: text)
            newComment = ""
            await loadComments()
        } catch {
            print("❌ addComment:", error.localizedDescription)
        }
    }
}
