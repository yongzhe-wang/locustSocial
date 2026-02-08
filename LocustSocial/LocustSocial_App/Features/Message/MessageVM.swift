// Features/Messages/MessagesVM.swift
import Foundation
import FirebaseFirestore
@MainActor
final class MessagesVM: ObservableObject {
    @Published var items: [DMMessage] = []
    nonisolated(unsafe) private var listener: ListenerRegistration?

    func start(threadId: String, api: FirebaseMessagesAPI) {
        stop()
        listener = api.messagesQuery(threadId: threadId).addSnapshotListener { [weak self] snap, _ in
            guard let docs = snap?.documents else { return }
            self?.items = docs.map(DMMessage.from)
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    deinit {
        // safe-by-contract cleanup; no main-actor hop needed
        listener?.remove()
    }
}

