
import SwiftUI

struct ComposerView: View {
    @State private var caption: String = ""
    var body: some View {
        Form {
            Section(header: Text("Caption")) {
                TextEditor(text: $caption).frame(height: 120)
            }
            Section {
                Button("Pick Photos") {}
                Button("Publish") {}
            }
        }
        .navigationTitle("New Post")
    }
}
