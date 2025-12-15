// Features/Messages/MessagesList.swift
import SwiftUI
import FirebaseAuth

struct MessagesList: View {
    let thread: DMThread
    @StateObject private var vm = MessagesVM()
    private let api = FirebaseMessagesAPI()
    private var me: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.items) { m in
                        HStack {
                            if m.senderId == me { Spacer(minLength: 40) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.text)
                                    .padding(10)
                                    .background(m.senderId == me ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                if let t = m.createdAt {
                                    Text(t.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if m.senderId != me { Spacer(minLength: 40) }
                        }
                        .id(m.id)
                        .padding(.horizontal)
                    }
                }
            }
            .onChange(of: vm.items.count) { _ in
                if let last = vm.items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .onAppear { vm.start(threadId: thread.id, api: api) }
        .onDisappear { vm.stop() }
    }
}
