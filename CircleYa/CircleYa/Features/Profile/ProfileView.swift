import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct ProfileView: View {
    @State private var username: String = "First Last"
    @State private var bio: String = "Tell something about yourself"
    @State private var profileImage: UIImage?
    @State private var selectedTab: ProfileTab = .notes
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var followerCount = 0
    @State private var followingCount = 0

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header Background (Sunrise Gradient)
                    ZStack(alignment: .bottom) {
                        Theme.sunnyGradient
                            .frame(height: 180)
                            .edgesIgnoringSafeArea(.top)
                        
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 108, height: 108)
                            
                            if let profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Theme.primaryBrand, lineWidth: 2))
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(Theme.secondaryBrand)
                                    .overlay(Circle().stroke(Theme.primaryBrand, lineWidth: 2))
                            }
                        }
                        .offset(y: 50)
                    }
                    .padding(.bottom, 50)

                    // Name + Bio
                    VStack(spacing: 8) {
                        Text(username)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text(bio.isEmpty ? "Share knowledge, life, and questions." : bio)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 24)

                    // Centered followers / following
                    HStack(spacing: 40) {
                        if let uid = Auth.auth().currentUser?.uid {
                            NavigationLink {
                                FollowersListView(userId: uid)
                            } label: {
                                StatView(count: followerCount, label: "Followers")
                            }

                            NavigationLink {
                                FollowingListView(userId: uid)
                            } label: {
                                StatView(count: followingCount, label: "Following")
                            }
                        } else {
                            StatView(count: followerCount, label: "Followers")
                            StatView(count: followingCount, label: "Following")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)

                    // Custom Tabs
                    HStack(spacing: 0) {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation { selectedTab = tab }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundColor(selectedTab == tab ? .white : Theme.textSecondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(
                                        Capsule()
                                            .fill(selectedTab == tab ? Theme.primaryBrand : Color.clear)
                                    )
                            }
                        }
                    }
                    .padding(4)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Content
                    VStack(spacing: 12) {
                        switch selectedTab {
                        case .notes:
                            NotesListView()
                        case .history:
                            HistoryListView()
                        case .saved:
                            SavedListView()
                        }
                    }
                    .padding(.horizontal)
                }
                .overlay {
                    if isLoading {
                        ProgressView("Loading…")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(
                        destination: EditProfileView(
                            username: $username,
                            bio: $bio,
                            profileImage: $profileImage
                        )
                    ) {
                        Image(systemName: "pencil.circle")
                            .imageScale(.large)
                    }

                    Button {
                        signOut()
                    } label: {
                        Image(systemName: "arrow.right.square")
                            .imageScale(.large)
                            .foregroundColor(.red)
                    }
                }
            }
            .task { await loadCurrentUser() }
            .refreshable { await loadCurrentUser() }
            .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
                Task { await loadCurrentUser() }
            }
        }
    }

    // MARK: - Firestore fetch
    private func loadCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            await MainActor.run { errorMessage = "Not signed in." }
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        defer {
            Task {
                await MainActor.run { isLoading = false }
            }
        }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else {
                throw NSError(
                    domain: "Profile",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "User not found"]
                )
            }

            let displayName: String = {
                let raw = data["displayName"] as? String ?? ""
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "First Last" : trimmed
            }()

            let bio = data["bio"] as? String ?? ""
            let avatarURLString = data["avatarURL"] as? String

            await MainActor.run {
                self.username = displayName
                self.bio = bio
            }

            if let s = avatarURLString, let url = URL(string: s) {
                do {
                    let (d, _) = try await URLSession.shared.data(from: url)
                    if let img = UIImage(data: d) {
                        await MainActor.run { self.profileImage = img }
                    }
                } catch {
                    print("⚠️ Avatar download failed:", error.localizedDescription)
                }
            } else {
                await MainActor.run { self.profileImage = nil }
            }

            // Followers / following in parallel
            async let followersSnap = try db.collection("users")
                .document(uid)
                .collection("followers")
                .getDocuments()

            async let followingSnap = try db.collection("users")
                .document(uid)
                .collection("following")
                .getDocuments()

            let (fSnap, gSnap) = try await (followersSnap, followingSnap)

            await MainActor.run {
                self.followerCount = fSnap.documents.count
                self.followingCount = gSnap.documents.count
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load profile: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sign Out
    private func signOut() {
        do {
            try Auth.auth().signOut()
            print("🧹 Signed out from Firebase")
            NotificationCenter.default.post(name: .userDidSignOut, object: nil)
        } catch {
            errorMessage = "Sign-out failed: \(error.localizedDescription)"
        }
    }
}

struct StatView: View {
    let count: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundColor(Theme.primaryBrand)
                Text("\(count)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.primaryBrand)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Notifications & Tabs

extension Notification.Name {
    static let userDidSignOut = Notification.Name("userDidSignOut")
    static let profileDidChange = Notification.Name("profileDidChange")
}

enum ProfileTab: String, CaseIterable {
    case notes = "Notes"
    case history = "History"
    case saved = "Saved"
}
