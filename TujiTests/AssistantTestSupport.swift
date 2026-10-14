// Fixtures and fakes shared by the 助手 suites: the device-only responder
// (AssistantTests) and the paid tier on top of it (TieredAssistantResponderTests).

import Foundation
@testable import Tuji

enum AssistantFixture {
    static func word(
        _ id: String,
        word: String? = nil,
        chinese: String = "",
        category: String = "kitchen",
        authorHandle: String? = nil
    )
        -> CardWord
    {
        CardWord(
            id: id,
            word: word ?? id,
            chinese: chinese,
            imageUrl: "",
            category: category,
            pronunciation: "",
            authorHandle: authorHandle
        )
    }

    static func category(_ id: String, name: String, nameZh: String) -> TujiCategory {
        TujiCategory(
            id: id,
            name: name,
            nameZh: nameZh,
            emoji: "",
            description: nil,
            color: nil,
            imageUrl: nil
        )
    }

    static func collection(_ id: String) -> AtlasCollection {
        AtlasCollection(
            id: id,
            slug: "slug-\(id)",
            title: id,
            description: nil,
            targetLanguage: .ja,
            author: nil,
            itemCount: 1,
            saveCount: 0,
            avatarColor: nil,
            avatarImageUrl: nil,
            coverImageUrl: nil,
            publishedAt: nil
        )
    }

    static let categories = [
        category("kitchen", name: "Kitchen", nameZh: "廚房"),
        category("clothing", name: "Clothing", nameZh: "衣物")
    ]
}

@MainActor
final class AssistantDictionary: LocalDictionaryReading {
    var words: [CardWord]
    init(_ words: [CardWord] = []) {
        self.words = words
    }
}

@MainActor
final class AssistantCatalog: CategoryCatalogReading {
    var categories: [TujiCategory]
    init(_ categories: [TujiCategory] = AssistantFixture.categories) {
        self.categories = categories
    }
}

@MainActor
final class AssistantBookmarks: BookmarkReading {
    var favoriteIds: Set<String>
    init(_ ids: Set<String> = []) {
        self.favoriteIds = ids
    }
}

struct ShelfUnreachable: Error {}

@MainActor
final class AssistantShelf: CollectionBookmarking {
    var result: Result<[AtlasCollection], Error> = .success([])
    private(set) var requestedLanguages: [TargetLanguage] = []
    /// When set, `savedCollections` waits here — the slow answer a second
    /// question has to overtake.
    var gate: CheckedContinuation<Void, Never>?
    var holds = false

    func savedCollections(lang: TargetLanguage) async throws -> [AtlasCollection] {
        self.requestedLanguages.append(lang)
        if self.holds {
            await withCheckedContinuation { self.gate = $0 }
        }
        return try self.result.get()
    }

    func release() {
        self.gate?.resume()
        self.gate = nil
    }

    func collectionSaveState(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    }

    func saveCollection(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: true, saveCount: 1)
    }

    func unsaveCollection(slug _: String) async throws -> AtlasSaveResponse {
        AtlasSaveResponse(ok: true, saved: false, saveCount: 0)
    }
}
