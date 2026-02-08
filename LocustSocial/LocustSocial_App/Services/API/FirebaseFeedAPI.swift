//
//  FirebaseFeedAPI.swift
//  LocustSocial
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import UIKit

// MARK: - Errors
enum AuthError: Error {
    case noUser
    case noAuthor
}

actor UserCache {
    static let shared = UserCache()
    private var cache: [String: (user: User, stamp: Date)] = [:]

    func get(_ uid: String, maxAge: TimeInterval = 60) -> User? {
        guard let e = cache[uid] else { return nil }
        return Date().timeIntervalSince(e.stamp) <= maxAge ? e.user : nil
    }
    func set(_ uid: String, user: User) { cache[uid] = (user, Date()) }
    func invalidate(_ uid: String? = nil) {
        if let uid { cache.removeValue(forKey: uid) } else { cache.removeAll() }
    }
}

// MARK: - Centralized Firestore Paths (schema aligned with your design)
private enum FSPath {
    static let db = Firestore.firestore()

    // Collections
    static var posts: CollectionReference { db.collection("posts") }
    static func user(_ uid: String) -> DocumentReference { db.collection("users").document(uid) }

    // Subcollections under /users/{uid}
    static func userHistory(_ uid: String) -> CollectionReference {
        user(uid).collection("history")
    }
    static func userSaves(_ uid: String) -> CollectionReference {
        user(uid).collection("saves")
    }
    static func userFollowers(_ uid: String) -> CollectionReference {
        user(uid).collection("followers")
    }
    static func userFollowing(_ uid: String) -> CollectionReference {
        user(uid).collection("following")
    }
    static func userSettingPreferences(_ uid: String) -> CollectionReference {
        user(uid).collection("settingPreferences")
    }
    static func userCreator(_ uid: String) -> CollectionReference {
        user(uid).collection("creator")
    }
    static func userPostsICreate(_ uid: String) -> CollectionReference {
        user(uid).collection("postsICreate")
    }
    // (Optional) separate likes subcollection for fast membership checks
    static func userLikes(_ uid: String) -> CollectionReference {
        user(uid).collection("likes")
    }
}

// MARK: - API
struct FirebaseFeedAPI: FeedAPI {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: Feed (Discover)
    // FirebaseFeedAPI.swift

    private let pageLimit = 15

    func fetchFeed(cursor: String?) async throws -> FeedPage {
        // 1) order by createdAt DESC, then documentID DESC (stable tiebreaker)
        var query = FSPath.posts
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: pageLimit)

        // 2) decode cursor (timestamp + docID) and apply start(after:)
        if let cursor {
            let (ts, docId) = try decodeCursor(cursor)
            print("📨 fetchFeed cursor=\(cursor) ⇒ startAfter [\(ts), \(docId)]")
            query = query.start(after: [ts, docId])  // ordering tuple matches query
        } else {
            print("📨 fetchFeed first page")
        }

        let snap = try await query.getDocuments()
        let posts = try await decodePosts(snap.documents)

        // 3) nextCursor from the last doc’s createdAt & docID
        let nextCursor: String? = {
            guard snap.documents.count == pageLimit,
                  let last = snap.documents.last,
                  let ts = last.data()["createdAt"] as? Timestamp
            else { return nil }
            return encodeCursor(ts: ts, id: last.documentID)
        }()

