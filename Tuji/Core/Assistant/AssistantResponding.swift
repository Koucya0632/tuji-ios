// 助手 — the seam between a question and its answer.
//
// Tier one answers from what the device already holds (`LocalAssistantResponder`):
// no model, no token spend, no 罐頭點數. A later tier that does call a model is
// another conformer of this protocol; the chat model and the screen stay as
// they are.

import Foundation

@MainActor
protocol AssistantResponding {
    /// What the cat says when the chat opens.
    func greeting() -> AssistantReply
    /// Answers free text. `nil` only for blank input — there is nothing to
    /// answer. Free text goes to the responder whole, rather than being parsed
    /// by the caller, because what it means depends on what the responder
    /// knows: 「廚房」 is a category only if the catalogue has one.
    func reply(toText text: String) async -> AssistantReply?
    /// Answers a quick-reply chip. No parsing — the chip already is the intent,
    /// so a keyword rule cannot misread it.
    func reply(to intent: AssistantIntent) async -> AssistantReply
}

/// The category list as 助手 reads it — live at call time, like
/// `LocalDictionaryReading`.
@MainActor
protocol CategoryCatalogReading {
    var categories: [TujiCategory] { get }
}

/// The device's copy of the account's bookmarks.
@MainActor
protocol BookmarkReading {
    var favoriteIds: Set<String> { get }
}

extension CategoriesStore: CategoryCatalogReading {}

extension LocalCache: BookmarkReading {}
