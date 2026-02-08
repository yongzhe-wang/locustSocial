//// Features/Nearby/NearbyView.swift
//import SwiftUI
//
//struct NearbyView: View {
//    @StateObject private var vm: FeedVM
//
//    init(container: AppContainer = .live) {
//        _vm = StateObject(wrappedValue: FeedVM(api: container.feedAPI, kind: .nearby))
//    }
//
//    var body: some View {
//        NavigationStack {
//            ScrollView {
//                MasonryLayout(columns: 2, spacing: 8) {
//                    ForEach(vm.items) { post in
//                        NavigationLink(value: post) {
//                            FeedCard(post: post)   // <-- same card component
//                        }
//                        .buttonStyle(.plain)
//                    }
//                }
//                .padding(.horizontal, 12)
//                .padding(.vertical, 12)
//            }
//            .navigationTitle("Nearby")
//            .navigationBarTitleDisplayMode(.large)
//            .task { await vm.loadInitial() }
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    NavigationLink(destination: SearchView(api: AppContainer.live.feedAPI)) {
//                        Image(systemName: "magnifyingglass")
//                    }
//                    .accessibilityLabel("Search")
//                }
//            }
//            .navigationDestination(for: Post.self) { post in
//                PostDetailView(post: post)
//            }
//            .navigationDestination(for: User.self) { user in
//                OtherUserProfileView(userId: user.id)
//            }
//            .overlay { if vm.isLoading { ProgressView() } }
//            .refreshable { await vm.loadInitial() }
//        }
//    }
//}
