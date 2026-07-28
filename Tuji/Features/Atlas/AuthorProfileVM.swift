// View model for AtlasAuthorProfileView (作者主頁). A load-and-render screen:
// fetches the author identity + their public items behind the AuthorReading seam
// so the view stays presentation-only. Analytics tracking stays in the view (the
// codebase convention — VMs don't reach AnalyticsService).

import Foundation
import Observation

@MainActor
@Observable
final class AuthorProfileVM {
    enum Phase: Equatable {
        case loading, ready, failed(String)
    }

    let handle: String
    private(set) var author: AtlasAuthor?
    private(set) var items: [AtlasPublicItem] = []
    private(set) var phase: Phase = .loading

    private let repo: AuthorReading

    init(handle: String, repo: AuthorReading = LiveAtlasRepository.shared) {
        self.handle = handle
        self.repo = repo
    }

    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    func load() async {
        self.phase = .loading
        do {
            let response = try await self.repo.author(handle: self.handle)
            self.author = response.author
            self.items = response.items
            self.phase = .ready
        } catch {
            self.author = nil
            self.items = []
            self.phase = .failed(error.localizedDescription)
        }
    }
}
