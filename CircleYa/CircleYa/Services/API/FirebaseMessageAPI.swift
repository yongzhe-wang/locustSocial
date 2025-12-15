// CircleYa/Services/API/FirebaseMessageAPI.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

struct DMThread: Identifiable, Hashable {
    let id: String        // Firestore document id
    let members: [String] // user ids, always sorted
}

struct DMMessage: Identifiable, Hashable {
    let id: String
    let threadId: String
    let senderId: String
    let text: String
    let createdAt: Date?

    static func from(_ doc: QueryDocumentSnapshot) -> DMMessage {
        let data = doc.data()
        return DMMessage(
            id: doc.documentID,
            threadId: data["threadId"] as? String ?? "",
            senderId: data["senderId"] as? String ?? "",
            text: data["text"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }
}

// MARK: - API

struct FirebaseMessagesAPI {
    private let db = Firestore.firestore()

    // Root collection for all DM threads
    private var threadsCollection: CollectionReference {
        db.collection("dmThreads")
    }

    private func threadDoc(_ id: String) -> DocumentReference {
        threadsCollection.document(id)
    }

    private func messagesCollection(_ threadId: String) -> CollectionReference {
        threadDoc(threadId).collection("messages")
    }

    // MARK: Thread creation / lookup

    /// Create or find the unique thread between current user and `otherUserId`.
    func ensureDMThread(with otherUserId: String) async throws -> DMThread {
        guard let me = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        precondition(me != otherUserId, "DM with self is not supported")

        // canonical pair id
        let pair = [me, otherUserId].sorted()
        let threadId = pair.joined(separator: "_")
        let ref = threadDoc(threadId)

        let snap = try await ref.getDocument()
        if !snap.exists {
            try await ref.setData([
                "members": pair,
                "createdAt": FieldValue.serverTimestamp(),
                "lastMessageText": "",
                "lastMessageAt": FieldValue.serverTimestamp(),
                "lastSenderId": ""
            ])
        }

        return DMThread(id: threadId, members: pair)
    }

    // MARK: Messages

    func sendMessage(threadId: String, text: String) async throws {
        guard let me = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let msgs = messagesCollection(threadId)
        let msgRef = msgs.document()
        let ts = FieldValue.serverTimestamp()

        // write message
        try await msgRef.setData([
            "id": msgRef.documentID,
            "threadId": threadId,
            "senderId": me,
            "text": trimmed,
            "createdAt": ts
        ])

        // update thread summary
        try await threadDoc(threadId).setData([
            "lastMessageText": trimmed,
            "lastMessageAt": ts,
            "lastSenderId": me
        ], merge: true)
    }

    /// Live query for a thread’s messages, oldest → newest.
    func messagesQuery(threadId: String) -> Query {
        messagesCollection(threadId)
            .order(by: "createdAt", descending: false)
    }

    // MARK: Gating logic

    /// If not mutual, allow only one outgoing message from `me` in this thread.
    func canSendMessage(in threadId: String, isMutual: Bool) async throws -> Bool {
        guard let me = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        if isMutual { return true }

        let snap = try await messagesCollection(threadId)
            .whereField("senderId", isEqualTo: me)
            .limit(to: 1)
            .getDocuments()

        return snap.documents.isEmpty   // true = still allowed to send first message
    }

    // MARK: Thread list (for MessagesView)

    /// All threads that involve `userId`, ordered by last message time.
    func threadsQuery(for userId: String) -> Query {
        threadsCollection
            .whereField("members", arrayContains: userId)
            .order(by: "lastMessageAt", descending: true)
    }

    /// Build a `ConversationItem` row given a thread snapshot.
    func buildConversationItem(
        from doc: QueryDocumentSnapshot,
        currentUserId me: String
    ) async -> ConversationItem? {

        let data = doc.data()
        let members = data["members"] as? [String] ?? []
        guard let otherId = members.first(where: { $0 != me }) ?? members.first else {
            return nil
        }

        // Fetch other user's profile
        let userDoc: DocumentSnapshot
        do {
            userDoc = try await db.collection("users").document(otherId).getDocument()
        } catch {
            print("⚠️ buildConversationItem: user fetch failed:", error.localizedDescription)
            return nil
        }

        let uData = userDoc.data() ?? [:]
        let avatarURL = (uData["avatarURL"] as? String).flatMap(URL.init(string:))

        let otherUser = User(
            id: otherId,
            idForUsers: (uData["idForUsers"] as? String)
                ?? (uData["handle"] as? String)
                ?? (uData["email"] as? String)?.components(separatedBy: "@").first
                ?? "user",
            displayName: (uData["displayName"] as? String) ?? "Unknown",
            email: (uData["email"] as? String) ?? "",
            avatarURL: avatarURL,
            bio: uData["bio"] as? String
        )

        let lastText = (data["lastMessageText"] as? String) ?? ""
        let lastAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()

        let thread = DMThread(id: doc.documentID, members: members)

        return ConversationItem(
            id: doc.documentID,
            thread: thread,
            otherUser: otherUser,
            lastMessagePreview: lastText.isEmpty ? "Tap to view messages" : lastText,
            lastMessageAt: lastAt
        )
    }
}
