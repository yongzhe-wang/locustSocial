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

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    var body: some View {
        Form {
            // MARK: - Profile Picture
            Section("Profile Picture") {
                VStack {
                    if let profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.secondary)
                    }

                    Button("Change Picture") { showPhotoPicker = true }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // MARK: - Info
            Section("Info") {
                TextField("First Name", text: $firstName)
                TextField("Last Name", text: $lastName)
                TextField("Bio", text: $bio)
            }

            // MARK: - Actions
            Section {
                Button {
                    Task { await saveChanges() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Save Changes").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving)
                .tint(.blue)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(image: $profileImage)
        }
        .task { await loadCurrentUserInfo() } // load user when open
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
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
