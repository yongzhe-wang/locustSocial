// CircleYa/Models/Comment.swift
import Foundation

struct Comment: Identifiable, Codable, Hashable {
    let id: String
    let postId: String
    let author: User
    let text: String
    let createdAt: Date
    var likeCount: Int = 0          // NEW
    var dislikeCount: Int = 0       // kept for logic; not shown
    var parentId: String? 
    var isAI: Bool = false
}
