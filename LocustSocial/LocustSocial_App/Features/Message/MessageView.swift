import SwiftUI
import FirebaseAuth

struct MessagesView: View {
    @StateObject private var vm: ThreadsVM

    init() {
        _vm = StateObject(wrappedValue: ThreadsVM())
    }

    var body: some View {
        NavigationStack {

                // Conversations list
                List {
                    Section(header: Text("Conversations")) {
                        if vm.items.isEmpty {
                            Text("No conversations yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.items) { item in
                                NavigationLink(
                                    destination: ChatView(
                                        thread: item.thread,
                                        otherUser: item.otherUser,
                                        isMutual: false   // or your real mutual flag
                                    )
                                ) {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color.blue.opacity(0.2))
                                            .frame(width: 44, height: 44)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.otherUser.displayName)
                                                .font(.headline)

                                            Text(item.lastMessagePreview)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        if let ts = item.lastMessageAt {
                                            Text(ts.formatted(date: .omitted, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .task {
                vm.start()
            }
            .onDisappear {
                vm.stop()
            }
        }
    }

