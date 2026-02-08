import SwiftUI

// Install this inside the TabView hierarchy to attach a UITabBarControllerDelegate
struct TabBarReselectHandler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()

        // After this VC is inserted, walk up to the UITabBarController and set our delegate.
        DispatchQueue.main.async {
            if let tbc = Self.findTabBarController(from: vc) {
                if !(tbc.delegate is TabBarDelegateProxy) {
                    tbc.delegate = TabBarDelegateProxy.shared
                }
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // Walk up the parent chain to locate the UITabBarController created by SwiftUI's TabView.
    private static func findTabBarController(from vc: UIViewController) -> UITabBarController? {
        var parent = vc.parent
        while let p = parent {
            if let tbc = p as? UITabBarController { return tbc }
            parent = p.parent
        }
        return vc.view.window?.rootViewController as? UITabBarController
    }
}

// Delegate proxy that fires when the user taps the already-selected tab item.
final class TabBarDelegateProxy: NSObject, UITabBarControllerDelegate {
    static let shared = TabBarDelegateProxy()

    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        // Re-select on the same tab?
        if viewController == tabBarController.selectedViewController {
            // Index 0 == Discover in your TabView order
            if tabBarController.selectedIndex == 0 {
                NotificationCenter.default.post(name: .refreshDiscover, object: nil)
            }
        }
        return true
    }
}
