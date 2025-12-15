//
//  ThreadsVM.swift
//  CircleYa
//
//  Created by Andrew Wang on 11/18/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// What `MessagesView` actually needs for each row.
struct ConversationItem: Identifiable {
    let id: String
    let thread: DMThread
    let otherUser: User
    let lastMessagePreview: String
    let lastMessageAt: Date?
}

@MainActor
final class ThreadsVM: ObservableObject {
    @Published var items: [ConversationItem] = []

    private let api: FirebaseMessagesAPI
    private let me: String

    nonisolated(unsafe) private var listener: ListenerRegistration?

    init(
        api: FirebaseMessagesAPI = FirebaseMessagesAPI(),
        me: String = Auth.auth().currentUser?.uid ?? ""
    ) {
        self.api = api
        self.me = me
    }

    func start() {
        guard !me.isEmpty else { return }

        stop()

        listener = api.threadsQuery(for: me).addSnapshotListener { [weak self] snap, _ in
            guard let self, let docs = snap?.documents else { return }

            Task { @MainActor in
                self.items = await self.buildItems(from: docs)
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    deinit {
        listener?.remove()
    }

    private func buildItems(from docs: [QueryDocumentSnapshot]) async -> [ConversationItem] {
        var result: [ConversationItem] = []
        result.reserveCapacity(docs.count)

        for doc in docs {
            if let row = await api.buildConversationItem(from: doc, currentUserId: me) {
                result.append(row)
            }
        }

        // they’re already ordered by lastMessageAt in the query,
        // but you can sort here if you ever change the query
        return result
    }
}
