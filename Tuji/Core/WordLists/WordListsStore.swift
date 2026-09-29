// The account's 個人詞表 in the current learning language — the one shared read
// that 我, the 詞表 screen and the word page's 加入詞表 all ask.
//
// Data only. Whether the feature shows, and in which form, is `MemberAccess`;
// this used to keep its own copy of policy and tier, which went stale after a
// purchase.

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WordListsStore {
    static let shared = WordListsStore()

    private(set) var phase: LoadPhase = .idle
    private(set) var canCreate = false
    private(set) var limits: WordListLimits?
    private(set) var lists: [WordList] = []

    private let repository: WordListRepository
    private let language: LanguageContext
    /// The direction `lists` belongs to. Lists are per language, so a switch
    /// makes the loaded answer someone else's.
    private var loadedDirection: LearningDirection?
    private let log = Logger(subsystem: "app.tuji.ios", category: "word-lists")

    init(
        repository: WordListRepository = LiveWordListRepository.shared,
        language: LanguageContext = SettingsStore.shared
    ) {
        self.repository = repository
        self.language = language
    }

    func loadIfNeeded() async {
        if self.phase == .loaded, self.loadedDirection == self.language.learningDirection { return }
        await self.reload()
    }

    func reload() async {
        let started = self.phase
        let direction = self.language.learningDirection
        self.phase = self.loadedDirection == direction ? started.reloading : .loading
        do {
            try await self.apply(self.repository.lists(containing: nil), direction: direction)
        } catch {
            self.phase = started.afterFailure
            self.log.error("word lists load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The same listing with `containsWord` marked, for the 加入詞表 sheet. Also
    /// refreshes the shared answer, since it is the same read.
    func lists(containing wordId: String) async throws -> [WordList] {
        let direction = self.language.learningDirection
        let response = try await self.repository.lists(containing: wordId)
        self.apply(response, direction: direction)
        return response.lists
    }

    private func apply(_ response: WordListsResponse, direction: LearningDirection) {
        self.canCreate = response.canCreate ?? false
        self.limits = response.limits
        self.lists = response.lists
        self.loadedDirection = direction
        self.phase = .loaded
    }

    // MARK: - Writes

    func create(name: String) async -> (MemberWriteOutcome, WordList?) {
        do {
            let list = try await self.repository.create(name: name)
            self.lists.append(list)
            await self.reload()
            return (.done, list)
        } catch {
            return (MemberWriteOutcome.from(error), nil)
        }
    }

    func rename(_ list: WordList, to name: String) async -> MemberWriteOutcome {
        do {
            try await self.repository.rename(id: list.id, name: name)
            await self.reload()
            return .done
        } catch {
            return MemberWriteOutcome.from(error)
        }
    }

    func delete(_ list: WordList) async -> MemberWriteOutcome {
        let before = self.lists
        self.lists.removeAll { $0.id == list.id }
        do {
            try await self.repository.delete(id: list.id)
            await self.reload()
            return .done
        } catch {
            let outcome = MemberWriteOutcome.from(error)
            // Already gone elsewhere is what the person asked for.
            if outcome != .missing { self.lists = before }
            return outcome == .missing ? .done : outcome
        }
    }

    /// Optimistic: the rows move first, the server is told after. Order also
    /// decides which lists stay usable after a downgrade, so it is reloaded to
    /// pick up the new `locked` flags.
    func move(_ listId: String, by offset: Int) async -> MemberWriteOutcome {
        guard let from = self.lists.firstIndex(where: { $0.id == listId }),
              self.lists.indices.contains(from + offset)
        else { return .done }
        let before = self.lists
        self.lists.swapAt(from, from + offset)
        do {
            try await self.repository.reorder(ids: self.lists.map(\.id))
            await self.reload()
            return .done
        } catch {
            self.lists = before
            return MemberWriteOutcome.from(error)
        }
    }

    func setWord(_ wordId: String, in list: WordList, present: Bool) async -> MemberWriteOutcome {
        do {
            try await self.repository.setWord(wordId, inList: list.id, present: present)
            if let i = self.lists.firstIndex(where: { $0.id == list.id }) {
                let old = self.lists[i]
                self.lists[i] = WordList(
                    id: old.id,
                    name: old.name,
                    targetLanguage: old.targetLanguage,
                    position: old.position,
                    wordCount: max(0, old.wordCount + (present ? 1 : -1)),
                    locked: old.locked,
                    containsWord: present
                )
            }
            return .done
        } catch {
            return MemberWriteOutcome.from(error)
        }
    }

    /// The account changed: none of this is the next account's.
    func reset() {
        self.phase = .idle
        self.canCreate = false
        self.limits = nil
        self.lists = []
        self.loadedDirection = nil
    }
}
