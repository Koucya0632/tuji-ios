import Foundation
import Observation

@MainActor
@Observable
final class SavedCollectionsVM {
    enum Phase: Equatable {
        case idle, loading, ready, failed(String)
    }

    private(set) var collections: [AtlasCollection] = []
    private(set) var phase: Phase = .idle
    private(set) var loadedLanguage: TargetLanguage?

    private let repo: CollectionBookmarking

    init(repo: CollectionBookmarking = LiveAtlasRepository.shared) {
        self.repo = repo
    }

    var errorMessage: String? {
        if case let .failed(message) = self.phase { return message }
        return nil
    }

    func load(lang: TargetLanguage, force: Bool = false) async {
        guard force || self.loadedLanguage != lang || self.phase == .idle else { return }
        if self.loadedLanguage != lang {
            self.collections = []
        }
        self.phase = .loading
        do {
            self.collections = try await self.repo.savedCollections(lang: lang)
            self.loadedLanguage = lang
            self.phase = .ready
        } catch {
            self.loadedLanguage = lang
            self.phase = .failed(error.localizedDescription)
        }
    }

    func apply(_ change: CollectionBookmarkStore.Change, lang: TargetLanguage) {
        guard change.collection.targetLanguage == lang else { return }
        self.collections.removeAll { $0.id == change.collection.id }
        if change.saved {
            self.collections.insert(change.collection, at: 0)
        }
    }
}
