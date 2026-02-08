import SwiftUI

struct FollowersDetailView: View {
    var body: some View {
        List {
            Section(header: Text("Followers")) {
                // TODO: Replace with real follower notifications from your API
                Text("No new followers yet")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.inline)
    }
}
