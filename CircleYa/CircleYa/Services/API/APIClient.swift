
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

    // Interactions
    func isPostLiked(_ postId: String) async -> Bool { false }
    func isPostSaved(_ postId: String) async -> Bool { false }
    func recordHistoryView(postId: String) async {}
    func recordViewTime(postId: String, seconds: Double) async {}
    func toggleLike(for postId: String) async throws -> Bool { throw URLError(.badURL) }
    func toggleSave(for postId: String) async throws -> Bool { throw URLError(.badURL) }
    
    // Comments
    func addComment(postId: String, text: String, isAI: Bool) async throws -> Comment { throw URLError(.badURL) }
    func fetchComments(postId: String, limit: Int) async throws -> [Comment] { throw URLError(.badURL) }
}
