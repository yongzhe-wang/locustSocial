import SwiftUI
import FirebaseFirestore
struct FollowersListView: View {
    let userId: String

    @State private var users: [FollowUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let db = Firestore.firestore()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            ForEach(users) { user in
                FollowUserRow(user: user)
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationTitle("Followers")
        .task {
            await loadFollowers()
        }
        .refreshable {
            await loadFollowers()
        }
    }

    private func loadFollowers() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        defer {
            Task { await MainActor.run { isLoading = false } }
        }

        do {
            let snap = try await db.collection("users")
                .document(userId)
                .collection("followers")
                .order(by: "createdAt", descending: true)
                .getDocuments()

            let mapped: [FollowUser] = snap.documents.map { doc in
                let data = doc.data()
                return FollowUser(
                    id: data["id"] as? String ?? doc.documentID,
                    displayName: data["displayName"] as? String ?? "",
                    handle: data["handle"] as? String ?? "",
                    avatarURL: data["avatarURL"] as? String
                )
            }

            await MainActor.run { self.users = mapped }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load followers: \(error.localizedDescription)"
            }
        }
    }
}
