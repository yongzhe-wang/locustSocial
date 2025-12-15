import SwiftUI
import FirebaseAuth
import PhotosUI

struct CreatePostView: View {
    // MARK: - Properties
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedImage: UIImage?
    @State private var isPostingGate = false        // UI gate for 1s cooldown
    @State private var showPicker = false
    @State private var errorText: String?

    let api = FirebaseFeedAPI()

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1) Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            TextField("Enter a title", text: $title)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }

                        // 2) Content
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Content")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Spacer()
                                // live word counter
                            }

                            ZStack(alignment: .topLeading) {
                                if bodyText.isEmpty {
                                    Text("What's on your mind?")
                                        .foregroundColor(.gray.opacity(0.6))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 16)
                                }
                                TextEditor(text: $bodyText)
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 150)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }

                        }

                        // 3) Image preview
                        if let selectedImage {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .clipped()
                                Button {
                                    withAnimation { self.selectedImage = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.4))
                                        .clipShape(Circle())
                                }
                                .padding(10)
                            }
                        }

                        // 4) Add photo
                        HStack {
                            Button { showPicker = true } label: {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .padding(10)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                }

                // 5) Sticky Post button
                VStack {
                    Button {
                        handlePost()
                    } label: {
                        Text(isPostingGate ? "Posting…" : "Post")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isFormValid ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .disabled(!isFormValid || isPostingGate)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPicker) {
                PhotoPicker(image: $selectedImage)
            }
            .alert("Upload failed", isPresented: .constant(errorText != nil), actions: {
                Button("OK") { errorText = nil }
            }, message: {
                Text(errorText ?? "")
            })
        }
    }

    // MARK: - Helpers

    // Count words by splitting on whitespace/newlines
    var wordCount: Int {
        bodyText
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    var meetsWordMin: Bool { wordCount >= 5 }

    var isFormValid: Bool {
        !title.isEmpty && meetsWordMin
    }

    /// Fire-and-forget upload; UI unlocks after 1s regardless of backend completion
    func handlePost() {
        guard isFormValid && !isPostingGate else { return }

        // Gate the button for ~1 second
        isPostingGate = true

        // Capture current values so we can reset UI immediately
        let postTitle = title
        let postBody  = bodyText
        let postImage = selectedImage

        // Immediately reset the UI so user can type a new post soon
        title = ""
        bodyText = ""
        selectedImage = nil

        // Kick off the upload in the background
        Task.detached {
            do {
                try await api.uploadPost(title: postTitle, text: postBody, image: postImage)
            } catch {
                // Surface error without blocking the UI
                await MainActor.run { errorText = error.localizedDescription }
            }
        }

        // Re-enable the Post button after ~1 second
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isPostingGate = false
        }
    }
}
