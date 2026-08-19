// View model for one word's detail page.
//
// The fetch used to live on `WordDetailPage` as a `private func` with a
// hardcoded `private let repository: CatalogRepository = .shared`, reaching
// `AtlasStore.shared` and `SettingsStore.shared` from inside itself — the last
// of those despite the screen *already* having `@Environment(SettingsStore)`
// injected and unused. Nothing about the routing could be tested: which of the
// two sources an id goes to, whether a provisional card renders first, or the
// rule that a late failure must not blank a page that already has content.
//
// Three narrow seams rather than one fat one, per ADR-0001: this screen reads a
// catalogue word, an atlas item, and the grid's lite payload — three different
// slices, three different fakes in a test.

import Observation
import SwiftUI

/// The grid's already-loaded lite payload, used to render something instantly.
@MainActor
protocol WordLookup {
    func find(id: String) -> CardWord?
}

/// One catalogue word. A 1-method slice of `CatalogRepository`, whose other
/// five methods this screen never calls — carved so a test fake stubs one
/// method rather than six (ADR-0001).
@MainActor
protocol WordReading {
    func word(id: String, lang: String, learning: String) async throws -> Word
}

extension LiveCatalogRepository: WordReading {}

/// One 自製圖鑑 item's full detail (lazily enriched server-side on first open).
@MainActor
protocol AtlasItemDetailReading {
    func detail(itemId: String) async throws -> Word
}

extension WordsStore: WordLookup {}
extension AtlasStore: AtlasItemDetailReading {}

@MainActor
@Observable
final class WordDetailVM {
    /// Ids of 自製圖鑑 words carry this prefix; everything else is a catalogue
    /// word. The prefix is the routing decision, so it lives with the routing.
    static let atlasPrefix = "atlas:"

    private(set) var word: Word?
    private(set) var loading = false
    private(set) var error: Error?

    private let catalog: WordReading
    private let atlas: AtlasItemDetailReading
    private let words: WordLookup

    init(
        catalog: WordReading = LiveCatalogRepository.shared,
        atlas: AtlasItemDetailReading = AtlasStore.shared,
        words: WordLookup = WordsStore.shared
    ) {
        self.catalog = catalog
        self.atlas = atlas
        self.words = words
    }

    /// Loads `id`, rendering whatever can be shown immediately first.
    ///
    /// Returns the word to log a page view for, or nil. Analytics stays in the
    /// View (view models don't reach `AnalyticsService`), and 自製圖鑑 is
    /// private content that is deliberately never counted.
    @discardableResult
    func load(id: String, lang: String, learning: String) async -> Word? {
        guard self.word == nil, !self.loading else { return nil }
        self.loading = true
        defer { self.loading = false }

        if id.hasPrefix(Self.atlasPrefix) {
            await self.loadAtlasItem(id: id)
            return nil
        }
        // Public words: the grid already knows the word / image / 中文, so
        // render those instantly and let the enrichment sections (definitions,
        // 例句, 詞形, 來源) fill in when the full payload lands — a blank page
        // with a lone spinner made every card feel broken for 2-3s.
        if let lite = self.words.find(id: id) {
            self.word = Self.provisionalWord(from: lite, tags: [])
        }
        do {
            self.word = try await self.catalog.word(id: id, lang: lang, learning: learning)
        } catch {
            // A failure that arrives after the provisional card is on screen is
            // not worth blanking the page for.
            if self.word == nil { self.error = error }
        }
        return self.word
    }

    private func loadAtlasItem(id: String) async {
        // /api/users/custom-words now embeds the full detail (definition /
        // synonyms / forms / etymology) enriched at capture time, so the common
        // path renders with zero extra round-trips.
        if let lite = self.words.find(id: id) {
            if let full = lite.detail {
                self.word = full
                return
            }
            // No embedded detail (cold store, or an item that missed
            // enrichment): show the lite card instantly, then upgrade via the
            // detail endpoint, which lazily enriches on first open.
            self.word = Self.provisionalWord(from: lite, tags: ["custom"])
        }
        do {
            self.word = try await self.atlas.detail(
                itemId: String(id.dropFirst(Self.atlasPrefix.count))
            )
        } catch {
            if self.word == nil { self.error = error }
        }
    }

    /// Lite grid payload → renderable Word shell: enough for the hero, title
    /// row, and 中文 definition while the full detail is fetched.
    static func provisionalWord(from lite: CardWord, tags: [String]) -> Word {
        Word(
            id: lite.id,
            word: lite.word,
            alsoKnownAs: nil,
            category: lite.category,
            partOfSpeech: nil,
            pronunciation: lite.pronunciation,
            reading: lite.reading,
            readingSegments: lite.readingSegments,
            targetLanguage: lite.targetLanguage,
            audioUrl: nil,
            audioUrls: lite.audioUrls,
            imageUrl: lite.imageUrl,
            cefrLevel: nil,
            status: "published",
            chinese: lite.chinese,
            definitions: [
                WordDefinition(language: "zh", definition: lite.chinese, cefrLevel: nil, sortOrder: 0)
            ],
            examples: nil,
            relations: nil,
            collocations: nil,
            collocationsZh: nil,
            note: nil,
            etymology: nil,
            forms: nil,
            chineseDefinition: lite.chinese,
            targetDefinition: nil,
            targetDefinitionSpans: nil,
            englishDefinition: nil,
            tags: tags
        )
    }
}
