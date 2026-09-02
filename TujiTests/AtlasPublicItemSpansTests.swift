// Pins that a 物見 item's payload really carries annotated example sentences.
//
// This is the fact the 詞塊 host on `AtlasPublicDetailView` rests on, and it is
// not obvious from that screen: a capture's own content has no examples at all
// (`lib/atlas/enrich.ts` writes `examples: null`, and ADR-0009 puts 自製圖鑑
// outside the annotation's scope). The sentences come from somewhere else —
// when a capture's lemma is also a catalogue word, `/api/atlas/public/{slug}`
// joins that word's examples onto the item, spans and all.
//
// Nothing pinned that, and nothing pinned the decode either: this is the first
// test in the suite that takes a `GlossSpan` off the wire rather than building
// one in Swift. The screen went live with tappable data and no host for exactly
// as long as that was true.

import Foundation
import Testing
@testable import Tuji

struct AtlasPublicItemSpansTests {
    /// Shaped like `/api/atlas/public/{slug}` — a capture whose lemma matched
    /// the catalogue, so the route attached the catalogue word's examples.
    private static let payload = """
    {
      "id": "public-0001",
      "slug": "atlas-0001",
      "lemma": "bucket",
      "displayZhHant": "水桶",
      "targetLanguage": "en",
      "category": "bathroom",
      "imageUrl": "https://example.invalid/atlas-0001/thumb.webp",
      "author": { "handle": "TJ00000001", "displayName": "Someone", "avatar": "face" },
      "publishedAt": "2026-07-26T15:08:53.414Z",
      "learningWord": {
        "id": "bucket",
        "word": "bucket",
        "chinese": "水桶",
        "category": "bathroom",
        "partOfSpeech": "noun",
        "pronunciation": "/ˈbʌk.ɪt/",
        "imageUrl": "https://example.invalid/word-images/bucket.webp",
        "examples": [
          {
            "en": "I filled the bucket with water.",
            "zh": "我在水桶裡裝了水。",
            "target": "I filled the bucket with water.",
            "spans": [
              { "text": "I " },
              { "text": "filled", "baseForm": "fill", "partOfSpeech": "verb", "gloss": "注入" },
              { "text": " the " },
              { "text": "bucket", "baseForm": "bucket", "partOfSpeech": "noun", "gloss": "水桶", "pronunciation": "/ˈbʌk.ɪt/" },
              { "text": " with " },
              { "text": "water", "baseForm": "water", "partOfSpeech": "noun", "gloss": "水" },
              { "text": "." }
            ]
          }
        ]
      }
    }
    """

    private func example() throws -> WordExample {
        let data = try #require(Self.payload.data(using: .utf8))
        let item = try JSONDecoder.tuji.decode(AtlasPublicItem.self, from: data)
        return try #require(item.learningWord?.examples?.first)
    }

    @Test
    func aPublicItemCarriesItsExampleSpans() throws {
        let example = try self.example()
        #expect(example.spans?.count == 7)
    }

    /// The full-cover invariant, checked here for the third time and on the far
    /// side of JSON: if the wire ever stopped agreeing with the sentence, the
    /// screen would quietly go back to plain text and nothing would say so.
    @Test
    func theSpansOffTheWireStillSpellTheSentence() throws {
        let example = try self.example()
        let sentence = try #require(example.target)
        #expect(SentenceAnnotation.spans(example.spans, for: sentence) != nil)
    }

    /// Tappability is "has a gloss", and it has to survive decoding — a payload
    /// that dropped `gloss` would leave every word underlined and dead.
    @Test
    func onlyTheGlossedSpansSurviveAsTappable() throws {
        let spans = try #require(self.example().spans)
        #expect(spans.filter(\.isTappable).map(\.text) == ["filled", "bucket", "water"])
    }

    /// `baseForm` is the field this project renamed away from `lemma`, and the
    /// wire spells it in camelCase; a decoder change would silently blank the
    /// 原形 line rather than fail.
    @Test
    func theBaseFormDecodes() throws {
        let spans = try #require(self.example().spans)
        #expect(spans.first(where: { $0.text == "filled" })?.baseForm == "fill")
    }

    /// The transcription is attached by the server and only for a span spelled
    /// exactly like the headword it links to — so `filled`, which links to
    /// `fill` through its base form, must arrive without one. Both halves are
    /// the wire's job; the client re-derives neither.
    @Test
    func onlyTheSpanSpelledLikeItsHeadwordCarriesATranscription() throws {
        let spans = try #require(self.example().spans)
        #expect(spans.first(where: { $0.text == "bucket" })?.pronunciation == "/ˈbʌk.ɪt/")
        #expect(spans.first(where: { $0.text == "filled" })?.pronunciation == nil)
    }
}
