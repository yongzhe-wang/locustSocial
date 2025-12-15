// Features/Profile/ProfileHeaderButtons.swift
import SwiftUI

struct ProfileHeaderButtons: View {
    /// Non-optional user for this header
    let user: User

    // Follow + mutual state
    @State private var isFollowing: Bool = false
    @State private var isMutual: Bool = false

    // DM + gating state
    @State private var showChat: Bool = false
    @State private var activeThread: DMThread?
    @State private var alertText: String?

    private let dmAPI = FirebaseMessagesAPI()

    var body: some View {
        HStack(spacing: 12) {

            // Follow / Unfollow button
            FollowButton(
                user: user,
                isFollowing: $isFollowing,              // <- missing argument fixed
                onCountsDelta: { _ in
                    // update visible follower count here if this view owns one
                },
                onMutualChange: { mutual in
                    isMutual = mutual
                }
            )

            // Message button
            Button {
                Task { await startChat() }
            } label: {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("Message")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showChat) {
            if let thread = activeThread {
                NavigationStack {
                    ChatView(thread: thread, otherUser: user, isMutual: isMutual)
                }
            }
        }
        .alert("Heads up",
               isPresented: Binding(
                get: { alertText != nil },
                set: { if !$0 { alertText = nil } }
               )
        ) {
            Button("OK") { alertText = nil }
        } message: {
            Text(alertText ?? "")
        }
    }

    // MARK: - DM start

    private func startChat() async {
        do {
            let thread = try await dmAPI.ensureDMThread(with: user.id)
            let allowed = try await dmAPI.canSendMessage(in: thread.id, isMutual: isMutual)

            await MainActor.run {
                if allowed {
                    activeThread = thread
                    showChat = true
                } else {
                    alertText = "You’ve already sent a message. You can send more once they reply."
                }
            }
        } catch {
            await MainActor.run {
                alertText = error.localizedDescription
            }
        }
    }
}
