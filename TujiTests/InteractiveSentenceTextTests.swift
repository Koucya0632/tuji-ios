// Pins which runs of an example sentence become links.
//
// The whole feature is one AttributedString: the sentence is handed to
// SwiftUI's text engine with a link on every tappable 詞塊, and everything
// visible — what is underlined, what is tappable, what the tap resolves to —
// falls out of how that string is built. Rendering a view is the only other
// way to ask, and a rule you can only reach by rendering is a rule nothing
// tests.

import Foundation
import SwiftUI
import Testing
@testable import Tuji

@MainActor
struct InteractiveSentenceTextTests {
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

    /// Every run that carries a link, as plain text.
    private func linked(_ attributed: AttributedString) -> [String] {
        attributed.runs.compactMap { run in
            run.link == nil ? nil : String(attributed[run.range].characters)
        }
    }

    private static let text = "I look forward to the weekend."

    private var sentence: [GlossSpan] {
        [
            self.span("I "),
            self.span("look forward to", gloss: "期待"),
            self.span(" the "),
            self.span("weekend", gloss: "週末"),
            self.span(".")
        ]
    }

    @Test
    func onlyGlossedSpansBecomeLinks() {
        let attributed = InteractiveSentenceText.attributed(self.sentence)
        #expect(self.linked(attributed) == ["look forward to", "weekend"])
    }

    /// The failure the screenshot was taken to rule out: punctuation and bare
    /// function words wearing the tappable underline makes a sentence read as
    /// spell-check errors, and taps a learner nothing comes of.
    @Test
    func punctuationAndFunctionWordsCarryNoLink() {
        let attributed = InteractiveSentenceText.attributed(self.sentence)
        let dead = self.linked(attributed).joined()
        #expect(!dead.contains("."))
        #expect(!dead.contains("the"))
    }

