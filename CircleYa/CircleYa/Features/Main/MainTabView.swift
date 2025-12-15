import SwiftUI

extension Notification.Name {
    static let refreshDiscover = Notification.Name("refreshDiscover")
}

struct MainTabView: View {
    enum Tab { case discover, create, messages, profile }
    @State private var selection: Tab = .discover

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        UITabBar.appearance().tintColor = .black
        UITabBar.appearance().unselectedItemTintColor = .lightGray
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("Discover", systemImage: "house.fill") }
                .tag(Tab.discover)

//            NearbyView()
//                .tabItem { Label("Nearby", systemImage: "location.circle") }
//                .tag(Tab.nearby)

            CreatePostView()
                .tabItem { Label("Create", systemImage: "plus.circle") }
                .tag(Tab.create)

            MessagesView()
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(Tab.messages)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .onChange(of: selection) { _, newValue in
            // Whenever user switches TO Discover, ask it to scroll+refresh
            if newValue == .discover {
                NotificationCenter.default.post(name: .refreshDiscover, object: nil)
            }
        }
        .background(TabBarReselectHandler())   // ⬅️ install the delegate
        .tint(.blue)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(.systemBackground), for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
    }
}
