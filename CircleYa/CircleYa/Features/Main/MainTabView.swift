import SwiftUI

extension Notification.Name {
    static let refreshDiscover = Notification.Name("refreshDiscover")
}

struct MainTabView: View {
    enum Tab { case discover, create, messages, profile }
    @State private var selection: Tab = .discover

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(Theme.backgroundMain.opacity(0.9))
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        
        // Apply pplLikeME theme
        UITabBar.appearance().tintColor = UIColor(Theme.primaryBrand)
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.textHint)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        VStack(spacing: 0) {
            
            ZStack(alignment: .bottom) {
                TabView(selection: $selection) {
                    FeedView()
                        .tag(Tab.discover)
                        .toolbar(.hidden, for: .tabBar)

                    CreatePostView()
                        .tag(Tab.create)
                        .toolbar(.hidden, for: .tabBar)

                    ProfileView()
                        .tag(Tab.profile)
                        .toolbar(.hidden, for: .tabBar)
                }

                // Custom Floating Tab Bar
                HStack(spacing: 0) {
                    tabButton(title: "Home", icon: "house", selectedIcon: "house.fill", tab: .discover)
                    tabButton(title: "Share", icon: "plus.circle", selectedIcon: "plus.circle.fill", tab: .create)
                    tabButton(title: "Me", icon: "person.crop.circle", selectedIcon: "person.crop.circle.fill", tab: .profile)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            }
            .ignoresSafeArea(.keyboard)
        }
    }

    private func tabButton(title: String, icon: String, selectedIcon: String, tab: Tab) -> some View {
        Button {
            if selection == tab && tab == .discover {
                 NotificationCenter.default.post(name: .refreshDiscover, object: nil)
            }
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selection == tab ? selectedIcon : icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(selection == tab ? Theme.primaryBrand : .secondary)
        }
    }
}