        print("📦 fetchFeed count=\(posts.count) nextCursor=\(nextCursor ?? "nil")")
        return FeedPage(items: posts, nextCursor: nextCursor)
    }
    func fetchNearby(cursor: String?) async throws -> FeedPage {
        // plug a geo-filter later; keep the same paging contract
        try await fetchFeed(cursor: cursor)
    }
    // Cursor helpers stay the same
    private func encodeCursor(ts: Timestamp, id: String) -> String {
        "\(ts.seconds).\(ts.nanoseconds)|\(id)"
    }
    private func decodeCursor(_ s: String) throws -> (Timestamp, String) {
        let parts = s.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let dot = parts[0].firstIndex(of: ".") else {
            throw NSError(domain: "cursor", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad cursor"])
        }
        let sec = Int64(parts[0][..<dot]) ?? 0
        let nsec = Int32(parts[0][parts[0].index(after: dot)...]) ?? 0
        return (Timestamp(seconds: sec, nanoseconds: nsec), parts[1])
    }



    // MARK: Upload Post (Global + /users/{uid}/postsICreate)
    func uploadPost(text: String, image: UIImage?) async throws {
        guard let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }

        Log.info("🚀 uploadPost start uid=\(user.uid.prefix(6)) text=\(text.prefix(20))")


        // 2) upload media if provided (same as before)
        var mediaItems: [[String: Any]] = []
        if let image = image {
            let imageURL = try await uploadImage(image)
            mediaItems = [[
                "id": UUID().uuidString,
                "type": "image",
                "url": imageURL.absoluteString,
                "width": 600,
                "height": 600,
                "thumbURL": imageURL.absoluteString
            ]]
        }

        // 3) prepare post object
        let postId = UUID().uuidString
        var postData: [String: Any] = [
            "id": postId,
            "authorId": user.uid,
            "text": text,
            "media": mediaItems,
            "tags": [],
            "createdAt": FieldValue.serverTimestamp(),
            "likeCount": 0,
            "saveCount": 0,
            "commentCount": 0
        ]

        // 3b) add embedding if we got one

        // 4) write global post
        try await FSPath.posts.document(postId).setData(postData)

        // 5) write user pointer
        try await FSPath.userPostsICreate(user.uid).document(postId).setData([
            "postRef": FSPath.posts.document(postId).path,
            "createdAt": FieldValue.serverTimestamp()
        ])

        Log.info("✅ uploadPost done id=\(postId)")
    }


    func uploadPost(title: String, text: String, image: UIImage?) async throws {
        guard let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }

        Log.info("🚀 uploadPost start uid=\(user.uid.prefix(6)) title=\(title.prefix(20)) text=\(text.prefix(20))")

        var mediaItems: [[String: Any]] = []
        if let image = image {
            let imageURL = try await uploadImage(image)
            mediaItems = [[
                "id": UUID().uuidString,
                "type": "image",
                "url": imageURL.absoluteString,
                "width": 600,
                "height": 600,
                "thumbURL": imageURL.absoluteString
            ]]
        }

        let postId = UUID().uuidString
        var postData: [String: Any] = [
            "id": postId,
            "authorId": user.uid,
            "title": title,                // ← NEW FIELD
            "text": text,                  // ← BODY / CONTENT
            "media": mediaItems,
            "tags": [],
            "createdAt": FieldValue.serverTimestamp(),
            "likeCount": 0,
            "saveCount": 0,
            "commentCount": 0
        ]

        try await FSPath.posts.document(postId).setData(postData)

        try await FSPath.userPostsICreate(user.uid).document(postId).setData([
            "postRef": FSPath.posts.document(postId).path,
            "createdAt": FieldValue.serverTimestamp()
        ])

        Log.info("✅ uploadPost done id=\(postId)")
    }
    
    
    // MARK: Upload Image helper
    func uploadImage(_ image: UIImage) async throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotCreateFile)
        }
        let name = "posts/\(UUID().uuidString).jpg"
        let ref = storage.reference().child(name)
        _ = try await ref.putDataAsync(data)
        return try await ref.downloadURL()
    }

    // MARK: Decode a batch of posts
    private func decodePosts(_ docs: [QueryDocumentSnapshot]) async throws -> [Post] {
        var posts: [Post] = []
        posts.reserveCapacity(docs.count)

        for doc in docs {
            do {
                let post = try await decodePost(from: doc.data(), id: doc.documentID)
                posts.append(post)
            } catch {
                Log.warn("⚠️ decodePosts skip \(doc.documentID): \(error.localizedDescription)")
            }
        }
        return posts
    }

    // MARK: Decode a single post (with live author lookup)
    func decodePost(from data: [String: Any], id: String) async throws -> Post {
        let authorId = data["authorId"] as? String ?? ""
        guard !authorId.isEmpty else { throw AuthError.noAuthor }

        // Fetch author from /users/{uid} (cached)
        let author = try await fetchAuthor(for: authorId)

        // Decode media
        let mediaArray: [Media] = (data["media"] as? [[String: Any]] ?? []).compactMap { m in
            guard let urlStr = m["url"] as? String, let url = URL(string: urlStr) else { return nil }
            let thumbStr = (m["thumbURL"] as? String) ?? urlStr
            return Media(
                id: (m["id"] as? String) ?? UUID().uuidString,
                type: .image,
                url: url,
                width: (m["width"] as? Int) ?? 600,
                height: (m["height"] as? Int) ?? 600,
                thumbURL: URL(string: thumbStr)
            )
        }

        // Timestamp
        let timestamp = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let title = (data["title"] as? String) ?? ""
        
        return Post(
            id: id,
            author: author,
            text: (data["text"] as? String) ?? "",
            media: mediaArray,
            tags: (data["tags"] as? [String]) ?? [],
            createdAt: timestamp,
            title: title,
            likeCount: (data["likeCount"] as? Int) ?? 0,
            saveCount: (data["saveCount"] as? Int) ?? 0,
            commentCount: (data["commentCount"] as? Int) ?? 0
        )
    }
    // FirebaseFeedAPI.fetchAuthor(for:)
    private func fetchAuthor(for uid: String) async throws -> User {
        // Skip cache for "me" (profile edits), otherwise use TTL
        if uid != Auth.auth().currentUser?.uid, let cached = await UserCache.shared.get(uid) {
            return cached
        }

        let doc = try await FSPath.user(uid).getDocument()
        let data = doc.data() ?? [:]

        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        let author = User(
            id: uid,
            idForUsers: (data["idForUsers"] as? String)
                ?? (data["handle"] as? String)
                ?? (data["email"] as? String)?.components(separatedBy: "@").first
                ?? "user",
            displayName: (data["displayName"] as? String) ?? "Unknown",
            email: (data["email"] as? String) ?? "",
            avatarURL: (data["avatarURL"] as? String).flatMap(URL.init(string:)),
            bio: data["bio"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: updatedAt,
            numTotalLikes: data["numTotalLikes"] as? Int,
            numTotalSaves: data["numTotalSaves"] as? Int
        )

        await UserCache.shared.set(uid, user: author)
        return author
    }
    


}
// MARK: - Replies
extension FirebaseFeedAPI {
    @discardableResult
    func addReply(
        postId: String,
        parentCommentId: String,
        text: String
    ) async throws -> Comment {
        guard let me = Auth.auth().currentUser else {
            throw URLError(.userAuthenticationRequired)
        }

        let id  = UUID().uuidString
        let now = Date()

        // write to Firestore
        try await commentsCollection(postId).document(id).setData([
            "id": id,
            "postId": postId,
            "parentId": parentCommentId,
            "authorId": me.uid,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "likeCount": 0,
            "dislikeCount": 0
        ])

        // fetch full author so UI has avatar, displayName, etc.
        let author = try await fetchAuthor(for: me.uid)

        // build Comment in memory (no Decoder involved)
        return Comment(
            id: id,
            postId: postId,
            author: author,
            text: text,
            createdAt: now,
            likeCount: 0,
            dislikeCount: 0,
            parentId: parentCommentId    // include if your Comment has this field
        )
    }
}



