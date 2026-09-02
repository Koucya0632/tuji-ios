// Word data models matching the backend payloads.
//
// `CardWord` is the lite shape returned by GET /api/words — used by list
// views (Cards / Today's themes / Search results / Favorites).
//
// The full `Word` shape (with definitions / examples / relations /
// etymology / forms) comes from GET /api/words/{id} and is loaded
// on-demand by WordDetailView; defined separately when that view ships.

import Foundation

extension String {
    /// The public slug when this is a saved 物見 word id (`saved:<slug>`),
    /// else nil. The prefix is the routing decision: these belong to someone
    /// else, so they open on the public detail rather than the word screen —
    /// the same way `atlas:` marks the user's own captures.
    var savedCommunitySlug: String? {
        let prefix = "saved:"
        guard self.hasPrefix(prefix) else { return nil }
        let slug = String(self.dropFirst(prefix.count))
        return slug.isEmpty ? nil : slug
    }
}

struct CardWord: Codable, Identifiable, Hashable {
    let id: String
    let word: String
    let chinese: String
    let imageUrl: String
    let category: String
    let pronunciation: String
    let reading: String?
    /// Which kana sit over which characters of `word`; nil when the server has
    /// no trustworthy split and the reading falls back to a line of its own.
    let readingSegments: [FuriganaSegment]?
    let targetLanguage: TargetLanguage?
    /// Pre-generated pronunciation clips keyed by locale ("en-US" / "en-GB" /
    /// "ja-JP"). The server only sends the locales relevant to the active
    /// learning direction; nil when no audio has been generated.
    let audioUrls: [String: String]?
    /// Full per-word detail, present only for 自制圖鑑 (custom) words —
    /// /api/users/custom-words embeds it so WordDetailView can render without a
    /// second /api/atlas/items/{id}/detail round-trip. nil for public words.
    let detail: Word?

    init(
        id: String,
        word: String,
        chinese: String,
        imageUrl: String,
        category: String,
        pronunciation: String,
        reading: String? = nil,
        readingSegments: [FuriganaSegment]? = nil,
        targetLanguage: TargetLanguage? = nil,
        audioUrls: [String: String]? = nil,
        detail: Word? = nil
    ) {
        self.id = id
        self.word = word
        self.chinese = chinese
        self.imageUrl = imageUrl
        self.category = category
        self.pronunciation = pronunciation
        self.reading = reading
        self.readingSegments = readingSegments
        self.targetLanguage = targetLanguage
        self.audioUrls = audioUrls
        self.detail = detail
    }

    var imageURL: URL? {
        URL(string: imageUrl)
    }

    /// Which kind of picture this word carries.
    ///
    /// The dictionary's own artwork is a cut-out on a pure white backdrop; a
    /// word the user photographed, or saved from someone else's atlas, is a
    /// real scene. They cannot be presented the same way — multiplying a
    /// photograph against the paper darkens the whole frame, while leaving a
    /// cut-out unmultiplied leaves a white rectangle floating on the page.
    var imageKind: WordImageKind {
        WordImageKind(category: self.category)
    }
}

/// Distinguishes dictionary artwork from user photography.
nonisolated enum WordImageKind {
    /// White-backdrop product shot. Blends into the paper.
    case cutout
    /// A real photograph. Rendered as-is.
    case photograph

    /// `CardWord`, `StudyQueueWord` and `Word` all carry the same `category`
    /// string and all three had their own copy of this two-line test. It is one
    /// rule, so it lives with the type it produces — a fourth model asking the
    /// question gets the answer for free, and a change to what counts as a
    /// photograph happens once.
    init(category: String) {
        self = switch category {
        case "custom", "community": .photograph
        default: .cutout
        }
    }
}

/// The kana line under a headword, or nil when there is nothing to add.
///
/// A Japanese reading is furigana: kanji are spelled out, kana are copied as
/// written. A headword already written in kana is therefore *its own* reading —
/// バスマット reads バスマット — and printing that under itself tells the reader
/// nothing. (It only ever looked informative while the catalogue was flattening
/// katakana to hiragana, which is the bug that produced ばすまっと.)
///
/// `CardWord`, `StudyQueueWord` and `Word` all render this line, so the test
/// lives once, beside the rule it enforces.
enum ReadingLine {
    static func shown(_ reading: String?, for headword: String) -> String? {
        guard let reading = reading?.trimmingCharacters(in: .whitespaces),
              !reading.isEmpty,
              reading != headword
        else { return nil }
        return reading
    }
}

/// One run of a headword and the kana read over it (`nil` for bare kana).
///
/// Produced on the server, never here: which kana belong to which kanji is a
/// dictionary fact, and `reading` alone cannot yield it — はみがきこ does not
/// say that 歯 is は. The two invariants the server guarantees are that `text`
/// re-spells the headword and `ruby ?? text` re-spells the reading, which is
/// what lets a renderer draw either from this alone.
nonisolated struct FuriganaSegment: Codable, Hashable {
    let text: String
    let ruby: String?
}

