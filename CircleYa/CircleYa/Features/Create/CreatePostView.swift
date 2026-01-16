import SwiftUI
import FirebaseAuth
import PhotosUI

struct CreatePostView: View {
    // MARK: - Properties
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedImages: [UIImage] = []
    @State private var isPostingGate = false        // UI gate for 1s cooldown
    @State private var showPicker = false
    @State private var errorText: String?

    let api = FirebaseFeedAPI()

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 24) {
                        titleSection
                        contentSection
                        imagePreviewSection
                        addPhotoButton
                    }
                    .padding()
                }

                postButtonSection
            }
            .navigationTitle("Share a moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.backgroundMain, for: .navigationBar)
            .background(Theme.backgroundMain)
            .sheet(isPresented: $showPicker) {
                PhotoPicker(images: $selectedImages)
            }
            .alert("Upload failed", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Topic or Title", text: $title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .padding()
                .background(Theme.cardWhite)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        }
    }

    private var contentSection: some View {
        ZStack(alignment: .topLeading) {
            if bodyText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Something that stayed with you today…")
                    Text("A small thought you don’t want to lose")
                }
                .font(.system(.body, design: .rounded))
                .foregroundColor(Theme.textHint)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            TextEditor(text: $bodyText)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 200)
                .background(Theme.secondaryBrand.opacity(0.1))
                .cornerRadius(16)
        }
    }

    @ViewBuilder
    private var imagePreviewSection: some View {
        if !selectedImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    imagePreviewList
                    addMoreButton
                }
            }
        }
    }

    private var imagePreviewList: some View {
        ForEach(0..<selectedImages.count, id: \.self) { index in
            imagePreviewCell(at: index)
        }
    }

    private func imagePreviewCell(at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: selectedImages[index])
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .clipped()
            
            Button {
                removeImage(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .padding(8)
        }
    }

    private func removeImage(at index: Int) {
        withAnimation {
            if selectedImages.indices.contains(index) {
                selectedImages.remove(at: index)
            }
        }
    }

    @ViewBuilder
    private var addMoreButton: some View {
        if selectedImages.count < 10 {
            Button {
                showPicker = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.secondaryBrand.opacity(0.2))
                        .frame(width: 100, height: 200)
                    
                    Image(systemName: "plus")
                        .font(.title)
                        .foregroundColor(Theme.primaryBrand)
                }
            }
        }
    }

    @ViewBuilder
    private var addPhotoButton: some View {
        HStack {
            Button { showPicker = true } label: {
                HStack {
                    Image(systemName: "camera")
                    Text("Add Photo")
                }
                .font(.subheadline)
                .foregroundColor(Theme.primaryBrand)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.primaryBrand.opacity(0.1))
                .cornerRadius(20)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var postButtonSection: some View {
        Group {
            if isFormValid {
                VStack {
                    Button {
                        handlePost()
                    } label: {
                        Text(isPostingGate ? "Sharing…" : "Share")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.gradient)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .disabled(isPostingGate)
                }
                .padding()
                .padding(.bottom, 80) // Avoid overlap with floating tab bar
                .background(Color(.systemBackground))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
        let postImages = selectedImages

        // Immediately reset the UI so user can type a new post soon
        title = ""
        bodyText = ""
        selectedImages = []

        // Kick off the upload in the background
        Task.detached {
            do {
                try await api.uploadPost(title: postTitle, text: postBody, images: postImages)
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
