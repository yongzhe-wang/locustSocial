
import Foundation

struct Post: Identifiable, Codable, Hashable {
    let id: String
    let author: User
    let text: String
    let media: [Media]
    let tags: [String]
    let createdAt: Date
    let title:String
    var likeCount: Int
    var saveCount: Int
    var commentCount: Int
    
}

struct FeedPage: Codable {
    var items: [Post]
    var nextCursor: String?
}
