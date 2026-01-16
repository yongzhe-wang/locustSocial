// CircleYa/Services/API/PersonalizedFeedAPI.swift
import Foundation

struct PersonalizedFeedAPI: FeedAPI {
    private let feed: FirebaseFeedAPI
    private let ranker: BackendRankAPI

    // Make the initializer accessible.
    init(feed: FirebaseFeedAPI = FirebaseFeedAPI(),
         ranker: BackendRankAPI = .shared) {
        self.feed = feed
        self.ranker = ranker
    }

    func fetchFeed(cursor: String?) async throws -> FeedPage {
        print("🟢 [PersonalizedFeedAPI] fetchFeed(cursor=\(cursor ?? "nil"))")

        // Ask the ranker for the correct page.
        let (ids, nextCursor) = try await ranker.rankedPostIDs(limit: 15, cursor: cursor)

        // Hydrate in that exact order.
        let posts = try await feed.fetchPostsByIdsInOrder(ids)
        let returnedIds = posts.map(\.id)

        let missing = ids.filter { !returnedIds.contains($0) }
        if !missing.isEmpty {
            print("🔍 [PersonalizedFeedAPI] MISSING ids (not in Firestore read path): \(missing)")
        }

        return FeedPage(items: posts, nextCursor: nextCursor)
    }

    func fetchNearby(cursor: String?) async throws -> FeedPage {
        try await feed.fetchNearby(cursor: cursor)
    }

    // Interactions
    func isPostLiked(_ postId: String) async -> Bool { await feed.isPostLiked(postId) }
    func isPostSaved(_ postId: String) async -> Bool { await feed.isPostSaved(postId) }
    func recordHistoryView(postId: String) async { await feed.recordHistoryView(postId: postId) }
    func recordViewTime(postId: String, seconds: Double) async { await feed.recordViewTime(postId: postId, seconds: seconds) }
    func toggleLike(for postId: String) async throws -> Bool { try await feed.toggleLike(for: postId) }
    func toggleSave(for postId: String) async throws -> Bool { try await feed.toggleSave(for: postId) }
    
    // Comments
    func addComment(postId: String, text: String, isAI: Bool) async throws -> Comment { 
        try await feed.addComment(postId: postId, text: text, isAI: isAI) 
    }
    func fetchComments(postId: String, limit: Int) async throws -> [Comment] { try await feed.fetchComments(postId: postId, limit: limit) }
}
