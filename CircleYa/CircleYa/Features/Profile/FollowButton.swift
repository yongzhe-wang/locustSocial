import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct FollowButton: View {
    let user: User
    @Binding var isFollowing: Bool
    var onCountsDelta: (Int) -> Void
    var onMutualChange: (Bool) -> Void

    @State private var isBusy = false

    private let db = Firestore.firestore()
    private var me: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        Button {
            Task { await toggleFollow() }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        // Color + text change
        .tint(isFollowing ? .gray.opacity(0.2) : .blue)
        .foregroundColor(isFollowing ? .primary : .white)
        .disabled(isBusy || me == nil || me == user.id)
    }

    private func toggleFollow() async {
        guard let me = me, me != user.id else { return }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let myFollowingRef = db.collection("users").document(me)
                .collection("following").document(user.id)
            let theirFollowersRef = db.collection("users").document(user.id)
                .collection("followers").document(me)

            let currentlyFollowing = isFollowing

            if currentlyFollowing {
                // Unfollow
                try await myFollowingRef.delete()
                try await theirFollowersRef.delete()
                await MainActor.run {
                    isFollowing = false
                    onCountsDelta(-1)
                }
            } else {
                // Follow
                try await myFollowingRef.setData(["createdAt": FieldValue.serverTimestamp()])
                try await theirFollowersRef.setData(["createdAt": FieldValue.serverTimestamp()])
                await MainActor.run {
                    isFollowing = true
                    onCountsDelta(1)
                }
            }

            // Recompute mutual: do they follow me?
            let theyFollowMeDoc = try await db.collection("users").document(user.id)
                .collection("following").document(me).getDocument()

            let mutualNow = theyFollowMeDoc.exists && !(!isFollowing) // basically they follow me and I now follow them
            await MainActor.run {
                onMutualChange(mutualNow)
            }
        } catch {
            print("⚠️ toggleFollow failed:", error.localizedDescription)
        }
    }
}