    /// Japanese has no spaces to mark the boundaries, so particles ride
    /// directly against the words they follow — the case where a link one
    /// character too wide is invisible to a reader who cannot read it.
    @Test
    func japaneseParticlesCarryNoLink() {
        let spans = [
            self.span("冷蔵庫", gloss: "冰箱"),
            self.span("の"),
            self.span("中", gloss: "裡面"),
            self.span("に"),
            self.span("牛乳", gloss: "牛奶"),
            self.span("が"),
            self.span("入っています", gloss: "裝著"),
            self.span("。")
        ]
        #expect(
            self.linked(InteractiveSentenceText.attributed(spans))
                == ["冷蔵庫", "中", "牛乳", "入っています"]
        )
    }

    /// The whole sentence must survive being turned into runs — the same
    /// invariant `SentenceAnnotation` checks, now on the far side of the
    /// rendering step.
    @Test
    func theAttributedStringStillSpellsTheSentence() {
        let attributed = InteractiveSentenceText.attributed(self.sentence)
        #expect(String(attributed.characters) == Self.text)
    }

    // MARK: - Resolving a tap

    @Test
    func aLinkResolvesToItsSpan() throws {
        let attributed = InteractiveSentenceText.attributed(self.sentence)
        let url = try #require(attributed.runs.compactMap(\.link).first)
        #expect(InteractiveSentenceText.spanIndex(in: url) == 1)
        #expect(self.sentence[1].text == "look forward to")
    }

    /// `tuji://` is a registered deep-link scheme this app already routes. A
    /// span link wearing it would hand `TujiApp.onOpenURL` a bogus route, so
    /// the two must not be the same scheme — and the resolver must refuse
    /// anything that is not its own.
    @Test
    func foreignSchemesAreRefused() throws {
        for raw in ["tuji://word/3", "https://example.com/word/3"] {
            let url = try #require(URL(string: raw))
            #expect(InteractiveSentenceText.spanIndex(in: url) == nil)
        }
    }

    /// A selection only accepts a span it could show something for; without
    /// this the scrim could be raised over an empty card.
    @Test
    func selectionRefusesAnUntappableSpan() {
        let selection = GlossSelection()
        selection.select(self.span(" the "), at: 2, in: Self.text, language: .en)
        #expect(selection.span == nil)
        selection.select(self.span("weekend", gloss: "週末"), at: 3, in: Self.text, language: .en)
        #expect(selection.span?.text == "weekend")
        selection.clear()
        #expect(selection.span == nil)
    }

    // MARK: - Marking the selected 詞塊

    /// Every run that carries a 螢光筆, as plain text.
    private func highlighted(_ attributed: AttributedString) -> [String] {
        attributed.runs.compactMap { run in
            run.backgroundColor == nil ? nil : String(attributed[run.range].characters)
        }
    }

    @Test
    func nothingIsMarkedWithoutASelection() {
        #expect(self.highlighted(InteractiveSentenceText.attributed(self.sentence)).isEmpty)
        #expect(InteractiveSentenceText.split(self.sentence, highlighting: nil).selected == nil)
    }

    @Test
    func onlyTheSelectedSpanIsMarked() {
        let attributed = InteractiveSentenceText.attributed(self.sentence, highlighting: 3)
        #expect(self.highlighted(attributed) == ["weekend"])
    }

    /// The 螢光筆 the reader sees and the run the renderer measures are the same
    /// piece — the selected 詞塊 is spliced out precisely so it can be marked,
    /// so anything lit and unmeasured would be a caret aimed at the wrong word.
    @Test
    func theMarkedSpanIsTheOneSplicedOut() throws {
        let parts = InteractiveSentenceText.split(self.sentence, highlighting: 1)
        let marked = try #require(parts.selected)
        #expect(String(marked.characters) == "look forward to")
        #expect(self.highlighted(marked) == ["look forward to"])
        #expect(self.highlighted(parts.before).isEmpty)
        #expect(self.highlighted(parts.after).isEmpty)
    }

    /// The full-cover invariant again, on the far side of the splice: three
    /// pieces still have to spell the sentence exactly once.
    @Test
    func theSplicedSentenceIsStillTheSentence() {
        let attributed = InteractiveSentenceText.attributed(self.sentence, highlighting: 1)
        #expect(String(attributed.characters) == Self.text)
    }

    /// The splice must not renumber what follows it. Links carry the span's
    /// index in the *whole* sentence, so a run rebuilt from a slice would send
    /// every later tap to the word before it.
    @Test
    func theSpliceLeavesLaterLinksPointingAtTheirOwnSpan() throws {
        let parts = InteractiveSentenceText.split(self.sentence, highlighting: 1)
        let url = try #require(parts.after.runs.compactMap(\.link).first)
        #expect(InteractiveSentenceText.spanIndex(in: url) == 3)
        #expect(self.sentence[3].text == "weekend")
    }

    // MARK: - Anchoring

    @Test
    func aSelectionBelongsToOneSentence() {
        let selection = GlossSelection()
        selection.select(self.sentence[1], at: 1, in: Self.text, language: .en)
        #expect(selection.selectedIndex(in: Self.text) == 1)
        #expect(selection.selectedIndex(in: "Another sentence entirely.") == nil)
    }

    /// A sentence that draws one frame late would otherwise aim the caret at
    /// the word the user tapped *before* this one.
    @Test
    func anAnchorReportedForAnythingButTheLiveSelectionIsDropped() {
        let anchor = CGRect(x: 12, y: 34, width: 56, height: 20)
        let selection = GlossSelection()
        selection.select(self.sentence[1], at: 1, in: Self.text, language: .en)

        selection.report(anchor: anchor, for: .init(sentence: Self.text, index: 0))
        #expect(selection.anchor == nil)
        selection.report(anchor: anchor, for: .init(sentence: "Another sentence entirely.", index: 1))
        #expect(selection.anchor == nil)

        selection.report(anchor: anchor, for: .init(sentence: Self.text, index: 1))
        #expect(selection.anchor == anchor)
    }

    /// Keeping the previous word's anchor would point the new card at the old
    /// word for the frame before the new measurement lands.
    @Test
    func selectingAgainForgetsWhereTheLastWordWas() {
        let selection = GlossSelection()
        selection.select(self.sentence[1], at: 1, in: Self.text, language: .en)
        selection.report(anchor: CGRect(x: 1, y: 2, width: 3, height: 4), for: .init(sentence: Self.text, index: 1))
        #expect(selection.anchor != nil)

        selection.select(self.sentence[3], at: 3, in: Self.text, language: .en)
        #expect(selection.anchor == nil)

        selection.clear()
        #expect(selection.target == nil)
        #expect(selection.anchor == nil)
    }
}
