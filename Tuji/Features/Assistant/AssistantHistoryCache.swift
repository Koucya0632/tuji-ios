// 查詞紀錄 and 語法紀錄 — the list, kept so opening it again does not ask the
// server again.
//
// Read once per launch for each filter, then only when it is known to have
// changed: a card arrived, a bookmark was flipped, a record was deleted — all
// from this page, which drops the account's kept lists. Pull to refresh always
// reads. A card made on another device appears after a refresh or a relaunch.
//
// Memory only: the lists are long and the first visit after a launch reads them
// anyway.

import Foundation

/// The type-safe face over `HistoryShelf`, a struct for the same reason as
/// `AssistantOfferCache`: Swift 6.3.3's release build crashes on a generic
/// class's `deinit`.
@MainActor
struct AssistantHistoryCache<Record> {
    struct Page {
        let records: [Record]
        let nextCursor: String?
    }

    private let shelf = HistoryShelf()

    init() {}

    func page(owner: String, filter: String) -> Page? {
        self.shelf.pages[HistoryShelf.key(owner, filter)] as? Page
    }

    func store(_ page: Page, owner: String, filter: String) {
        self.shelf.pages[HistoryShelf.key(owner, filter)] = page
    }

    /// Every filter's list for this account is behind.
    func invalidate(owner: String) {
        let prefix = HistoryShelf.key(owner, "")
        self.shelf.pages = self.shelf.pages.filter { !$0.key.hasPrefix(prefix) }
    }

    func reset() {
        self.shelf.pages = [:]
    }
}

@MainActor
private final class HistoryShelf {
    var pages: [String: Any] = [:]

    static func key(_ owner: String, _ filter: String) -> String {
        "\(owner)\n\(filter)"
    }
}

@MainActor
enum AssistantHistoryCaches {
    static let vocabulary = AssistantHistoryCache<VocabularyRecord>()
    static let grammar = AssistantHistoryCache<GrammarRecord>()
}