// MARK: - Like / Save operations (aligned with subcollections in your design)
extension FirebaseFeedAPI {


    // Convenience checks used by UI
    func isPostLiked(_ postId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return (try? await FSPath.userLikes(uid).document(postId).getDocument().exists) ?? false
    }

    func isPostSaved(_ postId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return (try? await FSPath.userSaves(uid).document(postId).getDocument().exists) ?? false
    }
}

// MARK: - History (viewed posts)
extension FirebaseFeedAPI {
    /// Log that the current user viewed a post.
    func recordHistoryView(postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FSPath.userHistory(uid)
                .document(postId)
                .setData(["viewedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            print("⚠️ recordHistoryView failed:", error.localizedDescription)
        }
    }

    /// Fetch recently viewed posts for current user, newest first.
    func fetchHistory(limit: Int = 50) async throws -> [Post] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }

        let historySnap = try await FSPath.userHistory(uid)
            .order(by: "viewedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        var posts: [Post] = []
        for doc in historySnap.documents {
            let postId = doc.documentID
            do {
                let postDoc = try await FSPath.posts.document(postId).getDocument()
                if let data = postDoc.data() {
                    let post = try await decodePost(from: data, id: postId)
                    posts.append(post)
                }
            } catch {
                print("⚠️ history decode failed for \(postId):", error.localizedDescription)
            }
        }
        return posts
    }

    /// Remove one item from history (for swipe-to-delete).
    func removeFromHistory(postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await FSPath.userHistory(uid).document(postId).delete()
        } catch {
            print("⚠️ removeFromHistory failed:", error.localizedDescription)
        }
    }

    /// Clear all history.
    func clearHistory() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await FSPath.userHistory(uid).getDocuments()
            let batch = Firestore.firestore().batch()
            for d in snap.documents {
                batch.deleteDocument(d.reference)
            }
            try await batch.commit()
        } catch {
            print("⚠️ clearHistory failed:", error.localizedDescription)
        }
    }
}





// FirebaseFeedAPI.swift (add near the other extensions)
extension FirebaseFeedAPI {

    private func interactionRef(uid: String, postId: String) -> DocumentReference {
        FSPath.user(uid).collection("interactions").document(postId)
    }

