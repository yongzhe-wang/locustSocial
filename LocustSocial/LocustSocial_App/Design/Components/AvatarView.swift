import SwiftUI

struct AvatarView: View {
    var user: User
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            if let url = user.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    default:
                        Circle().fill(Color.gray.opacity(0.15))
                        Text(String(user.displayName.prefix(1)))
                            .font(.system(size: size * 0.5, weight: .semibold))
                    }
                }
            } else {
                Circle().fill(Color.gray.opacity(0.15))
                Text(String(user.displayName.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
    }
}
