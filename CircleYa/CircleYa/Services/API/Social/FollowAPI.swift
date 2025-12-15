// APIs/Social/FollowAPI.swift
import Foundation
import FirebaseFirestore
import FirebaseAuth

public struct FollowToggleResult {
    public let isFollowing: Bool
    public let followerDelta: Int   // +1 when I follow them, -1 when I unfollow
    public let followingDelta: Int  // +1/-1 for my own "following" count (if you show mine)
}

final class FollowAPI {
    private let db = Firestore.firestore()
    private var me: String {
        guard let uid = Auth.auth().currentUser?.uid else {
            fatalError("No authenticated user")
        }
        return uid
    }

    private func user(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    // MARK: - Reads

    func amIFollowing(_ otherUid: String) async -> Bool {
        (try? await user(me).collection("following").document(otherUid).getDocument().exists) ?? false
    }

    func isMutual(with otherUid: String) async -> Bool {
        do {
            async let a = user(me).collection("following").document(otherUid).getDocument()
            async let b = user(otherUid).collection("following").document(me).getDocument()
            let (aDoc, bDoc) = try await (a, b)
            return aDoc.exists && bDoc.exists
        } catch {
            return false
        }
    }

    // MARK: - Writes

    @discardableResult
    func toggleFollow(_ otherUid: String) async throws -> FollowToggleResult {
        let myFollowing   = user(me).collection("following").document(otherUid)
        let theirFollower = user(otherUid).collection("followers").document(me)

        let currentlyFollowing = try await myFollowing.getDocument().exists
        let batch = db.batch()

        if currentlyFollowing {
            batch.deleteDocument(myFollowing)
            batch.deleteDocument(theirFollower)
            try await batch.commit()
            return .init(isFollowing: false, followerDelta: -1, followingDelta: -1)
        } else {
            let now = ["createdAt": FieldValue.serverTimestamp()] as [String: Any]
            batch.setData(now, forDocument: myFollowing)
            batch.setData(now, forDocument: theirFollower)
            try await batch.commit()
            return .init(isFollowing: true, followerDelta: +1, followingDelta: +1)
        }
    }
}
