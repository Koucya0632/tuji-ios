// 物見搜尋 — the model behind `AtlasSearchView`.
//
// Server-only, unlike 搜尋: 物見 is other people's work and nothing of it lives
// on the device, so there is no local first pass to show while the request is
// out. One debounced GET /api/atlas/public/search answers both shelves (合集 and
// 單字卡片) at once.
//
// Blocked authors are hidden here exactly as `PublicAtlasBrowsingModel` hides
// them: raw results are kept, the published ones are filtered, so a block made
// from a pushed detail applies on the way back without a refetch.

import Foundation
import Observation

@MainActor
@Observable
final class AtlasSearchModel {
    typealias Sleep = @MainActor (Duration) async -> Void

    enum Phase: Equatable {
        /// Nothing typed.
        case idle
        /// A request for `lastQuery` is out (or about to be, after the debounce).
        case loading
        case ready
        case failed(String)
    }

    private(set) var query = ""
    /// The query the results on screen answer.
    private(set) var lastQuery = ""
    private(set) var phase: Phase = .idle

    private var rawCollections: [AtlasCollection] = []
    private var rawItems: [AtlasPublicItem] = []
    private var blockedAuthors: Set<String> = []

    var collections: [AtlasCollection] {
        self.rawCollections.filter { self.isVisible($0.author?.handle) }
    }

    var items: [AtlasPublicItem] {
        self.rawItems.filter { self.isVisible($0.author?.handle) }
    }

    var isEmpty: Bool {
        self.collections.isEmpty && self.items.isEmpty
    }

    private var task: Task<Void, Never>?
    private let repository: AtlasPublicSearching
    private let debounce: Duration
    private let sleep: Sleep

    init(
        repository: AtlasPublicSearching = LiveAtlasRepository.shared,
        debounce: Duration = .milliseconds(300),
        sleep: @escaping Sleep = { try? await Task.sleep(for: $0) }
    ) {
        self.repository = repository
        self.debounce = debounce
        self.sleep = sleep
    }

    func applyBlocks(_ handles: Set<String>) {
        self.blockedAuthors = handles
    }

    func updateQuery(_ q: String, language: TargetLanguage) {
        self.query = q
        self.task?.cancel()
        let trimmed = Self.normalized(q)
        guard !trimmed.isEmpty else {
            self.rawCollections = []
            self.rawItems = []
            self.lastQuery = ""
            self.phase = .idle
            return
        }
        self.phase = .loading
        self.task = Task { [weak self] in
            guard let self else { return }
            await self.sleep(self.debounce)
            guard !Task.isCancelled else { return }
            await self.run(trimmed, language: language)
        }
    }

    /// Re-run the current query now — 重試, or the learning language changed.
    func retry(language: TargetLanguage) {
        self.task?.cancel()
        let trimmed = Self.normalized(self.query)
        guard !trimmed.isEmpty else { return }
        self.phase = .loading
        self.task = Task { [weak self] in
            await self?.run(trimmed, language: language)
        }
    }

    /// Await whatever is in flight — the seam tests settle on.
    func settle() async {
        await self.task?.value
    }

    // MARK: - Internals

    /// The backend caps `q` at 40 characters and 400s past it; trimming here
    /// keeps a long paste searchable instead of failing.
    static func normalized(_ q: String) -> String {
        String(q.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    private func isVisible(_ handle: String?) -> Bool {
        guard let handle, !self.blockedAuthors.isEmpty else { return true }
        return !self.blockedAuthors.contains(handle.lowercased())
    }

    private func run(_ q: String, language: TargetLanguage) async {
        let outcome: Result<AtlasPublicSearchResponse, Error>
        do {
            outcome = try await .success(self.repository.searchPublic(q: q, lang: language))
        } catch {
            outcome = .failure(error)
        }
        // The user kept typing: this answers a question no longer on screen.
        guard q == Self.normalized(self.query), !Task.isCancelled else { return }

        switch outcome {
        case let .success(response):
            self.rawCollections = response.collections
            self.rawItems = response.items
            self.lastQuery = q
            self.phase = .ready
        case let .failure(error):
            self.rawCollections = []
            self.rawItems = []
            self.lastQuery = q
            self.phase = .failed(tujiUserMessage(for: error))
        }
    }
}
