// UI/AuthorLink.swift
import SwiftUI

struct AuthorLink<Content: View>: View {
    let user: User
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationLink(value: user, label: content)
            .buttonStyle(.plain)
    }
}
