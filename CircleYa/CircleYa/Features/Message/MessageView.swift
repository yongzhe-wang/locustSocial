import SwiftUI
import FirebaseAuth

struct MessagesView: View {
    @StateObject private var vm: ThreadsVM

    init() {
        _vm = StateObject(wrappedValue: ThreadsVM())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundMain.ignoresSafeArea()
                
                if vm.items.isEmpty {
                    // Empty State
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundStyle(Theme.primaryBrand.opacity(0.5))
                        
                        Text("Conversations grow slowly here.")
                            .font(.system(.title3, design: .rounded).weight(.medium))
                            .foregroundColor(Theme.textPrimary)
                        
                        Text("When they start, they tend to matter.")
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                    }
                } else {
                    // Conversations list
                    List {
                        ForEach(vm.items) { item in
                            NavigationLink(
                                destination: ChatView(
                                    thread: item.thread,
                                    otherUser: item.otherUser,
                                    isMutual: false
                                )
                            ) {
                                HStack(spacing: 16) {
                                    // Avatar
                                    ZStack(alignment: .topTrailing) {
                                        AvatarView(user: item.otherUser, size: 50)
                                        
                                        // Unread indicator (mock logic for now)
                                        if item.thread.unreadCount(for: Auth.auth().currentUser?.uid ?? "") > 0 {
                                            Circle()
                                                .fill(Theme.primaryBrand)
                                                .frame(width: 12, height: 12)
                                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.otherUser.displayName)
                                            .font(.system(.headline, design: .rounded))
                                            .foregroundColor(Theme.textPrimary)

                                        Text(item.lastMessagePreview)
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundColor(Theme.textSecondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if let ts = item.lastMessageAt {
                                        Text(ts.formatted(date: .omitted, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textHint)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .task {
                vm.start()
            }
            .onDisappear {
                vm.stop()
            }
        }
    }
}

