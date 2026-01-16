
import Foundation

// MARK: - Protocols
protocol FeedAPI {
    func fetchFeed(cursor: String?) async throws -> FeedPage
    func fetchNearby(cursor: String?) async throws -> FeedPage
    
    // Interactions
    func isPostLiked(_ postId: String) async -> Bool
    func isPostSaved(_ postId: String) async -> Bool
    func recordHistoryView(postId: String) async
    func recordViewTime(postId: String, seconds: Double) async
    func toggleLike(for postId: String) async throws -> Bool
    func toggleSave(for postId: String) async throws -> Bool
    
    // Comments
    func addComment(postId: String, text: String, isAI: Bool) async throws -> Comment
    func fetchComments(postId: String, limit: Int) async throws -> [Comment]
}


final class AppContainer {
    let feedAPI: FeedAPI

    init(feedAPI: FeedAPI) {
        self.feedAPI = feedAPI
    }
}

// CircleYa/DI/AppContainer.swift

extension AppContainer {
    static var live: AppContainer {
        // Use FirebaseFeedAPI directly to ensure immediate consistency for now.
        // Was: .init(feedAPI: PersonalizedFeedAPI(feed: FirebaseFeedAPI()))
        .init(feedAPI: FirebaseFeedAPI())
    }
}


// MARK: - SwiftUI EnvironmentKey
import SwiftUI
private struct ContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer = .live
}

extension EnvironmentValues {
    var container: AppContainer {
        get { self[ContainerKey.self] }
        set { self[ContainerKey.self] = newValue }
    }
}
