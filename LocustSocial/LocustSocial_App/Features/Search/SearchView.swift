import SwiftUI
import FirebaseFirestore

@MainActor
struct SearchView: View {
    enum Segment: String, CaseIterable { case posts = "Posts", users = "Users" }

    let api: FeedAPI

    @State private var query = ""
    @State private var segment: Segment = .posts

    @State private var isLoading = false
    @State private var postResults: [Post] = []
    @State private var userResults: [User] = []

    var body: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search users or posts", text: $query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { Task { await runSearch() } }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        postResults = []
                        userResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal)

            // Segmented control
            Picker("Type", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Results
            ScrollView {
                LazyVStack(spacing: 12) {
                    if query.isEmpty {
                        Text("Start typing to search posts or people.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    } else if isLoading {
                        ProgressView()
                            .padding(.top, 24)
                    } else {
                        if segment == .posts {
                            if postResults.isEmpty {
                                Text("No posts found.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 24)
                            } else {
                                ForEach(postResults, id: \.id) { post in
                                    NavigationLink(destination: PostDetailView(post: post)) {
                                        postRow(post)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            if userResults.isEmpty {
                                Text("No users found.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 24)
                            } else {
                                ForEach(userResults, id: \.id) { user in
                                    NavigationLink(
                                        destination: OtherUserProfileView(userId: user.id)
                                    ) {
                                        userRow(user)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Search") {
                        Task { await runSearch() }
                    }
                }
            }
        }
    }

    // MARK: - Row views

    @ViewBuilder
    private func postRow(_ post: Post) -> some View {
        HStack(spacing: 12) {
            if let m = post.media.first {
                AsyncImage(url: m.thumbURL ?? m.url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 70, height: 70)
                .clipped()
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !post.title.isEmpty {
                    Text(post.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(post.text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("@\(post.author.idForUsers) • \(post.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    @ViewBuilder
    private func userRow(_ user: User) -> some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.headline)

                Text("@\(user.idForUsers)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Search

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { postResults = []; userResults = []; return }

        isLoading = true
        defer { isLoading = false }

        // Posts: reuse your current feed then filter locally
        if let page = try? await api.fetchFeed(cursor: nil) {
            postResults = page.items.filter {
                $0.title.lowercased().contains(q) ||
                $0.text.lowercased().contains(q)  ||
                $0.tags.contains { $0.lowercased().contains(q) } ||
                $0.author.displayName.lowercased().contains(q) ||
                $0.author.idForUsers.lowercased().contains(q)
            }
        } else {
            postResults = []
        }

        // Users: simple fetch+filter
        do {
            let snap = try await Firestore.firestore()
                .collection("users")
                .limit(to: 100)
                .getDocuments()

            userResults = snap.documents.compactMap { doc in
                let d = doc.data()
                let display = (d["displayName"] as? String) ?? ""
                let handle  = (d["idForUsers"] as? String)
                    ?? (d["handle"] as? String) ?? ""
                let email   = (d["email"] as? String) ?? ""
                let avatar  = (d["avatarURL"] as? String).flatMap(URL.init(string:))

                return User(
                    id: doc.documentID,
                    idForUsers: handle,
                    displayName: display,
                    email: email,
                    avatarURL: avatar,
                    bio: d["bio"] as? String
                )
            }
            .filter {
                $0.displayName.lowercased().contains(q) ||
                $0.idForUsers.lowercased().contains(q)
            }
        } catch {
            userResults = []
            print("User search failed:", error.localizedDescription)
        }
    }
}
