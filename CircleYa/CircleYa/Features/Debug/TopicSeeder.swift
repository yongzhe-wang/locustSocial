// TopicSeeder.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

enum TopicSeeder {
    /// Creates 100 posts (20×5 topics) via FirebaseFeedAPI.uploadPost(title:text:image:)
    /// - Parameters:
    ///   - usePicsum: true = fetch from picsum, false = generate locally
    ///   - chunkSize: parallelism per wave
    ///   - staggerMs: tiny delay between task starts (helps avoid 429s)
    // MARK: - Seed Users
    static let seedUsers: [(uid: String, name: String, handle: String, bio: String, avatarURL: String)] = [
        ("seed_user_tennis", "Tennis Pro", "tennis_lover", "I love tennis!", "https://i.pravatar.cc/300?u=tennis"),
        ("seed_user_dancing", "Dance Star", "dancer_123", "Born to dance.", "https://i.pravatar.cc/300?u=dancing"),
        ("seed_user_china", "Traveler", "china_explorer", "Exploring the world.", "https://i.pravatar.cc/300?u=china"),
        ("seed_user_school", "Student Life", "study_buddy", "Learning every day.", "https://i.pravatar.cc/300?u=school"),
        ("seed_user_food", "Foodie", "yummy_eats", "Food is life.", "https://i.pravatar.cc/300?u=food")
    ]

    static func seed100ViaAPI(
        usePicsum: Bool = true,
        chunkSize: Int = 10,
        staggerMs: UInt64 = 80
    ) async throws {
        try await ensureAuth()
        
        // 1. Create Seed Users
        try await createSeedUsers()

        let api = FirebaseFeedAPI()
        let topics: [(tag: String, titlePrefix: String, samples: [String])] = [
            ("tennis",  "Tennis",  ["Serve practice today!", "Backhand felt solid.", "Court time at 6pm.", "Spin shots all day.", "Match recap – tough but fun."]),
            ("dancing", "Dancing", ["Practiced popping.", "Hip-hop choreo, 20s set.", "Freestyle session.", "Studio mirrors were kind.", "Footwork drills."]),
            ("china",   "China",   ["Beijing street scenes.", "Tea and calligraphy.", "Temple visit notes.", "Old hutongs walk.", "River and bridges."]),
            ("school",  "School",  ["Study group tonight.", "Project demo coming.", "Lecture highlights.", "Midterm reflections.", "Campus walk shots."]),
            ("food",    "Food",    ["Ramen night.", "Dim sum morning.", "Street tacos!", "Baked something sweet.", "Café latte art."])
        ]

        struct SeedItem: Hashable {
            let idx: Int
            let title: String
            let text: String
            let tag: String
        }

        // Build 100 items in a fixed, known order (tennis first, etc.)
        var items: [SeedItem] = []
        var global = 0
        for (tag, prefix, samples) in topics {
            for i in 1...20 {
                global += 1
                items.append(.init(
                    idx: global,
                    title: "\(prefix) #\(i)",
                    text: samples.randomElement()!,
                    tag: tag
                ))
            }
        }

        // Counters (actor ensures thread safety)
        actor Counter {
            var ok = 0
            var fail = 0
            func incOK() { ok += 1 }
            func incFail() { fail += 1 }
            func snapshot() -> (Int, Int) { (ok, fail) }
        }
        let counter = Counter()

        print("🚀 seed100ViaAPI start | total=\(items.count) usePicsum=\(usePicsum) chunkSize=\(chunkSize)")
        let t0 = Date()

        var start = 0
        while start < items.count {
            let end = min(start + chunkSize, items.count)
            let slice = Array(items[start..<end])

            print("——— CHUNK \(start)..<\(end) ———")

            await withTaskGroup(of: Void.self) { group in
                for (offset, item) in slice.enumerated() {
                    group.addTask {
                        // small stagger to reduce burst
                        if staggerMs > 0 {
                            try? await Task.sleep(nanoseconds: (staggerMs * UInt64(offset)) * 1_000_000)
                        }

                        let stamp = Self.shortStamp()
                        print("➡️ [\(stamp)] start #\(item.idx) “\(item.title)” tag=\(item.tag)")

                        do {
                            let image: UIImage? = try await (usePicsum
                                ? fetchPicsumImageWithRetry(width: 700, height: 700, retries: 2, backoffMs: 250)
                                : generatePlaceholderImage(width: 700, height: 700, title: item.title))

                            let body = "\(item.text)\n#\(item.tag)"
                            
                            // Find the correct user for this tag
                            let user = seedUsers.first { $0.uid.contains(item.tag) } ?? seedUsers[0]
                            
                            // Use custom upload function
                            try await uploadSeedPost(api: api, title: item.title, text: body, image: image, author: user)
                            await counter.incOK()

                            print("✅ [\(Self.shortStamp())] ok   #\(item.idx) “\(item.title)”")
                        } catch {
                            await counter.incFail()
                            print("❌ [\(Self.shortStamp())] fail #\(item.idx) “\(item.title)”: \(error)")
                        }
                    }
                }
                await group.waitForAll()
            }

            let (ok, fail) = await counter.snapshot()
            print("CHUNK done \(start)..<\(end) | ok=\(ok) fail=\(fail)")
            start = end
        }

        let dt = String(format: "%.2fs", Date().timeIntervalSince(t0))
        let (ok, fail) = await counter.snapshot()
        print("🏁 seed100ViaAPI finished | ok=\(ok) fail=\(fail) elapsed=\(dt)")
    }
    
