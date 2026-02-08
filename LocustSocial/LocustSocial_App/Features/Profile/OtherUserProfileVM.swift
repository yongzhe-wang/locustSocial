// Features/Profile/OtherUserProfileVM.swift
import Foundation
import FirebaseFirestore

@MainActor
final class OtherUserProfileVM: ObservableObject {
    @Published var user: User               // the profile being viewed
    @Published var followerCount: Int
    @Published var followingCount: Int
    @Published var isMutual: Bool = false
    @Published var amIFollowing: Bool = false

    private let api = FollowAPI()
    private var followerListener: ListenerRegistration?
    private var followingListener: ListenerRegistration?

    init(user: User, followerCount: Int, followingCount: Int) {
        self.user = user
        self.followerCount = followerCount
        self.followingCount = followingCount
    }

    func loadInitial() {
        Task {
            amIFollowing = await api.amIFollowing(user.id)
            isMutual = await api.isMutual(with: user.id)
        }
    }

    func startLiveCountListeners() {
        // Optional: keeps the numbers in sync if other devices change state.
        let db = Firestore.firestore()
        followerListener = db.collection("users").document(user.id)
            .collection("followers")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                Task { @MainActor in self.followerCount = snap.documents.count }
            }

        followingListener = db.collection("users").document(user.id)
            .collection("following")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                Task { @MainActor in self.followingCount = snap.documents.count }
            }
    }

    func stopLiveCountListeners() {
        followerListener?.remove(); followerListener = nil
        followingListener?.remove(); followingListener = nil
    }

    // Called by FollowButton callback
    func applyFollowToggle(result: FollowToggleResult) {
        amIFollowing = result.isFollowing
        followerCount += result.followerDelta   // bump their followers immediately
        // If you also display "their following" here, adjust with result.followingDelta appropriately.
        Task { isMutual = await api.isMutual(with: user.id) }
    }
}
