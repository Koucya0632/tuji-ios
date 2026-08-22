// 加入項目 — which of the author's own 圖鑑 a 合集 can take, and the optimistic
// add that puts one in.
//
// Membership eligibility is the headline 合集 rule in CONTEXT.md (approved,
// pending and private members can be added; rejected, taken-down, unfinished
// and deleted ones cannot) and until now the client expressed none of it: the
// server's `eligible` flag was decoded and read by nobody, and the picker's only
// filter was de-duplication. The tick was also inserted before the await and
// never rolled back, so an add that failed stayed ticked.

import Foundation
import Observation

@MainActor
@Observable
final class CollectionCandidatesModel {
    private(set) var candidates: [AtlasPublicItem] = []
    private(set) var loading = true
    private(set) var loadError: String?
    private(set) var added: Set<String> = []
    private(set) var addError: String?

    let language: TargetLanguage

    private let existingIds: Set<String>
    private let repo: CollectionManaging

    init(
        language: TargetLanguage,
        existingIds: Set<String>,
        repo: CollectionManaging = LiveAtlasRepository.shared
    ) {
        self.language = language
        self.existingIds = existingIds
        self.repo = repo
    }

    /// What the 合集 can actually take. The server scopes the list to confirmed
    /// items in this language and marks anything it would refuse with
    /// `eligible == false`; an item that omits the flag is allowed, so an older
    /// server never blocks the whole picker. Members already in the collection
    /// drop out.
    var available: [AtlasPublicItem] {
        self.candidates.filter { item in
            item.eligible != false && !self.existingIds.contains(item.id)
        }
    }

    func isAdded(_ id: String) -> Bool {
        self.added.contains(id)
    }

    func load() async {
        self.loading = true
        self.loadError = nil
        defer { self.loading = false }
        do {
            self.candidates = try await self.repo.collectionCandidates(lang: self.language)
        } catch {
            self.loadError = tujiUserMessage(for: error)
        }
    }

    /// Ticks the tile immediately and un-ticks it if the add fails, so the
    /// picker can never claim an item is in a 合集 that refused it. The caller
    /// supplies the add itself (it belongs to the edit screen's VM, which owns
    /// the member list).
    func add(_ id: String, using perform: (String) async -> Bool) async {
        guard !self.added.contains(id) else { return }
        self.added.insert(id)
        self.addError = nil
        guard await perform(id) else {
            self.added.remove(id)
            self.addError = tujiLocalized("加入失敗，請再試一次。")
            return
        }
    }
}
