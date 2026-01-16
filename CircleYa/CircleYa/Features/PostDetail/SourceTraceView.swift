import SwiftUI

struct SourceTraceView: View {
    let post: Post
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // 1. Original Content
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Original Content", systemImage: "doc.text")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.originalText ?? "No original text available")
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                            
                            HStack {
                                Text("Uploaded: \(post.createdAt.formatted())")
                                Spacer()
                                Text("Device: iPhone 15 Pro") // Mock device info
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        }
                    }
                    
                    Divider()
                    
                    // 2. AI Modifications
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Modifications", systemImage: "wand.and.stars")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        if let logs = post.adaptationLog, !logs.isEmpty {
                            ForEach(logs, id: \.self) { log in
                                HStack(alignment: .top) {
                                    Image(systemName: "pencil.line")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .padding(.top, 4)
                                    Text(log)
                                        .font(.subheadline)
                                }
                            }
                        } else {
                            Text("No specific modifications logged.")
                                .font(.caption)
                                .italic()
                        }
                        
                        if let style = post.adaptationStyle {
                            Text("Style applied: \(style)")
                                .font(.caption)
                                .padding(6)
                                .background(Theme.primaryBrand.opacity(0.1))
                                .cornerRadius(4)
                                .padding(.top, 4)
                        }
                    }
                    
                    Divider()
                    
                    // 3. Preserved Facts (Fact Locking)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Fact Locking", systemImage: "lock.shield")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        if let facts = post.preservedFacts, !facts.isEmpty {
                            ForEach(facts, id: \.self) { fact in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    Text(fact)
                                        .font(.subheadline)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.05))
                                .cornerRadius(8)
                            }
                        } else {
                            Text("No specific facts identified to lock.")
                                .font(.caption)
                                .italic()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Source Trace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
