// One 個人詞表 on screen: its words, its counts, and what this account may do
// with it — all as the server answered. Removing a word and deleting the list
// are never gated (a refund must not trap data); the rest follow `canEdit` /
// `canStudy`.

import Foundation
import Observation

@MainActor
@Observable
final class WordListDetailModel {
    let listId: String

    private(set) var phase: LoadPhase = .idle
    private(set) var detail: WordListDetailResponse?
    /// Set when the list no longer exists (deleted on another device).
    private(set) var missing = false

    private let repository: WordListRepository

    init(listId: String, repository: WordListRepository = LiveWordListRepository.shared) {
        self.listId = listId
        self.repository = repository
    }

    var name: String {
        self.detail?.list.name ?? ""
    }

    var wordIds: [String] {
        self.detail?.wordIds ?? []
    }

    /// Which study buttons to offer. A mode with nothing in it is not offered:
    /// an empty session is a dead end.
    var studyModes: [StudyMode] {
        guard let detail, detail.canStudy else { return [] }
        var modes: [StudyMode] = []
        if detail.stats.unseen > 0 { modes.append(.new) }
        if detail.stats.due > 0 { modes.append(.review) }
        return modes
    }

    /// Locked or a non-member: the list is theirs to read and trim, not to grow.
    var isReadOnly: Bool {
        !(self.detail?.canEdit ?? false)
    }

    func load() async {
        let started = self.phase
        self.phase = started.reloading
        do {
            self.detail = try await self.repository.detail(id: self.listId)
            self.phase = .loaded
        } catch APIError.notFound {
            self.missing = true
            self.phase = .loaded
        } catch {
            self.phase = started.afterFailure
        }
    }

    /// Optimistic; restored if the server refuses.
    func remove(_ wordId: String) async -> MemberWriteOutcome {
        guard let before = self.detail else { return .done }
        self.detail = WordListDetailResponse(
            list: before.list,
            wordIds: before.wordIds.filter { $0 != wordId },
            stats: before.stats,
            canEdit: before.canEdit,
            canStudy: before.canStudy,
            wordLimit: before.wordLimit
        )
        do {
            try await self.repository.setWord(wordId, inList: self.listId, present: false)
            // Counts are the server's to compute (they are per deck).
            await self.load()
            return .done
        } catch {
            self.detail = before
            return MemberWriteOutcome.from(error)
        }
    }
}
