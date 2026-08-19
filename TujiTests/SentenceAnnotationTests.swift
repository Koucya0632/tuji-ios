// Pins the one invariant that lets an example sentence be tapped: the spans
// must re-spell the sentence exactly.
//
// This is the checkable half of a model's answer, and checking it is the whole
// reason the annotation is a list of covering spans rather than a set of
// character offsets ([ADR-0009](../docs/adr/0009-example-sentence-annotation.md)).
// Failing the check is not an error — the sentence renders as the plain text
// the app showed before any of this existed — which is exactly why nothing
// would ever surface a regression here. Hence these.

import Foundation
import Testing
@testable import Tuji

struct SentenceAnnotationTests {
    private func span(_ text: String, gloss: String? = nil) -> GlossSpan {
        GlossSpan(
            text: text,
            gloss: gloss,
            baseForm: nil,
            partOfSpeech: nil,
            reading: nil,
            wordId: nil
        )
    }

    @Test
    func fullCoverIsAccepted() {
        let sentence = "I look forward to the weekend."
        let spans = [
            self.span("I "),
            self.span("look forward to", gloss: "期待"),
            self.span(" the "),
            self.span("weekend", gloss: "週末"),
            self.span(".")
        ]
        #expect(SentenceAnnotation.spans(spans, for: sentence)?.count == spans.count)
    }

    /// A dropped character is the failure a covering format exists to catch:
    /// the spans still look plausible on their own and only the join disagrees.
    @Test
    func missingCharacterIsRejected() {
        let spans = [self.span("I "), self.span("read", gloss: "讀"), self.span(" it")]
        #expect(SentenceAnnotation.spans(spans, for: "I read it.") == nil)
    }

    /// Whitespace belongs *inside* a span, so a model that normalises it away
    /// produces a join that is one space short of the sentence.
    @Test
    func collapsedWhitespaceIsRejected() {
        let spans = [self.span("I"), self.span("read", gloss: "讀"), self.span("it.")]
        #expect(SentenceAnnotation.spans(spans, for: "I read it.") == nil)
    }

    /// Extra material is as wrong as missing material, and a naive "does the
    /// sentence contain every span" check would pass this.
    @Test
    func extraTrailingSpanIsRejected() {
        let spans = [self.span("Hi", gloss: "嗨"), self.span("."), self.span(" ")]
        #expect(SentenceAnnotation.spans(spans, for: "Hi.") == nil)
    }

    @Test
    func absentSpansAreNil() {
        #expect(SentenceAnnotation.spans(nil, for: "Hi.") == nil)
    }

    /// An empty list joins to "" and would pass the comparison for an empty
    /// sentence, so it is rejected up front — there is nothing to make tappable.
    @Test
    func emptySpansAreNil() {
        #expect(SentenceAnnotation.spans([], for: "") == nil)
    }

    /// The case a space-splitting tokenizer cannot produce at all, which is
    /// half the reason the split is made on the server.
    @Test
    func japaneseSentenceWithoutSpacesIsAccepted() {
        let sentence = "猫が窓の外を見ている。"
        let spans = [
            self.span("猫", gloss: "貓"),
            self.span("が"),
            self.span("窓", gloss: "窗戶"),
            self.span("の"),
            self.span("外", gloss: "外面"),
            self.span("を"),
            self.span("見ている", gloss: "正在看"),
            self.span("。")
        ]
        #expect(SentenceAnnotation.spans(spans, for: sentence)?.count == spans.count)
    }

    // MARK: - 有釋義 = 可點

    /// The rule is derived from the gloss rather than stated beside it, so
    /// these pin the derivation rather than a field.
    @Test
    func onlyGlossedSpansAreTappable() {
        #expect(self.span("weekend", gloss: "週末").isTappable)
        #expect(!self.span(" the ").isTappable)
    }

    /// An empty string is what a serializer produces for a missing gloss when
    /// nobody guards it, and a card with a blank meaning is worse than a word
    /// that was never tappable.
    @Test
    func emptyGlossIsNotTappable() {
        #expect(!self.span("the", gloss: "").isTappable)
    }

    // MARK: - Payload

    /// Every example the app has ever cached, and every response from a server
    /// that has not been backfilled, carries no `spans` at all. Decoding must
    /// not care.
    @Test
    func exampleWithoutSpansStillDecodes() throws {
        let json = """
        {"en": "I read it.", "target": "I read it.", "zh": "我讀了它。"}
        """
        let example = try JSONDecoder.tuji.decode(WordExample.self, from: Data(json.utf8))
        #expect(example.spans == nil)
    }

    @Test
    func exampleWithSpansDecodes() throws {
        let json = """
        {
          "en": "I read it.",
          "target": "I read it.",
          "zh": "我讀了它。",
          "spans": [
            {"text": "I "},
            {"text": "read", "gloss": "讀", "baseForm": "read",
             "partOfSpeech": "verb", "wordId": "read"},
            {"text": " it."}
          ]
        }
        """
        let example = try JSONDecoder.tuji.decode(WordExample.self, from: Data(json.utf8))
        let spans = try #require(SentenceAnnotation.spans(example.spans, for: example.en))
        #expect(spans.count == 3)
        #expect(spans.filter(\.isTappable).map(\.text) == ["read"])
        #expect(spans[1].wordId == "read")
        // Japanese-only field, absent on an English payload.
        #expect(spans[1].reading == nil)
    }
}
