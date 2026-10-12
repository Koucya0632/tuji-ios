// 助手, tier one — answers from the data the app already has.
//
// The dictionary, the categories and the bookmarks are in memory from launch,
// so every answer but one is a filter over them: instant, offline, and free.
// 收藏的合集 is the exception — that shelf lives on the server — and it is the
// only reply here that can fail.

import Foundation

@MainActor
final class LocalAssistantResponder: AssistantResponding {
    /// How many rows a reply shows before it points at the full list. A chat
    /// bubble is not a results page.
    static let previewLimit = 6

    private let dictionary: LocalDictionaryReading
    private let catalog: CategoryCatalogReading
    private let bookmarks: BookmarkReading
    private let collections: CollectionBookmarking
    private let language: LanguageContext
    private let isSignedIn: @MainActor () -> Bool

    init(
        dictionary: LocalDictionaryReading = WordsStore.shared,
        catalog: CategoryCatalogReading = CategoriesStore.shared,
        bookmarks: BookmarkReading = LocalCache.shared,
        collections: CollectionBookmarking = LiveAtlasRepository.shared,
        language: LanguageContext = SettingsStore.shared,
        isSignedIn: @escaping @MainActor () -> Bool = { AuthService.shared.isSignedIn }
    ) {
        self.dictionary = dictionary
        self.catalog = catalog
        self.bookmarks = bookmarks
        self.collections = collections
        self.language = language
        self.isSignedIn = isSignedIn
    }

    func greeting() -> AssistantReply {
        AssistantReply(
            outcome: .greeting,
            text: tujiLocalized("嗨，我可以幫你查分類、收藏，還有圖鑑裡的詞。想找什麼？"),
            suggestions: [.categories, .favorites, .lookupPrompt]
        )
    }

    func reply(toText text: String) async -> AssistantReply? {
        guard let intent = AssistantIntent.parse(text, categories: self.themes) else {
            return nil
        }
        var reply = await self.reply(to: intent)
        // The command words are words too: 「保存」 asks for the favourites and
        // is also an entry a learner may be looking up. The command wins, and
        // the other reading stays one tap away.
        if !intent.isLookup, let headword = self.headword(matching: text) {
            reply.suggestions.insert(.lookup(query: headword), at: 0)
        }
        return reply
    }

