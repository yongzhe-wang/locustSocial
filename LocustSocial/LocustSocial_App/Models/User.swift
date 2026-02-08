import Foundation

struct User: Identifiable, Codable, Hashable {
    // MARK: - Core Profile Fields
    let id: String
    var idForUsers: String                // searchable user handle
    var displayName: String
    var email: String
    var avatarURL: URL?
    var bio: String?

    // MARK: - Metadata
    var createdAt: Date?
    var updatedAt: Date?

    // MARK: - Interaction Counters
    var numTotalLikes: Int?
    var numTotalSaves: Int?

    // MARK: - Preferences and Embeddings
    var preferenceEmbedding: [[Double]]?  // list of 5 embedding vectors from LLM
    var settingPreferences: SettingPreferences?

    // MARK: - Codable Key Mapping
    enum CodingKeys: String, CodingKey {
        case id
        case idForUsers
        case displayName
        case email
        case avatarURL
        case bio
        case createdAt
        case updatedAt
        case numTotalLikes
        case numTotalSaves
        case preferenceEmbedding
        case settingPreferences
    }
}

// MARK: - Nested Preferences Struct
struct SettingPreferences: Codable, Hashable {
    var autoLogin: Bool?
}
