
import Foundation

struct Post: Identifiable, Codable, Hashable {
    let id: String
    let author: User
    var text: String
    let media: [Media]
    let tags: [String]
    let createdAt: Date
    var title:String
    var likeCount: Int
    var saveCount: Int
    var commentCount: Int
    
    // Source Tracing & Fact Locking
    var originalText: String?
    var preservedFacts: [String]?
    var adaptationLog: [String]?
    var adaptationStyle: String?
}

struct FeedPage: Codable {
    var items: [Post]
    var nextCursor: String?
}
