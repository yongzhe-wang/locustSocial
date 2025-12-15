import Foundation
import FirebaseFirestore

enum FeedKind {
    case discover
    case nearby
}

@MainActor
final class FeedVM: ObservableObject {
    // UI state
    @Published var items: [Post] = []
    @Published var isLoading = false          // first page / refresh
    @Published var isLoadingMore = false      // next page
    @Published var error: String?
    @Published var lastUpdated: Date?
    @Published private(set) var hasMore: Bool = true

    // paging
    private var nextCursor: String?

    private let api: FeedAPI
    private let kind: FeedKind

    init(api: FeedAPI, kind: FeedKind = .discover) {
        self.api = api
        self.kind = kind
    }

    // MARK: - First page / refresh
    private var didInitialLoad = false
    private var initialTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?

    func loadInitial(forceRefresh: Bool = false) async {
        if !forceRefresh, didInitialLoad { return }
        if initialTask != nil { return } // already running

        didInitialLoad = true
        initialTask = Task { [weak self] in
            guard let self = self else { return }
            if self.isLoading && !forceRefresh { return }
            self.isLoading = true
            self.isLoadingMore = false
            self.error = nil
            defer {
                self.isLoading = false
                self.initialTask = nil
            }

            self.nextCursor = nil
            self.hasMore = true

            do {
                let page: FeedPage = try await {
                    switch self.kind {
                    case .discover: return try await self.api.fetchFeed(cursor: nil)
                    case .nearby:   return try await self.api.fetchNearby(cursor: nil)
                    }
                }()
                self.items = page.items
                self.nextCursor = page.nextCursor
                self.hasMore = (self.nextCursor != nil)
                self.lastUpdated = Date()
            } catch {
                self.error = error.localizedDescription
                self.items = []
                self.nextCursor = nil
                self.hasMore = false
            }
        }
        await initialTask?.value
    }

    func refresh() async {
        await loadInitial(forceRefresh: true)
    }

    // MARK: - Next page (triggered by bottom refresher)
    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore, loadMoreTask == nil, let cursor = nextCursor else { return }
        isLoadingMore = true
        loadMoreTask = Task { [weak self] in
            guard let self = self else { return }
            defer {
                self.isLoadingMore = false
                self.loadMoreTask = nil
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            do {
                let page: FeedPage = try await {
                    switch self.kind {
                    case .discover: return try await self.api.fetchFeed(cursor: cursor)
                    case .nearby:   return try await self.api.fetchNearby(cursor: cursor)
                    }
                }()

                var seen = Set(self.items.map(\.id))
                let newOnes = page.items.filter { seen.insert($0.id).inserted }

                self.items.append(contentsOf: newOnes)
                self.nextCursor = page.nextCursor
                self.hasMore = (self.nextCursor != nil)
                self.lastUpdated = Date()
            } catch {
                self.error = error.localizedDescription
            }
        }
        await loadMoreTask?.value
    }
}
