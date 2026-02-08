
import Foundation

// MARK: - Protocols
protocol FeedAPI {
    func fetchFeed(cursor: String?) async throws -> FeedPage
    func fetchNearby(cursor: String?) async throws -> FeedPage   // NEW
}


final class AppContainer {
    let feedAPI: FeedAPI

    init(feedAPI: FeedAPI) {
        self.feedAPI = feedAPI
    }
}

// LocustSocial/DI/AppContainer.swift

extension AppContainer {
    static var live: AppContainer {
        // OLD: .init(feedAPI: FirebaseFeedAPI())
        .init(feedAPI: PersonalizedFeedAPI(feed: FirebaseFeedAPI()))
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
