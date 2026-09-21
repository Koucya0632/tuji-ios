// 加入項目 — which of the author's own 圖鑑 a 合集 can take, and the optimistic
// add that puts one in.
//
// Membership eligibility is the headline 合集 rule in CONTEXT.md (approved,
// pending and private members can be added; rejected, taken-down, unfinished
// and deleted ones cannot) and until now the client expressed none of it: the
// server's `eligible` flag was decoded and read by nobody, and the picker's only
// filter was de-duplication. The tick was also inserted before the await and
// never rolled back, so an add that failed stayed ticked.
//
// **Eligibility is a pair, not a property.** `eligible` answers 「這個項目本身壞了
// 嗎」 — and it is the only question `/collections/candidates` *can* answer,
// because it is scoped by language and never told which 合集 you are filling.
// The other half belongs to the collection: once it is public or in review it
// can only take items that are already public. The picker used to offer those
// tiles anyway, and the tap came back as 「伺服器出了點問題（409）」. So the
// collection's review status is now an input, and a tile that cannot be taken
// says so before it is tapped.

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
    /// Where the 合集 being filled sits in review. The picker is opened from the
    /// loaded edit screen, so this is never a guess.
    let collectionReview: AtlasReviewStatus

    private let existingIds: Set<String>
    private let repo: CollectionManaging

    init(
        language: TargetLanguage,
        collectionReview: AtlasReviewStatus,
        existingIds: Set<String>,
        repo: CollectionManaging = LiveAtlasRepository.shared
    ) {
        self.language = language
        self.collectionReview = collectionReview
        self.existingIds = existingIds
        self.repo = repo
    }

    /// What the picker lists. The server scopes the list to confirmed items in
    /// this language and marks anything it would refuse with
    /// `eligible == false`; an item that omits the flag is allowed, so an older
    /// server never blocks the whole picker. Members already in the collection
    /// drop out.
    ///
    /// Items the *collection* cannot take stay on the list — see `isAddable`.
    /// Dropping them would answer 「我的圖鑑呢？」 with silence; showing them
    /// disabled answers it with the rule.
    var available: [AtlasPublicItem] {
        self.candidates.filter { item in
            item.eligible != false && !self.existingIds.contains(item.id)
        }
    }

    /// True while the 合集 is public or in review, when an unpublished item
    /// cannot join it. The picker says this once, above the grid.
    var blocksUnpublished: Bool {
        !self.collectionReview.acceptsUnpublishedMembers
    }

    /// Whether this tile can be tapped. An item already carrying an approved
    /// public row is always addable; anything else needs a collection that is
    /// still off the shelf.
    ///
    /// `publicationState` is the server's word for the same three states the
    /// grid's badge shows (public / pending / private). A payload that omits it
    /// is treated as public — the old contract, and the server still has the
    /// final say.
    func isAddable(_ item: AtlasPublicItem) -> Bool {
        guard self.blocksUnpublished else { return true }
        guard let state = item.publicationState else { return true }
        return state == "public"
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
    /// the member list) and returns **nil when the server took it, otherwise
    /// the sentence to show**.
    ///
    /// The message has to come back through here rather than being left on the
    /// screen underneath: the picker is a sheet *on top* of the edit screen, so
    /// a refusal that only set `actionError` was invisible until the sheet was
    /// closed — and what stood in for it here was 「加入失敗，請再試一次。」,
    /// which is advice that cannot work when the reason is a rule.
    func add(_ id: String, using perform: (String) async -> String?) async {
        guard !self.added.contains(id) else { return }
        self.added.insert(id)
        self.addError = nil
        if let message = await perform(id) {
            self.added.remove(id)
            self.addError = message
        }
    }
}