/// One unit of an annotated example sentence — see 詞塊 in `CONTEXT.md`.
///
/// Deliberately not "one word": `look forward to` is a single span, because to
/// a learner it is one unit and translating the bare `to` inside it is not
/// merely useless but wrong. Which is also why the split is made on the server,
/// against the whole sentence, rather than by the `NLTagger` sitting free on
/// the device ([ADR-0009](../../../docs/adr/0009-example-sentence-annotation.md)).
///
/// **A span with a `gloss` is tappable and one without it is not.** There is no
/// `isTappable`, and the answer must not vary by interface language: a span
/// missing its ja gloss falls back to zh-Hant server-side rather than going
/// dead, or the same sentence would lose half its live words in 日本語.
nonisolated struct GlossSpan: Codable, Hashable {
    /// This span's slice of the sentence, verbatim — including whatever spaces
    /// and punctuation belong to it. `SentenceAnnotation` re-spells the
    /// sentence from these, so it is never normalised.
    let text: String
    /// What the span means *in this sentence*. nil for function words and
    /// punctuation, which is exactly what makes them untappable.
    let gloss: String?
    /// `running` → `run`. nil when the span is already its own base form.
    ///
    /// Not `lemma`: that name is taken by the 自製圖鑑 item headword
    /// (`atlas_items.lemma`), and one word meaning two things in one codebase
    /// is the next person's trap.
    let baseForm: String?
    /// Canonical English part of speech, as `localizedPartOfSpeech` expects.
    let partOfSpeech: String?
    /// Kana reading, Japanese only. nil for English spans.
    let reading: String?
    /// The catalogue word this span teaches, when it is one. Lets the card
    /// offer a way into 圖鑑詳情; nil for the many spans that will never be
    /// dictionary entries.
    let wordId: String?
    /// The catalogue's transcription — IPA for English, a copy of the kana
    /// reading for Japanese. Never authored per span and never produced by a
    /// model: it is `word_terms.pronunciation`, joined on the server.
    ///
    /// **A stricter condition than `wordId`**, and the client does not re-derive
    /// it. `wordId` is resolved from the span's *base form*, so `documents`
    /// links to `document`; the server only attaches a transcription when the
    /// span is spelled exactly like the headword, because the headword's
    /// pronunciation printed under an inflection is not useless but wrong.
    /// About one tappable span in five has one — the same shape of "sometimes"
    /// as 書籤 and 看完整詳情, and for the same reason.
    let pronunciation: String?

    /// Spelled out rather than synthesised so `pronunciation` can default:
    /// every span built in a test or a preview predates it, and a field the
    /// server fills has no business rewriting them.
    init(
        text: String,
        gloss: String?,
        baseForm: String?,
        partOfSpeech: String?,
        reading: String?,
        wordId: String?,
        pronunciation: String? = nil
    ) {
        self.text = text
        self.gloss = gloss
        self.baseForm = baseForm
        self.partOfSpeech = partOfSpeech
        self.reading = reading
        self.wordId = wordId
        self.pronunciation = pronunciation
    }

    /// The one question every consumer asks. Spelled out here so no screen
    /// re-derives it as `span.gloss != nil` and lets the two drift.
    var isTappable: Bool {
        self.gloss?.isEmpty == false
    }
}

/// Whether a sentence's spans may be trusted to render it.
///
/// The annotation is **total**: every character of the sentence sits in exactly
/// one span, so concatenating them re-spells it. That is the same invariant
/// `FuriganaSegment` carries, kept for the same reason — the checkable half of
/// a model's answer gets checked. It also means a renderer never indexes into
/// the string (it appends span by span), so the two languages never have to
/// agree on what one character is: JS counts UTF-16, Swift's `Character` is a
/// grapheme cluster, and Postgres counts code points.
///
/// Failing the check is not an error state. It renders the plain sentence the
/// app shipped with before any of this existed.
nonisolated enum SentenceAnnotation {
    static func spans(_ spans: [GlossSpan]?, for sentence: String) -> [GlossSpan]? {
        guard let spans, !spans.isEmpty else { return nil }
        guard spans.map(\.text).joined() == sentence else { return nil }
        return spans
    }
}

/// What a screen puts with a headword.
///
/// Five screens each carried their own `if let pronunciation` and they did not
/// agree: only 認識 checked the reading against the headword, so on the other
/// four every kana-only Japanese word printed itself twice — バスマット at
/// display size, then バスマット again underneath. The rule belongs in one
/// place, beside `ReadingLine`, which is the same question one layer down.
nonisolated enum HeadwordDisplay: Equatable {
    /// Japanese with a usable split: kana sit over the characters they read.
    case ruby([FuriganaSegment])
    /// A line of its own — an English IPA transcription, or Japanese kana that
    /// could not be aligned.
    case line(String)
    /// Nothing to add. The headword already says it.
    case plain
}

/// A payload that can decide how its headword is presented.
nonisolated protocol Headworded: LanguageTagged {
    var word: String { get }
    /// Spelled out because the three models disagree on optionality, and a
    /// protocol witness may not narrow `String` to `String?`.
    var headwordPronunciation: String? { get }
    var readingSegments: [FuriganaSegment]? { get }
}