    static func createSeedUsers() async throws {
        let db = Firestore.firestore()
        for u in seedUsers {
             let userData: [String: Any] = [
                "id": u.uid,
                "idForUsers": u.handle,
                "displayName": u.name,
                "email": "\(u.handle)@example.com",
                "bio": u.bio,
                "avatarURL": u.avatarURL,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await db.collection("users").document(u.uid).setData(userData, merge: true)
            print("👤 Created/Updated seed user: \(u.name) (\(u.uid))")
        }
    }
    
    static func uploadSeedPost(api: FirebaseFeedAPI, title: String, text: String, image: UIImage?, author: (uid: String, name: String, handle: String, bio: String, avatarURL: String)) async throws {
        // Replicating uploadPost logic but with explicit authorId
        
        var mediaItems: [[String: Any]] = []
        if let image = image {
            let imageURL = try await api.uploadImage(image)
            mediaItems = [[
                "id": UUID().uuidString,
                "type": "image",
                "url": imageURL.absoluteString,
                "width": 600,
                "height": 600,
                "thumbURL": imageURL.absoluteString
            ]]
        }

        let postId = UUID().uuidString
        let postData: [String: Any] = [
            "id": postId,
            "authorId": author.uid,
            "authorName": author.name,
            "authorHandle": author.handle,
            "authorAvatar": author.avatarURL,
            "title": title,
            "text": text,
            "media": mediaItems,
            "tags": [],
            "createdAt": FieldValue.serverTimestamp(),
            "likeCount": 0,
            "saveCount": 0,
            "commentCount": 0
        ]

        let db = Firestore.firestore()
        try await db.collection("posts").document(postId).setData(postData)

        try await db.collection("users").document(author.uid).collection("postsICreate").document(postId).setData([
            "postRef": db.collection("posts").document(postId).path,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Auth
    private static func ensureAuth() async throws {
        if Auth.auth().currentUser == nil {
            print("🔐 signing in anonymously…")
            _ = try await Auth.auth().signInAnonymously()
            print("🔐 auth ok: \(Auth.auth().currentUser?.uid ?? "nil")")
        }
    }

    // MARK: - Image sources
    /// Picsum with tiny retry/backoff so we can confirm if rate limits cause early stops.
    private static func fetchPicsumImageWithRetry(
        width: Int,
        height: Int,
        retries: Int,
        backoffMs: UInt64
    ) async throws -> UIImage {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await fetchPicsumImage(width: width, height: height)
            } catch {
                if attempt > retries {
                    throw error
                }
                try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
            }
        }
    }

    private static func fetchPicsumImage(width: Int, height: Int) async throws -> UIImage {
        let id = Int.random(in: 1...1000)
        let url = URL(string: "https://picsum.photos/id/\(id)/\(width)/\(height)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse {
            print("🖼️ picsum \(http.statusCode) id=\(id)")
        }
        guard let img = UIImage(data: data) else { throw URLError(.cannotDecodeRawData) }
        return img
    }

    /// Local generator (no network)
    private static func generatePlaceholderImage(width: Int, height: Int, title: String) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(
                hue: CGFloat.random(in: 0...1),
                saturation: 0.25,
                brightness: 0.95,
                alpha: 1
            ).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .semibold),
                .foregroundColor: UIColor(white: 0.1, alpha: 1)
            ]
            let text = NSString(string: title)
            let textSize = text.size(withAttributes: attrs)
            let point = CGPoint(
                x: (size.width - textSize.width)/2,
                y: (size.height - textSize.height)/2
            )
            text.draw(at: point, withAttributes: attrs)
        }
    }

    // MARK: - Utils
    private static func shortStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
