// 加入卡片 — which of the author's own 圖鑑 a 合集 can take, and the optimistic
// add that puts one in.
//
// Membership eligibility is the headline 合集 rule in CONTEXT.md (approved,
// pending and private members can be added; rejected, taken-down, unfinished
// and deleted ones cannot) and until now the client expressed none of it: the
// server's `eligible` flag was decoded and read by nobody, and the picker's only
// filter was de-duplication. The tick was also inserted before the await and
// never rolled back, so an add that failed stayed ticked.
//
// **Eligibility is a pair, not a property.** `eligible` answers 「這張卡片本身壞了
// 嗎」 — and it is the only question `/collections/candidates` *can* answer,
// because it is scoped by language and never told which 合集 you are filling.
// The other half belongs to the collection, and it is no longer about *whether*
// an unpublished item can join but about *what happens when it does*: an
// unpublished 合集 carries it at publish time, a live one sends it through the
// item gate on its own, and until it passes it sits in the collection unseen.
// So the collection's review status is still an input — it decides what the
// tile promises, not whether the tile works.

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
    var available: [AtlasPublicItem] {
        self.candidates.filter { item in
            item.eligible != false && !self.existingIds.contains(item.id)
        }
    }

    /// True while the 合集 is public or in review, when a member that isn't
    /// public yet goes through the item gate by itself instead of riding along
    /// with the collection. Nothing is blocked by it — it is what the picker
    /// promises about the tiles that aren't public yet, said once above the
    /// grid.
    var submitsMembersOnTheirOwn: Bool {
        !self.collectionReview.acceptsUnpublishedMembers
    }

    /// Whether adding this item starts a review of its own. `publicationState`
    /// is the server's word for the three states the badge shows (public /
    /// pending / private); a payload that omits it is treated as public — the
    /// old contract, and the server still has the final say.
    func entersReviewOnAdd(_ item: AtlasPublicItem) -> Bool {
        guard self.submitsMembersOnTheirOwn else { return false }
        guard let state = item.publicationState else { return false }
        return state != "public"
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
