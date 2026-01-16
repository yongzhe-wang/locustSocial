import Foundation

struct AdaptContentRequest: Encodable {
    let text: String
    let style: String
}

struct AdaptContentResponse: Decodable {
    let adapted_text: String
    let facts: [String]?
    let modifications: [String]?
}

class ContentAdaptationService {
    static let shared = ContentAdaptationService()
    
    private init() {}
    
    // Use the backend URL - assuming running locally for now
    // In production, this would be your deployed backend URL
    private let baseURL = "http://127.0.0.1:8000/api/adapt-content"
    
    func adaptPost(_ post: Post) async -> Post {
        guard let url = URL(string: baseURL) else { return post }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // We can vary the style based on some user preference or random "persona"
        let styles = [
            "engaging and personal",
            "witty and concise",
            "poetic and descriptive",
            "enthusiastic and energetic"
        ]
        let selectedStyle = styles.randomElement() ?? "engaging"
        
        let body = AdaptContentRequest(text: post.text, style: selectedStyle)
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("❌ Adaptation API Error: \(httpResponse.statusCode)")
                if let errorText = String(data: data, encoding: .utf8) {
                    print("❌ Response body: \(errorText)")
                }
                return post
            }
            
            let decodedResponse = try JSONDecoder().decode(AdaptContentResponse.self, from: data)
            
            var adapted = post
            adapted.originalText = post.text // Store original
            adapted.text = decodedResponse.adapted_text
            adapted.preservedFacts = decodedResponse.facts ?? []
            adapted.adaptationLog = decodedResponse.modifications ?? []
            adapted.adaptationStyle = selectedStyle
            adapted.adaptationStyle = selectedStyle
            
            // Add a visual indicator that this is adapted content
            if !adapted.text.contains("✨") {
                adapted.text = "✨ " + adapted.text
            }
            
            print("✅ Adaptation success: \(adapted.text.prefix(20))...")
            return adapted
        } catch {
            print("❌ Adaptation failed: \(error)")
            // Fallback to original post on error
            return post
        }
    }
}
