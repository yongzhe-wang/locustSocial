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
}
