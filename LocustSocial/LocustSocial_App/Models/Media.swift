
import Foundation

enum MediaType: String, Codable {
    case image, video
}

struct Media: Identifiable, Codable, Hashable {
    let id: String
    let type: MediaType
    let url: URL
    let width: Int
    let height: Int
    var thumbURL: URL?
}
