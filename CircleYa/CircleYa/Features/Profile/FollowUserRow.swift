import SwiftUI

struct FollowUser: Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let avatarURL: String?
}

struct FollowUserRow: View {
    let user: FollowUser

    var body: some View {
        HStack(spacing: 12) {
            if let urlString = user.avatarURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    case .failure(_):
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .frame(width: 40, height: 40)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName.isEmpty ? "Unknown" : user.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if !user.handle.isEmpty {
                    Text("@\(user.handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
