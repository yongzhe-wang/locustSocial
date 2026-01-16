// AppRouter.swift
import SwiftUI

final class AppRouter: ObservableObject {
    enum Tab: Hashable { case discover, create, messages, aiClone, profile }
    enum Route: Hashable { case conversation(withUserID: String) }

    @Published var selectedTab: Tab = .discover
    @Published var messagesPath = NavigationPath()

    func openConversation(with userID: String) {
        selectedTab = .messages
        messagesPath.removeLast(messagesPath.count)   // reset stack
        messagesPath.append(Route.conversation(withUserID: userID))
    }
}
