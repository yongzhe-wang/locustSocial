import SwiftUI

struct LikesDetailView: View {
    var body: some View {
        List {
            Section(header: Text("Likes")) {
                // TODO: Replace with real like notifications from your API
                Text("No likes yet")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Likes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
