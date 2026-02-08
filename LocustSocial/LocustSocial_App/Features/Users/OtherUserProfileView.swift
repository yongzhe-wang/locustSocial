import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct OtherUserProfileView: View {
    let userId: String

    @State private var user: User?
    @State private var posts: [Post] = []

    @State private var isLoading = false
    @State private var error: String?

    // Follow state
    @State private var isFollowing = false
    @State private var isTogglingFollow = false
    @State private var followerCount: Int = 0
    @State private var followingCount: Int = 0

    private let db = Firestore.firestore()
    private let api = FirebaseFeedAPI()

    // DM
    @State private var isMutual: Bool = false
    @State private var activeThread: DMThread? = nil
    @State private var alertText: String? = nil
    @State private var navigateToChat = false
    private let dmAPI = FirebaseMessagesAPI()

    private var currentUid: String? { Auth.auth().currentUser?.uid }
    private var isViewingSelf: Bool { currentUid == userId }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                // FOLLOW centered under header
                if let u = user, !isViewingSelf {
                    HStack {
                        Spacer()
                        FollowButton(
                            user: u,
                            isFollowing: $isFollowing,
                            onCountsDelta: { delta in
                                followerCount = max(0, followerCount + delta)
                            },
                            onMutualChange: { mutual in
                                isMutual = mutual
                            }
                        )
                        .frame(width: 160)
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 24) {
                    VStack {
                        Text("\(followerCount)").bold()
                        Text("Followers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("\(followingCount)").bold()
                        Text("Following")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal)

                if isLoading {
                    ProgressView("Loading…")
                        .padding()
                } else if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    MasonryLayout(columns: 2, spacing: 8) {
                        ForEach(posts) { p in
                            NavigationLink(destination: PostDetailView(post: p)) {
                                FeedCard(post: p)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle(user?.displayName.isEmpty == false ? user!.displayName : "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // MESSAGE button in top-right
            if let _ = user, !isViewingSelf {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await startChat() }
                    } label: {
                        Label("Message", systemImage: "paperplane")
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .background(
            NavigationLink(
                isActive: $navigateToChat,
                destination: {
                    if let thread = activeThread, let u = user {
                        ChatView(thread: thread, otherUser: u, isMutual: isMutual)
                    } else {
                        EmptyView()
                    }
                },
                label: { EmptyView() }
            )
            .hidden()
        )
        .alert(
            "Heads up",
            isPresented: Binding(
                get: { alertText != nil },
                set: { if !$0 { alertText = nil } }
            )
        ) {
            Button("OK") { alertText = nil }
        } message: {
            Text(alertText ?? "")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 10) {
            if let u = user, let url = u.avatarURL {
                AsyncImage(url: url) { ph in
                    switch ph {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .shadow(radius: 4)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(.secondary)
            }

            Text(user?.displayName ?? " ")
                .font(.title3)
                .bold()

            if let bio = user?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Load profile, posts, and follow state

    private func load() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        defer {
            Task { await MainActor.run { isLoading = false } }
        }

        do {
            // Profile
            let doc = try await db.collection("users").document(userId).getDocument()
            let data = doc.data() ?? [:]
            let avatar = (data["avatarURL"] as? String).flatMap(URL.init(string:))

            let u = User(
                id: userId,
                idForUsers: (data["idForUsers"] as? String)
                    ?? (data["handle"] as? String)
                    ?? "user",
                displayName: (data["displayName"] as? String) ?? "Unknown",
                email: (data["email"] as? String) ?? "",
                avatarURL: avatar,
                bio: data["bio"] as? String
            )

            await MainActor.run { self.user = u }

            // Posts
            let snap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            var decoded: [Post] = []
            for d in snap.documents {
                if let p = try? await api.decodePost(from: d.data(), id: d.documentID) {
                    decoded.append(p)
                }
            }
            await MainActor.run { self.posts = decoded }

            // Follow state + counts
            await loadFollowStateAndCounts()

            // Mutual follow state for DM gate
            if let uMe = Auth.auth().currentUser?.uid, uMe != userId {
                let myFollowing = try await db.collection("users").document(uMe)
                    .collection("following").document(userId).getDocument()
                let theyFollowMe = try await db.collection("users").document(userId)
                    .collection("following").document(uMe).getDocument()

                await MainActor.run {
                    self.isMutual = myFollowing.exists && theyFollowMe.exists
                }
            }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func loadFollowStateAndCounts() async {
        guard let me = currentUid else { return }

        async let isFollowingDoc = db.collection("users").document(me)
            .collection("following").document(userId).getDocument()

        async let followersCountAgg = db.collection("users").document(userId)
            .collection("followers").count.getAggregation(source: .server)

        async let followingCountAgg = db.collection("users").document(userId)
            .collection("following").count.getAggregation(source: .server)

        do {
            let (followDoc, followersAgg, followingAgg) =
                try await (isFollowingDoc, followersCountAgg, followingCountAgg)

            await MainActor.run {
                self.isFollowing = followDoc.exists
                self.followerCount = Int(truncating: followersAgg.count)
                self.followingCount = Int(truncating: followingAgg.count)
            }
        } catch {
            print("⚠️ follow state/counts load failed:", error.localizedDescription)
        }
    }

    // MARK: - Start chat

    private func startChat() async {
        guard !isViewingSelf else { return }

        do {
            let thread = try await dmAPI.ensureDMThread(with: userId)
            let allowed = try await dmAPI.canSendMessage(in: thread.id, isMutual: isMutual)

            await MainActor.run {
                if allowed {
                    activeThread = thread
                    navigateToChat = true
                } else {
                    alertText = "You’ve already sent a message. You can send more once they reply."
                }
            }
        } catch {
            await MainActor.run {
                alertText = error.localizedDescription
            }
        }
    }
}