    /// Merge `like` flag into /users/{uid}/interactions/{postId}
    private func setLikeFlag(_ liked: Bool, for postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await interactionRef(uid: uid, postId: postId).setData([
                "like": liked,
                "lastEventAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("⚠️ setLikeFlag failed:", error.localizedDescription)
        }
    }

    /// Merge `save` flag into /users/{uid}/interactions/{postId}
    private func setSaveFlag(_ saved: Bool, for postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await interactionRef(uid: uid, postId: postId).setData([
                "save": saved,
                "lastEventAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("⚠️ setSaveFlag failed:", error.localizedDescription)
        }
    }

    /// Additive screen time (in seconds) into /users/{uid}/interactions/{postId}.viewSecs
    func recordViewTime(postId: String, seconds: Double) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard seconds > 0 else { return }
        do {
            try await interactionRef(uid: uid, postId: postId).setData([
                "viewSecs": FieldValue.increment(seconds),
                "lastEventAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("⚠️ recordViewTime failed:", error.localizedDescription)
        }
    }

    // Hook the flags from existing toggles:

    func toggleLike(for postId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { throw URLError(.userAuthenticationRequired) }

        let likeRef = FSPath.userLikes(uid).document(postId)
        let postRef = FSPath.posts.document(postId)

        let exists = try await likeRef.getDocument().exists
        if exists {
            try await likeRef.delete()
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(-1))])
            await setLikeFlag(false, for: postId)
            return false
        } else {
            try await likeRef.setData(["createdAt": FieldValue.serverTimestamp()])
            try await postRef.updateData(["likeCount": FieldValue.increment(Int64(1))])
            await setLikeFlag(true, for: postId)
            return true
        }
    }

    func toggleSave(for postId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { throw AuthError.noUser }

        let userRef = FSPath.user(uid)
        let saveRef = FSPath.userSaves(uid).document(postId)
        let postRef = FSPath.posts.document(postId)

        let doc = try await saveRef.getDocument()
        if doc.exists {
            try await saveRef.delete()
            try await userRef.updateData(["savedPostIds": FieldValue.arrayRemove([postId])])
            try await postRef.updateData(["saveCount": FieldValue.increment(Int64(-1))])
            await setSaveFlag(false, for: postId)
            return false
        } else {
            try await saveRef.setData(["createdAt": FieldValue.serverTimestamp()])
            try await userRef.updateData(["savedPostIds": FieldValue.arrayUnion([postId])])
            try await postRef.updateData(["saveCount": FieldValue.increment(Int64(1))])
            await setSaveFlag(true, for: postId)
            return true
        }
    }
    
    
    
}


// LocustSocial/Services/API/FirebaseFeedAPI.swift (append this extension)

extension FirebaseFeedAPI {
    /// Fetch posts by ID and return them in the exact order of `ids`.
    func fetchPostsByIdsInOrder(_ ids: [String]) async throws -> [Post] {
        guard !ids.isEmpty else { return [] }

        // Firestore has no "IN with order", so fetch individually then reorder.
        var map: [String: Post] = [:]
        map.reserveCapacity(ids.count)

        try await withThrowingTaskGroup(of: (String, Post?).self) { group in
            for id in ids {
                group.addTask {
                    let doc = try await FSPath.posts.document(id).getDocument()
                    guard let data = doc.data() else { return (id, nil) }
                    let post = try await self.decodePost(from: data, id: id)
                    return (id, post)
                }
            }

            for try await (id, post) in group {
                if let p = post { map[id] = p }
            }
        }

        // Preserve ranking order and drop any missing ones
        return ids.compactMap { map[$0] }
    }
}

// MARK: - Comments
extension FirebaseFeedAPI {
    private func commentsCollection(_ postId: String) -> CollectionReference {
        Firestore.firestore().collection("posts").document(postId).collection("comments")
    }
    private func commentDoc(_ postId: String, _ commentId: String) -> DocumentReference {
        commentsCollection(postId).document(commentId)
    }

