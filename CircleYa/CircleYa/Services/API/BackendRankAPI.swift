// CircleYa/Services/API/BackendRankAPI.swift
import Foundation
import FirebaseAuth

struct BackendRankAPI {
    static let shared = BackendRankAPI()

    private let functionURL = URL(string: "http://127.0.0.1:5001/minutes-7c7d7/us-central1/rankProxy")!

    struct RankResponse: Decodable {
        let post_ids: [String]
        let next_cursor: String?

        enum CodingKeys: String, CodingKey { case post_ids, next_cursor }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.post_ids = try c.decode([String].self, forKey: .post_ids)

            // Accept "15", 15, or 15.0, or missing
            if let s = try? c.decode(String.self, forKey: .next_cursor), !s.isEmpty {
                self.next_cursor = s
            } else if let i = try? c.decode(Int.self, forKey: .next_cursor) {
                self.next_cursor = String(i)
            } else if let d = try? c.decode(Double.self, forKey: .next_cursor) {
                self.next_cursor = String(Int(d))
            } else {
                self.next_cursor = nil
            }
        }
    }

    /// Returns ranked IDs for a page and the backend's next_cursor (if any).
    func rankedPostIDs(limit: Int = 15, cursor: String? = nil) async throws -> ([String], String?) {
        guard let user = Auth.auth().currentUser else {
            throw URLError(.userAuthenticationRequired)
        }

        var comps = URLComponents(url: functionURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "uid", value: user.uid),
            .init(name: "limit", value: String(limit))
        ]
        if let cursor, !cursor.isEmpty { items.append(.init(name: "cursor", value: cursor)) }
        comps.queryItems = items

        guard let url = comps.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "GET"

        let rid = UUID().uuidString.prefix(8)
        let t0 = Date()
        Log.info("🟢 [BackendRankAPI \(rid)] GET \(url.absoluteString)")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(t0))

            guard let http = resp as? HTTPURLResponse else {
                Log.error("❌ [BackendRankAPI \(rid)] Non-HTTP response in \(elapsed)")
                throw URLError(.badServerResponse)
            }
            Log.info("📡 [BackendRankAPI \(rid)] status=\(http.statusCode) elapsed=\(elapsed)")

            guard http.statusCode == 200 else {
                let preview = String(data: data, encoding: .utf8)?.prefix(300) ?? "‹non-utf8 \(data.count)B›"
                Log.warn("⚠️ [BackendRankAPI \(rid)] body preview: \(preview)")
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(RankResponse.self, from: data)
            Log.info("✅ [BackendRankAPI \(rid)] received \(decoded.post_ids.count) ids")
            return (decoded.post_ids, decoded.next_cursor)
        } catch {
            Log.error("❌ [BackendRankAPI \(rid)] request failed: \(error.localizedDescription)")
            throw error
        }
    }
}
