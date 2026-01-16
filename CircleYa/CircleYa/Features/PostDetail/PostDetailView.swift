import SwiftUI

struct PostDetailView: View {
    let post: Post
    @State private var adaptedPost: Post?
    
    private var displayPost: Post {
        adaptedPost ?? post
    }
    
    @Environment(\.container) private var container
    private var api: FeedAPI { container.feedAPI }
    
    @State private var comments: [Comment] = []
    @State private var newComment: String = ""
    
    @State private var isLiked: Bool = false
    @State private var isSaved: Bool = false
    @State private var likeCount: Int = 0
    
    @State private var isLoadingComments = false
    @State private var viewStart: Date?
    @State private var didLogView = false
    @State private var showSourceTrace = false

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        
                        // MEDIA
                        mediaView
                            .padding(.bottom, 16)

                        // AUTHOR
                        authorRow
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        // BODY TEXT
                        VStack(alignment: .leading, spacing: 8) {
                            if adaptedPost == nil {
                                Text("Adapting content...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if !displayPost.title.isEmpty {
                                Text(displayPost.title)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !displayPost.text.isEmpty {
                                Text(displayPost.text)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineSpacing(4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                        // META ROW
                        metaRow
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)

                        Divider()
                            .padding(.bottom, 16)

                        // COMMENTS
                        commentsSection
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                    }
                }
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
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !didLogView {
                didLogView = true
                await api.recordHistoryView(postId: post.id)
            }

            await loadComments()
            isLiked = await api.isPostLiked(post.id)
            isSaved = await api.isPostSaved(post.id)
            
            // Trigger content adaptation
            if adaptedPost == nil {
                adaptedPost = await ContentAdaptationService.shared.adaptPost(post)
            }
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
            if !post.media.isEmpty {
                TabView {
                    ForEach(post.media) { media in
                        AsyncImage(url: media.url) { phase in
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
                        .frame(height: 320)
                        .clipped()
                        .tag(media.id)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 320)
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
                        }
                    }
                }
            }
            Spacer()
            
            // Timestamp
            Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Meta Row (It resonates / Keep this)
    
    private var metaRow: some View {
        HStack(spacing: 20) {
            // LIKE -> It resonates
            Button {
                toggleLikeOptimistic()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                    Text("It resonates")
                }
                .font(.subheadline)
                .foregroundColor(isLiked ? Theme.likeRed : .secondary)
            }
            .buttonStyle(.plain)

            // SAVE -> Keep this
            Button {
                toggleSaveOptimistic()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    Text("Keep this")
                }
                .font(.subheadline)
                .foregroundColor(isSaved ? Theme.primaryBrand : .secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // TRACE SOURCE (溯源)
            if let original = displayPost.originalText {
                Button {
                    showSourceTrace = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Trace Source")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSourceTrace) {
                    SourceTraceView(post: displayPost)
                        .presentationDetents([.medium, .large])
                }
            }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Conversation")
                    .font(.headline)
                Spacer()
                if isLoadingComments {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            let commentThreads = comments.filter { !$0.isAI }

            if commentThreads.isEmpty && !isLoadingComments {
                Text("Be the first to add a thought.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(commentThreads) { thread in
                        VStack(alignment: .leading, spacing: 0) {
                            CommentRow(
                                postId: post.id,
                                comment: thread,
                                replies: [], // Assuming flat for now or handled in CommentRow
                                onReplyAdded: {
                                    Task { await loadComments() }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var commentInputBar: some View {
        HStack(spacing: 8) {
            TextField("If you want to add a thought…", text: $newComment, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            if !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await addComment() }
                } label: {
                    Text("Share")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
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
            _ = try await api.addComment(postId: post.id, text: text, isAI: false)
            newComment = ""
            await loadComments()
        } catch {
            print("❌ addComment:", error.localizedDescription)
        }
    }
}
