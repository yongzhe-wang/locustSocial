import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct NotesListView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let db = Firestore.firestore()

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading your posts...")
                    .padding()
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if posts.isEmpty {
                Text("You haven’t posted anything yet.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                MasonryLayout(columns: 2, spacing: 8) {
                    ForEach(posts) { post in
                        NavigationLink(destination: PostDetailView(post: post)) {
                            FeedCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .task { await loadUserPosts() } // runs on appear
    }

    // MARK: - Firestore fetch from /users/{uid}/posts
    private func loadUserPosts() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "No user logged in"
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            guard let data = userDoc.data(),
                  let noteIds = data["notePostIds"] as? [String],
                  !noteIds.isEmpty else {
                await MainActor.run { self.posts = [] }
                return
            }

            var result: [Post] = []
            let api = FirebaseFeedAPI()

            for pid in noteIds {
                let postDoc = try await db.collection("posts").document(pid).getDocument()
                if let pdata = postDoc.data() {
                    do {
                        let post = try await api.decodePost(from: pdata, id: pid)
                        result.append(post)
                    } catch {
                        print("⚠️ Failed to decode \(pid): \(error.localizedDescription)")
                    }
                }
            }

            await MainActor.run { self.posts = result }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load: \(error.localizedDescription)"
            }
        }
    }

}


// MARK: - Placeholder History & Saved Views
// MARK: - HistoryListView
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct HistoryListView: View {
    @State private var items: [Post] = []
    @State private var isLoading = false
    @State private var error: String?

    private let api = FirebaseFeedAPI()

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading history…").padding()
            } else if let error {
                Text(error).foregroundStyle(.red).padding()
            } else if items.isEmpty {
                Text("No history yet. Open some posts and they’ll appear here.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                MasonryLayout(columns: 2, spacing: 8) {
                    ForEach(items) { post in
                        NavigationLink(destination: PostDetailView(post: post)) {
                            FeedCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty {
                    Button("Clear") {
                        Task {
                            await api.clearHistory()
                            await load()
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        await MainActor.run { isLoading = true; error = nil }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            let res = try await api.fetchHistory(limit: 100)
            await MainActor.run { items = res }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }
}



// MARK: - SavedListView
struct SavedListView: View {
    @State private var savedPosts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()
    private let api = FirebaseFeedAPI()

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading saved posts...")
                    .padding()
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if savedPosts.isEmpty {
                Text("You haven’t saved any posts yet.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                MasonryLayout(columns: 2, spacing: 8) {
                    ForEach(savedPosts) { post in
                        NavigationLink(destination: PostDetailView(post: post)) {
                            FeedCard(post: post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .task { await loadSavedPosts() }
    }

    // MARK: - Load saved posts from Firestore
    private func loadSavedPosts() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "No user logged in"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Step 1: Get saved post IDs
            let snapshot = try await db.collection("users")
                .document(uid)
                .collection("saves")
                .order(by: "createdAt", descending: true)
                .getDocuments()

            let postIds = snapshot.documents.map { $0.documentID }

            // Step 2: Fetch each post by ID
            var loaded: [Post] = []
            for pid in postIds {
                let postDoc = try await db.collection("posts").document(pid).getDocument()
                if let data = postDoc.data() {
                    do {
                        let post = try await api.decodePost(from: data, id: pid)
                        loaded.append(post)
                    } catch {
                        print("⚠️ Couldn’t decode post \(pid):", error)
                    }
                }
            }

            await MainActor.run {
                self.savedPosts = loaded
            }

        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load saved posts: \(error.localizedDescription)"
            }
        }
    }
}
