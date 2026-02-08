// Features/Messages/ChatView.swift
import SwiftUI

struct ChatView: View {
    let thread: DMThread
    let otherUser: User
    let isMutual: Bool

    @State private var text: String = ""
    @State private var sending = false
    @State private var blocked = false
    private let dmAPI = FirebaseMessagesAPI()

    var body: some View {
        VStack(spacing: 0) {
            // Messages list (your existing implementation)
            MessagesList(thread: thread)

            // Input bar
            VStack(spacing: 8) {
                if blocked {
                    Text("Waiting for a reply to continue.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Message \(otherUser.displayName)…", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .disabled(blocked)
                    Button {
                        Task {
                            await send()
                        }
                    } label: { Text("Send") }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || blocked || sending)
                }
            }
            .padding()
        }
        .navigationTitle(otherUser.displayName)
        .task {
            await refreshGate()
        }
    }

    private func refreshGate() async {
        do {
            let allowed = try await dmAPI.canSendMessage(in: thread.id, isMutual: isMutual)
            await MainActor.run { blocked = !allowed }
        } catch {
            await MainActor.run { blocked = false } // fail open on UI; server rules should still enforce
        }
    }

    private func send() async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        do {
            try await dmAPI.sendMessage(threadId: thread.id, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            text = ""
            // after sending, if non-mutual we should block until reply
            if !isMutual {
                blocked = true
            }
        } catch {
            // handle error toast
        }
        sending = false
    }
}
