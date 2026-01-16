import SwiftUI

struct FeedView: View {
    @StateObject private var vm: FeedVM
    @State private var scrollProxy: ScrollViewProxy?
    private let topAnchorID = "top-anchor"
    @State private var didKickoff = false
    
    
    init(container: AppContainer = .live) {
        _vm = StateObject(wrappedValue: FeedVM(api: container.feedAPI))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // Top anchor for "scroll to top"
                    Color.clear
                        .frame(height: 0)
                        .id(topAnchorID)
                        .onAppear { scrollProxy = proxy }

                    if let updated = vm.lastUpdated {
                        Text("Today · \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 4)
                    }

                    ScrollView {
                        MasonryLayout(columns: 2, spacing: 6) {
                            ForEach(vm.items, id: \.id) { post in
                                NavigationLink(value: post) {
                                    MasonryFeedCard(post: post)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)

                        // Bottom refresher
                        if vm.hasMore && !vm.isLoading {
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .global).minY) { y in
                                        let screenHeight = UIScreen.main.bounds.height
                                        let triggerThreshold = screenHeight * 1.2
                                        if y < triggerThreshold {
                                            Task { await vm.loadMore() }
                                        }
                                    }
                                    .frame(height: 1)
                            }
                            .frame(height: 1)
                        } else if vm.isLoadingMore {
                            ProgressView().padding(.vertical, 12)
                        } else if !vm.items.isEmpty {
                            
                            Text("You’re all caught up")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        }
                    }
                    .refreshable { await vm.refresh() }
                    .navigationDestination(for: Post.self) { post in
                        PostDetailView(post: post)
                    }
                    .navigationDestination(for: User.self) { user in
                        OtherUserProfileView(userId: user.id)
                    }
                }
            }
            // .navigationTitle("hi, Day")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didKickoff else { return }
                didKickoff = true
                Task { await vm.loadInitial() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink(destination: MessagesView()) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.primaryBrand)
                        }
                        
                        NavigationLink(destination: SearchView(api: AppContainer.live.feedAPI)) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.primaryBrand)
                                .padding(10)
                                .background(
                                    Circle()
                                        .stroke(Theme.primaryBrand.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
            .overlay { if vm.isLoading { ProgressView() } }
        }
    }
}