extension Headworded {
    /// `session` is 當前圖鑑語言, for a word the server did not tag. It reaches
    /// here from `TujiHeadword`'s environment rather than from each screen —
    /// this used to be an untagged word's silent vote for the English branch.
    func headwordDisplay(in session: TargetLanguage) -> HeadwordDisplay {
        // Japanese only. An English `pronunciation` is IPA — different
        // information from the headword, and nothing ruby can express.
        guard self.language(in: session) == .ja else {
            return ReadingLine.shown(self.headwordPronunciation, for: self.word)
                .map(HeadwordDisplay.line) ?? .plain
        }
        if let segments = self.readingSegments, !segments.isEmpty {
            return .ruby(segments)
        }
        // No split: fall back to the line this replaced. For Japanese the
        // server sends `pronunciation` as a copy of `reading`, so either
        // spelling of the question gives the same answer — and a headword
        // already written in kana is its own reading, which is the case that
        // used to print twice.
        return ReadingLine.shown(self.reading ?? self.headwordPronunciation, for: self.word)
            .map(HeadwordDisplay.line) ?? .plain
    }
}

struct WordsListResponse: Decodable {
    let words: [CardWord]
    let total: Int
}

// Full per-word detail returned by GET /api/words/{id}. Most heavy fields
// (definitions / examples / relations / etymology / forms / collocations)
// are optional — the backend trims them when there's nothing to send, so
// every section in WordDetailView renders conditionally.

struct Word: Codable, Identifiable, Hashable {
    let id: String
    let word: String
    let alsoKnownAs: [String]?
    let category: String
    let partOfSpeech: String?
    let pronunciation: String?
    let reading: String?
    let readingSegments: [FuriganaSegment]?
    let targetLanguage: TargetLanguage?
    let audioUrl: String?
    /// Per-locale pronunciation clips ("en-US" / "en-GB" / "ja-JP"); superset
    /// of `audioUrl`, which mirrors the en-US clip.
    let audioUrls: [String: String]?
    let imageUrl: String
    let cefrLevel: String?
    let status: String?

    /// Convenience: server primaries the first zh-Hant definition into
    /// `chinese` so list views can render without unwrapping the full
    /// definitions array.
    let chinese: String

    let definitions: [WordDefinition]?
    let examples: [WordExample]?
    let relations: [WordRelation]?
    let collocations: [String]?
    /// zh-Hant translations parallel to `collocations`. Server overlays
    /// these from word_localized_texts(field='collocations',
    /// language='zh-Hant'); ja currently has none so this may be nil for
    /// ja users. iOS treats it as optional and falls back to en-only.
    let collocationsZh: [String]?
    let note: String?
    let etymology: String?
    let forms: [WordForm]?
    let chineseDefinition: String?
    /// Definition in the active learning target language (`en` or `ja`).
    let targetDefinition: String?
    /// 詞塊 for `targetDefinition`. The 譯義 line is a sentence in the language
    /// being learned, so it is tappable on the same terms an example sentence
    /// is. The Chinese explainer beside it deliberately is not: glossing
    /// Chinese for a Chinese reader teaches nothing, and a ja/en interface
    /// never renders that line at all.
    let targetDefinitionSpans: [GlossSpan]?
    /// Convenience: first en-language definition prefilled by the server
    /// (the `definitions` array itself is lang-filtered so the en row
    /// gets dropped when UI lang is zh-Hant — see lib/word-localize.ts).
    let englishDefinition: String?
    let tags: [String]?

    var imageURL: URL? {
        URL(string: imageUrl)
    }

    /// Same question `CardWord` and `StudyQueueWord` answer, from the same
    /// `category`. It was missing here, and that absence is what produced the
    /// last hand-written copy of the picture rules: 圖鑑詳情 could not ask a
    /// `Word` what kind of picture it had, so it built an `isCutout` helper and
    /// then spelled out fit-vs-fill, the inset and the multiply beside it.
    var imageKind: WordImageKind {
        WordImageKind(category: self.category)
    }
}

struct WordDefinition: Codable, Hashable {
    let language: String
    let definition: String
    let cefrLevel: String?
    let sortOrder: Int?
}

struct WordExample: Codable, Hashable {
    let en: String
    /// Sentence in the active learning target language. Japanese detail
    /// payloads omit examples that do not have this value.
    let target: String?
    let zh: String?
    let translations: [String: String]?
    let cefrLevel: String?
    let sortOrder: Int?
    /// The sentence split into tappable 詞塊, glossed in the requested UI
    /// language. Optional and often absent: an un-annotated sentence renders as
    /// the plain text it always was. Ask `SentenceAnnotation.spans(_:for:)`
    /// rather than reading this directly — the spans are only usable if they
    /// re-spell the sentence.
    let spans: [GlossSpan]?
}

struct WordRelation: Codable, Hashable {
    let wordId: String
    let type: String
    let note: String?
}

struct WordForm: Codable, Hashable {
    let label: String
    let value: String
}