    private func headword(matching text: String) -> String? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return self.dictionary.words.first { $0.word.lowercased() == needle }?.word
    }

    func reply(to intent: AssistantIntent) async -> AssistantReply {
        switch intent {
        case .categories: self.categoriesReply()
        case let .category(id): self.categoryReply(id: id)
        case .favorites: self.favoritesReply()
        case .bookmarks: self.bookmarksReply()
        case .savedCards: self.savedCardsReply()
        case .savedCollections: await self.savedCollectionsReply()
        case .lookupPrompt: self.lookupPromptReply()
        case let .lookup(query): self.lookupReply(query: query)
        // This responder holds no model. `TieredAssistantResponder` answers
        // this intent before it gets here.
        case .askModel:
            AssistantReply(
                outcome: .modelUnavailable,
                text: tujiLocalized("現在不能問 AI。沒有扣點。"),
                suggestions: [.categories, .favorites]
            )
        }
    }

    // MARK: - 分類

    /// The categories a person would call categories. The table also holds
    /// `custom` and `community`, which are *sources* (`ThemeCatalog`) — and
    /// 「物見」 typed here means the saved cards, not a theme by that name.
    private var themes: [TujiCategory] {
        ThemeCatalog.themes(
            from: self.catalog.categories,
            presentIds: Set(self.dictionary.words.map(\.category))
        )
    }

    private func categoriesReply() -> AssistantReply {
        let categories = self.themes
        guard !categories.isEmpty else {
            return AssistantReply(
                outcome: .categoriesUnavailable,
                text: tujiLocalized("分類還沒載入。連上網路後再問我一次。"),
                suggestions: [.lookupPrompt, .favorites]
            )
        }
        return AssistantReply(
            outcome: .categories,
            text: tujiLocalized("圖鑑裡有 \(categories.count) 個分類，點一個進去看。"),
            attachment: .categories(categories)
        )
    }

    private func categoryReply(id: String) -> AssistantReply {
        let words = self.dictionary.words.filter { $0.category == id }
        let category = self.catalog.categories.first { $0.id == id }
        let name = category?.nameZh ?? id
        return AssistantReply(
            outcome: .category,
            text: tujiLocalized("「\(name)」有 \(words.count) 張卡片。"),
            attachment: Self.preview(words, more: .categoryDetail(id: id)),
            // 「廚房」 is a category and may also be a word; the category won,
            // so the other reading stays one tap away.
            suggestions: [.lookup(query: name), .categories]
        )
    }

    // MARK: - 詞條

    private func lookupPromptReply() -> AssistantReply {
        AssistantReply(
            outcome: .lookupPrompt,
            text: tujiLocalized("把想查的字打給我，用中文或正在學的語言都可以。")
        )
    }

    private func lookupReply(query: String) -> AssistantReply {
        // The ranking 搜尋 already owns — one answer to "what matches this".
        let matches = SearchVM.localMatches(query, in: self.dictionary.words)
        guard !matches.isEmpty else {
            return AssistantReply(
                outcome: .noMatch,
                text: tujiLocalized("圖鑑裡還沒有「\(query)」。試試用中文查，或換個說法。"),
                suggestions: [.categories, .favorites]
            )
        }
        return AssistantReply(
            outcome: .words,
            text: tujiLocalized("找到 \(matches.count) 個跟「\(query)」有關的詞。"),
            attachment: Self.preview(matches, more: .search(query: query))
        )
    }

    // MARK: - 收藏

    private var bookmarkedWords: [CardWord] {
        let ids = self.bookmarks.favoriteIds
        return self.dictionary.words.filter { ids.contains($0.id) }
    }

    private var savedCardWords: [CardWord] {
        self.dictionary.words.filter { $0.id.savedCommunitySlug != nil }
    }

    /// The overview counts only what is on the device. 合集 would need a
    /// request, and a question as loose as 「收藏」 should not wait on one.
    private func favoritesReply() -> AssistantReply {
        let bookmarked = self.bookmarkedWords.count
        let saved = self.savedCardWords.count
        return AssistantReply(
            outcome: .favorites,
            text: tujiLocalized("你有 \(bookmarked) 個書籤、\(saved) 張物見卡片。想看哪一種？"),
            suggestions: [.bookmarks, .savedCards, .savedCollections]
        )
    }

    private func bookmarksReply() -> AssistantReply {
        let words = self.bookmarkedWords
        guard !words.isEmpty else {
            return AssistantReply(
                outcome: .nothingKept,
                text: tujiLocalized("加了書籤的詞會出現在這裡。在單字頁點書籤就能收進來。"),
                suggestions: [.categories, .lookupPrompt]
            )
        }
        return AssistantReply(
            outcome: .bookmarks,
            text: tujiLocalized("你加了書籤的詞有 \(words.count) 個。"),
            attachment: Self.preview(words, more: nil)
        )
    }

    private func savedCardsReply() -> AssistantReply {
        let words = self.savedCardWords
        guard !words.isEmpty else {
            return AssistantReply(
                outcome: .nothingKept,
                text: tujiLocalized("從物見收藏的卡片會出現在這裡。"),
                suggestions: [.bookmarks, .savedCollections]
            )
        }
        return AssistantReply(
            outcome: .savedCards,
            text: tujiLocalized("你從物見收藏了 \(words.count) 張卡片。"),
            attachment: Self.preview(words, more: nil)
        )
    }

    private func savedCollectionsReply() async -> AssistantReply {
        guard self.isSignedIn() else {
            return AssistantReply(
                outcome: .collectionsNeedSignIn,
                text: tujiLocalized("登入後才看得到收藏的合集。"),
                suggestions: [.bookmarks, .categories]
            )
        }
        let lang = self.language.learningDirection.targetLanguage
        do {
            let saved = try await self.collections.savedCollections(lang: lang)
            guard !saved.isEmpty else {
                return AssistantReply(
                    outcome: .nothingKept,
                    text: tujiLocalized("收藏的合集會出現在這裡。到物見逛逛，看到喜歡的就收起來。"),
                    suggestions: [.bookmarks, .savedCards]
                )
            }
            return AssistantReply(
                outcome: .collections,
                text: tujiLocalized("你收藏了 \(saved.count) 個合集。"),
                attachment: .collections(saved)
            )
        } catch {
            // The one answer that needs the network. Say so and offer what
            // still works offline, rather than putting an error screen in a chat.
            return AssistantReply(
                outcome: .collectionsUnreachable,
                text: tujiLocalized("現在讀不到收藏的合集，等網路好一點再問我。"),
                suggestions: [.bookmarks, .savedCards]
            )
        }
    }

    private static func preview(_ words: [CardWord], more: NavRoute?) -> AssistantReply.Attachment {
        .words(
            Array(words.prefix(previewLimit)),
            total: words.count,
            more: words.count > previewLimit ? more : nil
        )
    }
}
