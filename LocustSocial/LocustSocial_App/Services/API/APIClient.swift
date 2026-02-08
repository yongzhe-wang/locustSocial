
import Foundation

// Example of a future real API client (using URLSession)
struct LiveFeedAPI: FeedAPI {
    func fetchFeed(cursor: String?) async throws -> FeedPage {
        // TODO: Replace with real networking.
        throw URLError(.badURL)
    }
    func fetchNearby(cursor: String?) async throws -> FeedPage {
        throw URLError(.badURL)
    }
}
