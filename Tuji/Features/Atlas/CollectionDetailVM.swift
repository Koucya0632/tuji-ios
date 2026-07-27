// View model for AtlasCollectionDetailView (公開合集詳情). A load-and-render screen:
// fetches the collection + member items behind the CollectionDetailReading seam so
// the view stays presentation-only. Seeds from the feed card preview so the header
// renders instantly while the members load.

import Foundation
import Observation

@MainActor
@Observable
final class CollectionDetailVM {
    enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    let slug: String
    private(set) var collection: AtlasCollection?
    private(set) var items: [AtlasPublicItem] = []
    private(set) var phase: Phase = .loading

    private let repo: CollectionDetailReading

    init(
        slug: String,
        preview: AtlasCollection? = nil,
        repo: CollectionDetailReading = LiveAtlasRepository.shared
    ) {
        self.slug = slug
        self.collection = preview
        self.repo = repo
    }

    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    func load() async {
        self.phase = .loading
        do {
            let response = try await self.repo.collection(slug: self.slug)
            self.collection = response.collection
            self.items = response.items
            self.phase = .ready
        } catch {
            // Keep any preview header on screen; the error state shows only when
            // there's nothing to render.
            self.phase = .failed(error.localizedDescription)
        }
    }
}
