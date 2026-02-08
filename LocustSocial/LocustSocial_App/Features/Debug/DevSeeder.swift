// LocustSocial/Features/Debug/DevSeeder.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore

enum DevSeeder {
    /// Creates 5 users and 10 posts with random content.
    /// Safe to call multiple times (ids are random).
    static func run() async throws {
        let db = Firestore.firestore()

        // MARK: Users
        let firstNames = ["Alex","Bailey","Casey","Drew","Elliot","Frankie","Gabe","Harper","Indie","Jules"]
        let lastNames  = ["Rivera","Nguyen","Patel","Smith","Chen","Johnson","Garcia","Brown","Davis","Moore"]

        struct TempUser { let id: String; let handle: String }
        var createdUsers: [TempUser] = []

        for i in 0..<5 {
            let id = UUID().uuidString
            let first = firstNames.randomElement()!
            let last  = lastNames.randomElement()!
            let display = "\(first) \(last)"
            let handle = (first + last).lowercased()
            let email  = "\(handle)\(Int.random(in: 100...999))@example.com"

            try await db.collection("users").document(id).setData([
                "id": id,
                "displayName": display,
                "idForUsers": handle,
                "email": email,
                "bio": ["Loves coffee ☕️","SwiftUI fan","Photographer","Traveler ✈️","Music nerd"].randomElement()!,
                "avatarURL": "https://i.pravatar.cc/150?img=\(Int.random(in: 1...70))",  // placeholder avatar
                "numTotalLikes": 0,
                "numTotalSaves": 0,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])

            createdUsers.append(.init(id: id, handle: handle))
            print("👤 Seeded user \(i+1): \(display) (\(id))")
        }

        // MARK: Posts
        let sampleTexts = [
            "Hello, I am new to this platform",
            "What a beautiful day 🌤️",
            "SwiftUI masonry layout test",
            "Just shipped a new feature!",
            "Weekend vibes ✌️",
            "Coffee then code ☕️💻",
            "Flowers from today’s walk 🌸",
            "Trying Firebase SDKs",
            "Any book recs?",
            "Sunset appreciation post 🌅"
        ]
        let sampleTags = ["swift","ios","daily","nature","tech","life","design","music","travel","photo"]

        // Use picsum.photos placeholders for images (no Storage upload needed)
        func randomImageURL() -> String {
            let w = Int.random(in: 500...900)
            let h = Int.random(in: 500...900)
            let id = Int.random(in: 1...1000)
            return "https://picsum.photos/id/\(id)/\(w)/\(h)"
        }

        for i in 0..<10 {
            let postId = UUID().uuidString
            let author = createdUsers.randomElement()!

            let imgURL = randomImageURL()
            let media: [[String: Any]] = [[
                "id": UUID().uuidString,
                "type": "image",
                "url": imgURL,
                "width": 600,
                "height": 600,
                "thumbURL": imgURL
            ]]

            try await db.collection("posts").document(postId).setData([
                "id": postId,
                "authorId": author.id,
                "text": sampleTexts.randomElement()!,
                "media": media,
                "tags": Array(sampleTags.shuffled().prefix(Int.random(in: 0...3))),
                "createdAt": FieldValue.serverTimestamp(),
                "likeCount": Int.random(in: 0...9),
                "saveCount": Int.random(in: 0...5),
                "commentCount": Int.random(in: 0...3)
            ])

            // Optional: also create a pointer in /users/{uid}/postsICreate per your schema
            try await db.collection("users")
                .document(author.id)
                .collection("postsICreate")
                .document(postId)
                .setData([
                    "postRef": "posts/\(postId)",
                    "createdAt": FieldValue.serverTimestamp()
                ])

            print("📝 Seeded post \(i+1) (\(postId)) for user \(author.handle)")
        }

        print("✅ DevSeeder finished: 5 users + 10 posts")
    }
}