    @discardableResult
    func addComment(postId: String, text: String) async throws -> Comment {
        guard let me = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }
        let id = UUID().uuidString
        try await commentsCollection(postId).document(id).setData([
            "id": id,
            "postId": postId,
            "authorId": me.uid,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "likeCount": 0,            // NEW
            "dislikeCount": 0          // NEW
        ])
        let author = try await fetchAuthor(for: me.uid)
        return Comment(id: id, postId: postId, author: author, text: text, createdAt: Date(), likeCount: 0, dislikeCount: 0)
    }

    /// Fetch newest, then sort by likes desc on the server (requires an index on createdAt/likeCount if you want compound queries later).
    func fetchComments(postId: String, limit: Int = 50) async throws -> [Comment] {
        let snap = try await commentsCollection(postId)
            .order(by: "createdAt", descending: false) // chronological is nicer for threads
            .limit(to: limit)
            .getDocuments()

        var result: [Comment] = []
        for d in snap.documents {
            let data = d.data()
            let authorId = data["authorId"] as? String ?? ""
            let author = try await fetchAuthor(for: authorId)
            let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

            result.append(
                Comment(
                    id: d.documentID,
                    postId: postId,
                    author: author,
                    text: (data["text"] as? String) ?? "",
                    createdAt: ts,
                    likeCount: (data["likeCount"] as? Int) ?? 0,
                    dislikeCount: (data["dislikeCount"] as? Int) ?? 0,
                    parentId: data["parentId"] as? String    // ← NEW
                )
            )
        }
        return result
    }

    
    @discardableResult
    func toggleCommentLike(postId: String, commentId: String) async throws -> (liked: Bool, likeCount: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { throw URLError(.userAuthenticationRequired) }

        let db = Firestore.firestore()
        let likeRef    = commentDoc(postId, commentId).collection("likes").document(uid)
        let dislikeRef = commentDoc(postId, commentId).collection("dislikes").document(uid)
        let commentRef = commentDoc(postId, commentId)

        let anyResult = try await db.runTransaction { (tx, errorPointer) -> Any? in
            do {
                // ---- ALL READS FIRST ----
                let likeSnap     = try tx.getDocument(likeRef)
                let dislikeSnap  = try tx.getDocument(dislikeRef)
                let commentSnap  = try tx.getDocument(commentRef)
                var count = (commentSnap.data()?["likeCount"] as? Int) ?? 0

                var likedNow = false
                // ---- DECIDE + WRITES ----
                if likeSnap.exists {
                    tx.deleteDocument(likeRef)
                    tx.updateData(["likeCount": FieldValue.increment(Int64(-1))], forDocument: commentRef)
                    count -= 1
                    likedNow = false
                } else {
                    tx.setData(["createdAt": FieldValue.serverTimestamp()], forDocument: likeRef)
                    tx.updateData(["likeCount": FieldValue.increment(Int64(1))], forDocument: commentRef)
                    count += 1
                    if dislikeSnap.exists {
                        tx.deleteDocument(dislikeRef)
                        tx.updateData(["dislikeCount": FieldValue.increment(Int64(-1))], forDocument: commentRef)
                    }
                    likedNow = true
                }
                return ["liked": likedNow, "count": count]
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard
            let dict  = anyResult as? [String: Any],
            let liked = dict["liked"] as? Bool,
            let count = dict["count"] as? Int
        else { throw NSError(domain: "ToggleCommentLike", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected transaction return"]) }

        return (liked, count)
    }


    
    @discardableResult
    func toggleCommentDislike(postId: String, commentId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { throw URLError(.userAuthenticationRequired) }

        let db = Firestore.firestore()
        let likeRef    = commentDoc(postId, commentId).collection("likes").document(uid)
        let dislikeRef = commentDoc(postId, commentId).collection("dislikes").document(uid)
        let commentRef = commentDoc(postId, commentId)

        let anyResult = try await db.runTransaction { (tx, errorPointer) -> Any? in
            do {
                // ---- ALL READS FIRST ----
                let disSnap  = try tx.getDocument(dislikeRef)
                let likeSnap = try tx.getDocument(likeRef)

                // ---- WRITES ----
                if disSnap.exists {
                    tx.deleteDocument(dislikeRef)
                    tx.updateData(["dislikeCount": FieldValue.increment(Int64(-1))], forDocument: commentRef)
                    return false
                } else {
                    tx.setData(["createdAt": FieldValue.serverTimestamp()], forDocument: dislikeRef)
                    tx.updateData(["dislikeCount": FieldValue.increment(Int64(1))], forDocument: commentRef)
                    if likeSnap.exists {
                        tx.deleteDocument(likeRef)
                        tx.updateData(["likeCount": FieldValue.increment(Int64(-1))], forDocument: commentRef)
                    }
                    return true
                }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard let result = anyResult as? Bool else {
            throw NSError(domain: "ToggleCommentDislike", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected transaction return"])
        }
        return result
    }



    // Optional helpers to paint initial state (not required for core flow)
    func isCommentLiked(postId: String, commentId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return (try? await commentDoc(postId, commentId).collection("likes").document(uid).getDocument().exists) ?? false
    }
    func isCommentDisliked(postId: String, commentId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return (try? await commentDoc(postId, commentId).collection("dislikes").document(uid).getDocument().exists) ?? false
    }
}

