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
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    ScrollView {
                        MasonryLayout(columns: 2, spacing: 1) {
                            ForEach(vm.items, id: \.id) { post in
                                NavigationLink(value: post) {
                                    FeedCard(post: post)
                                }
                                .buttonStyle(.plain)
                            }

                            // Bottom refresher
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .refreshable { await vm.refresh() }
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                guard !didKickoff else { return }
                didKickoff = true
                Task { await vm.loadInitial() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SearchView(api: AppContainer.live.feedAPI)) {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .navigationDestination(for: Post.self) { post in
                PostDetailView(post: post)
            }
            .navigationDestination(for: User.self) { user in
                OtherUserProfileView(userId: user.id)
            }
            .overlay { if vm.isLoading { ProgressView() } }
        }
    }
}
