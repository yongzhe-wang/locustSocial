import SwiftUI

struct CommentsDetailView: View {
    var body: some View {
        List {
            Section(header: Text("Comments")) {
                // TODO: Replace with real comment notifications from your API
                Text("No comment notifications yet")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
    }
}
