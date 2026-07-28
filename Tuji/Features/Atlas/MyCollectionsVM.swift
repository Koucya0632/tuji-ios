// View model for AtlasMyCollectionsView (我的合集 — the author's own collections
// list). Owns the load state behind the CollectionManaging seam so the view is
// presentation-only and the load/error transitions are unit-testable.

import Foundation
import Observation

@MainActor
@Observable
final class MyCollectionsVM {
    private(set) var collections: [AtlasMyCollection] = []
    private(set) var loading = true
    private(set) var loadError: String?

    private let repo: CollectionManaging

    init(repo: CollectionManaging = LiveAtlasRepository.shared) {
        self.repo = repo
    }

    func load() async {
        self.loading = true
        self.loadError = nil
        do {
            self.collections = try await self.repo.myCollections()
        } catch {
            self.loadError = error.localizedDescription
        }
        self.loading = false
    }
}
