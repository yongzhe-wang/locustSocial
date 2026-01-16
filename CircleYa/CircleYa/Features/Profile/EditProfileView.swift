import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

struct EditProfileView: View {
    @Binding var username: String
    @Binding var bio: String
    @Binding var profileImage: UIImage?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPhotoPicker = false

    @Environment(\.dismiss) var dismiss

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundMain.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // MARK: - Header / Profile Pic Area
                        ZStack(alignment: .bottom) {
                            // Profile Image
                            ZStack {
                                // Sun glow
                                Circle()
                                    .fill(Theme.sunnyGradient.opacity(0.2))
                                    .frame(width: 140, height: 140)
                                    .blur(radius: 10)
                                
                                Circle()
                                    .stroke(Theme.sunnyGradient, lineWidth: 3)
                                    .frame(width: 128, height: 128)
                                    .background(Circle().fill(Color.white))
                                
                                if let profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)
                                        .foregroundColor(Theme.secondaryBrand)
                                }
                                
                                // Camera Button
                                Button {
                                    showPhotoPicker = true
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Theme.primaryBrand)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 3)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                                }
                                .offset(x: 45, y: 45)
                            }
                        }
                        .padding(.top, 30)
                        
                        // MARK: - Form Fields
                        VStack(spacing: 24) {
                            HStack(spacing: 16) {
                                EditProfileTextField(title: "First Name", text: $firstName)
                                EditProfileTextField(title: "Last Name", text: $lastName)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About You")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundColor(Theme.textSecondary)
                                
                                TextField("Share knowledge, life, and questions...", text: $bio, axis: .vertical)
                                    .font(.system(.body, design: .rounded))
                                    .padding()
                                    .background(Theme.cardWhite)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Theme.secondaryBrand.opacity(0.3), lineWidth: 1)
                                    )
                                    .lineLimit(3...6)
                            }
                        }
                        .padding(.horizontal)
                        
                        // MARK: - Save Button
                        Button {
                            Task { await saveChanges() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Save Profile")
                                        .font(.system(.title3, design: .rounded).weight(.bold))
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.sunnyGradient)
                            .foregroundColor(.white)
                            .cornerRadius(25)
                            .shadow(color: Theme.primaryBrand.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .disabled(isSaving)
                        .opacity(isSaving ? 0.7 : 1)
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundColor(Theme.likeRed)
                                .font(.system(.footnote, design: .rounded))
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.backgroundMain, for: .navigationBar)
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(image: $profileImage)
            }
            .task { await loadCurrentUserInfo() }
        }
    }

    // MARK: - Load Firestore User
    private func loadCurrentUserInfo() async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            let doc = try await db.collection("users").document(user.uid).getDocument()
            if let data = doc.data() {
                firstName = (data["displayName"] as? String)?
                    .split(separator: " ").first.map(String.init) ?? ""
                lastName = (data["displayName"] as? String)?
                    .split(separator: " ").dropFirst().joined(separator: " ") ?? ""
                bio = data["bio"] as? String ?? ""
                username = data["displayName"] as? String ?? (user.email ?? "")
                if let avatarURL = data["avatarURL"] as? String,
                   let url = URL(string: avatarURL),
                   let imgData = try? Data(contentsOf: url),
                   let uiImg = UIImage(data: imgData) {
                    profileImage = uiImg
                }
            }
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    // MARK: - Save Changes to Firestore + Storage
    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        guard let user = Auth.auth().currentUser else {
            errorMessage = "No user logged in."
            return
        }

        var avatarURL: String? = nil

        // Upload image if selected
        if let img = profileImage,
           let data = img.jpegData(compressionQuality: 0.8) {
            let ref = storage.reference().child("profilePhotos/\(user.uid).jpg")
            do {
                _ = try await ref.putDataAsync(data)
                let url = try await ref.downloadURL()
                avatarURL = url.absoluteString
            } catch {
                print("⚠️ Image upload failed:", error)
            }
        }

        let newDisplayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)

        // Update Auth + Firestore
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = newDisplayName
        try? await changeRequest.commitChanges()

        var updateData: [String: Any] = [
            "displayName": newDisplayName,
            "bio": bio,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let avatarURL { updateData["avatarURL"] = avatarURL }

        do {
            // EditProfileView.saveChanges()
            try await db.collection("users").document(user.uid).setData(updateData, merge: true)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
            Task { await UserCache.shared.invalidate(user.uid) }
            username = newDisplayName
            print("✅ Profile updated successfully")
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

struct EditProfileTextField: View {
    let title: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(Theme.textSecondary)
            
            TextField(title, text: $text)
                .font(.system(.body, design: .rounded))
                .padding()
                .background(Theme.cardWhite)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.secondaryBrand.opacity(0.3), lineWidth: 1)
                )
        }
    }
}